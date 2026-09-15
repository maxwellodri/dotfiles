/**
 * ask-user-questions — `ask_user_question` tool: interactive questions with
 * typed / checkbox answer modes.
 *
 * Ported from amosblomqvist/pi-config extensions/ask-user-question.ts
 * (https://github.com/amosblomqvist/pi-config), since heavily reworked here.
 *
 * Batching: one call asks `question` plus any `additional_questions` —
 * sequential popups ("Question 2 of 3: …") under one UI lock. Esc on a
 * later question keeps earlier answers: the result reports the partial
 * answers plus which questions went unanswered. Batch closely related
 * questions this way; unrelated decisions want separate calls.
 *
 * Modes per question (derived from params):
 *   - no options            → free-form text editor
 *   - options               → checkbox list + inline "Custom" editor + Submit
 *
 * Options are *parts of an answer*, not alternatives: the user checks any
 * number of them and can type extra detail into the Custom editor (row 0,
 * default focus — prefer it for detail); everything checked and typed is
 * combined into one answer. There is deliberately no single-select mode.
 *
 * Keys (the complete set — ↑↓ do nothing outside the editor, where they are
 * its history):
 *   Tab / ⇧Tab   cycle rows (wrapping). EXCEPTION on the editor row: while
 *                the editor's completion dropdown (`@`/`$`) is open, Tab
 *                accepts the completion and Esc closes the dropdown instead
 *                of cycling / cancelling the question (main-prompt parity)
 *   Enter        submit from anywhere (checked options + custom text)
 *   ⇧Enter       newline inside the editor, no-op elsewhere (main-prompt
 *                parity)
 *   Ctrl+Space   confirm — toggle the focused option and move down one; on
 *                the Custom row skips ahead to the first option; on Submit
 *                it finalizes
 *   ^C           clear the custom editor
 *   Esc          cancel the question
 *
 * RPC degradation (ctx.mode === "rpc", e.g. under a remote bridge such as
 * paseo): ctx.ui.custom() returns undefined without a terminal, which would
 * make every user-select question silently resolve "cancelled". User-select
 * falls back to ctx.ui.editor taking one answer per line (option labels or
 * your own text). Text mode already uses ctx.ui.editor and works unchanged.
 *
 * Custom carries no checkbox: the custom answer simply IS the editor text at
 * submit time, omitted when empty/whitespace. It sorts first in results,
 * mirroring the picker where it is row 0.
 *
 * User-authored answers (Custom editor, and free-form text mode) behave like
 * a regular prompt: `$name` snippets are expanded and `@path` refs inject
 * their file/dir contents, reusing snippet_expansion.ts / prompt_expansion.ts
 * directly (relative imports; pi loads extensions with the module cache off,
 * so each extension gets its own copy — fine, both are stateless for our
 * use). The transcript shows the raw typed text; the expansion lands in the
 * model-facing tool result.
 *
 * Single in-flight question at a time: pop-up UI is serialized through a
 * globalThis mutex shared with any future pop-up-style tools, since
 * ctx.ui.custom() can only host one overlay at a time.
 *
 * Load: auto-discovered from pi/extensions/ask-user-questions/index.ts;
 * `/reload` after edits.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
	Editor,
	type EditorTheme,
	Key,
	Text,
	matchesKey,
	truncateToWidth,
	wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { expandSnippets } from "../snippet_expansion";
import { buildInjections } from "../prompt_expansion";

interface AskOption {
	label: string;
	value: string;
	description?: string;
}

interface DisplayOption extends AskOption {
	id: string;
	index?: number;
	isSubmit?: boolean;
}

interface TextAnswer {
	type: "text";
	label: string;
	value: string;
}

interface OptionAnswer {
	type: "option";
	label: string;
	value: string;
	index: number;
}

interface CustomAnswer {
	type: "custom";
	label: string;
	value: string;
}

type AskAnswer = TextAnswer | OptionAnswer | CustomAnswer;
type AskUserQuestionStatus = "answered" | "cancelled" | "unavailable";
type AskUserQuestionMode = "text" | "user-select";

interface AskUserQuestionResultDetails {
	status: AskUserQuestionStatus;
	/** Single-question calls (back-compat shape). */
	question?: string;
	context?: string;
	mode?: AskUserQuestionMode;
	answers?: AskAnswer[];
	/** Multi-question calls: per-question results in ask order. */
	questions?: QuestionResult[];
	message?: string;
}

/** One question's spec: the top-level params for the first, additional_questions entries after. */
interface QuestionSpec {
	question: string;
	context?: string;
	options: AskOption[];
}

interface QuestionResult {
	question: string;
	context?: string;
	mode: AskUserQuestionMode;
	status: "answered" | "cancelled" | "unavailable";
	answers: AskAnswer[];
	/** Text mode: the expanded answer ($snippets/@path) for the model-facing
	 *  content — answers[].label keeps the raw typed text for the transcript. */
	expandedAnswer?: string;
}

const OptionSchema = Type.Object({
	label: Type.String({
		description: "Display label for the option.",
	}),
	value: Type.Optional(
		Type.String({
			description: "Optional machine-readable value returned for the option. Defaults to the label.",
		}),
	),
	description: Type.Optional(Type.String({ description: "Optional extra detail shown below the option." })),
});

const AskUserQuestionParams = Type.Object({
	question: Type.String({
		description: "The first question to ask the user.",
	}),
	details: Type.Optional(
		Type.String({
			description: "Optional extra context or instructions shown under the question.",
		}),
	),
	options: Type.Optional(
		Type.Array(OptionSchema, {
			description:
				"Optional suggested parts of the answer. The user can check any number of them and type extra detail in the Custom editor; everything is combined into the answer. Omit for free-form text input.",
		}),
	),
	additional_questions: Type.Optional(
		Type.Array(
			Type.Object({
				question: Type.String({ description: "The question to ask." }),
				details: Type.Optional(
					Type.String({ description: "Optional extra context or instructions shown under the question." }),
				),
				options: Type.Optional(
					Type.Array(OptionSchema, { description: "Optional suggested parts of the answer, as for the first question." }),
				),
			}),
			{
				description:
					"Extra questions asked sequentially in the same call. Batch closely related questions here; use separate calls for unrelated decisions.",
			},
		),
	),
});

function normalizeOptions(options: Array<{ label: string; value?: string; description?: string }> | undefined): AskOption[] {
	return (options || [])
		.map((option) => ({
			label: option.label.trim(),
			value: option.value?.trim() || option.label.trim(),
			description: option.description?.trim() || undefined,
		}))
		.filter((option) => option.label.length > 0);
}

function getCustomLabel(options: AskOption[]): string {
	return options.some((option) => option.label.toLowerCase() === "custom") ? "Custom (type your own)" : "Custom";
}

function createEditorTheme(theme: any): EditorTheme {
	return {
		borderColor: (s) => theme.fg("accent", s),
		selectList: {
			selectedPrefix: (t) => theme.fg("accent", t),
			selectedText: (t) => theme.fg("accent", t),
			description: (t) => theme.fg("muted", t),
			scrollInfo: (t) => theme.fg("dim", t),
			noMatch: (t) => theme.fg("warning", t),
		},
	};
}

// ─────────────────────── height-aware layout ───────────────────────
// A ctx.ui.custom() component taller than the terminal pushes the status
// line / footer (and any live transcript updates) above the visible fold;
// pi-tui then falls back to full clear-and-repaint per update, which reads
// as constant flicker in a short tmux split (upstream pi issue #4021 —
// "please send an issue to the extension to fix their UI so it honors the
// terminal viewport height"). Cap the popup to the pane: reserve rows for
// the status line + footer around the editor container, and when the full
// card does not fit, compress — descriptions, then details/hints, then
// window the option list around the focused row with ↑/↓ counters — so
// status + popup + footer always fit the viewport and rendering stays
// differential.

/** Rows pi renders around the editor container: status (~2) + footer (3) + 1 breathing. */
const POPUP_RESERVED_ROWS = 6;
/** Never render fewer popup lines than this, however tiny the pane. */
const MIN_POPUP_ROWS = 8;

/** Live line budget for the popup: terminal rows minus the reserved chrome. */
function popupBudget(tui: any): number {
	const rows = tui?.terminal?.rows;
	const height = typeof rows === "number" && rows > 0 ? rows : 50;
	return Math.max(MIN_POPUP_ROWS, height - POPUP_RESERVED_ROWS);
}

/** Wrap text to width but keep at most maxLines lines, marking a cut with …. */
function clampWrapped(text: string, width: number, maxLines: number, indent = ""): string[] {
	const wrapped = wrapTextWithAnsi(text, Math.max(1, width - indent.length));
	if (wrapped.length <= maxLines) {
		return wrapped.map((line) => truncateToWidth(`${indent}${line}`, width));
	}
	const kept = wrapped.slice(0, maxLines);
	const last = kept[maxLines - 1] ?? "";
	kept[maxLines - 1] = `${last.slice(0, Math.max(0, last.length - 1))}…`;
	return kept.map((line) => truncateToWidth(`${indent}${line}`, width));
}

/**
 * Window [from, to) over `count` option rows that fits `avail` lines,
 * centered on the focused option when possible. Marker lines ("…↑N more")
 * eat into the available rows so the returned window always fits.
 */
function optionWindow(count: number, focused: number, avail: number): { from: number; to: number } {
	if (count <= 0 || avail <= 0) return { from: 0, to: 0 };
	// Two marker lines cost one option row each; reserve conservatively.
	let slots = Math.min(count, Math.max(1, avail - (count > avail ? 2 : 0)));
	const center = Math.min(Math.max(focused, 0), count - 1);
	let from = Math.max(0, Math.min(center - Math.floor(slots / 2), count - slots));
	from = Math.max(0, from);
	return { from, to: Math.min(count, from + slots) };
}

interface PopupSection {
	/** Pre-styled option label line. */
	line: string;
	/** Pre-styled description lines (droppable). */
	desc?: string[];
}

/**
 * Assemble the popup card under `budget` lines. Sections compress in
 * priority order: descriptions → blank padding + hints → details →
 * question clamp → option window → hard slice (bottom rule stays last).
 * When the full card fits (usual case on roomy panes) the layout is
 * identical to the uncapped one.
 */
function renderCappedPopup(args: {
	width: number;
	budget: number;
	theme: any;
	question: string;
	context?: string;
	customLabelLine: string;
	editorLines: string[];
	options: PopupSection[];
	focusedOption: number; // index into options; -1 when the editor row has focus
	submitLine?: string;
	hints: string[];
}): string[] {
	const { width, budget, theme, question, context, customLabelLine, editorLines, options, focusedOption, submitLine, hints } = args;
	const add = (lines: string[], text: string) => lines.push(truncateToWidth(text, width));
	const topRule = () => theme.fg("accent", "─".repeat(width));

	// Fixed overhead: rules + custom row (label + editor) + submit (multi).
	const submitCount = submitLine ? 1 : 0;
	const overhead = 2 /* rules */ + 1 + editorLines.length + submitCount;

	const questionFull = wrapTextWithAnsi(theme.fg("text", ` ${question}`), width);
	const contextFull = context ? wrapTextWithAnsi(theme.fg("muted", ` ${context}`), width) : [];
	const descTotal = options.reduce((n, o) => n + (o.desc?.length ?? 0), 0);
	const extras = (context ? contextFull.length + 1 : 0) + 1 /* padding */ + hints.length;

	// Roomy pane: everything fits — render the full card.
	if (overhead + questionFull.length + options.length + descTotal + extras <= budget) {
		const lines: string[] = [];
		add(lines, topRule());
		for (const line of questionFull) add(lines, truncateToWidth(line, width));
		if (context) {
			lines.push("");
			for (const line of contextFull) add(lines, truncateToWidth(line, width));
		}
		lines.push("");
		add(lines, customLabelLine);
		for (const line of editorLines) add(lines, line);
		for (const option of options) {
			add(lines, option.line);
			for (const line of option.desc ?? []) add(lines, line);
		}
		if (submitLine) add(lines, submitLine);
		lines.push("");
		for (const hint of hints) add(lines, hint);
		add(lines, topRule());
		return lines;
	}

	// Tight pane: compress. Descriptions and details go first.
	// Question: clamp to 2 wrapped lines (1 on degenerate panes).
	const questionMax = budget < overhead + options.length + 3 ? 1 : 2;
	const questionLines = clampWrapped(theme.fg("text", ` ${question}`), width, questionMax);

	// Option window: rows left after rules, question, custom row, and a
	// floor of one hint/padding line.
	const maxOptionRows = Math.max(1, budget - overhead - questionLines.length - 1);
	const window = optionWindow(options.length, focusedOption, maxOptionRows);

	// Progressive sparse builds: drop padding, then ↑/↓ markers, before
	// ever letting the hard slice eat an option row.
	const buildTight = (withBlank: boolean, withMarkers: boolean): string[] => {
		const lines: string[] = [];
		add(lines, topRule());
		for (const line of questionLines) add(lines, line);
		if (withBlank) lines.push("");
		add(lines, customLabelLine);
		for (const line of editorLines) add(lines, line);
		if (withMarkers && window.from > 0) {
			add(lines, theme.fg("dim", `   …↑ ${window.from} more`));
		}
		for (let i = window.from; i < window.to; i++) {
			add(lines, options[i].line);
		}
		if (withMarkers && window.to < options.length) {
			add(lines, theme.fg("dim", `   …↓ ${options.length - window.to} more`));
		}
		if (submitLine) add(lines, submitLine);
		if (lines.length + hints.length + 1 <= budget) {
			lines.push("");
			for (const hint of hints) add(lines, hint);
		}
		add(lines, topRule());
		return lines;
	};

	let lines = buildTight(true, true);
	if (lines.length > budget) lines = buildTight(false, true);
	if (lines.length > budget) lines = buildTight(false, false);

	// Degenerate pane: hard slice, keeping the closing rule as the last line.
	if (lines.length > budget) {
		const sliced = lines.slice(0, Math.max(1, budget - 1));
		sliced.push(topRule());
		return sliced;
	}
	return lines;
}

function answerSortRank(answer: AskAnswer): number {
	switch (answer.type) {
		case "custom":
			return 0; // custom leads, mirroring the picker where it is row 0
		case "option":
			return answer.index;
		case "text":
			return Number.MAX_SAFE_INTEGER;
	}
}

function sortAnswers(answers: AskAnswer[]): AskAnswer[] {
	return [...answers].sort((a, b) => answerSortRank(a) - answerSortRank(b));
}

/** The answer as one string: all parts — checked options and typed text — appended together. */
function answerPartsText(answers: AskAnswer[]): string {
	return sortAnswers(answers)
		.map((answer) => answer.label)
		.join("; ");
}

const textPart = (content: string) => ({ type: "text" as const, text: content });

function modeFor(spec: QuestionSpec): AskUserQuestionMode {
	return spec.options.length === 0 ? "text" : "user-select";
}

function toResult(spec: QuestionSpec, status: QuestionResult["status"], answers: AskAnswer[]): QuestionResult {
	return { question: spec.question, context: spec.context, mode: modeFor(spec), status, answers };
}

/** Model-facing line per question for multi-question results. */
function questionLine(result: QuestionResult): string {
	if (result.status !== "answered") return `- ${result.question}: (unanswered)`;
	const parts = result.mode === "text" ? result.expandedAnswer ?? "" : answerPartsText(result.answers);
	return `- ${result.question}: ${parts || "(empty response)"}`;
}

async function askMultiChoice(
	ctx: ExtensionContext,
	question: string,
	context: string | undefined,
	options: AskOption[],
): Promise<AskAnswer[] | null> {
	const customLabel = getCustomLabel(options);
	const choiceItems: DisplayOption[] = options.map((option, index) => ({
		...option,
		id: `option:${index}`,
		index: index + 1,
	}));
	const submitItem: DisplayOption = { id: "submit", label: "Submit", value: "__submit__", isSubmit: true };
	// Row 0 is the inline Custom editor; options occupy rows 1..n, Submit last.
	const allItems: DisplayOption[] = [...choiceItems, submitItem];

	return ctx.ui.custom<AskAnswer[] | null>((tui: any, theme: any, _kb: any, done: (result: AskAnswer[] | null) => void) => {
		let rowIndex = 0;
		let cachedLines: string[] | undefined;
		let cachedWidth = -1;
		let cachedHeight = -1;
		const selected = new Map<string, AskAnswer>();
		const editor = new Editor(tui, createEditorTheme(theme));
		editor.disableSubmit = true; // Enter is handled by the popup, not the editor
		if (promptAutocompleteProvider) {
			// @ file / $ snippet completions, same as the main prompt
			editor.setAutocompleteProvider(promptAutocompleteProvider);
		}

		function refresh() {
			cachedLines = undefined;
			tui.requestRender();
		}

		function toggleOption(item: DisplayOption) {
			if (selected.has(item.id)) {
				selected.delete(item.id);
			} else {
				selected.set(item.id, {
					type: "option",
					label: item.label,
					value: item.value,
					index: item.index!,
				});
			}
			refresh();
		}

		function submitAnswers() {
			const answers = Array.from(selected.values());
			const text = editor.getText().trim();
			if (text) {
				answers.push({ type: "custom", label: text, value: text });
			}
			if (answers.length > 0) {
				done(sortAnswers(answers));
			}
		}

		function handleInput(data: string) {
			editor.focused = rowIndex === 0;

			// While the editor's completion dropdown (`@`/`$`) is open, Tab and
			// Esc belong to the editor — accept the completion / close the
			// dropdown — exactly like the main prompt, instead of cycling rows
			// away mid-token or cancelling the whole question. Enter still
			// submits and ⇧Tab still cycles.
			if (rowIndex === 0 && editor.isShowingAutocomplete()) {
				if (matchesKey(data, Key.tab) || matchesKey(data, Key.escape)) {
					editor.handleInput(data);
					refresh();
					return;
				}
			}

			// Enter submits from anywhere: the checked options plus the
			// custom answer, which is simply the editor text if non-empty.
			if (matchesKey(data, Key.enter)) {
				submitAnswers();
				return;
			}

			// Tab / ⇧Tab cycle focus through the rows, wrapping at the edges.
			if (matchesKey(data, Key.tab)) {
				editor.focused = false;
				rowIndex = (rowIndex + 1) % (allItems.length + 1);
				refresh();
				return;
			}
			if (matchesKey(data, Key.shift("tab"))) {
				editor.focused = false;
				rowIndex = (rowIndex + allItems.length) % (allItems.length + 1);
				refresh();
				return;
			}

			if (rowIndex === 0) {
				// Editor row: no checkbox — the custom answer simply IS the
				// editor text at submit time. ↑↓ are the editor's history,
				// Enter a no-op; ^C clears the text.
				if (matchesKey(data, Key.escape)) {
					done(null);
					return;
				}
				if (matchesKey(data, Key.ctrl("c"))) {
					editor.setText("");
					refresh();
					return;
				}
				if (matchesKey(data, "ctrl+space")) {
					editor.focused = false; // nothing to confirm here; move along
					rowIndex = 1;
					refresh();
					return;
				}
				editor.handleInput(data);
				refresh();
				return;
			}

			const current = allItems[rowIndex - 1];

			// Ctrl+Space confirms: toggle the focused option and move down
			// one; on the Submit row, finalize the answers.
			if (matchesKey(data, "ctrl+space")) {
				if (current.isSubmit) {
					submitAnswers();
					return;
				}
				toggleOption(current);
				rowIndex = Math.min(allItems.length, rowIndex + 1);
				refresh();
				return;
			}

			if (matchesKey(data, Key.escape)) {
				done(null);
			}
		}

		function render(width: number): string[] {
			// The cache MUST be keyed on width AND height: pi-tui calls
		// requestRender() but NOT invalidate() on terminal resize, so render()
		// can be re-entered with new dimensions. Returning stale wider lines
		// trips the TUI width guard and crashes the process; a stale taller
		// layout re-triggers the small-pane flicker this cap exists to fix.
			const height = tui?.terminal?.rows;
			if (cachedLines && cachedWidth === width && cachedHeight === height) return cachedLines;

			editor.focused = rowIndex === 0;
			const customPrefix = rowIndex === 0 ? theme.fg("accent", "> ") : "  ";
			const customRow = rowIndex === 0 ? theme.fg("accent", customLabel) : theme.fg("text", customLabel);
			const editorLines = editor.render(Math.max(1, width - 2)).map((line: string) => ` ${line}`);
			const pending = selected.size + (editor.getText().trim() ? 1 : 0);

			const optionSections: PopupSection[] = choiceItems.map((item, i) => {
				const isFocused = rowIndex === i + 1;
				const prefix = isFocused ? theme.fg("accent", "> ") : "  ";
				const checked = selected.has(item.id);
				const marker = checked ? "[x]" : "[ ]";
				const label = `${marker} ${item.index}. ${item.label}`;
				return {
					line: `${prefix}${isFocused ? theme.fg("accent", label) : theme.fg(checked ? "success" : "text", label)}`,
					desc: item.description
						? wrapTextWithAnsi(theme.fg("muted", item.description), Math.max(1, width - 5)).map(
								(l: string) => truncateToWidth(`     ${l}`, width),
								)
						: undefined,
				};
			});

			const submitIsFocused = rowIndex === allItems.length;
			const submitPrefix = submitIsFocused ? theme.fg("accent", "> ") : "  ";
			const submitLabel = pending > 0 ? `✓ ${submitItem.label} (${pending} selected)` : `○ ${submitItem.label}`;
			const submitLine = `${submitPrefix}${submitIsFocused ? theme.fg("accent", submitLabel) : theme.fg(pending > 0 ? "success" : "dim", submitLabel)}`;

			const hints: string[] = [];
			if (rowIndex === 0) {
				hints.push(theme.fg("dim", " Tab completes when list open • Tab/⇧Tab rows • ^C clear • Enter submit • Esc cancel"));
			} else {
				if (pending === 0) {
					hints.push(theme.fg("warning", " Select at least one answer before submitting."));
				}
				hints.push(theme.fg("dim", " Tab/⇧Tab rows • Ctrl+Space toggle+down • Enter submit • Esc cancel"));
			}

			const lines = renderCappedPopup({
				width,
				budget: popupBudget(tui),
				theme,
				question,
				context,
				customLabelLine: `${customPrefix}${customRow}`,
				editorLines,
				options: optionSections,
				focusedOption: rowIndex - 1 >= choiceItems.length ? choiceItems.length - 1 : rowIndex - 1,
				submitLine,
				hints,
			});

			cachedLines = lines;
			cachedWidth = width;
			cachedHeight = height;
			return lines;
		}

		return {
			render,
			invalidate: () => {
				cachedLines = undefined;
			},
			handleInput,
		};
	});
}

/**
 * RPC fallback (ctx.mode === "rpc", e.g. under a remote bridge such as
 * paseo): ctx.ui.custom() returns undefined without a terminal, so the popup
 * degrades to a free-form editor accepting one answer per line. Lines
 * matching an option label become option answers; unmatched lines collapse
 * into a single custom answer joined by newlines — same result shape the TUI
 * popup produces (any options + one custom).
 */
async function askMultiChoiceRpc(
	ctx: ExtensionContext,
	question: string,
	context: string | undefined,
	options: AskOption[],
): Promise<AskAnswer[] | null> {
	const title =
		(context ? `${question}\n\n${context}` : question) +
		"\n\nEnter one answer per line — an option label or your own text.";
	const raw = await ctx.ui.editor(title);
	if (raw === undefined) return null;
	const answers: AskAnswer[] = [];
	const customs: string[] = [];
	for (const line of raw.split("\n")) {
		const text = line.trim();
		if (!text) continue;
		const index = options.findIndex((option) => option.label === text);
		if (index !== -1) {
			answers.push({ type: "option", label: options[index].label, value: options[index].value, index: index + 1 });
		} else {
			customs.push(text);
		}
	}
	if (customs.length > 0) {
		const label = customs.join("\n");
		answers.push({ type: "custom", label, value: label });
	}
	return answers.length > 0 ? sortAnswers(answers) : null;
}

// Shared UI mutex. ctx.ui.custom()/editor can only handle one active call at
// a time, so ALL pop-up-style tools must serialize against each other, not
// just against themselves. Stashed on globalThis so separate extension files
// can share it without importing each other (pi loads extensions with the
// module cache disabled — a shared import would give each extension its own
// copy of the lock).
const SHARED_UI_LOCK_KEY = "__piSharedUiLock";
function getSharedUiLock() {
	const g = globalThis as any;
	if (!g[SHARED_UI_LOCK_KEY]) {
		let chain: Promise<void> = Promise.resolve();
		g[SHARED_UI_LOCK_KEY] = {
			withLock<T>(fn: () => T | Promise<T>): Promise<T> {
				const prev = chain;
				let release: () => void;
				chain = new Promise<void>((r) => { release = r; });
				return prev.then(fn).finally(() => release!());
			},
		};
	}
	return g[SHARED_UI_LOCK_KEY] as { withLock<T>(fn: () => T | Promise<T>): Promise<T> };
}
const sharedUiLock = getSharedUiLock();

function withUILock<T>(fn: () => Promise<T>): Promise<T> {
	return sharedUiLock.withLock(fn);
}

/**
 * Run user-authored answer text through the same expansions a regular prompt
 * gets: `$name` snippet substitution (snippet_expansion.ts) and `@path`
 * file/dir injection (prompt_expansion.ts). Returns the expanded text plus
 * any `<file>` blocks to append to the model-facing result. Best-effort:
 * failures fall back to the raw text.
 */
async function expandAnswerText(text: string, ctx: any): Promise<{ text: string; blocks: string[] }> {
	let expanded = text;
	try {
		expanded = expandSnippets(text);
	} catch {
		expanded = text;
	}
	const blocks: string[] = [];
	if (expanded.includes("@")) {
		try {
			const injections = await buildInjections(expanded, ctx);
			if (injections.injected > 0) {
				blocks.push(...injections.blocks);
			}
		} catch {
			// leave @tokens verbatim
		}
	}
	return { text: expanded, blocks };
}

function withBlocks(text: string, blocks: string[]): string {
	return blocks.length > 0 ? `${text}\n\n${blocks.join("\n\n")}` : text;
}

/**
 * pi's composite autocomplete provider (base `@` + registered wrappers such
 * as fuzzy-filter and snippet_expansion), captured via transparent no-op
 * registrations. Wrappers run in REGISTRATION order and this extension loads
 * before snippet_expansion registers its `$` layer — so besides the
 * synchronous capture at session_start, a deferred re-registration (setTimeout)
 * appends our factory last, where it sees the complete composite. Attached to
 * each Custom editor so answers get the same `@`/`$` completions as the main
 * prompt.
 */
let promptAutocompleteProvider: any = null;

export default function askUserQuestion(pi: ExtensionAPI) {
	// Capture the main prompt's autocomplete stack for the Custom editor.
	// Transparent: adds nothing to the chain, just remembers the composite.
	pi.on("session_start", (_event, ctx) => {
		const capture = (inner: any) => {
			promptAutocompleteProvider = inner;
			return inner;
		};
		ctx.ui?.addAutocompleteProvider?.(capture);
		// The synchronous capture above runs before later-loading extensions
		// (snippet_expansion's `$`) register their layers — observed as `@`
		// completing but `$` not. All session_start handlers are synchronous,
		// so a short deferral re-registers us LAST; the inner we then see is
		// the complete chain, and every later rebuild keeps us last.
		setTimeout(() => {
			try {
				ctx.ui?.addAutocompleteProvider?.(capture);
			} catch {
				// Session was replaced/reloaded inside the deferral window: this
				// ctx is stale and throws on access. Skip — the new session's own
				// session_start re-registers with its fresh ctx.
			}
		}, 100);
	});

	pi.registerTool({
		name: "ask_user_question",
		label: "ask_user_question",
		description:
			"Ask the user one or more related questions and pause execution until they answer. Use this when requirements are ambiguous, user preferences are needed, a decision would materially affect implementation, or you need confirmation before proceeding. Closely related questions can be batched via additional_questions.",
		promptSnippet:
			"Use ask_user_question to ask clarifying questions, missing-requirement questions, preference questions, or decision questions before continuing.",
		promptGuidelines: [
			"Batch closely related questions into one ask_user_question call via additional_questions; use separate calls for unrelated decisions.",
			"Options are suggested parts of the answer, not alternatives: the user can check any number of them and type extra detail in the Custom editor, and everything is combined into one answer.",
			"Omit options for free-form input.",
			'Custom editor text behaves like a regular prompt ($snippets and @path includes are expanded).',
			"Order ask_user_question options with the most likely answer first.",
			"Prefer ask_user_question over guessing when requirements, preferences, or implementation choices are unclear.",
		],
		parameters: AskUserQuestionParams,

		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const specs: QuestionSpec[] = [
				{
					question: params.question,
					context: params.details?.trim() || undefined,
					options: normalizeOptions(params.options),
				},
				...(params.additional_questions ?? []).map((q) => ({
					question: q.question,
					context: q.details?.trim() || undefined,
					options: normalizeOptions(q.options),
				})),
			];
			const multi = specs.length > 1;

			if (signal?.aborted) {
				return multi
					? { content: [textPart("User cancelled the questions")], details: { status: "cancelled", questions: specs.map((s) => toResult(s, "cancelled", [])), message: "User cancelled the questions" } }
					: { content: [textPart("User cancelled the question")], details: { status: "cancelled", question: specs[0].question, context: specs[0].context, mode: modeFor(specs[0]), answers: [], message: "User cancelled the question" } };
			}

			if (!ctx.hasUI) {
				const message = "ask_user_question requires interactive mode UI";
				return multi
					? { content: [textPart(message)], details: { status: "unavailable", questions: specs.map((s) => toResult(s, "unavailable", [])), message } }
					: { content: [textPart(message)], details: { status: "unavailable", question: specs[0].question, context: specs[0].context, mode: modeFor(specs[0]), answers: [], message } };
			}

			return withUILock(async () => {
				const results: QuestionResult[] = [];
				const blocks: string[] = [];

				for (let i = 0; i < specs.length; i++) {
					const spec = specs[i];
					const mode = modeFor(spec);
					const title = multi ? `Question ${i + 1} of ${specs.length}: ${spec.question}` : spec.question;

					if (mode === "text") {
						const answer = await ctx.ui.editor(spec.context ? `${title}\n\n${spec.context}` : title);
						if (answer === undefined) break; // Esc: keep what we have
						const trimmed = answer.trim();
						let expanded = trimmed;
						if (trimmed) {
							const expansion = await expandAnswerText(trimmed, ctx);
							expanded = expansion.text;
							blocks.push(...expansion.blocks);
						}
						// answers keep the RAW typed text (transcript parity with the old
						// shape); the expansion rides along for the model-facing text only
						results.push({ question: spec.question, context: spec.context, mode, status: "answered", answers: trimmed ? [{ type: "text", label: trimmed, value: trimmed }] : [], expandedAnswer: trimmed ? expanded : undefined });
					} else {
						const askSelect = ctx.mode === "rpc" ? askMultiChoiceRpc : askMultiChoice;
						const answers = await askSelect(ctx, title, spec.context, spec.options);
						if (!answers) break; // Esc: keep what we have
						const custom = answers.find((a) => a.type === "custom");
						if (custom?.label) {
							const expansion = await expandAnswerText(custom.label, ctx);
							custom.label = expansion.text;
							blocks.push(...expansion.blocks);
						}
						results.push({ question: spec.question, context: spec.context, mode, status: "answered", answers });
					}
				}
				// Unanswered tail (Esc mid-way): mark cancelled so the model sees what it missed.
				for (let i = results.length; i < specs.length; i++) results.push(toResult(specs[i], "cancelled", []));

				if (!multi) {
					const spec = specs[0];
					const r = results[0];
					if (r.status !== "answered") {
						return { content: [textPart("User cancelled the question")], details: { status: "cancelled", question: spec.question, context: spec.context, mode: r.mode, answers: [], message: "User cancelled the question" } };
					}
					if (r.mode === "text") {
						const text = r.answers.length ? `User answered: ${r.expandedAnswer ?? r.answers[0].label}` : "User submitted an empty response";
						return { content: [textPart(withBlocks(text, blocks))], details: { status: "answered", question: spec.question, context: spec.context, mode: "text", answers: r.answers } };
					}
					return {
						content: [textPart(withBlocks(`User answered: ${answerPartsText(r.answers)}`, blocks))],
						details: { status: "answered", question: spec.question, context: spec.context, mode: "user-select", answers: r.answers },
					};
				}

				const answered = results.filter((r) => r.status === "answered");
				if (answered.length === specs.length) {
					return {
						content: [textPart(withBlocks(`User answered:\n${results.map(questionLine).join("\n")}`, blocks))],
						details: { status: "answered", questions: results },
					};
				}
				const message = `User cancelled after ${answered.length} of ${specs.length} questions`;
				const unanswered = results.filter((r) => r.status !== "answered").map((r) => r.question).join("; ");
				return {
					content: [
						textPart(
							withBlocks(
								`${message}; answered questions kept:\n${answered.map(questionLine).join("\n") || "(none)"}\nUnanswered: ${unanswered}`,
								blocks,
							),
						),
					],
					details: { status: "cancelled", questions: results, message },
				};
			});
		},
		renderCall(args, theme) {
			const options = normalizeOptions(args.options as Array<{ label: string; value?: string; description?: string }> | undefined);
			let text = theme.fg("toolTitle", theme.bold("ask_user_question ")) + theme.fg("muted", args.question);
			const extra = (args.additional_questions as { question: string }[] | undefined)?.length ?? 0;
			if (extra > 0) {
				text += theme.fg("dim", ` +${extra}`);
			}
			if (options.length > 0) {
				const labels = [getCustomLabel(options), ...options.map((option) => option.label)].join(", ");
				text += `\n${theme.fg("dim", `  Options: ${labels}`)}`;
			}
			return new Text(text, 0, 0);
		},

		renderResult(result, _options, theme) {
			const details = result.details as AskUserQuestionResultDetails | undefined;
			if (!details) {
				const first = result.content[0];
				return new Text(first?.type === "text" ? first.text : "", 0, 0);
			}

			const renderPart = (answer: AskAnswer): string => {
				switch (answer.type) {
					case "text":
						return theme.fg("accent", answer.label || "(empty response)");
					case "custom": {
						// may hold an expanded snippet body — show only its first line
						const first = answer.label.split("\n")[0].slice(0, 80);
						const shown = first + (answer.label.length > first.length ? "…" : "");
						return `${theme.fg("muted", "Custom: ")}${theme.fg("accent", shown)}`;
					}
					case "option":
						return theme.fg("accent", `${answer.index}. ${answer.label}`);
				}
			};

			// Multi-question results: one block per question — parts are the answer.
			if (details.questions) {
				const lines: string[] = [];
				for (const q of details.questions) {
					if (q.status !== "answered") {
						lines.push(`${theme.fg("warning", "✗ ")}${theme.fg("muted", q.question)}`);
						continue;
					}
					const parts = sortAnswers(q.answers).map(renderPart);
					lines.push(`${theme.fg("success", "✓ ")}${theme.fg("accent", q.question)}${parts.length ? "" : theme.fg("muted", " — (empty response)")}`);
					for (const part of parts) lines.push(`${theme.fg("dim", "      ")}${part}`);
				}
				if (details.status === "cancelled" && details.message) lines.push(theme.fg("warning", details.message));
				return new Text(lines.join("\n"), 0, 0);
			}

			if (details.status === "cancelled") {
				return new Text(theme.fg("warning", details.message || "Cancelled"), 0, 0);
			}

			if (details.status === "unavailable") {
				return new Text(theme.fg("warning", details.message || "ask_user_question unavailable"), 0, 0);
			}

			const answers = details.answers ?? [];
			if (answers.length === 0) {
				return new Text(`${theme.fg("success", "✓ ")}${theme.fg("muted", "(empty response)")}`, 0, 0);
			}
			return new Text(answers.map((answer) => `${theme.fg("success", "✓ ")}${renderPart(answer)}`).join("\n"), 0, 0);
		},
	});
}

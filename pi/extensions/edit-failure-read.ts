/**
 * edit-failure-read.ts — append the target file's current contents to a
 * failed `edit` result so the model can retry without a read round-trip.
 * Capped like the read tool; missing/binary targets skipped silently.
 * The renderer wrapper draws the appended contents inside the edit tool's
 * error-styled block instead of loose red text below it.
 */
import type { ExtensionAPI, Theme, ToolRenderers } from "@earendil-works/pi-coding-agent";
import { Box, Container, Text } from "@earendil-works/pi-tui";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";

const MAX_LINES = 2000;
const MAX_BYTES = 50 * 1024;
const COLLAPSED_PREVIEW_LINES = 10;

/** Identifies the appended block so the renderer can split it from the tool's own error text. */
const CURRENT_CONTENTS_PREFIX = "Current contents of ";

export default function (pi: ExtensionAPI) {
	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "edit" || !event.isError) return;
		const rel = (event.input as { path?: unknown }).path;
		if (typeof rel !== "string" || rel.length === 0) return;
		const abs = isAbsolute(rel) ? rel : resolve(ctx.cwd, rel);
		if (!existsSync(abs)) return;

		let raw: string;
		try {
			raw = readFileSync(abs, "utf8");
		} catch {
			return;
		}
		if (raw.slice(0, 8192).includes("\0")) return;

		const lines = raw.split("\n");
		const kept: string[] = [];
		let bytes = 0;
		for (const line of lines) {
			const cost = Buffer.byteLength(line, "utf8") + 1;
			if (kept.length >= MAX_LINES || bytes + cost > MAX_BYTES) break;
			kept.push(line);
			bytes += cost;
		}

		const note =
			kept.length < lines.length
				? `\n[Truncated — showing ${kept.length} of ${lines.length} lines. Use read (offset/limit) for the rest.]`
				: "";
		return {
			content: [
				...event.content,
				{
					type: "text" as const,
					text: `${CURRENT_CONTENTS_PREFIX}${abs}:\n\n${kept.join("\n")}${note}`,
				},
			],
		};
	});

	pi.registerToolRenderer((toolName, next) => {
		if (toolName !== "edit") return next();
		const base = next();
		const baseRenderResult = base?.renderResult;
		if (!base) return undefined;
		if (!baseRenderResult) return base;
		return {
			...base,
			renderResult(result, options, theme, context) {
				const contentsBlock = result.content.find(contentsBlockPredicate);
				// Fresh lastComponent: the base renderer clears and refills whatever it is given.
				const delegateContext = { ...context, lastComponent: undefined };
				if (contentsBlock === undefined || !context.isError) {
					return baseRenderResult(result, options, theme, delegateContext);
				}
				const withoutContents = {
					...result,
					content: result.content.filter((block) => block !== contentsBlock),
				};
				const container = new Container();
				container.addChild(baseRenderResult(withoutContents, options, theme, delegateContext));
				container.addChild(contentsBox(contentsBlock.text, theme, context.outputPad, context.expanded));
				return container;
			},
		};
	});
}

function contentsBlockPredicate(
	block: (TextBlock | ImageBlock),
): block is TextBlock {
	return block.type === "text" && block.text.startsWith(CURRENT_CONTENTS_PREFIX);
}

type TextBlock = { type: "text"; text: string };
type ImageBlock = { type: "image" };

function contentsBox(
	blockText: string,
	theme: Theme,
	outputPad: number,
	expanded: boolean,
): Box {
	const labelEnd = blockText.indexOf("\n");
	const path = blockText
		.slice(CURRENT_CONTENTS_PREFIX.length, labelEnd === -1 ? undefined : labelEnd)
		.replace(/:$/, "");
	let lines = blockText.slice(labelEnd + 1).split("\n");
	if (lines[0] === "") lines.shift();
	const note = lines.at(-1)?.startsWith("[Truncated") ? lines.pop() : undefined;

	const shown = expanded ? lines : lines.slice(0, COLLAPSED_PREVIEW_LINES);
	const hidden = lines.length - shown.length;
	const parts = [theme.fg("muted", `${CURRENT_CONTENTS_PREFIX}${shortenHome(path)}:`), ""];
	for (const line of shown) {
		parts.push(theme.fg("toolOutput", stripAnsi(line.replace(/\t/g, "   "))));
	}
	if (hidden > 0) parts.push(theme.fg("muted", `... (${hidden} more lines)`));
	if (note) parts.push(theme.fg("muted", note));

	// Same bg and padding as the edit header box so the two read as one block.
	const box = new Box(outputPad, 1, (text) => theme.bg("toolErrorBg", text));
	box.addChild(new Text(parts.join("\n"), 0, 0));
	return box;
}

function shortenHome(path: string): string {
	const home = homedir();
	if (path === home) return "~";
	return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

function stripAnsi(text: string): string {
	return text.replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "");
}

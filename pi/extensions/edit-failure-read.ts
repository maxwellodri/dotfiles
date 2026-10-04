/**
 * edit-failure-read.ts — append the target file's current contents to a
 * failed `edit` result so the model can retry without a read round-trip.
 * Capped like the read tool; missing/binary targets skipped silently.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

const MAX_LINES = 2000;
const MAX_BYTES = 50 * 1024;

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
					text: `Current contents of ${abs}:\n\n${kept.join("\n")}${note}`,
				},
			],
		};
	});
}

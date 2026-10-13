/**
 * update-notice.ts — cooldown-aware replacement for pi's built-in
 * "Update Available" card, firing only when install_flake.sh --update would
 * actually bump pi: the newest plain x.y.z release newer than the running
 * version must be published at least npm_config_min_release_age days ago
 * AND ship the npm-shrinkwrap.json the nix package pins deps from — the
 * script stays put on releases without one, so the notice must too.
 * Cooldown exceptions in install_flake.sh aren't mirrored; they only apply
 * during deliberate early adoption. The built-in check (which carries no
 * publish date) is disabled by the wrapper (PI_SKIP_VERSION_CHECK).
 * Shrinkwrap verdicts are cached per version — a published tarball never
 * changes.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { VERSION } from "@earendil-works/pi-coding-agent";
import { gunzipSync } from "node:zlib";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

const PACKUMENT_URL = "https://registry.npmjs.org/@earendil-works/pi-coding-agent";
const FETCH_TIMEOUT_MS = 8_000;
const TARBALL_TIMEOUT_MS = 20_000;
const DEFAULT_COOLDOWN_DAYS = 7;
const PLAIN_SEMVER = /^\d+\.\d+\.\d+$/;
const SHRINKWRAP_MEMBER = "package/npm-shrinkwrap.json";

interface Packument {
	time: Record<string, string>;
	versions?: Record<string, { dist?: { tarball?: string } }>;
}

function compareSemver(a: string, b: string): number {
	const [a1, a2, a3] = a.split(".").map(Number);
	const [b1, b2, b3] = b.split(".").map(Number);
	return a1 - b1 || a2 - b2 || a3 - b3;
}

function cooldownDays(): number {
	const parsed = Number(process.env.npm_config_min_release_age);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_COOLDOWN_DAYS;
}

async function fetchPackument(): Promise<Packument> {
	const response = await fetch(PACKUMENT_URL, {
		headers: { accept: "application/json" },
		signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
	});
	if (!response.ok) throw new Error(`registry ${response.status}`);
	return (await response.json()) as Packument;
}

/** Newest plain release newer than VERSION and past the cooldown, if any. */
export function eligibleUpdate(packument: Packument, now: Date): string | undefined {
	const cutoff = now.getTime() - cooldownDays() * 86_400_000;
	let best: string | undefined;
	for (const [version, published] of Object.entries(packument.time)) {
		if (!PLAIN_SEMVER.test(version)) continue;
		if (compareSemver(version, VERSION) <= 0) continue;
		const age = Date.parse(published);
		if (!Number.isFinite(age) || age > cutoff) continue;
		if (best === undefined || compareSemver(version, best) > 0) best = version;
	}
	return best;
}

function cacheFile(): string {
	const base = process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache");
	return join(base, "pi", "update-notice.json");
}

function readVerdicts(): Record<string, boolean> {
	try {
		const parsed = JSON.parse(readFileSync(cacheFile(), "utf8")) as unknown;
		return parsed && typeof parsed === "object" ? (parsed as Record<string, boolean>) : {};
	} catch {
		return {};
	}
}

function writeVerdict(version: string, ships: boolean): void {
	try {
		const file = cacheFile();
		const verdicts = readVerdicts();
		verdicts[version] = ships;
		mkdirSync(dirname(file), { recursive: true });
		writeFileSync(`${file}.tmp`, JSON.stringify(verdicts));
		renameSync(`${file}.tmp`, file);
	} catch {
		/* unwritable cache — recheck next session */
	}
}

/** Ustar walk; null = malformed archive (don't cache the verdict). */
export function tarHasMember(gz: ArrayBuffer, member: string): boolean | null {
	let tar: Buffer;
	try {
		tar = gunzipSync(Buffer.from(gz));
	} catch {
		return null;
	}
	for (let off = 0; off + 512 <= tar.length; ) {
		const header = tar.subarray(off, off + 512);
		const name = header.subarray(0, 100).toString("utf8").replace(/\0[\s\S]*$/, "");
		if (name === "") return false; // end-of-archive marker
		const sizeField = header.subarray(124, 136).toString("ascii").replace(/\0[\s\S]*$/, "").trim();
		if (!/^[0-7]*$/.test(sizeField)) return null;
		const size = parseInt(sizeField, 8) || 0;
		const dataStart = off + 512;
		if (dataStart + size > tar.length) return null;
		const type = String.fromCharCode(header[156]);
		if ((type === "0" || type === "\0") && name === member) return true;
		off = dataStart + Math.ceil(size / 512) * 512;
	}
	return null; // no end marker before EOF
}

export async function shipsShrinkwrap(packument: Packument, version: string): Promise<boolean | null> {
	const cached = readVerdicts()[version];
	if (cached !== undefined) return cached;
	const url =
		packument.versions?.[version]?.dist?.tarball ??
		`${PACKUMENT_URL}/-/pi-coding-agent-${version}.tgz`;
	const response = await fetch(url, { signal: AbortSignal.timeout(TARBALL_TIMEOUT_MS) });
	if (!response.ok) return null;
	const verdict = tarHasMember(await response.arrayBuffer(), SHRINKWRAP_MEMBER);
	if (verdict !== null) writeVerdict(version, verdict);
	return verdict;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui" || process.env.PI_OFFLINE) return;

		void fetchPackument()
			.then(async (packument) => {
				const version = eligibleUpdate(packument, new Date());
				if (version === undefined) return;
				if ((await shipsShrinkwrap(packument, version)) !== true) return;

				ctx.ui.notify(`Update Available\nNew version ${version} is available.`, "warning");
			})
			.catch(() => {
				/* offline or registry hiccup — no notice */
			});
	});
}

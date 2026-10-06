/**
 * update-notice.ts — cooldown-aware replacement for pi's built-in
 * "Update Available" card. The built-in check (pi.dev/api/latest-version)
 * carries no publish date, so it advertises releases the npm supply-chain
 * cooldown hasn't cleared; the pi wrapper disables it (PI_SKIP_VERSION_CHECK)
 * and this re-adds the notice from the registry's .time map. Eligible =
 * plain x.y.z, newer than the running version, published at least
 * npm_config_min_release_age days ago (same env the wrapper exports for
 * install_flake.sh's cooldown).
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { VERSION } from "@earendil-works/pi-coding-agent";

const PACKUMENT_URL = "https://registry.npmjs.org/@earendil-works/pi-coding-agent";
const FETCH_TIMEOUT_MS = 8_000;
const DEFAULT_COOLDOWN_DAYS = 7;
const PLAIN_SEMVER = /^\d+\.\d+\.\d+$/;

interface Packument {
	time: Record<string, string>;
	"dist-tags"?: Record<string, string>;
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
function eligibleUpdate(packument: Packument, now: Date): string | undefined {
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

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui" || process.env.PI_OFFLINE) return;

		void fetchPackument()
			.then((packument) => {
				const version = eligibleUpdate(packument, new Date());
				if (version === undefined) return;

				const latest = packument["dist-tags"]?.latest;
				const cooling =
					latest !== undefined && PLAIN_SEMVER.test(latest) && compareSemver(latest, version) > 0
						? `\n(latest ${latest} is still inside the ${cooldownDays()}-day npm cooldown)`
						: "";

				ctx.ui.notify(
					`Update Available\nNew version ${version} is available. Run scripts/install_flake.sh --update\nChangelog: https://pi.dev/changelog${cooling}`,
					"warning",
				);
			})
			.catch(() => {
				/* offline or registry hiccup — no notice */
			});
	});
}

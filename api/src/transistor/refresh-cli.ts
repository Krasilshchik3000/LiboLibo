// Standalone CLI: `npm run refresh [-- --podcast-id <id> ...]`.
// Useful locally for one-shot refresh; supports limiting to specific podcasts.
import { refreshAllFeeds } from "./refresh.js";

const onlyPodcastIds: bigint[] = [];
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--podcast-id" && i + 1 < argv.length) {
    const raw = argv[++i]!;
    try {
      onlyPodcastIds.push(BigInt(raw));
    } catch {
      console.error(`invalid --podcast-id: ${raw}`);
      process.exit(1);
    }
  }
}

(async () => {
  const summary = await refreshAllFeeds(
    onlyPodcastIds.length > 0 ? { onlyPodcastIds } : {},
  );
  console.log(JSON.stringify(
    summary,
    (_k, v) => (typeof v === "bigint" ? v.toString() : v),
    2,
  ));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

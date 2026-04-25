// Standalone CLI: `npm run refresh`. Useful locally for one-shot refresh.
import { refreshAllFeeds } from "./refresh.js";

(async () => {
  const summary = await refreshAllFeeds();
  console.log(JSON.stringify(summary, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

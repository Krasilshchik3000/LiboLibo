// Standalone CLI: `npm run refresh:instagram`. Used by Railway Cron Service
// that runs every 30 minutes (configured separately in Railway UI as a cron
// service pointing at the same repo, command `npm run refresh:instagram`).
import { syncInstagramPosts } from "./collector.js";

(async () => {
  const summary = await syncInstagramPosts();
  console.log(JSON.stringify(summary, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

// Standalone CLI: `npm run refresh:instagram`. Used by Railway Cron Service
// that runs every 30 minutes (configured separately in Railway UI as a cron
// service pointing at the same repo, command `npm run refresh:instagram`).
//
// Phase A — sync metadata (instagram_posts).
// Phase B — download media files for posts that don't have them yet
//          (instagram_media).
import { syncInstagramPosts } from "./collector.js";
import { downloadPendingMedia } from "./media-downloader.js";

(async () => {
  const sync = await syncInstagramPosts();
  const download = await downloadPendingMedia();
  console.log(JSON.stringify({ sync, download }, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

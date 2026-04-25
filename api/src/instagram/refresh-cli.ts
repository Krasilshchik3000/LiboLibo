// Standalone CLI: `npm run refresh:instagram`. Используется Railway Cron Service.
//
// Двa режима:
//
// 1. **Remote** (используется на Railway): если установлены
//    INTERNAL_REFRESH_URL + INTERNAL_TOKEN — CLI делает POST на этот URL
//    в LiboLibo-сервис, который сам выполняет sync+download (потому что
//    Railway volume с медиа смонтирован только в LiboLibo).
//
// 2. **Local** (для локальной отладки): если переменных нет — CLI вызывает
//    syncInstagramPosts + downloadPendingMedia в текущем процессе. Удобно
//    при запуске на dev-машине, где нет split-сервисной конфигурации.

import { syncInstagramPosts } from "./collector.js";
import { downloadPendingMedia } from "./media-downloader.js";

const url = process.env.INTERNAL_REFRESH_URL;
const token = process.env.INTERNAL_TOKEN;

(async () => {
  if (url && token) {
    const resp = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!resp.ok) {
      throw new Error(`POST ${url} → HTTP ${resp.status}`);
    }
    const body = await resp.text();
    console.log(`triggered ${url} → ${resp.status}: ${body}`);
    process.exit(0);
  }

  // Local fallback.
  const sync = await syncInstagramPosts();
  const download = await downloadPendingMedia();
  console.log(JSON.stringify({ sync, download }, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});

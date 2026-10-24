// Single entrypoint: starts a Node HTTP server. Used by `npm run dev` locally,
// by Docker Compose, and by Railway in production (Dockerfile CMD).

import { createApp } from "./app.js";
import { warmupModel } from "./lib/semanticSearch.js";

const port = Number(process.env.PORT ?? 3000);
const app = createApp();

app.listen(port, () => {
  console.log(`libolibo-api: слушаю http://localhost:${port}`);
});

// Прогрев e5-модели в фоне: не блокирует listen и healthcheck, но к первому
// поисковому запросу модель уже готова. Ошибка не валит сервер — ручка
// семантики отдаст 503, остальное API работает.
warmupModel().catch((err) => {
  console.error("[server] semantic model warmup failed (non-fatal):", err);
});

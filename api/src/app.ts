import express, { type ErrorRequestHandler } from "express";
import { healthRouter } from "./routes/health.js";
import { podcastsRouter } from "./routes/podcasts.js";
import { feedRouter } from "./routes/feed.js";
import { episodesRouter } from "./routes/episodes.js";
import { devicesRouter } from "./routes/devices.js";
import { meRouter } from "./routes/me.js";
import { legalRouter } from "./routes/legal.js";
import { mediaRouter } from "./routes/media.js";
import { feedInstagramRouter } from "./routes/feed-instagram.js";
import { adminRouter } from "./admin/router.js";
import { internalRouter } from "./routes/internal.js";

export function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));

  // Lightweight access log: METHOD path → status (durMs).
  app.use((req, res, next) => {
    const started = Date.now();
    res.on("finish", () => {
      console.log(
        `${req.method} ${req.originalUrl} → ${res.statusCode} (${Date.now() - started}ms)`,
      );
    });
    next();
  });

  // Public API.
  app.use("/v1", healthRouter);
  app.use("/v1", podcastsRouter);
  app.use("/v1", feedRouter);
  app.use("/v1", episodesRouter);
  app.use("/v1", devicesRouter);
  app.use("/v1", meRouter);
  app.use("/v1", feedInstagramRouter);

  // Web-админка модерации Instagram-ленты (Phase 3.C). HTTP Basic Auth,
  // server-rendered EJS. Креды в env: ADMIN_USER, ADMIN_PASSWORD.
  app.use("/admin", adminRouter);

  // Internal endpoints (cron-сервис Railway дёргает sync+download через них,
  // потому что Railway volumes нельзя монтировать в два сервиса; volume на
  // LiboLibo, фактическую работу тоже делает LiboLibo).
  app.use("/internal", internalRouter);

  // Раздача Instagram-медиа (Phase 3.B). Файлы лежат на Railway volume.
  app.use("/media", mediaRouter);

  // Legal pages — served at the root, не под /v1, чтобы URL были короткие
  // и удобные для App Store / In-App-листинга.
  app.use(legalRouter);

  // На Railway фид обновляется отдельным Cron Service, который запускает
  // `npm run refresh` (см. docs/specs/step-02-backend.md и api/README.md).
  // HTTP-эндпоинта для cron здесь нет.

  app.use((req, res) => {
    res.status(404).json({ error: "not_found", path: req.originalUrl });
  });

  const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
    console.error("[error]", err);
    res.status(500).json({
      error: "internal",
      message: err instanceof Error ? err.message : String(err),
    });
  };
  app.use(errorHandler);

  return app;
}

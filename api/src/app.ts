import express, { type ErrorRequestHandler } from "express";
import { healthRouter } from "./routes/health.js";
import { podcastsRouter } from "./routes/podcasts.js";
import { feedRouter } from "./routes/feed.js";
import { episodesRouter } from "./routes/episodes.js";
import { devicesRouter } from "./routes/devices.js";
import { meRouter } from "./routes/me.js";

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

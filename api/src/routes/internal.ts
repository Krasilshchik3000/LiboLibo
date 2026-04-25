// Internal-only endpoints. Защищены через bearer-токен из env
// (INTERNAL_TOKEN). Используются Cron-сервисами Railway, у которых
// нет доступа к volume с медиа: они дёргают этот endpoint, а сам
// LiboLibo-процесс (с примонтированным volume) делает работу.

import { Router } from "express";
import { syncInstagramPosts } from "../instagram/collector.js";
import { downloadPendingMedia } from "../instagram/media-downloader.js";

export const internalRouter = Router();

internalRouter.use((req, res, next) => {
  const expected = process.env.INTERNAL_TOKEN;
  if (!expected) {
    res.status(503).type("text/plain").send("internal disabled: INTERNAL_TOKEN not set");
    return;
  }
  const auth = req.header("authorization") ?? "";
  const presented = auth.startsWith("Bearer ") ? auth.slice("Bearer ".length) : "";
  if (presented !== expected) {
    res.status(401).type("text/plain").send("unauthorized");
    return;
  }
  next();
});

internalRouter.post("/refresh-instagram", async (_req, res) => {
  // Fire-and-forget: отвечаем сразу, чтобы cron-сервис не висел до окончания
  // загрузки медиа (она занимает 30-90 секунд для 30 постов).
  res.status(202).json({ accepted: true });

  try {
    const sync = await syncInstagramPosts();
    const download = await downloadPendingMedia();
    console.log("[refresh-instagram]", JSON.stringify({ sync, download }));
  } catch (err) {
    console.error("[refresh-instagram]", err);
  }
});

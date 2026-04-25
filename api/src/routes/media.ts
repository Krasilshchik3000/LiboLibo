// Раздача скачанных Instagram-медиа из MEDIA_DIR. Имена файлов
// неизменяемы (post-id + order), поэтому agressive-кеш безопасен.
//
// `express.static` сам выставит правильный Content-Type (image/jpeg,
// video/mp4), 404 на ненайденный путь и 304 по If-Modified-Since.

import { Router } from "express";
import express from "express";
import { getMediaDir } from "../instagram/config.js";

export const mediaRouter = Router();

mediaRouter.use(
  express.static(getMediaDir(), {
    maxAge: "1y",
    immutable: true,
    fallthrough: false,
  }),
);

import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import { episodeToDTO } from "../lib/serialize.js";
import { resolveViewer } from "../middleware/viewer.js";
import {
  ensureIndexed,
  semanticSearch,
  indexSize,
} from "../lib/semanticSearch.js";

export const searchRouter = Router();

const MAX_QUERY_LEN = 200;
const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
// Порог косинусной близости. Ниже него выдача — шум: e5 для русского даёт
// ~0.78+ на релевантных парах, поэтому 0.75 отсекает явно мимо. Значение
// подобрано на корпусе Либо-Либо; вынесено в env на случай тюнинга без
// передеплоя кода.
const MIN_SCORE = Number(process.env.SEMANTIC_MIN_SCORE ?? "0.75");

interface SemanticBody {
  query?: unknown;
  limit?: unknown;
}

// POST /v1/search/semantic — семантический поиск по выпускам всех подкастов.
// Дополняет (не заменяет) текстовый поиск iOS-клиента: находит выпуски по
// смыслу запроса, даже если точных слов нет в title/summary.
//
// Тело: { "query": "как пережить расставание", "limit": 20 }
// Ответ: { "items": EpisodeDTO[] } — тот же формат, что /v1/feed, чтобы
// клиент переиспользовал существующую модель Episode и рендер ячеек.
//
// Если модель ещё не готова (не скачалась/пакет не установлен) — 503, и
// клиент откатывается на обычный текстовый поиск.
searchRouter.post(
  "/search/semantic",
  resolveViewer,
  asyncHandler(async (req, res) => {
    const body = (req.body ?? {}) as SemanticBody;

    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (query.length === 0) {
      return res.status(400).json({ error: "missing_query" });
    }
    if (query.length > MAX_QUERY_LEN) {
      return res.status(400).json({ error: "query_too_long" });
    }

    const limit = clampLimit(body.limit);

    // Кандидаты для индекса: все эпизоды с непустым summary/title. Тянем
    // минимум полей — id/title/summary хватает для эмбеддинга.
    const forIndex = await prisma.episode.findMany({
      select: { id: true, title: true, summary: true },
    });

    try {
      await ensureIndexed(
        forIndex.map((e) => ({
          id: e.id,
          title: e.title,
          summary: e.summary ?? "",
        })),
      );
    } catch (err) {
      // Модель недоступна (не установлен пакет, не скачалась модель и т.п.).
      // Не валим запрос 500-кой — отдаём 503, клиент знает, что нужно
      // откатиться на текстовый поиск.
      console.error("[search/semantic] model unavailable:", err);
      return res.status(503).json({ error: "semantic_unavailable" });
    }

    const hits = await semanticSearch(query, { limit, minScore: MIN_SCORE });
    if (hits.length === 0) {
      return res.json({ items: [] });
    }

    // Дотягиваем полные эпизоды из БД и сериализуем как везде, сохраняя
    // порядок ранжирования (Prisma вернёт в произвольном порядке).
    const ids = hits.map((h) => h.episodeId);
    const episodes = await prisma.episode.findMany({
      where: { id: { in: ids } },
      include: { podcast: { select: { name: true, artworkUrl: true } } },
    });
    const byId = new Map(episodes.map((e) => [e.id, e]));

    const items = hits
      .map((h) => byId.get(h.episodeId))
      .filter((e): e is NonNullable<typeof e> => e != null)
      .map((e) => episodeToDTO(e, e.podcast, req.viewer));

    res.json({ items });
  }),
);

// GET /v1/search/semantic/status — небольшая диагностика: готова ли модель и
// сколько эпизодов проиндексировано. Удобно для health-проверки фичи на
// проде и для отладки на стриме.
searchRouter.get(
  "/search/semantic/status",
  asyncHandler(async (_req, res) => {
    res.json({ indexed: indexSize() });
  }),
);

function clampLimit(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return DEFAULT_LIMIT;
  return Math.min(Math.floor(n), MAX_LIMIT);
}

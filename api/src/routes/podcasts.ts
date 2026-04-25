import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import { podcastToDTO, episodeToDTO } from "../lib/serialize.js";
import { decodeCursor, encodeCursor, parseLimit } from "../lib/cursor.js";
import { resolveViewer } from "../middleware/viewer.js";

export const podcastsRouter = Router();

podcastsRouter.get(
  "/podcasts",
  asyncHandler(async (_req, res) => {
    const items = await prisma.podcast.findMany({
      orderBy: { name: "asc" },
    });
    res.json({ items: items.map(podcastToDTO) });
  }),
);

podcastsRouter.get(
  "/podcasts/:id",
  asyncHandler(async (req, res) => {
    const id = parsePodcastId(asString(req.params.id));
    if (id === null) return res.status(404).json({ error: "not_found" });

    const podcast = await prisma.podcast.findUnique({ where: { id } });
    if (!podcast) return res.status(404).json({ error: "not_found" });

    res.json(podcastToDTO(podcast));
  }),
);

podcastsRouter.get(
  "/podcasts/:id/episodes",
  resolveViewer,
  asyncHandler(async (req, res) => {
    const id = parsePodcastId(asString(req.params.id));
    if (id === null) return res.status(404).json({ error: "not_found" });

    const podcast = await prisma.podcast.findUnique({ where: { id } });
    if (!podcast) return res.status(404).json({ error: "not_found" });

    const limit = parseLimit(req.query.limit);
    const cursor = decodeCursor(asString(req.query.cursor));

    const episodes = await prisma.episode.findMany({
      where: {
        podcastId: id,
        ...(cursor && {
          OR: [
            { pubDate: { lt: new Date(cursor.ts) } },
            { pubDate: new Date(cursor.ts), id: { lt: cursor.id } },
          ],
        }),
      },
      orderBy: [{ pubDate: "desc" }, { id: "desc" }],
      take: limit + 1,
    });

    const hasMore = episodes.length > limit;
    const page = episodes.slice(0, limit);
    const last = page[page.length - 1];

    res.json({
      items: page.map((e) => episodeToDTO(e, podcast, req.viewer)),
      next_cursor:
        hasMore && last
          ? encodeCursor({ ts: last.pubDate.toISOString(), id: last.id })
          : null,
    });
  }),
);

function parsePodcastId(raw: string | undefined): bigint | null {
  if (!raw) return null;
  try {
    const n = BigInt(raw);
    return n > 0n ? n : null;
  } catch {
    return null;
  }
}

function asString(v: unknown): string | undefined {
  return typeof v === "string" ? v : undefined;
}

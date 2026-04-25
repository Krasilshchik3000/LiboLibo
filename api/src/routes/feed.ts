import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import { episodeToDTO } from "../lib/serialize.js";
import { decodeCursor, encodeCursor, parseLimit } from "../lib/cursor.js";
import { resolveViewer } from "../middleware/viewer.js";

export const feedRouter = Router();

feedRouter.get(
  "/feed",
  resolveViewer,
  asyncHandler(async (req, res) => {
    const limit = parseLimit(req.query.limit);
    const cursor = decodeCursor(
      typeof req.query.cursor === "string" ? req.query.cursor : undefined,
    );

    const episodes = await prisma.episode.findMany({
      where: cursor
        ? {
            OR: [
              { pubDate: { lt: new Date(cursor.ts) } },
              { pubDate: new Date(cursor.ts), id: { lt: cursor.id } },
            ],
          }
        : undefined,
      orderBy: [{ pubDate: "desc" }, { id: "desc" }],
      take: limit + 1,
      include: { podcast: { select: { name: true, artworkUrl: true } } },
    });

    const hasMore = episodes.length > limit;
    const page = episodes.slice(0, limit);
    const last = page[page.length - 1];

    res.json({
      items: page.map((e) => episodeToDTO(e, e.podcast, req.viewer)),
      next_cursor:
        hasMore && last
          ? encodeCursor({ ts: last.pubDate.toISOString(), id: last.id })
          : null,
    });
  }),
);

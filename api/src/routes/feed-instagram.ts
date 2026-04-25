// Public Instagram feed endpoint for the iOS client.
// Returns only `status=PUBLISHED` posts ordered by publishedAt DESC.

import { Router } from "express";
import { prisma } from "../db.js";
import { encodeCursor, decodeCursor, parseLimit } from "../lib/cursor.js";
import { serializeInstagramPost, type InstagramPostRow } from "../lib/instagram-feed-serialize.js";
import { asyncHandler } from "../lib/asyncHandler.js";

export const feedInstagramRouter = Router();

const MEDIA_BASE_URL = process.env.MEDIA_BASE_URL ?? "/media";

feedInstagramRouter.get(
  "/feed/instagram",
  asyncHandler(async (req, res) => {
    const limit = parseLimit(req.query.limit, 20, 50);
    const cursor = decodeCursor(typeof req.query.cursor === "string" ? req.query.cursor : undefined);

    const posts = await prisma.instagramPost.findMany({
      where: {
        status: "PUBLISHED",
        ...(cursor
          ? {
              OR: [
                { publishedAt: { lt: new Date(cursor.ts) } },
                { publishedAt: new Date(cursor.ts), id: { lt: cursor.id } },
              ],
            }
          : {}),
      },
      orderBy: [{ publishedAt: "desc" }, { id: "desc" }],
      take: limit + 1,
      include: {
        media: { orderBy: { order: "asc" } },
        ctaEpisode: { select: { id: true, title: true, podcastId: true } },
        ctaPodcast: { select: { id: true, name: true } },
      },
    });

    const hasMore = posts.length > limit;
    const page = hasMore ? posts.slice(0, limit) : posts;

    const items = page.map((p) =>
      serializeInstagramPost(p as InstagramPostRow, { mediaBaseUrl: MEDIA_BASE_URL }),
    );

    let nextCursor: string | null = null;
    if (hasMore) {
      const last = page[page.length - 1]!;
      if (last.publishedAt) {
        nextCursor = encodeCursor({ ts: last.publishedAt.toISOString(), id: last.id });
      }
    }

    res.json({ items, nextCursor });
  }),
);

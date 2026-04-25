import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";

export const commentsRouter = Router();

commentsRouter.get(
  "/episodes/:episodeId/comments",
  asyncHandler(async (req, res) => {
    const episodeId = req.params.episodeId;
    if (typeof episodeId !== "string" || episodeId.length === 0) {
      return res.status(404).json({ error: "episode_not_found" });
    }
    const rows = await prisma.comment.findMany({
      where: { episodeId },
      include: { author: true },
      orderBy: [{ timecodeSec: "asc" }, { createdAt: "asc" }],
      take: 1000,
    });
    const baseUrl = `${req.protocol}://${req.get("host")}`;
    res.json({
      items: rows.map((c) => ({
        id: c.id,
        author: { birdName: c.author.displayName },
        transcript: c.transcript,
        timecodeSec: c.timecodeSec,
        durationSec: c.audioDurationSec,
        audioUrl: `${baseUrl}/v1/comments/${c.id}/audio`,
        createdAt: c.createdAt.toISOString(),
      })),
    });
  }),
);

import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import { episodeToDTO } from "../lib/serialize.js";
import { resolveViewer } from "../middleware/viewer.js";

export const episodesRouter = Router();

episodesRouter.get(
  "/episodes/:id",
  resolveViewer,
  asyncHandler(async (req, res) => {
    const rawId = req.params.id;
    if (typeof rawId !== "string" || rawId.length === 0) {
      return res.status(404).json({ error: "not_found" });
    }

    const episode = await prisma.episode.findUnique({
      where: { id: rawId },
      include: { podcast: { select: { name: true, artworkUrl: true } } },
    });
    if (!episode) return res.status(404).json({ error: "not_found" });

    res.json(episodeToDTO(episode, episode.podcast, req.viewer));
  }),
);

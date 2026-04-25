// Простой server-rendered admin для модерации Instagram-ленты.
// HTTP Basic Auth, EJS-шаблоны, без SPA. Single editor сценарий.

import { Router } from "express";
import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { prisma } from "../db.js";
import { basicAuth } from "./auth.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const VIEWS_DIR = path.join(__dirname, "views");

export const adminRouter = Router();

adminRouter.use(basicAuth);
adminRouter.use(express.urlencoded({ extended: false }));

adminRouter.get("/", (_req, res) => {
  res.redirect("/admin/posts?status=pending");
});

adminRouter.get("/posts", async (req, res) => {
  const status = parseStatus(req.query.status);
  const posts = await prisma.instagramPost.findMany({
    where: status ? { status } : undefined,
    orderBy: { igCreatedAt: "desc" },
    take: 60,
    include: {
      media: {
        where: { order: 0 },
        select: { kind: true, filePath: true, thumbnailPath: true },
        take: 1,
      },
    },
  });

  const counts = await prisma.instagramPost.groupBy({ by: ["status"], _count: true });
  const countsByStatus: Record<"pending" | "published" | "hidden" | "all", number> = {
    pending: 0,
    published: 0,
    hidden: 0,
    all: 0,
  };
  for (const c of counts) {
    const k = c.status.toLowerCase() as "pending" | "published" | "hidden";
    countsByStatus[k] = c._count;
    countsByStatus.all = countsByStatus.all + c._count;
  }

  const enriched = posts.map((p) => ({
    ...p,
    thumbnailUrl: thumbnailUrlFor(p.media[0]),
  }));

  res.render(path.join(VIEWS_DIR, "layout.ejs"), {
    title: `Список постов (${status ?? "all"})`,
    body: await renderPartial("list.ejs", {
      posts: enriched,
      currentStatus: req.query.status ?? "all",
      counts: countsByStatus,
    }),
  });
});

adminRouter.get("/posts/:id", async (req, res) => {
  const post = await prisma.instagramPost.findUnique({
    where: { id: req.params.id },
    include: { media: { orderBy: { order: "asc" } } },
  });
  if (!post) {
    res.status(404).type("text/plain").send("post not found");
    return;
  }

  const [episodes, podcasts] = await Promise.all([
    prisma.episode.findMany({
      orderBy: { pubDate: "desc" },
      take: 200,
      select: { id: true, title: true },
    }),
    prisma.podcast.findMany({
      orderBy: { name: "asc" },
      select: { id: true, name: true },
    }),
  ]);

  const media = post.media.map((m) => ({
    kind: m.kind,
    url: `/media/${m.filePath}`,
    thumbnailUrl: m.thumbnailPath ? `/media/${m.thumbnailPath}` : null,
  }));

  res.render(path.join(VIEWS_DIR, "layout.ejs"), {
    title: `Пост ${post.igMediaId}`,
    body: await renderPartial("detail.ejs", {
      post: {
        ...post,
        ctaPodcastId: post.ctaPodcastId?.toString() ?? null,
      },
      media,
      episodes,
      podcasts: podcasts.map((p) => ({ id: p.id.toString(), name: p.name })),
    }),
  });
});

adminRouter.post("/posts/:id", async (req, res) => {
  const action = String(req.body.action ?? "");
  const ctaType = String(req.body.cta_type ?? "none");

  const data: {
    status?: "PENDING" | "PUBLISHED" | "HIDDEN";
    publishedAt?: Date | null;
    ctaType?: "EPISODE" | "PODCAST" | "LINK" | null;
    ctaEpisodeId?: string | null;
    ctaPodcastId?: bigint | null;
    ctaUrl?: string | null;
    ctaLabel?: string | null;
  } = {};

  switch (ctaType) {
    case "episode":
      data.ctaType = "EPISODE";
      data.ctaEpisodeId = stringOrNull(req.body.cta_episode_id);
      data.ctaPodcastId = null;
      data.ctaUrl = null;
      break;
    case "podcast":
      data.ctaType = "PODCAST";
      data.ctaEpisodeId = null;
      data.ctaPodcastId = bigintOrNull(req.body.cta_podcast_id);
      data.ctaUrl = null;
      break;
    case "link":
      data.ctaType = "LINK";
      data.ctaEpisodeId = null;
      data.ctaPodcastId = null;
      data.ctaUrl = stringOrNull(req.body.cta_url);
      break;
    case "none":
    default:
      data.ctaType = null;
      data.ctaEpisodeId = null;
      data.ctaPodcastId = null;
      data.ctaUrl = null;
      break;
  }
  data.ctaLabel = stringOrNull(req.body.cta_label);

  switch (action) {
    case "publish":
      data.status = "PUBLISHED";
      data.publishedAt = new Date();
      break;
    case "hide":
      data.status = "HIDDEN";
      data.publishedAt = null;
      break;
    case "save_draft":
      // status/publishedAt не трогаем
      break;
    default:
      res.status(400).type("text/plain").send(`unknown action: ${action}`);
      return;
  }

  await prisma.instagramPost.update({
    where: { id: req.params.id },
    data,
  });

  res.redirect(`/admin/posts/${req.params.id}`);
});

function parseStatus(raw: unknown): "PENDING" | "PUBLISHED" | "HIDDEN" | undefined {
  if (raw === "pending") return "PENDING";
  if (raw === "published") return "PUBLISHED";
  if (raw === "hidden") return "HIDDEN";
  return undefined;
}

function thumbnailUrlFor(
  m?: { kind: "IMAGE" | "VIDEO"; filePath: string; thumbnailPath: string | null },
): string | null {
  if (!m) return null;
  if (m.kind === "IMAGE") return `/media/${m.filePath}`;
  return m.thumbnailPath ? `/media/${m.thumbnailPath}` : null;
}

function stringOrNull(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t;
}

function bigintOrNull(v: unknown): bigint | null {
  const s = stringOrNull(v);
  if (!s) return null;
  try {
    return BigInt(s);
  } catch {
    return null;
  }
}

async function renderPartial(file: string, locals: Record<string, unknown>): Promise<string> {
  const ejs = await import("ejs");
  return ejs.default.renderFile(path.join(VIEWS_DIR, file), locals, { async: false });
}

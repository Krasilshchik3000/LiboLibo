// Instagram post collector. Pulls the latest media via Graph API and upserts
// rows into the `instagram_posts` table by `igMediaId`. NO media files are
// downloaded here — that's Phase B (media-downloader). Idempotent: safe to
// run repeatedly, only `caption` and `igPermalink` get refreshed for known posts.

import { prisma } from "../db.js";
import { isConfigured, readConfig } from "./config.js";
import { listRecentMedia, type IgMediaSummary } from "./graph-client.js";

export type IgPostType = "IMAGE" | "CAROUSEL" | "VIDEO";

export interface UpsertablePost {
  igMediaId: string;
  igPermalink: string;
  type: IgPostType;
  caption: string | null;
  igCreatedAt: Date;
}

export function normalizeForUpsert(summary: IgMediaSummary): UpsertablePost {
  return {
    igMediaId: summary.id,
    igPermalink: summary.permalink,
    type: mapType(summary.mediaType),
    caption: summary.caption,
    igCreatedAt: summary.timestamp,
  };
}

function mapType(t: IgMediaSummary["mediaType"]): IgPostType {
  switch (t) {
    case "IMAGE":
      return "IMAGE";
    case "CAROUSEL_ALBUM":
      return "CAROUSEL";
    case "VIDEO":
      return "VIDEO";
  }
}

const BATCH_LIMIT = 30;

export interface SyncSummary {
  total: number;
  inserted: number;
  updated: number;
  skipped: number;
  apiEnabled: boolean;
}

export async function syncInstagramPosts(): Promise<SyncSummary> {
  if (!isConfigured()) {
    return { total: 0, inserted: 0, updated: 0, skipped: 0, apiEnabled: false };
  }

  const config = readConfig();
  const summaries = await listRecentMedia(config, BATCH_LIMIT);

  let inserted = 0;
  let updated = 0;

  for (const summary of summaries) {
    const upsertable = normalizeForUpsert(summary);

    const result = await prisma.instagramPost.upsert({
      where: { igMediaId: upsertable.igMediaId },
      create: {
        igMediaId: upsertable.igMediaId,
        igPermalink: upsertable.igPermalink,
        type: upsertable.type,
        caption: upsertable.caption,
        igCreatedAt: upsertable.igCreatedAt,
      },
      update: {
        igPermalink: upsertable.igPermalink,
        caption: upsertable.caption,
      },
      select: { createdAt: true, updatedAt: true },
    });

    // Heuristic: createdAt === updatedAt (within 1ms) means we just inserted.
    if (Math.abs(result.createdAt.getTime() - result.updatedAt.getTime()) < 1) {
      inserted += 1;
    } else {
      updated += 1;
    }
  }

  return {
    total: summaries.length,
    inserted,
    updated,
    skipped: summaries.length - inserted - updated,
    apiEnabled: true,
  };
}

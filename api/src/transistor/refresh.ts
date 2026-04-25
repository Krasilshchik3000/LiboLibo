import { prisma } from "../db.js";
import * as api from "./api.js";
import { fetchPublicMediaUrls } from "./public-rss.js";

// Источник метаданных — Transistor API. Public RSS используется ТОЛЬКО как
// gate-сигнал: если эпизод есть в API, но его media_url нет в публичном RSS,
// значит, Transistor его прячет за пэйволом (Exclusive Episode). На уровне
// API такого флага нет (см. docs.transistor.fm), это единственный способ
// отличить exclusive от обычного published-эпизода.
//
// is_premium = (mediaUrl ∉ publicMediaUrls) || type === "bonus"
//
// Episode.id = Transistor episode id (например, "3195076").

interface RefreshResult {
  podcastId: bigint;
  status: "ok" | "error";
  episodes?: number;
  premiumEpisodes?: number;
  error?: string;
}

export interface RefreshSummary {
  total: number;
  ok: number;
  errors: number;
  apiEnabled: boolean;
  results: RefreshResult[];
}

export interface RefreshOptions {
  // Если задан — рефрешим только подкасты с этими id. Используется CLI
  // для точечной проверки одного подкаста.
  onlyPodcastIds?: bigint[];
}

export async function refreshAllFeeds(opts: RefreshOptions = {}): Promise<RefreshSummary> {
  const apiEnabled = api.isConfigured();
  const podcasts = opts.onlyPodcastIds && opts.onlyPodcastIds.length > 0
    ? await prisma.podcast.findMany({ where: { id: { in: opts.onlyPodcastIds } } })
    : await prisma.podcast.findMany();

  console.log(
    `[refresh] starting: ${podcasts.length} podcasts${opts.onlyPodcastIds ? " (filtered)" : ""}, transistor api ${apiEnabled ? "enabled" : "disabled"}`,
  );

  if (!apiEnabled) {
    console.error("[refresh] TRANSISTOR_API_KEY missing — refresh aborted");
    return {
      total: podcasts.length,
      ok: 0,
      errors: podcasts.length,
      apiEnabled: false,
      results: podcasts.map((p) => ({
        podcastId: p.id,
        status: "error" as const,
        error: "TRANSISTOR_API_KEY missing",
      })),
    };
  }

  let showsByFeedUrl: Map<string, api.TransistorShow>;
  let episodesByShowId: Map<string, api.TransistorEpisode[]>;
  try {
    showsByFeedUrl = await api.listAllShowsByFeedUrl();
    episodesByShowId = await api.listAllEpisodesByShowId();
    const totalEps = Array.from(episodesByShowId.values()).reduce(
      (n, arr) => n + arr.length,
      0,
    );
    console.log(
      `[transistor-api] account fetch ok: ${showsByFeedUrl.size} shows, ${totalEps} episodes total`,
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[transistor-api] account fetch failed: ${msg}`);
    return {
      total: podcasts.length,
      ok: 0,
      errors: podcasts.length,
      apiEnabled: true,
      results: podcasts.map((p) => ({
        podcastId: p.id,
        status: "error" as const,
        error: msg,
      })),
    };
  }

  const results: RefreshResult[] = [];
  const total = podcasts.length;
  let processed = 0;

  for (const podcast of podcasts) {
    const result = await refreshOne(podcast, showsByFeedUrl, episodesByShowId);
    results.push(result);
    processed += 1;
    const tag = result.status === "error"
      ? `error: ${result.error}`
      : `ok episodes=${result.episodes ?? 0} premium=${result.premiumEpisodes ?? 0}`;
    console.log(`[refresh] ${processed}/${total} ${podcast.name} → ${tag}`);
  }

  return {
    total: results.length,
    ok: results.filter((r) => r.status === "ok").length,
    errors: results.filter((r) => r.status === "error").length,
    apiEnabled: true,
    results,
  };
}

type Podcast = Awaited<ReturnType<typeof prisma.podcast.findMany>>[number];

async function refreshOne(
  podcast: Podcast,
  showsByFeedUrl: Map<string, api.TransistorShow>,
  episodesByShowId: Map<string, api.TransistorEpisode[]>,
): Promise<RefreshResult> {
  const show =
    showsByFeedUrl.get(podcast.feedUrl) ??
    (podcast.transistorShowId
      ? Array.from(showsByFeedUrl.values()).find(
          (s) => s.id === podcast.transistorShowId,
        )
      : undefined);

  if (!show) {
    const msg = "show not found in Transistor account";
    await markError(podcast.id, msg);
    return { podcastId: podcast.id, status: "error", error: msg };
  }

  if (show.id !== podcast.transistorShowId) {
    await prisma.podcast.update({
      where: { id: podcast.id },
      data: { transistorShowId: show.id },
    });
  }

  const apiEpisodes = episodesByShowId.get(show.id) ?? [];

  // Тянем публичный RSS, чтобы определить, какие эпизоды реально доступны
  // публично. Те, что Transistor прячет за пэйволом (Exclusive), там
  // отсутствуют. Если RSS недоступен — fallback на bonus-only логику и
  // лог-предупреждение.
  let publicMediaUrls: Set<string> | null = null;
  try {
    publicMediaUrls = await fetchPublicMediaUrls(podcast.feedUrl);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.warn(
      `[refresh] podcast=${podcast.id} public RSS fetch failed (${msg}); ` +
        `premium gating falls back to type==="bonus" only`,
    );
  }

  const items: EpisodeRow[] = [];
  let premiumCount = 0;
  for (const ep of apiEpisodes) {
    if (ep.status !== "published") continue;
    if (!ep.mediaUrl || !ep.pubDate) continue;

    const notInPublicRSS = publicMediaUrls
      ? !publicMediaUrls.has(ep.mediaUrl)
      : false;
    const isPremium = notInPublicRSS || ep.type === "bonus";
    if (isPremium) premiumCount += 1;

    items.push({
      id: ep.id,
      title: ep.title,
      summary: ep.summary,
      pubDate: ep.pubDate,
      durationSec: ep.durationSec,
      audioUrl: ep.mediaUrl,
      isPremium,
    });
  }

  await upsertEpisodes(podcast.id, items);

  await prisma.feedFetch.upsert({
    where: { podcastId: podcast.id },
    create: {
      podcastId: podcast.id,
      etag: null,
      lastModified: null,
      lastOkAt: new Date(),
      lastError: null,
    },
    update: {
      etag: null,
      lastModified: null,
      lastOkAt: new Date(),
      lastError: null,
    },
  });

  await refreshPodcastMetadata(podcast, show, items, premiumCount);

  return {
    podcastId: podcast.id,
    status: "ok",
    episodes: items.length,
    premiumEpisodes: premiumCount,
  };
}

async function refreshPodcastMetadata(
  podcast: Podcast,
  show: api.TransistorShow,
  items: EpisodeRow[],
  premiumCount: number,
) {
  const latestPubDate = items.reduce<Date | null>(
    (acc, e) => (acc && acc.getTime() > e.pubDate.getTime() ? acc : e.pubDate),
    null,
  );

  const updates: {
    description?: string;
    artworkUrl?: string;
    lastEpisodeDate?: Date | null;
    hasPremium?: boolean;
  } = {};

  if (show.description && show.description !== podcast.description) {
    updates.description = show.description;
  }
  if (show.imageUrl && show.imageUrl !== podcast.artworkUrl) {
    updates.artworkUrl = show.imageUrl;
  }
  if (
    latestPubDate &&
    latestPubDate.getTime() !== podcast.lastEpisodeDate?.getTime()
  ) {
    updates.lastEpisodeDate = latestPubDate;
  }
  const shouldHavePremium = premiumCount > 0;
  if (shouldHavePremium !== podcast.hasPremium) {
    updates.hasPremium = shouldHavePremium;
  }

  if (Object.keys(updates).length === 0) return;
  await prisma.podcast.update({ where: { id: podcast.id }, data: updates });
}

interface EpisodeRow {
  id: string;
  title: string;
  summary: string | null;
  pubDate: Date;
  durationSec: number | null;
  audioUrl: string;
  isPremium: boolean;
}

async function upsertEpisodes(podcastId: bigint, items: EpisodeRow[]) {
  if (items.length === 0) return;
  await prisma.$transaction(
    items.map((e) =>
      prisma.episode.upsert({
        where: { id: e.id },
        create: {
          id: e.id,
          podcastId,
          title: e.title,
          summary: e.summary,
          pubDate: e.pubDate,
          durationSec: e.durationSec,
          audioUrl: e.audioUrl,
          isPremium: e.isPremium,
        },
        update: {
          title: e.title,
          summary: e.summary,
          pubDate: e.pubDate,
          durationSec: e.durationSec,
          audioUrl: e.audioUrl,
          isPremium: e.isPremium,
        },
      }),
    ),
  );
}

async function markError(podcastId: bigint, error: string) {
  await prisma.feedFetch.upsert({
    where: { podcastId },
    create: { podcastId, lastError: error },
    update: { lastError: error },
  });
}

import { prisma } from "../db.js";
import { parseRSS } from "./parser.js";
import * as api from "./api.js";

interface RefreshResult {
  podcastId: bigint;
  status: "ok" | "not-modified" | "error";
  publicEpisodes?: number;
  premiumEpisodes?: number;
  error?: string;
}

export interface RefreshSummary {
  total: number;
  ok: number;
  notModified: number;
  errors: number;
  apiEnabled: boolean;
  results: RefreshResult[];
}

const CONCURRENCY = 8;

export async function refreshAllFeeds(): Promise<RefreshSummary> {
  const apiEnabled = api.isConfigured();
  const podcasts = await prisma.podcast.findMany({
    include: { feedFetch: true },
  });

  console.log(
    `[refresh] starting: ${podcasts.length} podcasts, transistor api ${apiEnabled ? "enabled" : "disabled"}`,
  );

  // Pull the entire account from Transistor in two paginated calls (one for
  // shows, one for all episodes) instead of issuing per-podcast requests.
  // Per-podcast fan-out used to trigger Transistor's HTTP 429 rate limit,
  // which left transistorShowId unset and premium episodes never syncing.
  let showIdByFeedUrl: Map<string, string> | null = null;
  let episodesByShowId: Map<string, api.TransistorEpisode[]> | null = null;
  if (apiEnabled) {
    try {
      showIdByFeedUrl = await api.listAllShowsByFeedUrl();
      episodesByShowId = await api.listAllEpisodesByShowId();
      const totalEps = Array.from(episodesByShowId.values()).reduce(
        (n, arr) => n + arr.length,
        0,
      );
      console.log(
        `[transistor-api] account fetch ok: ${showIdByFeedUrl.size} shows, ${totalEps} episodes total`,
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[transistor-api] account fetch failed: ${msg}`);
      showIdByFeedUrl = null;
      episodesByShowId = null;
    }
  }

  const results: RefreshResult[] = [];
  let i = 0;
  let processed = 0;
  const total = podcasts.length;

  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      while (i < podcasts.length) {
        const podcast = podcasts[i++];
        if (!podcast) break;
        const result = await refreshOne(podcast, apiEnabled, showIdByFeedUrl, episodesByShowId);
        results.push(result);
        processed += 1;
        const tag = result.status === "error"
          ? `error: ${result.error}`
          : `${result.status} public=${result.publicEpisodes ?? 0} premium=${result.premiumEpisodes ?? 0}`;
        console.log(`[refresh] ${processed}/${total} ${podcast.name} → ${tag}`);
      }
    }),
  );

  return {
    total: results.length,
    ok: results.filter((r) => r.status === "ok").length,
    notModified: results.filter((r) => r.status === "not-modified").length,
    errors: results.filter((r) => r.status === "error").length,
    apiEnabled,
    results,
  };
}

type PodcastWithFetch = Awaited<
  ReturnType<typeof prisma.podcast.findMany>
>[number] & {
  feedFetch: { etag: string | null; lastModified: string | null } | null;
};

async function refreshOne(
  podcast: PodcastWithFetch,
  apiEnabled: boolean,
  showIdByFeedUrl: Map<string, string> | null,
  episodesByShowId: Map<string, api.TransistorEpisode[]> | null,
): Promise<RefreshResult> {
  // Step 1: fetch the public RSS. This is the source of truth for which
  // episodes are PUBLIC; everything else (visible only via API) is premium.
  const rssResult = await fetchPublicRSS(podcast);
  if (rssResult.kind === "error") {
    await markError(podcast.id, rssResult.error);
    return { podcastId: podcast.id, status: "error", error: rssResult.error };
  }

  const publicGuids = new Set(rssResult.feed.episodes.map((e) => e.id));
  let premiumCount = 0;

  // Step 2: if we have a Transistor API key and the bulk fetch succeeded,
  // mark anything not in publicGuids as premium.
  if (apiEnabled && episodesByShowId) {
    try {
      premiumCount = await syncPremiumFromBulk(
        podcast,
        publicGuids,
        showIdByFeedUrl,
        episodesByShowId,
      );
    } catch (err) {
      // API failure must not block public episode ingestion — log and continue.
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[transistor-api] podcast=${podcast.id}: ${msg}`);
    }
  }

  // Step 3: persist public episodes (parsed from RSS).
  // Bonus-эпизоды (<itunes:episodeType>bonus</itunes:episodeType>) у Либо-Либо
  // — это контент для подписчиков. Transistor публикует их в публичном RSS,
  // но mp3 раздавать всем нельзя — помечаем как premium, чтобы serialize.ts
  // занулил audio_url для viewer'ов без entitlement'а.
  if (rssResult.kind === "fresh") {
    let bonusCount = 0;
    await upsertEpisodes(
      podcast.id,
      rssResult.feed.episodes.map((e) => {
        const isBonus = e.episodeType === "bonus";
        if (isBonus) bonusCount++;
        return {
          id: e.id,
          title: e.title,
          summary: e.summary,
          pubDate: e.pubDate,
          durationSec: e.durationSec,
          audioUrl: e.audioUrl,
          isPremium: isBonus,
        };
      }),
    );
    premiumCount += bonusCount;
  }

  // Step 4: write fetch state and refresh denormalized podcast metadata
  // (channel description, lastEpisodeDate, hasPremium).
  await prisma.feedFetch.upsert({
    where: { podcastId: podcast.id },
    create: {
      podcastId: podcast.id,
      etag: rssResult.etag,
      lastModified: rssResult.lastModified,
      lastOkAt: new Date(),
      lastError: null,
    },
    update: {
      etag: rssResult.etag,
      lastModified: rssResult.lastModified,
      lastOkAt: new Date(),
      lastError: null,
    },
  });

  await refreshPodcastMetadata(podcast, rssResult.feed.channel.description, premiumCount);

  return {
    podcastId: podcast.id,
    status: rssResult.kind === "not-modified" ? "not-modified" : "ok",
    publicEpisodes: rssResult.feed.episodes.length,
    premiumEpisodes: premiumCount,
  };
}

// Recomputes denormalized fields on Podcast: channel description (when refreshed
// from RSS), `lastEpisodeDate` (max pubDate across all episodes), `hasPremium`.
async function refreshPodcastMetadata(
  podcast: PodcastWithFetch,
  channelDescription: string | null,
  premiumCount: number,
) {
  const latest = await prisma.episode.findFirst({
    where: { podcastId: podcast.id },
    orderBy: { pubDate: "desc" },
    select: { pubDate: true },
  });

  const updates: {
    description?: string;
    lastEpisodeDate?: Date | null;
    hasPremium?: boolean;
  } = {};

  // Update description only if RSS gave us a non-empty one — don't clobber
  // a good seed value with null on a 304 path.
  if (channelDescription && channelDescription !== podcast.description) {
    updates.description = channelDescription;
  }
  if (latest && latest.pubDate.getTime() !== podcast.lastEpisodeDate?.getTime()) {
    updates.lastEpisodeDate = latest.pubDate;
  }
  if (premiumCount > 0 && !podcast.hasPremium) {
    updates.hasPremium = true;
  }

  if (Object.keys(updates).length === 0) return;
  await prisma.podcast.update({ where: { id: podcast.id }, data: updates });
}

// --- helpers ---------------------------------------------------------------

type ParsedFeed = ReturnType<typeof parseRSS>;

interface RSSFresh {
  kind: "fresh";
  feed: ParsedFeed;
  etag: string | null;
  lastModified: string | null;
}
interface RSSNotModified {
  kind: "not-modified";
  feed: ParsedFeed;
  etag: string | null;
  lastModified: string | null;
}
interface RSSError { kind: "error"; error: string }

async function fetchPublicRSS(
  podcast: PodcastWithFetch,
): Promise<RSSFresh | RSSNotModified | RSSError> {
  const headers: Record<string, string> = {
    "User-Agent":
      "LiboLibo-API/0.1 (+https://github.com/Krasilshchik3000/LiboLibo)",
    Accept: "application/rss+xml, application/xml, text/xml",
  };
  if (podcast.feedFetch?.etag) headers["If-None-Match"] = podcast.feedFetch.etag;
  if (podcast.feedFetch?.lastModified)
    headers["If-Modified-Since"] = podcast.feedFetch.lastModified;

  try {
    const resp = await fetch(podcast.feedUrl, { headers });

    if (resp.status === 304) {
      // Episodes are still in DB — pass an empty parsed feed, no upsert needed.
      return {
        kind: "not-modified",
        feed: { channel: { description: null }, episodes: [] },
        etag: podcast.feedFetch?.etag ?? null,
        lastModified: podcast.feedFetch?.lastModified ?? null,
      };
    }
    if (!resp.ok) {
      return { kind: "error", error: `HTTP ${resp.status}` };
    }

    const xmlBody = await resp.text();
    return {
      kind: "fresh",
      feed: parseRSS(xmlBody),
      etag: resp.headers.get("etag"),
      lastModified: resp.headers.get("last-modified"),
    };
  } catch (err) {
    return {
      kind: "error",
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

// Picks the podcast's premium episodes out of the pre-fetched account-wide
// bulk and upserts them. Resolves show id via the cached value or the bulk
// shows map (and persists it on first sight so future runs need fewer
// lookups).
async function syncPremiumFromBulk(
  podcast: PodcastWithFetch,
  publicGuids: Set<string>,
  showIdByFeedUrl: Map<string, string> | null,
  episodesByShowId: Map<string, api.TransistorEpisode[]>,
): Promise<number> {
  const showId =
    podcast.transistorShowId ?? showIdByFeedUrl?.get(podcast.feedUrl) ?? null;
  if (!showId) return 0;
  if (showId !== podcast.transistorShowId) {
    await prisma.podcast.update({
      where: { id: podcast.id },
      data: { transistorShowId: showId },
    });
  }

  const apiEpisodes = episodesByShowId.get(showId) ?? [];
  const premium: Array<{
    id: string;
    title: string;
    summary: string | null;
    pubDate: Date;
    durationSec: number | null;
    audioUrl: string;
    isPremium: boolean;
  }> = [];

  for (const ep of apiEpisodes) {
    // Only published episodes are real; skip drafts/scheduled.
    if (ep.status !== "published") continue;
    if (!ep.mediaUrl || !ep.pubDate) continue;

    // Use guid if available, else fall back to media URL (same rule as RSS).
    const guid = ep.guid ?? ep.mediaUrl;
    if (publicGuids.has(guid)) continue; // public — already covered by RSS

    premium.push({
      id: guid,
      title: ep.title,
      summary: ep.summary,
      pubDate: ep.pubDate,
      durationSec: ep.durationSec,
      audioUrl: ep.mediaUrl,
      isPremium: true,
    });
  }

  if (premium.length > 0) {
    await upsertEpisodes(podcast.id, premium);
  }
  return premium.length;
}

async function upsertEpisodes(
  podcastId: bigint,
  items: Array<{
    id: string;
    title: string;
    summary: string | null;
    pubDate: Date;
    durationSec: number | null;
    audioUrl: string;
    isPremium: boolean;
  }>,
) {
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

// Thin client for the Transistor.fm REST API.
// Auth: header `x-api-key`, see https://developers.transistor.fm/.
// The key is ONLY ever read from process.env (loaded from `api/transistor.env`
// in dev, from Railway Variables in prod). It must never be logged or echoed.

import { stripHTML } from "../lib/strip-html.js";

const BASE = "https://api.transistor.fm/v1";
const PAGE_SIZE = 50;

export function isConfigured(): boolean {
  return typeof process.env.TRANSISTOR_API_KEY === "string"
    && process.env.TRANSISTOR_API_KEY.length > 0;
}

function authHeaders(): Record<string, string> {
  const key = process.env.TRANSISTOR_API_KEY;
  if (!key) throw new Error("TRANSISTOR_API_KEY is not set");
  return {
    "x-api-key": key,
    Accept: "application/json",
  };
}

// Minimal subset of fields we care about. Transistor returns much more.
export interface TransistorShow {
  id: string;
  feedUrl: string;
}

export interface TransistorEpisode {
  id: string;
  showId: string;
  guid: string | null;
  title: string;
  summary: string | null;
  pubDate: Date | null;
  durationSec: number | null;
  mediaUrl: string | null;
  status: string; // "published" | "draft" | "scheduled"
  type: string;   // "full" | "trailer" | "bonus"
}

interface JsonApiResource<A> {
  id: string;
  type: string;
  attributes: A;
  relationships?: Record<string, { data?: { id: string; type: string } }>;
}

interface JsonApiList<A> {
  data: JsonApiResource<A>[];
  meta?: {
    totalCount?: number;
    totalPages?: number;
    currentPage?: number;
  };
}

interface ShowAttrs {
  feed_url?: string | null;
}

interface EpisodeAttrs {
  guid?: string | null;
  title?: string | null;
  summary?: string | null;
  description?: string | null;
  published_at?: string | null;
  duration?: number | null;
  media_url?: string | null;
  audio_processing?: unknown;
  status?: string | null;
  type?: string | null;
}

// Transistor returns 429 when we burst too many requests at once. Retry with
// the server-provided Retry-After (seconds), falling back to exponential
// backoff. Only 429 is retried — other 4xx/5xx fail fast.
async function getJSON<T>(path: string, query?: Record<string, string>): Promise<T> {
  const url = new URL(BASE + path);
  if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);

  const MAX_RETRIES = 5;
  for (let attempt = 0; ; attempt++) {
    const resp = await fetch(url, { headers: authHeaders() });
    if (resp.ok) return (await resp.json()) as T;

    if (resp.status === 429 && attempt < MAX_RETRIES) {
      const retryAfter = Number(resp.headers.get("retry-after"));
      const waitMs = Number.isFinite(retryAfter) && retryAfter > 0
        ? retryAfter * 1000
        : 500 * 2 ** attempt;
      await new Promise((r) => setTimeout(r, waitMs));
      continue;
    }

    // Don't include the URL with query — keeps secrets out of logs even if
    // we ever pass auth via query params (we don't, but defense in depth).
    throw new Error(`Transistor API ${path} → HTTP ${resp.status}`);
  }
}

// All shows visible to the current API key, keyed by their `feed_url`.
// One bulk fetch replaces N per-podcast `findShowIdByFeedUrl` calls — without
// this, refreshing dozens of podcasts in parallel hammered Transistor and
// most calls came back as HTTP 429.
export async function listAllShowsByFeedUrl(): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  let page = 1;
  for (;;) {
    const list = await getJSON<JsonApiList<ShowAttrs>>("/shows", {
      "pagination[page]": String(page),
      "pagination[per]": String(PAGE_SIZE),
    });
    for (const s of list.data) {
      const url = s.attributes.feed_url;
      if (url) map.set(url, s.id);
    }
    const total = list.meta?.totalPages ?? 1;
    console.log(
      `[transistor-api] shows page ${page}/${total} → ${map.size} shows so far`,
    );
    if (page >= total) return map;
    page += 1;
  }
}

// All episodes across the account, grouped by show id. Transistor's
// /v1/episodes accepts no show_id filter and returns every episode for the
// API key's account in one paginated stream — much cheaper than fetching
// each show separately. Drafts and subscriber-only are included; caller
// decides what to do with them.
export async function listAllEpisodesByShowId(): Promise<Map<string, TransistorEpisode[]>> {
  const byShow = new Map<string, TransistorEpisode[]>();
  let page = 1;
  let processed = 0;
  for (;;) {
    const list = await getJSON<JsonApiList<EpisodeAttrs>>("/episodes", {
      "pagination[page]": String(page),
      "pagination[per]": String(PAGE_SIZE),
    });
    const totalCount = list.meta?.totalCount;
    const totalPages = list.meta?.totalPages ?? 1;
    for (const e of list.data) {
      const showId = e.relationships?.show?.data?.id;
      if (!showId) continue;
      const a = e.attributes;
      const ep: TransistorEpisode = {
        id: e.id,
        showId,
        guid: a.guid ?? null,
        title: a.title ?? "(без названия)",
        summary: stripHTML(a.summary ?? a.description ?? null),
        pubDate: a.published_at ? new Date(a.published_at) : null,
        durationSec: typeof a.duration === "number" ? a.duration : null,
        mediaUrl: a.media_url ?? null,
        status: a.status ?? "unknown",
        type: a.type ?? "full",
      };
      const bucket = byShow.get(showId);
      if (bucket) bucket.push(ep);
      else byShow.set(showId, [ep]);
    }
    processed += list.data.length;
    const totalLabel = typeof totalCount === "number" ? totalCount : "?";
    console.log(
      `[transistor-api] episodes page ${page}/${totalPages} → ${processed}/${totalLabel} fetched, ${byShow.size} shows touched`,
    );
    if (page >= totalPages) break;
    page += 1;
  }
  return byShow;
}

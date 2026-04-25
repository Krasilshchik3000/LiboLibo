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

async function getJSON<T>(path: string, query?: Record<string, string>): Promise<T> {
  const url = new URL(BASE + path);
  if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);

  const resp = await fetch(url, { headers: authHeaders() });
  if (!resp.ok) {
    // Don't include the URL with query — keeps secrets out of logs even if
    // we ever pass auth via query params (we don't, but defense in depth).
    throw new Error(`Transistor API ${path} → HTTP ${resp.status}`);
  }
  return (await resp.json()) as T;
}

// Resolve a Transistor show id by its feed URL. Used to bind our podcasts
// (seeded from podcasts-feeds.json by iTunes id) to Transistor shows.
export async function findShowIdByFeedUrl(feedUrl: string): Promise<string | null> {
  // /v1/shows lists shows owned by the API key holder.
  let page = 1;
  for (;;) {
    const list = await getJSON<JsonApiList<ShowAttrs>>("/shows", {
      "pagination[page]": String(page),
      "pagination[per]": String(PAGE_SIZE),
    });
    for (const s of list.data) {
      if (s.attributes.feed_url === feedUrl) return s.id;
    }
    const total = list.meta?.totalPages ?? 1;
    if (page >= total) return null;
    page += 1;
  }
}

// All episodes for a show, across pagination. Includes drafts and
// subscriber-only — caller decides what to do with them.
export async function listAllEpisodes(showId: string): Promise<TransistorEpisode[]> {
  const out: TransistorEpisode[] = [];
  let page = 1;
  for (;;) {
    const list = await getJSON<JsonApiList<EpisodeAttrs>>("/episodes", {
      "show_id": showId,
      "pagination[page]": String(page),
      "pagination[per]": String(PAGE_SIZE),
    });
    for (const e of list.data) {
      const a = e.attributes;
      out.push({
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
      });
    }
    const total = list.meta?.totalPages ?? 1;
    if (page >= total) break;
    page += 1;
  }
  return out;
}

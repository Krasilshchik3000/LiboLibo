import { XMLParser } from "fast-xml-parser";
import { stripHTML } from "../lib/strip-html.js";

export interface ParsedFeed {
  channel: ParsedChannel;
  episodes: ParsedEpisode[];
}

export interface ParsedChannel {
  // <channel><description> или <itunes:summary> на уровне канала.
  // HTML-теги вырезаны, базовые сущности декодированы.
  description: string | null;
}

export interface ParsedEpisode {
  id: string; // RSS guid (or fallback to enclosure URL)
  title: string;
  summary: string | null;
  pubDate: Date;
  durationSec: number | null;
  audioUrl: string;
  // Нормализованное значение <itunes:episodeType>: "full" | "trailer" | "bonus" | null.
  // Bonus-эпизоды у Либо-Либо считаются премиальными (см. refresh.ts).
  episodeType: "full" | "trailer" | "bonus" | null;
}

const xml = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  trimValues: true,
  parseAttributeValue: false,
  parseTagValue: false,
});

export function parseRSS(xmlBody: string): ParsedFeed {
  const empty: ParsedFeed = { channel: { description: null }, episodes: [] };

  const doc = xml.parse(xmlBody) as RawDoc;
  const channel = doc?.rss?.channel;
  if (!channel) return empty;

  const rawItems = toArray(channel.item);
  const episodes: ParsedEpisode[] = [];

  for (const item of rawItems) {
    const audioUrl = item.enclosure?.["@_url"];
    const pubDateStr = item.pubDate;
    if (!audioUrl || !pubDateStr) continue;

    const pubDate = new Date(pubDateStr);
    if (Number.isNaN(pubDate.getTime())) continue;

    const guid = extractGuid(item.guid) ?? audioUrl;

    episodes.push({
      id: guid,
      title: textOf(item.title) ?? "(без названия)",
      summary:
        stripHTML(textOf(item["itunes:summary"])) ??
        stripHTML(textOf(item.description)) ??
        null,
      pubDate,
      durationSec: parseDuration(textOf(item["itunes:duration"])),
      audioUrl,
      episodeType: parseEpisodeType(textOf(item["itunes:episodeType"])),
    });
  }

  // Channel-level description — для подкаст-страницы.
  const description =
    stripHTML(textOf(channel.description)) ??
    stripHTML(textOf(channel["itunes:summary"])) ??
    null;

  return {
    channel: { description },
    episodes,
  };
}

function toArray<T>(v: T | T[] | undefined): T[] {
  if (v == null) return [];
  return Array.isArray(v) ? v : [v];
}

function textOf(v: unknown): string | null {
  if (v == null) return null;
  if (typeof v === "string") return v;
  if (typeof v === "object" && v !== null && "#text" in v) {
    const t = (v as { "#text"?: unknown })["#text"];
    return typeof t === "string" ? t : null;
  }
  return null;
}

function extractGuid(v: unknown): string | null {
  if (v == null) return null;
  if (typeof v === "string") return v;
  if (typeof v === "object" && v !== null) {
    const obj = v as { "#text"?: unknown };
    if (typeof obj["#text"] === "string") return obj["#text"];
  }
  return null;
}

function parseEpisodeType(raw: string | null): "full" | "trailer" | "bonus" | null {
  if (!raw) return null;
  const v = raw.trim().toLowerCase();
  return v === "full" || v === "trailer" || v === "bonus" ? v : null;
}

// Parses iTunes duration: either "HH:MM:SS", "MM:SS", or a bare seconds count.
function parseDuration(raw: string | null): number | null {
  if (!raw) return null;
  if (raw.includes(":")) {
    const parts = raw.split(":").map((p) => Number(p));
    if (parts.some((p) => Number.isNaN(p))) return null;
    let sec = 0;
    for (const p of parts) sec = sec * 60 + p;
    return sec;
  }
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : null;
}

// Internal type matching what fast-xml-parser returns for this RSS shape.
interface RawDoc {
  rss?: {
    channel?: {
      description?: unknown;
      "itunes:summary"?: unknown;
      item?: RawItem | RawItem[];
    };
  };
}

interface RawItem {
  title?: unknown;
  description?: unknown;
  pubDate?: string;
  guid?: unknown;
  enclosure?: { "@_url"?: string };
  "itunes:summary"?: unknown;
  "itunes:duration"?: unknown;
  "itunes:episodeType"?: unknown;
}

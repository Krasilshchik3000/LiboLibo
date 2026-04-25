import { XMLParser } from "fast-xml-parser";

// Возвращает множество media URL'ов, опубликованных в публичном RSS-фиде шоу.
// Используется ТОЛЬКО как gate-сигнал: если эпизод есть в Transistor API,
// но его mediaUrl нет в этом множестве — эпизод exclusive (subscriber-only).
// Метаданные эпизода берём из API, RSS — только список «доступного публично».
export async function fetchPublicMediaUrls(feedUrl: string): Promise<Set<string>> {
  const resp = await fetch(feedUrl, {
    headers: {
      "User-Agent":
        "LiboLibo-API/0.1 (+https://github.com/Krasilshchik3000/LiboLibo)",
      Accept: "application/rss+xml, application/xml, text/xml",
    },
  });
  if (!resp.ok) {
    throw new Error(`public RSS HTTP ${resp.status}`);
  }
  const xml = await resp.text();
  return parsePublicMediaUrls(xml);
}

const xmlParser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  trimValues: true,
  parseAttributeValue: false,
  parseTagValue: false,
});

export function parsePublicMediaUrls(xml: string): Set<string> {
  const out = new Set<string>();
  const doc = xmlParser.parse(xml) as RawDoc;
  const items = toArray(doc?.rss?.channel?.item);
  for (const item of items) {
    const url = item.enclosure?.["@_url"];
    if (typeof url === "string" && url.length > 0) out.add(url);
  }
  return out;
}

function toArray<T>(v: T | T[] | undefined): T[] {
  if (v == null) return [];
  return Array.isArray(v) ? v : [v];
}

interface RawDoc {
  rss?: {
    channel?: {
      item?: RawItem | RawItem[];
    };
  };
}

interface RawItem {
  enclosure?: { "@_url"?: string };
}

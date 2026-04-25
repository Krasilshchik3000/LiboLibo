// Opaque cursor: base64url-encoded JSON of `{ ts, id }`.
// Pagination is by `pubDate desc, id desc` to keep ordering stable when
// multiple episodes share the exact same pubDate.

export interface Cursor {
  ts: string; // ISO timestamp of the last-returned episode's pubDate
  id: string; // last-returned episode id (RSS guid)
}

export function encodeCursor(c: Cursor): string {
  return Buffer.from(JSON.stringify(c), "utf8").toString("base64url");
}

export function decodeCursor(raw: string | undefined): Cursor | null {
  if (!raw) return null;
  try {
    const json = Buffer.from(raw, "base64url").toString("utf8");
    const parsed = JSON.parse(json) as Cursor;
    if (typeof parsed?.ts !== "string" || typeof parsed?.id !== "string") return null;
    return parsed;
  } catch {
    return null;
  }
}

export function parseLimit(raw: unknown, fallback = 50, max = 200): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(Math.floor(n), max);
}

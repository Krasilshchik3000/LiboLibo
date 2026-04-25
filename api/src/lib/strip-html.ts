// Strips HTML tags and decodes basic HTML entities. Mirrors iOS `RSSParser`
// (LiboLibo/Services/RSSParser.swift) and scripts/refresh-podcast-metadata.py
// so clients always get clean text.
//
// Also strips trailing whitespace and collapses runs of newlines/spaces.

const ENTITIES: Record<string, string> = {
  "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
  "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
  "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
  "&laquo;": "«", "&raquo;": "»",
};

export function stripHTML(input: string | null | undefined): string | null {
  if (!input) return null;
  let s = input;
  s = s.replace(/<br[^>]*>/gi, "\n");
  s = s.replace(/<\/p>/gi, "\n\n");
  s = s.replace(/<[^>]+>/g, "");
  for (const [k, v] of Object.entries(ENTITIES)) {
    s = s.split(k).join(v);
  }
  s = s.replace(/\n{3,}/g, "\n\n");
  s = s.replace(/[ \t]{2,}/g, " ");
  return s.trim() || null;
}

import { describe, it, expect } from "vitest";
import { normalizeForUpsert } from "../src/instagram/collector.js";
import type { IgMediaSummary } from "../src/instagram/graph-client.js";

const baseSummary = (over: Partial<IgMediaSummary> = {}): IgMediaSummary => ({
  id: "111",
  mediaType: "IMAGE",
  mediaProductType: "FEED",
  permalink: "https://www.instagram.com/p/abc/",
  caption: "Hello",
  timestamp: new Date("2026-04-25T10:00:00Z"),
  ...over,
});

describe("normalizeForUpsert", () => {
  it("маппит IMAGE → type=IMAGE", () => {
    const p = normalizeForUpsert(baseSummary({ mediaType: "IMAGE" }));
    expect(p.type).toBe("IMAGE");
    expect(p.igMediaId).toBe("111");
    expect(p.caption).toBe("Hello");
    expect(p.igPermalink).toBe("https://www.instagram.com/p/abc/");
    expect(p.igCreatedAt.toISOString()).toBe("2026-04-25T10:00:00.000Z");
  });

  it("маппит CAROUSEL_ALBUM → type=CAROUSEL", () => {
    const p = normalizeForUpsert(baseSummary({ mediaType: "CAROUSEL_ALBUM" }));
    expect(p.type).toBe("CAROUSEL");
  });

  it("маппит VIDEO (как FEED, так и REELS) → type=VIDEO", () => {
    expect(normalizeForUpsert(baseSummary({ mediaType: "VIDEO", mediaProductType: "FEED" })).type).toBe("VIDEO");
    expect(normalizeForUpsert(baseSummary({ mediaType: "VIDEO", mediaProductType: "REELS" })).type).toBe("VIDEO");
  });

  it("сохраняет caption=null", () => {
    const p = normalizeForUpsert(baseSummary({ caption: null }));
    expect(p.caption).toBeNull();
  });
});

import { describe, it, expect } from "vitest";
import { serializeInstagramPost, type InstagramPostRow } from "../src/lib/instagram-feed-serialize.js";

const BASE = { mediaBaseUrl: "https://api.example.com/media" };

const basePost = (over: Partial<InstagramPostRow> = {}): InstagramPostRow => ({
  id: "11111111-1111-1111-1111-111111111111",
  igPermalink: "https://www.instagram.com/p/abc/",
  type: "IMAGE",
  caption: "hi",
  publishedAt: new Date("2026-04-25T10:00:00Z"),
  ctaType: null,
  ctaEpisodeId: null,
  ctaPodcastId: null,
  ctaUrl: null,
  ctaLabel: null,
  media: [
    { order: 0, kind: "IMAGE", filePath: "11111111-1111-1111-1111-111111111111/0.jpg", thumbnailPath: null, width: 1080, height: 1080, durationSec: null },
  ],
  ctaEpisode: null,
  ctaPodcast: null,
  ...over,
});

describe("serializeInstagramPost", () => {
  it("базовый случай: одиночное изображение, без CTA", () => {
    const out = serializeInstagramPost(basePost(), BASE);
    expect(out.type).toBe("image");
    expect(out.permalink).toBe("https://www.instagram.com/p/abc/");
    expect(out.publishedAt).toBe("2026-04-25T10:00:00.000Z");
    expect(out.media).toEqual([
      { kind: "image", url: "https://api.example.com/media/11111111-1111-1111-1111-111111111111/0.jpg", thumbnailUrl: null, width: 1080, height: 1080, durationSec: null },
    ]);
    expect(out.cta).toBeNull();
  });

  it("сортирует media по order", () => {
    const out = serializeInstagramPost(
      basePost({
        type: "CAROUSEL",
        media: [
          { order: 2, kind: "IMAGE", filePath: "p/2.jpg", thumbnailPath: null, width: 1, height: 1, durationSec: null },
          { order: 0, kind: "VIDEO", filePath: "p/0.mp4", thumbnailPath: "p/0.thumb.jpg", width: 2, height: 2, durationSec: 10 },
          { order: 1, kind: "IMAGE", filePath: "p/1.jpg", thumbnailPath: null, width: 3, height: 3, durationSec: null },
        ],
      }),
      BASE,
    );
    expect(out.media.map((m) => m.url)).toEqual([
      "https://api.example.com/media/p/0.mp4",
      "https://api.example.com/media/p/1.jpg",
      "https://api.example.com/media/p/2.jpg",
    ]);
    expect(out.media[0]!.thumbnailUrl).toBe("https://api.example.com/media/p/0.thumb.jpg");
  });

  it("CTA episode → label по умолчанию + nested episode", () => {
    const out = serializeInstagramPost(
      basePost({
        ctaType: "EPISODE",
        ctaEpisodeId: "ep-1",
        ctaEpisode: { id: "ep-1", title: "Эпизод про N", podcastId: 12345n },
      }),
      BASE,
    );
    expect(out.cta).toEqual({
      type: "episode",
      label: "Слушать эпизод",
      episode: { id: "ep-1", title: "Эпизод про N", podcastId: "12345" },
    });
  });

  it("CTA link с кастомным label", () => {
    const out = serializeInstagramPost(
      basePost({
        ctaType: "LINK",
        ctaUrl: "https://libolibo.ru/x",
        ctaLabel: "Подробнее",
      }),
      BASE,
    );
    expect(out.cta).toEqual({
      type: "link",
      label: "Подробнее",
      url: "https://libolibo.ru/x",
    });
  });

  it("ctaType=PODCAST но ctaPodcast=null → cta=null (защита от рассинхронизации)", () => {
    const out = serializeInstagramPost(
      basePost({ ctaType: "PODCAST", ctaPodcastId: 99n, ctaPodcast: null }),
      BASE,
    );
    expect(out.cta).toBeNull();
  });
});

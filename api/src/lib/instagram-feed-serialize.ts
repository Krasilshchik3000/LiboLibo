// Чистая функция сериализации InstagramPost (с relations) в DTO для iOS.
// Никакой работы с БД или сетью — для лёгкого тестирования.

interface MediaRow {
  order: number;
  kind: "IMAGE" | "VIDEO";
  filePath: string;
  thumbnailPath: string | null;
  width: number;
  height: number;
  durationSec: number | null;
}

interface EpisodeRow {
  id: string;
  title: string;
  podcastId: bigint;
}

interface PodcastRow {
  id: bigint;
  name: string;
}

export interface InstagramPostRow {
  id: string;
  igPermalink: string;
  type: "IMAGE" | "CAROUSEL" | "VIDEO";
  caption: string | null;
  publishedAt: Date | null;
  ctaType: "EPISODE" | "PODCAST" | "LINK" | null;
  ctaEpisodeId: string | null;
  ctaPodcastId: bigint | null;
  ctaUrl: string | null;
  ctaLabel: string | null;
  media: MediaRow[];
  ctaEpisode: EpisodeRow | null;
  ctaPodcast: PodcastRow | null;
}

export interface SerializeOptions {
  mediaBaseUrl: string;
}

export function serializeInstagramPost(post: InstagramPostRow, opts: SerializeOptions) {
  const media = [...post.media]
    .sort((a, b) => a.order - b.order)
    .map((m) => ({
      kind: m.kind.toLowerCase() as "image" | "video",
      url: `${opts.mediaBaseUrl}/${m.filePath}`,
      thumbnailUrl: m.thumbnailPath ? `${opts.mediaBaseUrl}/${m.thumbnailPath}` : null,
      width: m.width,
      height: m.height,
      durationSec: m.durationSec,
    }));

  return {
    id: post.id,
    type: post.type.toLowerCase(),
    permalink: post.igPermalink,
    caption: post.caption,
    publishedAt: post.publishedAt?.toISOString() ?? null,
    media,
    cta: serializeCta(post),
  };
}

function serializeCta(post: InstagramPostRow) {
  if (!post.ctaType) return null;
  switch (post.ctaType) {
    case "EPISODE":
      if (!post.ctaEpisode) return null;
      return {
        type: "episode" as const,
        label: post.ctaLabel ?? "Слушать эпизод",
        episode: {
          id: post.ctaEpisode.id,
          title: post.ctaEpisode.title,
          podcastId: post.ctaEpisode.podcastId.toString(),
        },
      };
    case "PODCAST":
      if (!post.ctaPodcast) return null;
      return {
        type: "podcast" as const,
        label: post.ctaLabel ?? "Подкаст",
        podcast: {
          id: post.ctaPodcast.id.toString(),
          name: post.ctaPodcast.name,
        },
      };
    case "LINK":
      if (!post.ctaUrl) return null;
      return {
        type: "link" as const,
        label: post.ctaLabel ?? "Перейти",
        url: post.ctaUrl,
      };
  }
}

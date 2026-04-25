import type { Episode, Podcast } from "@prisma/client";

// Shape returned by /v1/podcasts and friends.
export interface PodcastDTO {
  id: number;
  name: string;
  artist: string | null;
  feed_url: string;
  artwork_url: string | null;
  description: string | null;
  genres: string[];
  has_premium: boolean;
  // ISO timestamp последнего выпуска. Клиент использует, чтобы делить
  // подкасты на «выходят сейчас / недавно / давно не выходят».
  last_episode_date: string | null;
}

export interface EpisodeDTO {
  id: string;
  podcast_id: number;
  podcast_name: string;
  podcast_artwork_url: string | null;
  title: string;
  summary: string | null;
  pub_date: string;
  duration_sec: number | null;
  audio_url: string | null;
  is_premium: boolean;
}

export function podcastToDTO(p: Podcast): PodcastDTO {
  return {
    id: Number(p.id),
    name: p.name,
    artist: p.artist,
    feed_url: p.feedUrl,
    artwork_url: p.artworkUrl,
    description: p.description,
    genres: p.genres,
    has_premium: p.hasPremium,
    last_episode_date: p.lastEpisodeDate ? p.lastEpisodeDate.toISOString() : null,
  };
}

// `podcast` arg lets us include podcast name + artwork without a join per row.
//
// `viewer.hasPremiumEntitlement` controls premium gating:
//   - false (default, phase 2.0): metadata is the teaser; audio_url is null
//     for premium episodes; everyone sees the teaser.
//   - true (phase 2.3, after IAP): paid subscribers also get audio_url for
//     premium episodes.
// Public (non-premium) episodes always include audio_url.
export interface ViewerContext {
  hasPremiumEntitlement: boolean;
}

const ANONYMOUS: ViewerContext = { hasPremiumEntitlement: false };

export function episodeToDTO(
  e: Episode,
  podcast: Pick<Podcast, "name" | "artworkUrl">,
  viewer: ViewerContext = ANONYMOUS,
): EpisodeDTO {
  const audioUrl =
    !e.isPremium || viewer.hasPremiumEntitlement ? e.audioUrl : null;

  return {
    id: e.id,
    podcast_id: Number(e.podcastId),
    podcast_name: podcast.name,
    podcast_artwork_url: podcast.artworkUrl,
    title: e.title,
    summary: e.summary,
    pub_date: e.pubDate.toISOString(),
    duration_sec: e.durationSec,
    audio_url: audioUrl,
    is_premium: e.isPremium,
  };
}

import { describe, it, expect } from "vitest";
import { episodeToDTO } from "../src/lib/serialize.js";

const podcast = { name: "Запуск завтра", artworkUrl: "https://example.com/art.jpg" };

const baseEpisode = {
  id: "ep-1",
  podcastId: 48202n,
  title: "Эпизод",
  summary: "Описание",
  pubDate: new Date("2026-04-01T10:00:00.000Z"),
  durationSec: 1800,
  audioUrl: "https://media.example.com/ep1.mp3",
  isPremium: false,
  createdAt: new Date(),
  updatedAt: new Date(),
};

describe("episodeToDTO premium gating", () => {
  it("public episode: audio_url is always present", () => {
    const anon = episodeToDTO(baseEpisode, podcast);
    expect(anon.audio_url).toBe(baseEpisode.audioUrl);

    const paid = episodeToDTO(baseEpisode, podcast, { hasPremiumEntitlement: true });
    expect(paid.audio_url).toBe(baseEpisode.audioUrl);
  });

  it("premium episode without entitlement: audio_url is null", () => {
    const ep = { ...baseEpisode, isPremium: true };
    const dto = episodeToDTO(ep, podcast);
    expect(dto.is_premium).toBe(true);
    expect(dto.audio_url).toBeNull();
  });

  it("premium episode with entitlement: audio_url is exposed", () => {
    const ep = { ...baseEpisode, isPremium: true };
    const dto = episodeToDTO(ep, podcast, { hasPremiumEntitlement: true });
    expect(dto.is_premium).toBe(true);
    expect(dto.audio_url).toBe(ep.audioUrl);
  });
});

import { describe, it, expect } from "vitest";
import { parseRSS } from "../src/transistor/parser.js";

const SAMPLE = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Тестовый подкаст</title>
    <description>&lt;p&gt;Описание шоу&lt;/p&gt;&lt;br&gt;Документальные истории.</description>
    <item>
      <title>Эпизод 1</title>
      <description>Описание эпизода 1</description>
      <pubDate>Tue, 22 Apr 2026 09:00:00 +0000</pubDate>
      <guid isPermaLink="false">guid-episode-1</guid>
      <enclosure url="https://media.example.com/ep1.mp3" type="audio/mpeg" length="123" />
      <itunes:duration>01:23:45</itunes:duration>
    </item>
    <item>
      <title>Эпизод 2</title>
      <pubDate>Wed, 23 Apr 2026 10:00:00 +0000</pubDate>
      <enclosure url="https://media.example.com/ep2.mp3" type="audio/mpeg" length="456" />
      <itunes:duration>3600</itunes:duration>
    </item>
    <item>
      <title>Битый эпизод без enclosure</title>
      <pubDate>Thu, 24 Apr 2026 11:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>`;

describe("parseRSS", () => {
  it("парсит валидные эпизоды и пропускает битые", () => {
    const { episodes } = parseRSS(SAMPLE);
    expect(episodes).toHaveLength(2);

    const ep1 = episodes[0]!;
    expect(ep1.id).toBe("guid-episode-1");
    expect(ep1.title).toBe("Эпизод 1");
    expect(ep1.summary).toBe("Описание эпизода 1");
    expect(ep1.audioUrl).toBe("https://media.example.com/ep1.mp3");
    expect(ep1.durationSec).toBe(1 * 3600 + 23 * 60 + 45);

    const ep2 = episodes[1]!;
    expect(ep2.id).toBe("https://media.example.com/ep2.mp3"); // fallback to enclosure
    expect(ep2.durationSec).toBe(3600); // bare seconds
  });

  it("вытаскивает channel-level description и стрипает HTML", () => {
    const { channel } = parseRSS(SAMPLE);
    expect(channel.description).toBe("Описание шоу\n\nДокументальные истории.");
  });

  it("возвращает пустой результат на мусоре", () => {
    expect(parseRSS("<not-rss/>").episodes).toEqual([]);
    expect(parseRSS("").episodes).toEqual([]);
    expect(parseRSS("").channel.description).toBeNull();
  });
});

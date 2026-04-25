// One-shot seed: load the 44 podcasts from `docs/specs/podcasts-feeds.json`
// into the `podcasts` table. Re-runnable; uses upsert by id.
//
// Run via: `npm run seed`.
//
// In Docker the JSON is bind-mounted at /app/seed/podcasts-feeds.json by
// docker-compose.yml; locally outside Docker we look up the path via repo root.

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { prisma } from "../db.js";

interface FeedFile {
  count: number;
  podcasts: SeedPodcast[];
}

interface SeedPodcast {
  id: number;
  name: string;
  artist?: string;
  feedUrl: string;
  artworkUrl?: string;
  description?: string;
  genres?: string[];
  lastEpisodeDate?: string; // ISO date — оба источника (Apple + scripts/refresh-podcast-metadata.py)
}

async function locatePodcastsFile(): Promise<string> {
  const candidates = [
    "/app/seed/podcasts-feeds.json", // docker-compose mount
    path.resolve(
      path.dirname(fileURLToPath(import.meta.url)),
      "../../../docs/specs/podcasts-feeds.json",
    ),
  ];
  for (const p of candidates) {
    try {
      await fs.access(p);
      return p;
    } catch {
      // try next
    }
  }
  throw new Error(
    `Не нашёл podcasts-feeds.json. Проверил: ${candidates.join(", ")}`,
  );
}

async function main() {
  const file = await locatePodcastsFile();
  const raw = await fs.readFile(file, "utf8");
  const data = JSON.parse(raw) as FeedFile;

  console.log(`Сидинг: ${data.podcasts.length} подкастов из ${file}`);

  for (const p of data.podcasts) {
    const lastEpisodeDate = p.lastEpisodeDate ? new Date(p.lastEpisodeDate) : null;
    await prisma.podcast.upsert({
      where: { id: BigInt(p.id) },
      create: {
        id: BigInt(p.id),
        name: p.name,
        artist: p.artist ?? null,
        feedUrl: p.feedUrl,
        artworkUrl: p.artworkUrl ?? null,
        description: p.description ?? null,
        genres: p.genres ?? [],
        lastEpisodeDate,
      },
      update: {
        name: p.name,
        artist: p.artist ?? null,
        feedUrl: p.feedUrl,
        artworkUrl: p.artworkUrl ?? null,
        description: p.description ?? null,
        genres: p.genres ?? [],
        // На update lastEpisodeDate не трогаем — refresh.ts держит его свежим
        // по реальным эпизодам в БД, не по бандлу.
      },
    });
  }

  const total = await prisma.podcast.count();
  console.log(`Готово. В БД сейчас ${total} подкастов.`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

// Дозаполнение эмбеддингов эпизодов. Считает векторы только для тех, у кого
// embedding IS NULL или embedding_text разошёлся с текущим текстом (эпизод
// отредактировали). Идемпотентно: повторный прогон без изменений ничего не
// пересчитывает. Вызывается из transistor/refresh.ts после upsert эпизодов.

import pgvector from "pgvector";
import { prisma } from "../db.js";
import { embedPassage, episodeEmbeddingText } from "./semanticSearch.js";

interface Row {
  id: string;
  title: string;
  summary: string | null;
}

export interface EmbedSummary {
  scanned: number;
  embedded: number;
}

// Размер пачки для прогресс-лога: эмбеддинги считаются по одному (модель
// однопоточная), батч — только гранулярность логирования.
const BATCH = 50;

export async function embedMissingEpisodes(): Promise<EmbedSummary> {
  // Кандидаты: вектор пуст ИЛИ текст изменился с момента последнего расчёта.
  // CASE-выражение должно точно повторять episodeEmbeddingText() — см.
  // предупреждение в semanticSearch.ts.
  const rows = await prisma.$queryRaw<Row[]>`
    SELECT e.id, e.title, e.summary
    FROM episodes e
    WHERE e.embedding IS NULL
       OR e.embedding_text IS DISTINCT FROM (
            CASE
              WHEN COALESCE(e.summary, '') = '' THEN e.title
              ELSE e.title || '. ' || LEFT(e.summary, 1000)
            END
          )
  `;

  let embedded = 0;
  for (let i = 0; i < rows.length; i += BATCH) {
    for (const r of rows.slice(i, i + BATCH)) {
      const text = episodeEmbeddingText({ title: r.title, summary: r.summary ?? "" });
      if (!text) continue; // пустые title и summary — нечего индексировать
      const vec = await embedPassage(text);
      await prisma.$executeRaw`
        UPDATE episodes
        SET embedding = ${pgvector.toSql(vec)}::vector,
            embedding_text = ${text}
        WHERE id = ${r.id}
      `;
      embedded += 1;
    }
    console.log(`[embed] ${Math.min(i + BATCH, rows.length)}/${rows.length} done`);
  }

  return { scanned: rows.length, embedded };
}

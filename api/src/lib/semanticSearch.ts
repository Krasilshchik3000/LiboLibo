// Сервис семантического поиска: считает эмбеддинги текста через локальную
// модель (Transformers.js, multilingual-e5-small) и держит векторы эпизодов
// в памяти процесса. Никаких API-ключей и внешних сервисов — модель ~110 МБ
// скачивается один раз при первом обращении и кешируется на диске
// (@huggingface/transformers сам кеширует в node_modules/.cache).
//
// Дизайн повторяет паттерн «optional integration» из lib/adapty.ts и
// instagram/config.ts: пока модель не загружена/недоступна — ручка отдаёт
// 503, остальной бэкенд работает как раньше. Поиск по словам в iOS-клиенте
// (Features/Search/SearchView.swift) при этом продолжает работать
// независимо: семантика — дополнительный слой, а не замена.
//
// Префиксы "query:" / "passage:" обязательны для e5-моделей — без них
// качество заметно падает (так предписывает карточка модели intfloat/e5).

import type { FeatureExtractionPipeline } from "@xenova/transformers";
import { cosineSimilarity, rankBySimilarity, type Scored } from "./semanticRank.js";

const MODEL_ID = "Xenova/multilingual-e5-small";

export interface EmbeddableEpisode {
  id: string;
  title: string;
  summary: string;
}

interface IndexedEpisode {
  id: string;
  vector: number[];
}

// Singleton состояние сервиса на процесс. tsx watch в dev пересоздаёт модуль
// при хот-релоаде — для прода (один процесс) этого достаточно; кеш просто
// прогреется заново. Аналогично globalThis-кешу PrismaClient в db.ts можно
// при желании закешировать и тут, но модель тяжёлая и грузится лениво, так
// что лишний прогрев в dev приемлем.
let pipelinePromise: Promise<FeatureExtractionPipeline> | null = null;
const index = new Map<string, IndexedEpisode>();

async function getPipeline(): Promise<FeatureExtractionPipeline> {
  if (!pipelinePromise) {
    // Динамический импорт: тяжёлую зависимость не тянем в память, пока
    // семантический поиск реально не понадобился. Если пакет не установлен
    // или модель не скачалась — отлетит сюда, ручка превратит это в 503.
    pipelinePromise = import("@xenova/transformers").then(({ pipeline }) =>
      pipeline("feature-extraction", MODEL_ID),
    );
  }
  return pipelinePromise;
}

async function embed(text: string, kind: "query" | "passage"): Promise<number[]> {
  const pipe = await getPipeline();
  const prefixed = `${kind}: ${text}`;
  const output = await pipe(prefixed, { pooling: "mean", normalize: true });
  return Array.from(output.data as Float32Array);
}

function episodeText(ep: EmbeddableEpisode): string {
  // title несёт основную смысловую нагрузку, summary уточняет. Обрезаем
  // summary, чтобы не упереться в лимит длины модели (512 токенов) и не
  // размывать вектор слишком длинным описанием.
  const summary = ep.summary.slice(0, 1000);
  return summary ? `${ep.title}. ${summary}` : ep.title;
}

// Идемпотентно дозаполняет индекс: считает эмбеддинги только для эпизодов,
// которых ещё нет в кеше. Вызывается ручкой перед поиском — на первом
// запросе прогревает весь корпус, дальше досчитывает только новые эпизоды.
export async function ensureIndexed(episodes: EmbeddableEpisode[]): Promise<void> {
  for (const ep of episodes) {
    if (index.has(ep.id)) continue;
    const vector = await embed(episodeText(ep), "passage");
    index.set(ep.id, { id: ep.id, vector });
  }
}

export interface SemanticHit {
  episodeId: string;
  score: number;
}

// Семантический поиск по проиндексированным эпизодам. Возвращает id +score,
// ранжированные по убыванию близости. Сам объект эпизода не трогаем — роутер
// дотянет полные данные из БД и сериализует через episodeToDTO, чтобы
// premium-гейтинг и формат ответа были консистентны с остальным API.
export async function semanticSearch(
  query: string,
  options: { limit: number; minScore?: number },
): Promise<SemanticHit[]> {
  const queryVector = await embed(query, "query");
  const candidates = Array.from(index.values()).map((e) => ({
    item: e.id,
    vector: e.vector,
  }));
  const ranked: Scored<string>[] = rankBySimilarity(queryVector, candidates, options);
  return ranked.map((r) => ({ episodeId: r.item, score: r.score }));
}

export function indexSize(): number {
  return index.size;
}

// Экспортируем для тестов/отладки: позволяет посчитать близость двух строк
// напрямую, без обращения к БД.
export async function debugSimilarity(a: string, b: string): Promise<number> {
  const [va, vb] = await Promise.all([embed(a, "query"), embed(b, "passage")]);
  return cosineSimilarity(va, vb);
}

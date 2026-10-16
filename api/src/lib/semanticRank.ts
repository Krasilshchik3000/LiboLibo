// Чистые функции для семантического ранжирования. Никакого I/O, сети или
// модели — только математика над уже посчитанными векторами. Это позволяет
// покрыть ранжирование юнит-тестами без загрузки ML-модели (см.
// test/semanticRank.test.ts), ровно как lib/serialize.ts тестируется без БД.

// Косинусная близость двух векторов одинаковой длины. Если оба вектора уже
// L2-нормализованы (как их отдаёт e5 с `normalize: true`), это просто
// скалярное произведение — но мы не полагаемся на это и нормализуем честно,
// чтобы функция была корректна для любых входов.
export function cosineSimilarity(a: readonly number[], b: readonly number[]): number {
  if (a.length !== b.length) {
    throw new Error(`cosineSimilarity: length mismatch ${a.length} vs ${b.length}`);
  }
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    const x = a[i]!;
    const y = b[i]!;
    dot += x * y;
    normA += x * x;
    normB += y * y;
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

export interface Scored<T> {
  item: T;
  score: number;
}

// Ранжирует кандидатов по близости их вектора к вектору запроса.
// Отсекает по minScore (порог релевантности) и обрезает до limit.
// Стабильно: при равных score сохраняется исходный порядок (важно для
// детерминизма тестов и предсказуемой выдачи).
export function rankBySimilarity<T>(
  queryVector: readonly number[],
  candidates: ReadonlyArray<{ item: T; vector: readonly number[] }>,
  options: { limit: number; minScore?: number },
): Scored<T>[] {
  const minScore = options.minScore ?? 0;
  const scored: Array<Scored<T> & { index: number }> = [];
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i]!;
    const score = cosineSimilarity(queryVector, c.vector);
    if (score >= minScore) {
      scored.push({ item: c.item, score, index: i });
    }
  }
  scored.sort((a, b) => (b.score - a.score) || (a.index - b.index));
  return scored.slice(0, options.limit).map(({ item, score }) => ({ item, score }));
}

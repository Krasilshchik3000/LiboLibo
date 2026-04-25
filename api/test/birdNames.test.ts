import { describe, it, expect } from "vitest";
import { BIRDS, pickBirdName, withSuffix } from "../src/lib/birdNames.js";

// Multi-word bird names are allowed (e.g. "Серая ворона", "Чёрный аист").
// Hyphens within a word are allowed ("Поползень-крошка"). Only the first
// word is capitalized; subsequent words are lowercase.
const NAME_RE = /^[А-ЯЁ][а-яё-]+( [а-яё-]+)*$/;

describe("BIRDS pool", () => {
  it("contains at least 1000 unique entries", () => {
    expect(BIRDS.length).toBeGreaterThanOrEqual(1000);
    expect(new Set(BIRDS).size).toBe(BIRDS.length);
  });

  it("contains only well-formed Russian bird names", () => {
    const bad = BIRDS.filter((n) => !NAME_RE.test(n));
    expect(bad).toEqual([]);
  });
});

describe("pickBirdName", () => {
  it("is deterministic: same profileId → same name", () => {
    const a = pickBirdName("11111111-1111-4111-8111-111111111111");
    const b = pickBirdName("11111111-1111-4111-8111-111111111111");
    expect(a).toBe(b);
  });

  it("returns a name from the pool", () => {
    const name = pickBirdName("22222222-2222-4222-8222-222222222222");
    expect(BIRDS).toContain(name);
  });

  it("distributes across the pool (different ids → different names, mostly)", () => {
    const names = new Set<string>();
    for (let i = 0; i < 200; i++) {
      const id = `${i.toString(16).padStart(8, "0")}-1111-4111-8111-111111111111`;
      names.add(pickBirdName(id));
    }
    expect(names.size).toBeGreaterThan(150);
  });
});

describe("withSuffix", () => {
  it("appends -N to the base name", () => {
    expect(withSuffix("Сорока", 2)).toBe("Сорока-2");
    expect(withSuffix("Сорока", 7)).toBe("Сорока-7");
  });

  it("rejects suffix < 2 (the bare name is the n=1 case)", () => {
    expect(() => withSuffix("Сорока", 1)).toThrow();
    expect(() => withSuffix("Сорока", 0)).toThrow();
  });
});

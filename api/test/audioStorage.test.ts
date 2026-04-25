import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createAudioStorage } from "../src/lib/audioStorage.js";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(path.join(tmpdir(), "libolibo-audio-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("audioStorage", () => {
  it("saves a buffer and returns a path inside the configured dir", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    // 16 bytes — content doesn't matter, only that the file is written.
    const buf = Buffer.from([
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20,
      0x00, 0x00, 0x00, 0x00,
    ]);

    const result = await storage.save(buf);

    expect(result.path.startsWith(dir + path.sep)).toBe(true);
    expect(result.path.endsWith(".m4a")).toBe(true);
    expect(result.size).toBe(buf.length);
    const written = await readFile(result.path);
    expect(written.equals(buf)).toBe(true);
  });

  it("delete removes the file", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    const { path: p } = await storage.save(Buffer.from("data"));
    await storage.delete(p);
    await expect(readFile(p)).rejects.toThrow();
  });

  it("delete is idempotent — non-existent path does not throw", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    await expect(
      storage.delete(path.join(dir, "missing.m4a")),
    ).resolves.toBeUndefined();
  });

  it("rejects paths outside the base dir (path-traversal guard)", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    await expect(storage.delete("/etc/passwd")).rejects.toThrow(/outside/);
  });

  it("creates the base dir if missing", async () => {
    const nested = path.join(dir, "nested", "dir");
    const storage = createAudioStorage({ baseDir: nested });
    const result = await storage.save(Buffer.from("data"));
    expect(result.path.startsWith(nested + path.sep)).toBe(true);
  });
});

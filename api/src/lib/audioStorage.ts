import { mkdir, unlink, writeFile, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type { Response } from "express";

export interface AudioStorageConfig {
  baseDir: string;
}

export interface SavedAudio {
  path: string;
  size: number;
}

export interface AudioStorage {
  save(buf: Buffer): Promise<SavedAudio>;
  delete(filePath: string): Promise<void>;
  stream(filePath: string, res: Response): Promise<void>;
}

export function createAudioStorage(cfg: AudioStorageConfig): AudioStorage {
  const baseDir = path.resolve(cfg.baseDir);

  async function ensureDir() {
    await mkdir(baseDir, { recursive: true });
  }

  function assertInBase(p: string) {
    const resolved = path.resolve(p);
    if (!resolved.startsWith(baseDir + path.sep) && resolved !== baseDir) {
      throw new Error(`refusing to operate on path outside ${baseDir}: ${p}`);
    }
  }

  return {
    async save(buf) {
      await ensureDir();
      const filePath = path.join(baseDir, `${randomUUID()}.m4a`);
      await writeFile(filePath, buf);
      return { path: filePath, size: buf.length };
    },
    async delete(filePath) {
      assertInBase(filePath);
      try {
        await unlink(filePath);
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return;
        throw err;
      }
    },
    async stream(filePath, res) {
      assertInBase(filePath);
      const s = await stat(filePath);
      res.setHeader("Content-Type", "audio/mp4");
      res.setHeader("Content-Length", String(s.size));
      res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
      res.setHeader("ETag", path.basename(filePath, ".m4a"));
      await new Promise<void>((resolve, reject) => {
        const stream = createReadStream(filePath);
        stream.on("end", () => resolve());
        stream.on("error", reject);
        stream.pipe(res);
      });
    },
  };
}

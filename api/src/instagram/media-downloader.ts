// Скачивает картинки/видео для постов, у которых ещё нет записей в
// instagram_media, и создаёт эти записи в одной транзакции с реально
// скачанным файлом. Запускается из refresh-cli после syncInstagramPosts.
//
// Инвариант: запись в instagram_media существует ⇒ файл реально лежит в
// MEDIA_DIR. Это упрощает раздачу и downloader: при перезапуске мы
// гарантированно НЕ скачали файлы для таких постов.

import { mkdir, writeFile, readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import { spawn } from "node:child_process";
import { imageSize } from "image-size";

import { prisma } from "../db.js";
import { isConfigured, readConfig, getMediaDir } from "./config.js";
import { fetchMediaDetails, type IgChildMedia, type IgMediaDetails } from "./graph-client.js";
import { extensionFor, parseFfprobeOutput, type IgMediaKind } from "./media-probe.js";

const POSTS_PER_RUN = 50;

export interface DownloadSummary {
  postsScanned: number;
  postsCompleted: number;
  filesWritten: number;
  errors: Array<{ postId: string; error: string }>;
}

export async function downloadPendingMedia(): Promise<DownloadSummary> {
  if (!isConfigured()) {
    return { postsScanned: 0, postsCompleted: 0, filesWritten: 0, errors: [] };
  }
  const config = readConfig();
  const mediaDir = getMediaDir();

  const posts = await prisma.instagramPost.findMany({
    where: { media: { none: {} } },
    select: { id: true, igMediaId: true, type: true },
    orderBy: { igCreatedAt: "desc" },
    take: POSTS_PER_RUN,
  });

  const summary: DownloadSummary = {
    postsScanned: posts.length,
    postsCompleted: 0,
    filesWritten: 0,
    errors: [],
  };

  for (const post of posts) {
    try {
      const details = await fetchMediaDetails(config, post.igMediaId);
      const items = expandToItems(post.type, details);
      const writtenItems: WrittenItem[] = [];

      for (let order = 0; order < items.length; order++) {
        const written = await downloadOne(post.id, order, items[order]!, mediaDir);
        writtenItems.push(written);
        summary.filesWritten += 1;
      }

      await prisma.$transaction(
        writtenItems.map((w, order) =>
          prisma.instagramMedia.create({
            data: {
              postId: post.id,
              order,
              kind: w.kind,
              filePath: w.filePath,
              thumbnailPath: w.thumbnailPath,
              width: w.width,
              height: w.height,
              durationSec: w.durationSec,
            },
          }),
        ),
      );
      summary.postsCompleted += 1;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      summary.errors.push({ postId: post.id, error: msg });
    }
  }

  return summary;
}

interface Item {
  kind: IgMediaKind;
  mediaUrl: string;
}

interface WrittenItem {
  kind: IgMediaKind;
  filePath: string;
  thumbnailPath: string | null;
  width: number;
  height: number;
  durationSec: number | null;
}

function expandToItems(
  type: "IMAGE" | "CAROUSEL" | "VIDEO",
  details: IgMediaDetails,
): Item[] {
  if (type === "CAROUSEL") {
    return details.children
      .filter((c): c is IgChildMedia & { mediaUrl: string } => !!c.mediaUrl)
      .map((c) => ({ kind: c.mediaType, mediaUrl: c.mediaUrl }));
  }
  if (!details.mediaUrl) {
    throw new Error(`media_url is null for ${type} post ${details.id}`);
  }
  return [
    {
      kind: type === "VIDEO" ? "VIDEO" : "IMAGE",
      mediaUrl: details.mediaUrl,
    },
  ];
}

async function downloadOne(
  postId: string,
  order: number,
  item: Item,
  mediaDir: string,
): Promise<WrittenItem> {
  const ext = extensionFor(item.kind);
  const relPath = `${postId}/${order}.${ext}`;
  const absPath = join(mediaDir, relPath);
  await mkdir(dirname(absPath), { recursive: true });
  await downloadToFile(item.mediaUrl, absPath);

  if (item.kind === "IMAGE") {
    const buf = await readFile(absPath);
    const dims = imageSize(buf);
    return {
      kind: "IMAGE",
      filePath: relPath,
      thumbnailPath: null,
      width: dims.width ?? 0,
      height: dims.height ?? 0,
      durationSec: null,
    };
  }

  // VIDEO: ffprobe → размеры/длительность, ffmpeg → thumbnail.
  const probeStdout = await runCmd("ffprobe", [
    "-v", "error",
    "-print_format", "json",
    "-show_streams",
    "-show_format",
    absPath,
  ]);
  const meta = parseFfprobeOutput(probeStdout);

  const thumbRel = `${postId}/${order}.thumb.jpg`;
  const thumbAbs = join(mediaDir, thumbRel);
  await runCmd("ffmpeg", [
    "-y",
    "-ss", "0",
    "-i", absPath,
    "-frames:v", "1",
    "-q:v", "3",
    thumbAbs,
  ]);

  return {
    kind: "VIDEO",
    filePath: relPath,
    thumbnailPath: thumbRel,
    width: meta.width,
    height: meta.height,
    durationSec: meta.durationSec,
  };
}

async function downloadToFile(url: string, dest: string): Promise<void> {
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`download HTTP ${resp.status}`);
  const buf = Buffer.from(await resp.arrayBuffer());
  await writeFile(dest, buf);
}

async function runCmd(cmd: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`${cmd} exit ${code}: ${stderr.slice(0, 500)}`));
    });
  });
}

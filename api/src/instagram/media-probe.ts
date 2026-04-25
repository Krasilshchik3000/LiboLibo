// Helpers for parsing ffprobe output and picking file extensions.
// Pure functions — no I/O, easy to unit-test.

export interface VideoMeta {
  width: number;
  height: number;
  durationSec: number;
}

interface RawProbe {
  streams?: Array<{
    codec_type?: string;
    width?: number;
    height?: number;
    duration?: string;
  }>;
  format?: { duration?: string };
}

export function parseFfprobeOutput(stdout: string): VideoMeta {
  const probe = JSON.parse(stdout) as RawProbe;
  const video = (probe.streams ?? []).find((s) => s.codec_type === "video");
  if (!video) throw new Error("ffprobe: no video stream");
  if (!video.width || !video.height) {
    throw new Error("ffprobe: video stream missing width/height");
  }
  const rawDuration = video.duration ?? probe.format?.duration ?? "0";
  const durationSec = Math.round(Number(rawDuration));
  return { width: video.width, height: video.height, durationSec };
}

export type IgMediaKind = "IMAGE" | "VIDEO";

export function extensionFor(kind: IgMediaKind): "jpg" | "mp4" {
  return kind === "VIDEO" ? "mp4" : "jpg";
}

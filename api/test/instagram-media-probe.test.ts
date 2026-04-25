import { describe, it, expect } from "vitest";
import { parseFfprobeOutput, extensionFor } from "../src/instagram/media-probe.js";

describe("parseFfprobeOutput", () => {
  it("извлекает width/height/duration из видео-стрима", () => {
    const json = JSON.stringify({
      streams: [
        { codec_type: "audio", duration: "23.5" },
        { codec_type: "video", width: 1080, height: 1920, duration: "23.456" },
      ],
      format: { duration: "23.5" },
    });
    expect(parseFfprobeOutput(json)).toEqual({
      width: 1080,
      height: 1920,
      durationSec: 23,
    });
  });

  it("использует format.duration если у стрима его нет", () => {
    const json = JSON.stringify({
      streams: [{ codec_type: "video", width: 720, height: 1280 }],
      format: { duration: "12.9" },
    });
    expect(parseFfprobeOutput(json)).toEqual({ width: 720, height: 1280, durationSec: 13 });
  });

  it("кидает ошибку если video-стрима нет", () => {
    const json = JSON.stringify({ streams: [], format: {} });
    expect(() => parseFfprobeOutput(json)).toThrow(/no video stream/i);
  });
});

describe("extensionFor", () => {
  it("video → mp4", () => {
    expect(extensionFor("VIDEO")).toBe("mp4");
  });
  it("image → jpg", () => {
    expect(extensionFor("IMAGE")).toBe("jpg");
  });
});

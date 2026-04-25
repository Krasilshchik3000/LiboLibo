import { describe, expect, it } from "vitest";
import { isLikelyM4A } from "../src/lib/audioMime.js";

describe("isLikelyM4A", () => {
  it("returns true for a buffer starting with the m4a ftyp box", () => {
    // 4 size bytes + 'ftyp' + brand 'M4A '
    const buf = Buffer.from([
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20,
      0x00, 0x00, 0x00, 0x00,
    ]);
    expect(isLikelyM4A(buf)).toBe(true);
  });

  it("returns true for ftyp brand mp42 (also AAC-in-MP4)", () => {
    const buf = Buffer.from([
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x6d, 0x70, 0x34, 0x32,
    ]);
    expect(isLikelyM4A(buf)).toBe(true);
  });

  it("returns false for an mp3 buffer", () => {
    // ID3v2 header
    const buf = Buffer.from([0x49, 0x44, 0x33, 0x03, 0x00]);
    expect(isLikelyM4A(buf)).toBe(false);
  });

  it("returns false for a too-short buffer", () => {
    expect(isLikelyM4A(Buffer.from([0x00, 0x01]))).toBe(false);
  });

  it("returns false for empty buffer", () => {
    expect(isLikelyM4A(Buffer.alloc(0))).toBe(false);
  });
});

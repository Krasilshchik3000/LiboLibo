// MP4-family magic-byte detector. m4a/AAC files are MP4 containers with a
// `ftyp` box at offset 4. We don't validate the brand strictly — Apple
// emits various brands (M4A , mp42, isom, …) depending on encoder settings.
// The 'ftyp' marker at offset 4 is the reliable signal.
export function isLikelyM4A(buf: Buffer): boolean {
  if (buf.length < 12) return false;
  // bytes 4..8 must be 'ftyp'
  return (
    buf[4] === 0x66 && // 'f'
    buf[5] === 0x74 && // 't'
    buf[6] === 0x79 && // 'y'
    buf[7] === 0x70 // 'p'
  );
}

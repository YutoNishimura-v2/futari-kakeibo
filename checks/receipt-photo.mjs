const longEdge = 1600;
const maximumBytes = 2_000_000;

export function targetSize(width, height) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    return null;
  }
  const longest = Math.max(width, height);
  if (longest <= longEdge) return { width, height };

  const scale = longEdge / longest;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

export function fits(byteCount) {
  return Number.isInteger(byteCount) && byteCount > 0 && byteCount <= maximumBytes;
}

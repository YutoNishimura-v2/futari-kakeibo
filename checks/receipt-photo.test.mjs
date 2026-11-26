import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { fits, targetSize } from './receipt-photo.mjs';

const swift = readFileSync(new URL('../Sources/FutariKakeibo/ReceiptPhoto.swift', import.meta.url), 'utf8');

test('receipt target caps the long edge in both orientations without upscaling', () => {
  assert.deepEqual(targetSize(4032, 3024), { width: 1600, height: 1200 });
  assert.deepEqual(targetSize(3024, 4032), { width: 1200, height: 1600 });
  assert.deepEqual(targetSize(2048, 2048), { width: 1600, height: 1600 });
  assert.deepEqual(targetSize(800, 1200), { width: 800, height: 1200 });
  assert.deepEqual(targetSize(1600, 1173), { width: 1600, height: 1173 });
  assert.match(swift, /static let longEdge = 1600\b/);
  assert.match(swift, /kCGImageSourceThumbnailMaxPixelSize: max\(target.width, target.height\)/);
});

test('receipt target rounds proportional dimensions and rejects invalid sizes', () => {
  assert.deepEqual(targetSize(1601, 901), { width: 1600, height: 900 });
  assert.deepEqual(targetSize(9000, 1), { width: 1600, height: 1 });
  assert.equal(targetSize(0, 100), null);
  assert.equal(targetSize(100, -1), null);
  assert.equal(targetSize(20.5, 100), null);
});

test('only nonempty JPEG output at or below the byte cap is accepted', () => {
  assert.equal(fits(0), false);
  assert.equal(fits(-1), false);
  assert.equal(fits(1), true);
  assert.equal(fits(1_999_999), true);
  assert.equal(fits(2_000_000), true);
  assert.equal(fits(2_000_001), false);
  assert.equal(fits(100.5), false);
  assert.match(swift, /static let maximumBytes = 2_000_000\b/);
  assert.match(swift, /UTType\.jpeg\.identifier[\s\S]*if fits\(byteCount: bytes\.length\)/);
});

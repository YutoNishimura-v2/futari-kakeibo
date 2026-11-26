import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const candidates = new URL('../docs/icon/candidates/', import.meta.url);
const svgNamespace = 'http://www.w3.org/2000/svg';
const attributesByTag = {
  svg: ['xmlns', 'width', 'height', 'viewBox'],
  rect: ['x', 'y', 'width', 'height', 'rx', 'fill'],
  circle: ['cx', 'cy', 'r', 'fill'],
  path: ['d', 'fill', 'fill-rule'],
  text: ['x', 'y', 'fill', 'font-size'],
};

function readAttributes(source, tag) {
  const attributes = new Map();
  const attribute = /\s+([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"<&]*)"|'([^'<&]*)')/y;
  while (source.slice(attribute.lastIndex).trim()) {
    const match = attribute.exec(source);
    assert.ok(match, 'malformed SVG attributes');
    const [, name, doubleQuoted, singleQuoted] = match;
    assert.ok(attributesByTag[tag].includes(name), 'unsupported attribute: ' + name);
    assert.ok(!attributes.has(name), 'duplicate attribute: ' + name);
    attributes.set(name, doubleQuoted ?? singleQuoted);
  }
  return attributes;
}

function validateIcon(source) {
  // This flat SVG subset excludes styles, scripts, references, and image elements.
  assert.doesNotMatch(source, /[^\u0009\u000a\u000d\u0020-\ud7ff\ue000-\ufffd\u{10000}-\u{10ffff}]/u, 'invalid XML character');
  const root = /^<svg(?=\s|>)([^<>]*)>([\s\S]*)<\/svg>$/.exec(source.trim());
  assert.ok(root, 'expected one SVG root');
  const attributes = readAttributes(root[1], 'svg');
  assert.equal(attributes.get('xmlns'), svgNamespace);
  assert.equal(attributes.get('width'), '1024');
  assert.equal(attributes.get('height'), '1024');
  assert.deepEqual(attributes.get('viewBox')?.trim().split(/\s+/), ['0', '0', '1024', '1024']);

  const body = root[2].trim();
  const element = /\s*<(rect|circle|path|text)(?=[\s/>])([^<>]*?)(?:\/>|>([^<&]*)<\/\1>)/y;
  const colors = new Set();
  let shapeCount = 0;
  let glyphCount = 0;
  while (element.lastIndex < body.length) {
    const match = element.exec(body);
    assert.ok(match, 'malformed or unsupported SVG element');
    const [, tag, attributeSource, content] = match;
    const shape = readAttributes(attributeSource, tag);
    const fill = shape.get('fill');
    assert.match(fill ?? '', /^#[0-9a-f]{6}$/i, 'expected an opaque flat fill');
    colors.add(fill.toUpperCase());

    if (shapeCount === 0) {
      assert.equal(tag, 'rect', 'expected a full-bleed background');
      assert.equal(shape.get('x') ?? '0', '0');
      assert.equal(shape.get('y') ?? '0', '0');
      assert.equal(shape.get('width'), '1024');
      assert.equal(shape.get('height'), '1024');
      assert.equal(shape.get('rx') ?? '0', '0');
    }
    if (tag === 'text') {
      glyphCount += Array.from(content?.trim() ?? '').length;
      assert.ok(glyphCount <= 1, 'text exceeds one character');
    } else {
      assert.ok(!content?.trim(), 'unexpected content in ' + tag);
    }
    shapeCount += 1;
  }
  assert.ok(shapeCount > 1, 'expected artwork over the background');
  assert.ok(colors.size <= 3, 'expected no more than three flat colors');
}

for (const name of ['a.svg', 'b.svg', 'c.svg']) {
  test(name + ' is a self-contained 1024px vector icon', () => {
    validateIcon(readFileSync(new URL(name, candidates), 'utf8'));
  });
}

test('icon check distinguishes one glyph from invalid SVG and unsupported content', () => {
  const svg = readFileSync(new URL('a.svg', candidates), 'utf8');
  const append = (element) => svg.replace('</svg>', element + '</svg>');
  assert.doesNotThrow(() => validateIcon(append('<text fill="#174938">¥</text>')));
  assert.throws(() => validateIcon(svg.replace('viewBox="0 0 1024 1024"', 'viewBox="0 0 60 60"')), /1024/);
  assert.throws(() => validateIcon(append('<text fill="#174938">家計</text>')), /exceeds one character/);
  assert.throws(() => validateIcon(append('<text fill="#174938">家</text><text fill="#174938">計</text>')), /exceeds one character/);
  assert.throws(() => validateIcon(append('<text fill="#174938">\u0000</text>')), /invalid XML character/);
  assert.throws(() => validateIcon(append('<path href="https://example.com/icon.svg" fill="#174938"/>')), /unsupported attribute: href/);
  assert.throws(() => validateIcon(append('<image href="data:image/png;base64,AAAA"/>')), /unsupported SVG element/);
  assert.throws(() => validateIcon(append('<path fill="#174938">')), /malformed/);
});

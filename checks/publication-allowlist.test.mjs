import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

test('publication allowlist contains only documented lowercase SHA-256 fingerprints', () => {
  const config = JSON.parse(readFileSync(new URL('../land.json', import.meta.url), 'utf8'));
  const allow = config.publish?.allow;
  assert.ok(Array.isArray(allow), 'publish.allow must be an array');

  const review = readFileSync(new URL('../docs/publish-review.md', import.meta.url), 'utf8');
  const [, section] = review.split(/^## Publication allowlist\r?$/m);
  assert.notEqual(section, undefined, 'docs/publish-review.md must have a Publication allowlist section');

  const table = section.split(/^#{1,2} /m)[0];
  const approvedRows = /^\| `([0-9a-f]{64})` \| [^|]+ \| [^|]+ \| [^|]+ \| 許可（[^|]+） \|\r?$/gm;
  const approved = new Set(Array.from(table.matchAll(approvedRows), (match) => match[1]));

  for (const [index, fingerprint] of allow.entries()) {
    assert.ok(
      typeof fingerprint === 'string' && fingerprint.length === 64 && /^[0-9a-f]+$/.test(fingerprint),
      `publish.allow[${index}] must be 64 lowercase hexadecimal characters`,
    );
    assert.ok(approved.has(fingerprint), `publish.allow[${index}] is missing an approved review row`);
  }
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const metadataPath = new URL('../docs/app-store/metadata.ja.json', import.meta.url);

function validateMetadata(metadata) {
  const limits = { name: 30, subtitle: 30, searchTerms: 100, description: 4000, whatsNew: 4000 };
  for (const [field, limit] of Object.entries(limits)) {
    const value = metadata[field];
    assert.ok(typeof value === 'string' && value.trim(), `${field} must be a nonempty string`);
    const length = Array.from(value).length;
    assert.ok(length <= limit, `${field} has ${length} characters; maximum is ${limit}`);
  }
  const searchTermBytes = Buffer.byteLength(metadata.searchTerms, 'utf8');
  assert.ok(searchTermBytes <= 100, `searchTerms has ${searchTermBytes} UTF-8 bytes; maximum is 100`);
}

test('the Japanese App Store draft fits the listing limits', () => {
  validateMetadata(JSON.parse(readFileSync(metadataPath, 'utf8')));
});

test('the listing explains solo entry and free iCloud sharing before Pro', () => {
  const { description } = JSON.parse(readFileSync(metadataPath, 'utf8'));
  const pro = description.indexOf('【Pro でできること】');
  assert.ok(pro > 0);
  const basics = description.slice(0, pro);
  assert.match(basics, /招待する前でも、ひとりで支出を記録できます/);
  assert.match(basics, /iCloud での共有と同期は無料です/);
  const catalog = JSON.parse(readFileSync(new URL('../FutariKakeibo.storekit', import.meta.url), 'utf8'));
  const [monthly, yearly] = catalog.subscriptionGroups[0].subscriptions.map(({ displayPrice }) => Number(displayPrice));
  const yearlyTotal = monthly * 12;
  const savings = Math.floor((1 - yearly / yearlyTotal) * 100);
  const yen = (price) => price.toLocaleString('ja-JP') + '円';

  assert.ok(description.includes('月額' + yen(monthly) + 'または年額' + yen(yearly) + 'の自動更新'));
  assert.ok(description.includes('一人の契約で、同じ共有家計簿のふたりとも Pro'));
  assert.ok(description.includes('月額12か月分の' + yen(yearlyTotal) + 'に比べて約' + savings + '%お得'));
});

test('metadata limits accept the boundary and reject overlong Japanese subtitles and keywords', () => {
  const boundary = {
    name: 'ふたりの家計簿',
    subtitle: '家'.repeat(30),
    searchTerms: 'a'.repeat(100),
    description: '家計簿の説明',
    whatsNew: '初回公開',
  };
  assert.doesNotThrow(() => validateMetadata(boundary));
  assert.throws(() => validateMetadata({ ...boundary, subtitle: '家'.repeat(31) }), /subtitle has 31 characters/);
  assert.throws(() => validateMetadata({ ...boundary, searchTerms: 'a'.repeat(101) }), /searchTerms has 101 characters/);
  assert.throws(() => validateMetadata({ ...boundary, searchTerms: '家'.repeat(34) }), /searchTerms has 102 UTF-8 bytes/);
});

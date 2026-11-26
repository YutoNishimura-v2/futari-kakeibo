import test from 'node:test';
import assert from 'node:assert/strict';
import { csv, mergeShopping, monthlySpending, settlementDate } from './paid-tools.mjs';

test('yearly spending fills empty months, sums records and observes year boundaries', () => {
  const start = Date.UTC(2026, 0, 1);
  const december = Date.UTC(2026, 11, 31);
  const range = monthlySpending([
    { date: start - 1, amount: 1000 },
    { date: start, amount: 101 },
    { date: Date.UTC(2026, 0, 31), amount: 200 },
    { date: december, amount: 99 },
    { date: Date.UTC(2027, 0, 1), amount: 600 },
  ], start, 12);
  assert.equal(range.length, 12);
  assert.deepEqual(range.map(({ amount }) => amount), [301, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99]);
});

test('month-over-month spending crosses New Year and preserves the safe integer limit', () => {
  const december = Date.UTC(2025, 11, 1);
  const january = Date.UTC(2026, 0, 1);
  assert.deepEqual(monthlySpending([{ date: january, amount: 10 }], december, 2), [
    { month: december, amount: 0 }, { month: january, amount: 10 },
  ]);
  assert.throws(() => monthlySpending([
    { date: january, amount: Number.MAX_SAFE_INTEGER }, { date: january, amount: 1 },
  ], december, 2), /too large/);
});

test('CSV has a UTF-8 BOM, quoted fields, escaped quotes and CRLF records', () => {
  const data = csv([['費目', 'メモ'], ['食料品,日用品', '「牛乳」"特売"\n2本'], ['', '0']]);
  assert.deepEqual([...data.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  assert.equal(data.subarray(3).toString('utf8'),
    '"費目","メモ"\r\n"食料品,日用品","「牛乳」""特売""\n2本"\r\n"","0"\r\n');
});

test('settlement day 29–31 clamps to February in normal and leap years', () => {
  for (const day of [29, 30, 31]) {
    assert.equal(settlementDate(day, Date.UTC(2025, 1, 1)), Date.UTC(2025, 1, 28, 9));
    assert.equal(settlementDate(day, Date.UTC(2024, 1, 1)), Date.UTC(2024, 1, 29, 9));
  }
  assert.equal(settlementDate(31, Date.UTC(2026, 3, 1)), Date.UTC(2026, 3, 30, 9));
  assert.equal(settlementDate(31, Date.UTC(2026, 11, 1)), Date.UTC(2026, 11, 31, 9));
  assert.equal(settlementDate(1, Date.UTC(2026, 11, 1)), Date.UTC(2026, 11, 1, 9));
  assert.equal(settlementDate(0, Date.UTC(2026, 11, 1)), null);
});

const milk = '00000000-0000-4000-8000-000000000001';
const bread = '00000000-0000-4000-8000-000000000002';

function edit(bookID, field, item, value, time, id) {
  return { bookID, key: 'shopping/' + field + '/' + item, value, time, id };
}

test('shopping merges concurrent additions and checks deterministically within one book', () => {
  const edits = [
    edit('home', 'name', milk, '牛乳', 1, 'a'),
    edit('home', 'name', bread, 'パン', 1, 'b'),
    edit('home', 'checked', milk, '0', 2, 'c'),
    edit('home', 'checked', milk, '1', 2, 'd'),
    edit('trip', 'checked', bread, '1', 3, 'e'),
    edit('trip', 'name', milk, '水', 3, 'f'),
  ];
  const expected = [{ id: milk, name: '牛乳', checked: true }, { id: bread, name: 'パン', checked: false }];
  assert.deepEqual(mergeShopping(edits, 'home'), expected);
  assert.deepEqual(mergeShopping([...edits].reverse(), 'home').sort((a, b) => a.id.localeCompare(b.id)), expected);
  assert.deepEqual(mergeShopping(edits, 'trip'), [{ id: milk, name: '水', checked: false }]);
});

test('a later check cannot resurrect a removed shopping item', () => {
  const edits = [
    edit('home', 'name', milk, '牛乳', 1, 'a'),
    edit('home', 'name', milk, '', 2, 'b'),
    edit('home', 'checked', milk, '1', 3, 'c'),
  ];
  assert.deepEqual(mergeShopping(edits, 'home'), []);
});

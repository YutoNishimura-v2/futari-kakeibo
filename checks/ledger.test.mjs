import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { createExpense, firstShare, localDay, monthStart, monthlyTotals, settlement } from './ledger.mjs';

const equal = { kind: 'equal' };
const ratio = { kind: 'ratio', first: 60, second: 40 };
const january = { start: Date.UTC(2026, 0, 1), end: Date.UTC(2026, 1, 1) };
const february = { start: january.end, end: Date.UTC(2026, 2, 1) };

test('Swift built-in categories call a declared string initializer', () => {
  const ledger = readFileSync(new URL('../Sources/FutariDomain/Ledger.swift', import.meta.url), 'utf8');
  const category = ledger.match(/public struct Category\b[\s\S]*?^\}/m)?.[0];
  assert.ok(category, 'Category declaration is missing');
  const calls = [...category.matchAll(/static let \w+\s*=\s*Category\((\w+):\s*"/g)];
  assert.ok(calls.length, 'Built-in category declarations are missing');
  for (const [, label] of calls) {
    assert.match(category, new RegExp(`\\binit\\(${label}:\\s*String\\)`),
      `Missing Category initializer for ${label}:`);
  }
});

function expense(overrides = {}) {
  return createExpense({
    amount: 100, date: january.start, category: 'groceries', payer: 'first', split: equal,
    ...overrides,
  });
}

test('equal split divides an even amount in half', () => {
  assert.equal(firstShare(1200, 'first', equal), 600);
  assert.equal(firstShare(1200, 'second', equal), 600);
});

test('fixed ratios are the members’ shares, independent of payer', () => {
  assert.equal(firstShare(2000, 'first', ratio), 1200);
  assert.equal(firstShare(2000, 'second', ratio), 1200);
  assert.equal(firstShare(99, 'first', { kind: 'ratio', first: 0, second: 100 }), 0);
});

test('fixed amount assigns the remainder to the second member', () => {
  const split = { kind: 'fixed', firstYen: 200 };
  assert.equal(firstShare(901, 'first', split), 200);
  assert.equal(firstShare(901, 'second', split), 200);
  assert.deepEqual(settlement([expense({ amount: 901, split })], january),
    { from: 'second', to: 'first', amount: 701 });
  assert.deepEqual(settlement([expense({ amount: 101, split: { kind: 'fixed', firstYen: 100 } })], january),
    { from: 'second', to: 'first', amount: 1 });
});

test('equal and ratio rounding give the remainder yen to either payer', () => {
  assert.equal(firstShare(101, 'first', equal), 51);
  assert.equal(firstShare(101, 'second', equal), 50);
  assert.equal(firstShare(101, 'first', ratio), 61);
  assert.equal(firstShare(101, 'second', ratio), 60);
  assert.equal(firstShare(1, 'second', equal), 0);
  assert.equal(firstShare(Number.MAX_SAFE_INTEGER, 'first', equal), 4_503_599_627_370_496);
});

test('Swift rounds the nonpayer share down per entry before netting expenses and refunds', () => {
  const swift = readFileSync(new URL('../Sources/FutariDomain/Ledger.swift', import.meta.url), 'utf8');
  assert.match(swift, /let otherPercent = payer == \.first \? 100 - firstPercent : firstPercent\s*let otherShare = magnitude \/ 100 \* otherPercent \+ \(magnitude % 100\) \* otherPercent \/ 100\s*let share = payer == \.first \? magnitude - otherShare : otherShare\s*return amount < 0 \? -share : share/);
  assert.deepEqual(settlement([
    expense({ amount: 101 }), expense({ amount: 101 }), expense({ amount: -99 }),
  ], january), { from: 'second', to: 'first', amount: 51 });
});

test('0/100 splits never round and the nonpaying member can owe the full yen', () => {
  const split = { kind: 'ratio', first: 0, second: 100 };
  assert.deepEqual(settlement([expense({ amount: 1, split })], january),
    { from: 'second', to: 'first', amount: 1 });
  assert.equal(settlement([expense({ amount: 1, split, payer: 'second' })], january), null);
});

test('refunds reverse the same split including the fractional yen, and reduce category totals', () => {
  for (const split of [equal, ratio, { kind: 'fixed', firstYen: 100 }]) {
    for (const payer of ['first', 'second']) {
      const sale = expense({ amount: 101, split, payer });
      const refund = expense({ amount: -101, split, payer });
      assert.equal(refund.firstShare, -sale.firstShare);
      assert.equal(settlement([sale, refund], january), null);
      assert.deepEqual(monthlyTotals([sale, refund], january.start), { groceries: 0 });
    }
  }
  assert.deepEqual(settlement([expense({ amount: -101 })], january),
    { from: 'first', to: 'second', amount: 50 });
  assert.throws(() => monthlyTotals([
    expense({ amount: -Number.MAX_SAFE_INTEGER }), expense({ amount: -1 }),
  ], january.start), /total too large/);
});

test('mixed payers and split rules net to one amount and direction', () => {
  const entries = [
    expense({ amount: 1201 }),
    expense({ amount: 900, payer: 'second', split: ratio }),
    expense({ amount: 400, payer: 'second', split: { kind: 'fixed', firstYen: 250 } }),
  ];
  assert.deepEqual(settlement(entries, january), { from: 'first', to: 'second', amount: 190 });
  assert.deepEqual(settlement(entries.slice(0, 2), january),
    { from: 'second', to: 'first', amount: 60 });
});

test('a balanced or empty period needs no transfer', () => {
  assert.equal(settlement([expense(), expense({ payer: 'second' })], january), null);
  assert.equal(settlement([], january), null);
});

test('monthly totals add whole expenses by category and respect month boundaries', () => {
  const entries = [
    expense(),
    expense({ amount: 201, payer: 'second', split: ratio, date: january.end - 1 }),
    expense({ amount: 80, category: 'transport' }),
    expense({ amount: 500, date: february.start }),
    expense({ amount: 600, date: january.start - 1 }),
  ];
  assert.deepEqual(monthlyTotals(entries, january.start), { groceries: 301, transport: 80 });
  assert.deepEqual(monthlyTotals(entries, february.start), { groceries: 500 });
});

test('JST midnight changes the ledger month at 15:00 UTC on the previous day', () => {
  const midnight = Date.parse('2026-02-01T00:00:00+09:00');
  const entries = [expense({ date: localDay(midnight - 1) }),
    expense({ amount: 301, date: localDay(midnight) })];
  assert.deepEqual(entries.map(({ date }) => monthStart(date)), [january.start, february.start]);
  assert.deepEqual(monthlyTotals(entries, january.start), { groceries: 100 });
  assert.deepEqual(settlement(entries, february), { from: 'second', to: 'first', amount: 150 });
});

test('settled months are excluded from period netting and preserved in totals', () => {
  const entries = [
    expense({ amount: 200 }),
    expense({ amount: 80, date: february.start, payer: 'second' }),
    expense({ amount: 500, date: february.end }),
  ];
  const marked = new Set([monthStart(january.start)]);
  assert.equal(settlement(entries, january, marked), null);
  assert.deepEqual(settlement(entries, { start: january.start, end: february.end }, marked),
    { from: 'first', to: 'second', amount: 40 });
  assert.deepEqual(monthlyTotals(entries, january.start), { groceries: 200 });
});

test('invalid amounts, ratio totals and fixed amounts are rejected', () => {
  for (const amount of [-(Number.MAX_SAFE_INTEGER + 1), 0, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => expense({ amount }), /invalid amount/);
  }
  for (const [first, second] of [[60, 30], [-1, 101], [50.5, 49.5]]) {
    assert.throws(() => expense({ split: { kind: 'ratio', first, second } }), /invalid ratio/);
  }
  for (const firstYen of [-1, 101]) {
    assert.throws(() => expense({ split: { kind: 'fixed', firstYen } }), /invalid fixed amount/);
  }
});

test('out-of-range aggregates report an error instead of rounding silently', () => {
  const entry = expense({
    amount: Number.MAX_SAFE_INTEGER, payer: 'second',
    split: { kind: 'fixed', firstYen: Number.MAX_SAFE_INTEGER },
  });
  assert.throws(() => monthlyTotals([entry, entry], january.start), /total too large/);
  assert.throws(() => settlement([entry, entry], january), /total too large/);
});

test('optional entry labels are trimmed and limited to 30 characters', () => {
  assert.equal(expense({ label: ' お米 ' }).label, 'お米');
  assert.equal(expense({ label: ' ' }).label, null);
  assert.throws(() => expense({ label: '米'.repeat(31) }), /label too long/);
});

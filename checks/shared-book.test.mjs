import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import * as rules from './shared-book.mjs';
import { editTime, latestEdits, memberForParticipant, migrateLegacy } from './shared-book.mjs';

const swift = readFileSync(new URL('../Sources/FutariKakeibo/CloudLedger.swift', import.meta.url), 'utf8');
const january = Date.UTC(2026, 0, 1);
const monthField = `month/${january / 1000}`;
const oldEntry = {
  id: '00000000-0000-4000-8000-000000000001',
  amount: 101, date: january, categoryKey: 'groceries', payerKey: 'second',
  splitKey: 'equal', firstValue: 0, label: ' お米 ',
};
const empty = { migrated: false, expenses: [], values: {} };
const legacy = {
  names: { first: '花', second: '空' },
  expenses: [
    oldEntry,
    { ...oldEntry, id: '00000000-0000-4000-8000-000000000002', splitKey: 'ratio', firstValue: 60 },
    { ...oldEntry, id: '00000000-0000-4000-8000-000000000003', splitKey: 'fixed', firstValue: 28 },
  ],
  settled: [january],
};

test('an empty legacy ledger never creates a migration book', () => {
  const blank = { expenses: [], settled: [], names: {} };
  assert.equal(migrateLegacy(empty, blank), empty);
  const migrate = swift.slice(swift.indexOf('private func migrate('), swift.indexOf('func activate('));
  assert.match(migrate, /guard !legacy\.expenses\.isEmpty \|\| !legacy\.settled\.isEmpty \|\| legacy\.names != Names\(\) else \{[\s\S]*?return\s*\}[\s\S]*?LedgerBookRow\(context: context\)/);
});

test('owned book creation waits for initial import and reuses a synced book', () => {
  const synced = { id: 'synced', shared: false, empty: false };
  assert.equal(typeof rules.ownedBookPlan, 'function');
  assert.deepEqual(rules.ownedBookPlan([], null, false), { selected: null, create: false });
  assert.deepEqual(rules.ownedBookPlan([synced], null, false), { selected: 'synced', create: false });
  assert.deepEqual(rules.ownedBookPlan([synced], null, true), { selected: 'synced', create: false });
  assert.deepEqual(rules.ownedBookPlan([], null, true), { selected: null, create: true });
  assert.match(swift, /account == \.available && initialPrivateImportFinished/);
  assert.match(swift, /if privateLedgerReady, !shareBusy, let privateStore \{[\s\S]*?if mayCreatePrimary, !storeLoadFailed, owned\.isEmpty, \(awaitingZone == nil \|\| noAccount\)/);
});

test('a shared owned book supersedes a previously selected empty unshared book', () => {
  const blank = { id: 'a', shared: false, empty: true };
  const shared = { id: 'b', shared: true, empty: true };
  assert.equal(typeof rules.ownedBookPlan, 'function');
  assert.deepEqual(rules.ownedBookPlan([blank, shared], 'a', true), { selected: 'b', create: false });
  assert.deepEqual(rules.ownedBookPlan([{ ...blank, empty: false }, shared], 'a', true),
    { selected: 'a', create: false });
});

test('a new invite can replace a pending partner but cannot replace an accepted partner', () => {
  assert.equal(typeof rules.partnerSlot, 'function');
  assert.deepEqual(rules.partnerSlot([{ id: 'A', status: 'pending' }], 'B'), { keep: null, remove: ['A'] });
  assert.equal(rules.partnerSlot([{ id: 'A', status: 'accepted' }], 'B'), null);
  assert.deepEqual(rules.partnerSlot([{ id: 'A', status: 'accepted' }], 'A'), { keep: 'A', remove: [] });
  const invite = swift.slice(swift.indexOf('func invite('), swift.indexOf('func participantShare('));
  assert.match(invite, /\.acceptanceStatus == \.accepted && \$0\.userIdentity\.userRecordID != target/);
  assert.match(invite, /\.acceptanceStatus == \.pending && \$0\.userIdentity\.userRecordID != target[\s\S]*?share\.removeParticipant\(pending\)[\s\S]*?container\.persistUpdatedShare/);
});

test('store-load retry detaches every persistent store before reusing one model', () => {
  const reopen = swift.match(/private func reopen\(\) \{([\s\S]*?)\n {4}\}/)?.[1] ?? '';
  assert.match(reopen, /for .* in coordinator\.persistentStores\s*\{\s*try coordinator\.remove\(/);
  assert.ok(reopen.indexOf('coordinator.remove(') < reopen.indexOf('open()'));
  assert.match(swift, /static let model = ledgerModel\(\)/);
  assert.equal([...swift.matchAll(/ledgerModel\(\)/g)].length, 1);
  const retry = swift.match(/func retry\(\) async \{([\s\S]*?)\n {4}\}/)?.[1] ?? '';
  assert.match(retry, /if storeLoadFailed \{ reopen\(\) \}/);
  assert.equal([...retry.matchAll(/\breopen\(\)/g)].length, 1);
});

test('owner and invited account use fixed payer slots regardless of the displayed names', () => {
  assert.equal(memberForParticipant({ isOwner: true, isPrivatePartner: false }), 'first');
  assert.equal(memberForParticipant({ isOwner: false, isPrivatePartner: true }), 'second');
  assert.equal(memberForParticipant({ isOwner: false, isPrivatePartner: false }), null);
  const book = migrateLegacy(empty, legacy);
  assert.equal(book.values[book.expenses[0].payer], '空');
});

test('migration carries all split rules, IDs, payer references, names and settled months once', () => {
  const book = migrateLegacy(empty, legacy);
  assert.deepEqual(book.expenses.map(({ id }) => id), legacy.expenses.map(({ id }) => id));
  assert.deepEqual(book.expenses.map(({ firstShare }) => firstShare), [50, 60, 28]);
  assert.equal(book.expenses[0].label, 'お米');
  assert.deepEqual(book.values, { first: '花', second: '空', [monthField]: '1' });
  assert.equal(migrateLegacy(book, legacy), book);
  const local = { ...legacy, expenses: [{ ...oldEntry, id: '00000000-0000-4000-8000-000000000004' }] };
  assert.equal(migrateLegacy(book, local).expenses.length, 4);
  assert.equal(migrateLegacy(empty, legacy, true), empty);
});

test('migration preserves an existing entry and newer settings and rejects invalid records atomically', () => {
  const existing = { ...empty, expenses: [{ id: oldEntry.id, amount: 200 }], values: { [monthField]: '0' } };
  const book = migrateLegacy(existing, legacy);
  assert.equal(book.expenses.length, 3);
  assert.equal(book.expenses[0].amount, 200);
  assert.equal(book.values[monthField], '0');
  const invalid = { ...legacy, expenses: [...legacy.expenses, { ...oldEntry, payerKey: 'someone' }] };
  assert.throws(() => migrateLegacy(empty, invalid), /invalid member/);
  assert.deepEqual(empty, { migrated: false, expenses: [], values: {} });
});

test('each setting converges by latest time then UUID in either import order', () => {
  const edits = [
    { key: 'first', value: '花', time: 50, id: '00000000-0000-4000-8000-000000000003' },
    { key: 'second', value: '空', time: 40, id: '00000000-0000-4000-8000-000000000004' },
    { key: monthField, value: '1', time: 30, id: '00000000-0000-4000-8000-0000000000FF' },
    { key: monthField, value: '0', time: 30, id: '00000000-0000-4000-8000-00000000000a' },
    { key: 'first', value: '春', time: 60, id: '00000000-0000-4000-8000-000000000001' },
  ];
  const expected = new Map([['first', edits[4]], ['second', edits[1]], [monthField, edits[2]]]);
  assert.deepEqual(latestEdits(edits), expected);
  assert.deepEqual(latestEdits([...edits].reverse()), expected);
  assert.equal(editTime(20, 30), 31);
  assert.equal(editTime(40, 30), 40);
  assert.equal(editTime(40), 40);
});

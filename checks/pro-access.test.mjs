import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { bookAccess } from './pro-access.mjs';

const day = 86_400_000;
const purchase = Date.UTC(2026, 10, 1);
const expiry = purchase + 14 * day;
const free = { plan: 'free', expiresAt: null };
const lifetime = { plan: 'pro', expiresAt: null };
const edit = (member, changes = {}) => ({
  bookID: 'home', member, originalID: 'apple-1', purchasedAt: purchase, expiresAt: expiry,
  revoked: false, ...changes,
});

test('a purchase by either current member unlocks their shared book only', () => {
  for (const member of ['owner', 'guest-a']) {
    const edits = [edit(member)];
    assert.deepEqual(bookAccess(edits, 'home', 'guest-a', purchase), { plan: 'pro', expiresAt: expiry });
    assert.deepEqual(bookAccess(edits, 'travel', 'guest-a', purchase), free);
  }
  assert.deepEqual(bookAccess([edit('guest-a')], 'home', 'guest-b', purchase), free);
  assert.deepEqual(bookAccess([edit('guest-a')], 'home', null, purchase), free);
});

test('the book stays Pro through the last valid entitlement and expires at its boundary', () => {
  const edits = [edit('owner'), edit('guest-a', { expiresAt: expiry + 2 * day })];
  assert.deepEqual(bookAccess(edits, 'home', 'guest-a', purchase - 1), free);
  assert.deepEqual(bookAccess(edits, 'home', 'guest-a', expiry), { plan: 'pro', expiresAt: expiry + 2 * day });
  assert.deepEqual(bookAccess(edits, 'home', 'guest-a', expiry + 2 * day), free);
  assert.deepEqual(bookAccess([edit('owner')], 'home', 'guest-a', expiry - 1), { plan: 'pro', expiresAt: expiry });
  assert.deepEqual(bookAccess([edit('owner')], 'home', 'guest-a', expiry), free);
});

test('lifetime access survives subscription expiry and refund wins over a stale copy in either order', () => {
  const grant = edit('guest-a', { expiresAt: null });
  const refund = { ...grant, revoked: true };
  assert.deepEqual(bookAccess([edit('owner'), grant], 'home', 'guest-a', expiry), lifetime);
  for (const edits of [[grant, refund], [refund, grant]]) {
    assert.deepEqual(bookAccess(edits, 'home', 'guest-a', expiry), free);
    assert.deepEqual(bookAccess([...edits, edit('owner')], 'home', 'guest-a', purchase), {
      plan: 'pro', expiresAt: expiry,
    });
  }
});

test('renewal replaces a previous period even when its edits arrive out of order', () => {
  const renewed = edit('owner', { purchasedAt: expiry, expiresAt: expiry + 365 * day });
  assert.deepEqual(bookAccess([renewed, edit('owner')], 'home', null, expiry), {
    plan: 'pro', expiresAt: renewed.expiresAt,
  });
});

test('a StoreKit scan waits for the running scan and still processes its own transaction', () => {
  const swift = readFileSync(new URL('../Sources/FutariKakeibo/ProPurchases.swift', import.meta.url), 'utf8');
  assert.match(swift, /while let pending = entitlementScan \{\s*_ = await pending\.result\s*\}/);
  assert.match(swift, /let task = Task \{\s*defer \{ entitlementScan = nil \}\s*return try await scanEntitlements\(including: transaction\)\s*\}\s*entitlementScan = task\s*return try await task\.value/);
  assert.match(swift, /if let transaction \{ include\(transaction, current: true\) \}[\s\S]*?ledger\.updatePurchases\(grants, verificationFailed: unverified\)/);
  assert.match(swift, /guard !activating else \{ return \}\s*activating = true\s*defer \{ activating = false \}/);
  assert.doesNotMatch(swift, /appliedScan/);
});

test('failed verification of the latest known purchase is reported even without a current entitlement', () => {
  const swift = readFileSync(new URL('../Sources/FutariKakeibo/ProPurchases.swift', import.meta.url), 'utf8');
  assert.match(swift, /switch await Transaction\.latest\(for: productID\) \{\s*case \.verified\(let latest\)\?: include\(latest, current: false\)\s*case \.unverified\?: unverified = true/);
  assert.match(swift, /let saved = try ledger\.updatePurchases\(grants, verificationFailed: unverified\)\s*guard !unverified else \{ throw PurchaseError\.verification \}/);
});

test('the StoreKit catalog sells only monthly and yearly auto-renewing plans at 480 and 3600 JPY', () => {
  const catalog = JSON.parse(readFileSync(new URL('../FutariKakeibo.storekit', import.meta.url)));
  const config = readFileSync(new URL('../Sources/FutariKakeibo/ProPurchases.swift', import.meta.url), 'utf8');
  const products = catalog.subscriptionGroups.flatMap((group) => group.subscriptions);
  const [monthly, yearly] = products;
  assert.equal(catalog.settings._storefront, 'JPN');
  assert.deepEqual(catalog.products, []);
  assert.deepEqual(catalog.nonRenewingSubscriptions, []);
  assert.equal(catalog.subscriptionGroups.length, 1);
  assert.deepEqual(products.map(({ displayPrice }) => Number(displayPrice)), [480, 3600]);
  assert.deepEqual([...config.matchAll(/case \w+ = "([^"]+)"/g)].map((match) => match[1]),
    products.map(({ productID }) => productID));
  for (const product of products) {
    assert.equal(product.type, 'RecurringSubscription');
    assert.equal(product.familyShareable, true);
  }
  assert.equal(monthly.recurringSubscriptionPeriod, 'P1M');
  assert.equal(yearly.recurringSubscriptionPeriod, 'P1Y');
  assert.equal(monthly.introductoryOffer, null);
  assert.deepEqual(
    [yearly.introductoryOffer.paymentMode, yearly.introductoryOffer.subscriptionPeriod,
      yearly.introductoryOffer.numberOfPeriods], ['free', 'P2W', 1],
  );
});

test('the generated app scheme runs with the local StoreKit catalog', () => {
  const project = readFileSync(new URL('../project.yml', import.meta.url), 'utf8');
  assert.match(project, /^fileGroups: \[FutariKakeibo\.storekit\]$/m);
  assert.match(project, /^schemes:\s*\n {2}FutariKakeibo:\n[\s\S]*?^ {4}run:\n {6}storeKitConfiguration: FutariKakeibo\.storekit$/m);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { readdirSync, readFileSync } from 'node:fs';
import { createExpense, localDay, monthlyTotals } from './ledger.mjs';
import { bookAccess } from './pro-access.mjs';
import { bookExpenses, bookSettlement, budgetProgress, budgetRemaining, changeExpense, missingRecurring, purgeDeletedExpenses, recurringID } from './pro-ledger.mjs';
import { latestEdits, ownedBookPlan } from './shared-book.mjs';

const january = Date.UTC(2026, 0, 1);
const february = Date.UTC(2026, 1, 1);
const march = Date.UTC(2026, 2, 1);
const bookID = 'D9C488D3-2E6F-44DB-BCB1-2AC693FE9E81';
const otherBookID = '7FAEECEE-9609-495E-B5E7-3336D679E1E9';
const rentID = 'AB147A1A-AFC2-4B15-934D-844CE34B0665';
const utilitiesID = '2D8C5132-18E2-4830-AACF-AA40F7548C93';
const dates = { start: february, end: march };

function expense(id, amount, date, category, payer = 'first') {
  return { id, ...createExpense({ amount, date, category, payer, split: { kind: 'equal' } }) };
}

function book({ id = bookID, expenses = [], settled = [], templates = [] } = {}) {
  return { id, expenses, settled: new Set(settled), templates };
}

test('monthly budget includes only this book, category and month and shows overspending', () => {
  const home = book({ expenses: [
    expense('1', 1_500, february, 'groceries'),
    expense('2', 900, february, 'dining'),
    expense('3', 600, january, 'groceries'),
    expense('4', 400, march, 'groceries'),
  ] });
  const trip = book({ id: otherBookID, expenses: [expense('5', 800, february, 'groceries')] });
  assert.equal(budgetRemaining(home, february, 'groceries', 2_000), 500);
  assert.equal(budgetRemaining(home, february, 'groceries', 1_000), -500);
  assert.equal(budgetRemaining(home, february, 'transport', 1_000), 1_000);
  assert.equal(budgetRemaining(trip, february, 'groceries', 2_000), 1_200);
});

test('offline devices generate the same monthly IDs and sync to one expense per template', () => {
  const rent = expense(rentID, 101, january, 'housing');
  const utilities = expense(utilitiesID, 500, february, 'utilities');
  const first = book({ templates: [rent, utilities] });
  const second = book({ templates: [{ ...utilities }, { ...rent }] });
  const firstWrites = missingRecurring(first, february);
  const secondWrites = missingRecurring(second, february + 86_400_000);
  assert.equal(firstWrites.length, 2);
  assert.deepEqual(firstWrites, [...secondWrites].reverse());
  assert.ok(firstWrites.every(({ date }) => date === february));
  assert.match(firstWrites[0].id, /^[a-f0-9]{8}-[a-f0-9]{4}-8[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  assert.notEqual(firstWrites[0].id, firstWrites[1].id);
  assert.notEqual(firstWrites[0].id, recurringID(otherBookID, rentID, february));
  assert.notEqual(firstWrites[0].id, recurringID(bookID, rentID, march));
  assert.deepEqual(missingRecurring(book({ ...first, expenses: firstWrites }), february), []);
  const merged = book({ ...first, expenses: [...firstWrites, ...secondWrites] });
  assert.deepEqual(missingRecurring(merged, february), []);
  assert.equal(missingRecurring(merged, march).length, 2);
  assert.equal(missingRecurring(first, january).length, 1);
  assert.deepEqual(missingRecurring(book({ ...first, settled: [february] }), february), []);
  assert.deepEqual(bookSettlement(merged, dates), { from: 'second', to: 'first', amount: 300 });
  assert.equal(budgetRemaining(merged, february, 'housing', 200), 99);
});

const source = (path) => readFileSync(new URL(`../Sources/${path}`, import.meta.url), 'utf8');
const cloud = source('FutariKakeibo/CloudLedger.swift');
const settings = source('FutariKakeibo/BookSettings.swift');

function cloudMethod(name) {
  return cloud.match(new RegExp(`func ${name}\\([\\s\\S]*?\\n {4}\\}`))?.[0] ?? '';
}

test('editing and deleting one expense ID recomputes totals and settlement even with late photo copies', () => {
  const original = expense('lunch', 600, february, 'dining');
  const other = expense('groceries', 200, february, 'groceries', 'second');
  const base = book({ expenses: [original, { ...original }, other] });
  const replacement = expense(original.id, 1_200, february, 'groceries');
  const edited = changeExpense(base, original.id, replacement);
  const editedWithLateCopy = { ...edited, expenses: [original, ...edited.expenses] };
  assert.deepEqual(bookExpenses(editedWithLateCopy), [replacement, other]);
  assert.deepEqual(monthlyTotals(bookExpenses(editedWithLateCopy), february), { groceries: 1_400 });
  assert.deepEqual(bookSettlement(editedWithLateCopy, dates), { from: 'second', to: 'first', amount: 500 });

  const deleted = changeExpense(edited, original.id);
  assert.deepEqual(deleted.expenses, [other]);
  const deletedWithLateCopy = { ...deleted, expenses: [original, ...deleted.expenses] };
  assert.deepEqual(bookExpenses(deletedWithLateCopy), [other]);
  assert.deepEqual(monthlyTotals(bookExpenses(deletedWithLateCopy), february), { groceries: 200 });
  assert.deepEqual(bookSettlement(deletedWithLateCopy, dates), { from: 'first', to: 'second', amount: 100 });
});

test('a settled source or destination month prevents expense changes', () => {
  const original = expense('lunch', 600, february, 'dining');
  const closed = book({ expenses: [original], settled: [february] });
  assert.throws(() => changeExpense(closed, original.id, { ...original, date: march }), /settled/);
  assert.throws(() => changeExpense(closed, original.id), /settled/);
  const open = book({ expenses: [original], settled: [march] });
  assert.throws(() => changeExpense(open, original.id, { ...original, date: march }), /settled/);
});

test('a deleted recurring occurrence stays deleted without stopping the template', () => {
  const base = book({ templates: [expense(rentID, 100, january, 'housing')] });
  const [generated] = missingRecurring(base, february);
  const deleted = changeExpense({ ...base, expenses: [generated] }, generated.id);
  assert.deepEqual(missingRecurring(deleted, february), []);
  assert.equal(missingRecurring(deleted, march).length, 1);
});

test('the app wires expense edits and confirmed deletions to the protected repository writes', () => {
  const detail = source('FutariKakeibo/ExpenseDetail.swift');
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(detail, /Button\("編集"\)[\s\S]*?EntryForm\(snapshot: snapshot, repository: ledger, editing: original\)/);
  assert.match(detail, /Button\("この支出を削除"[\s\S]*?\.confirmationDialog\("この支出を削除しますか？"[\s\S]*?try ledger\.delete\(expense\.id, from: book, matching: expense\)/);
  assert.match(app, /\.swipeActions\(allowsFullSwipe: false\)[\s\S]*?\.confirmationDialog\("この支出を削除しますか？"[\s\S]*?try ledger\.delete\(expense\.id, from: book, matching: expense\)/);
  assert.match(app, /Expense\(id: original\?\.id \?\? UUID\(\)[\s\S]*?repository\.update\(expense, replacing: original, in: snapshot\.book\)/);
  assert.match(cloudMethod('update'), /try receiptRows[\s\S]*?editableExpenseFields[\s\S]*?requireUnchanged[\s\S]*?monthKey\(Month\(containing: expense\.date\)\)[\s\S]*?throw BookError\.settled[\s\S]*?canUpdateRecord[\s\S]*?insertEdit\(key,/);
  assert.match(cloudMethod('delete'), /try receiptRows[\s\S]*?editableExpenseFields[\s\S]*?requireUnchanged[\s\S]*?copies\.allSatisfy[\s\S]*?canDeleteRecord[\s\S]*?insertEdit\(deletedExpenseKey\(expenseID\)[\s\S]*?for copy in copies \{ context\.delete\(copy\) \}/);
  assert.match(cloudMethod('editableExpenseFields'), /currentExpenseFields[\s\S]*?monthKey\(Month\(containing: fields\.date\)\)[\s\S]*?throw BookError\.settled/);
  assert.match(cloudMethod('expenses'), /edits\[deletedExpenseKey\(fields\.id\)\] == nil, ids\.insert\(fields\.id\)\.inserted[\s\S]*?currentExpenseFields\(fields/);
  assert.match(cloudMethod('generateRecurring'), /guard values\[deletedExpenseKey\(expense\.id\)\] == nil/);
});

test('a stop or settlement imported after launch prevents generation in its own store', () => {
  const rent = expense(rentID, 101, january, 'housing');
  const templateKey = 'recurring/' + rentID;
  const monthKey = 'month/' + february / 1000;
  const cached = { key: templateKey, value: rent, time: 1, id: 'a' };
  const importedStores = new Set();
  const generate = (store, edits, account = 'available') => {
    const values = latestEdits(edits);
    const ledger = book({
      templates: values.get(templateKey)?.value ? [values.get(templateKey).value] : [],
      settled: values.get(monthKey)?.value === '1' ? [february] : [],
    });
    return missingRecurring(ledger, february, { account, importedStores, store });
  };
  assert.deepEqual(generate('private', [cached], 'unknown'), []);
  assert.deepEqual(generate('private', [cached]), []);
  importedStores.add('private');
  assert.deepEqual(generate('private', [cached, { key: templateKey, value: '', time: 2, id: 'b' }]), []);
  assert.equal(generate('private', [cached]).length, 1);
  assert.deepEqual(generate('shared', [cached]), []);
  importedStores.add('shared');
  assert.deepEqual(generate('shared', [cached, { key: monthKey, value: '1', time: 2, id: 'b' }]), []);
  assert.equal(generate('shared', [cached]).length, 1);
  importedStores.clear();
  assert.equal(generate('private', [cached], 'noAccount').length, 1);
  assert.equal(missingRecurring(book({ templates: [rent] }), february).length, 1);
});

test('Swift opens recurring generation only after a successful import in the destination store', () => {
  assert.match(cloudMethod('generateRecurring'), /guard let store = row\.objectID\.persistentStore,\s*readyForRecurring\(in: store\),/);
  assert.match(cloudMethod('readyForRecurring'), /cloud == nil \|\| noAccount\s*\|\| \(account == \.available && !accountError && importedStores\.contains\(store\.identifier\)\)/);
  assert.match(cloudMethod('watch'), /if event\.succeeded && event\.type == \.import \{\s*self\.importedStores\.insert\(event\.storeIdentifier\)\s*self\.context\?\.reset\(\)\s*self\.refresh\(\)/);
  assert.match(cloudMethod('reopen'), /importedStores\.removeAll\(\)[\s\S]*?open\(\)/);
  assert.match(cloudMethod('checkAccount'), /if account == \.available && status != \.available \{\s*importedStores\.removeAll\(\)/);
});

test('a book title is read and written using the same persisted field', () => {
  assert.match(cloudMethod('createBook'), /row\.title = title/);
  assert.match(cloudMethod('refresh'), /if let title = row\.title \{/);
  assert.doesNotMatch(cloud, /book\/title/);
});

test('adding a private book requires personal access and saves its grants before selection', () => {
  assert.match(cloud, /var personalPlan: Plan \{\s*access\(from: verifiedPurchases\.values, at: \.now\)\.plan/);
  assert.match(cloudMethod('createBook'), /guard personalPlan\.allowsProFeatures[\s\S]*?try savePurchases\(prefix: "pro\/first\/", in: row,[\s\S]*?remember\(book\)/);
  assert.match(cloudMethod('refresh'), /access\(from: grants, at: now\)[\s\S]*?if !bookAccess\.plan\.allowsProFeatures/);
  assert.match(settings, /Section\("家計簿"\) \{\s*if ledger\.personalPlan\.allowsProFeatures/);
});

test('a guest writes under its real CloudKit user ID and the owner reads the same prefix', () => {
  assert.match(cloudMethod('checkAccount'), /try await cloud\.userRecordID\(\)/);
  assert.match(cloudMethod('watch'), /\.CKAccountChanged[\s\S]*?self\.currentUserID = nil\s*await self\.checkAccount\(\)/);
  assert.match(cloudMethod('refresh'), /self\.currentUserID \?\? participantID\.flatMap \{\s*\$0\.recordName == CKCurrentUserDefaultName \? nil : \$0/);
  assert.match(cloudMethod('refresh'), /let partnerID = book\.isGuest \? currentUserID : partner\?\.userIdentity\.userRecordID/);
  assert.match(cloudMethod('refresh'), /case \.second\?: memberPrefix = partnerPrefix/);
  assert.match(cloudMethod('refresh'), /partnerPrefix\.map\(\{ key\.hasPrefix\(\$0\) \}\)/);
  assert.match(cloudMethod('refresh'), /if memberPrefix == nil \|\| !canWriteGrant \{\s*purchaseSaveFailed = true/);
});

test('the expiry timer compares against the last applied access before refreshing reminders', () => {
  assert.match(cloudMethod('schedulePurchaseRefresh'), /self\?\.purchaseBoundary = nil\s*self\?\.refresh\(\)/);
  assert.match(cloudMethod('refresh'), /let previousAccess = snapshot\.flatMap \{ accessByBook\[\$0\.book\] \} \?\? \.free/);
  assert.match(cloudMethod('refresh'), /if previousAccess != access \{\s*Task \{ await SettlementReminder\.shared\.refresh\(access: access\) \}/);
});

test('reminder scheduling applies the latest access even when another operation is in flight', () => {
  const reminder = source('FutariKakeibo/SettlementReminder.swift');
  assert.match(reminder, /func refresh\(access: ProAccess\) async \{\s*pendingAccess = access\s*await applyPendingAccess\(\)/);
  assert.match(reminder, /while let access = pendingAccess \{\s*pendingAccess = nil\s*do \{\s*try await refreshSchedule\(access: access\)/);
  assert.match(reminder, /func save\(day: Int, access: ProAccess\)[\s\S]*?defer \{\s*busy = false\s*if pendingAccess != nil \{\s*Task \{ await applyPendingAccess\(\) \}/);
});

test('a cached empty private book cannot become writable before the initial import', () => {
  const blank = { id: bookID, empty: true, shared: false };
  assert.equal(ownedBookPlan([blank], bookID, false).selected, null);
  assert.equal(ownedBookPlan([blank], bookID, true).selected, bookID);
  const refresh = cloudMethod('refresh');
  assert.match(refresh, /let additional = available\.first \{ titles\[\$0\.0\] != nil \}/);
  assert.match(refresh, /else if !book\.isGuest, share == nil, !mayCreatePrimary \|\| hasSharedOwned,\s*try isEmpty\(row, context: context\) \{\s*continue/);
  assert.match(refresh, /selected \?\? establishedPrimary \?\? guest \?\? primary \?\? additional/);
});

test('an empty quick-start selection cannot hide imported history or an existing share', () => {
  const blank = { id: bookID, empty: true, shared: false };
  const populated = { id: otherBookID, empty: false, shared: false };
  assert.equal(ownedBookPlan([blank, populated], bookID, true).selected, otherBookID);
  const preferred = cloudMethod('preferredOwned');
  assert.match(preferred, /return populated \?\? \(privateLedgerReady \? \(current \?\? ordered.first\) : nil\)/);
  const refresh = cloudMethod('refresh');
  assert.match(refresh, /if mayCreatePrimary, !storeLoadFailed, owned\.isEmpty, \(awaitingZone == nil \|\| noAccount\)/);
  assert.match(cloud, /privateLedgerReady && \(cloud == nil \|\| noAccount \|\| sharedStore\.map \{ importedStores\.contains\(\$0\.identifier\) \} == true\)/);
  assert.doesNotMatch(cloudMethod('startRecording'), /LedgerBookRow\(context:|remember\(/);
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /RecordExpenseButton\(canRecord: ledger\.canStartRecording, record: startExpense\)/);
  assert.match(app, /\.disabled\(!canRecord\)/);
});

test('every titled book with a member remains available as a lock when Pro expires', () => {
  const refresh = cloudMethod('refresh');
  assert.match(refresh, /if let title = row\.title \{\s*titles\[book\] = title\s*if !bookAccess\.plan\.allowsProFeatures \{\s*if bookMember != nil \{\s*locked\.append\(book\)\s*\}\s*continue/);
  assert.match(refresh, /lockedBooks = locked/);
  assert.match(settings, /ForEach\(Array\(ledger\.lockedBooks\.enumerated\(\)\)[\s\S]*?ProLock\(title, ledger: ledger\)\s*if target\.isGuest \{\s*Button\("共有の管理"\) \{ manageShare\(target\) \}/);
  assert.match(source('FutariKakeibo/FutariKakeiboApp.swift'), /BookSettings\(ledger: ledger, book: ledger\.snapshot\?\.book\)/);
  const manage = cloudMethod('participantShare');
  assert.match(manage, /book\.isGuest,[\s\S]*?lockedBooks\.contains\(book\)/);
  assert.doesNotMatch(manage, /activeRow\(/);
});

test('a verified purchase waits for the first book or an in-progress share without a verification error', () => {
  const update = cloudMethod('updatePurchases');
  assert.match(update, /verifiedPurchases = purchases\s*purchaseVerificationFailed = verificationFailed\s*refresh\(\)/);
  assert.match(update, /if storageError \|\| storeLoadFailed \|\| purchaseSaveFailed \{ throw PurchaseError\.save \}/);
  assert.match(update, /return purchases\.isEmpty \|\| purchaseDestinationReady/);
  assert.doesNotMatch(update, /canPurchasePro/);
  const refresh = cloudMethod('refresh');
  assert.match(refresh, /purchaseDestinationReady = false[\s\S]*?if !shareBusy, bookMember != nil, !verifiedPurchases\.isEmpty \{[\s\S]*?try savePurchases\([\s\S]*?purchaseDestinationReady = true/);
  assert.match(cloudMethod('watch'), /if event\.succeeded && event\.type == \.import \{[\s\S]*?self\.refresh\(\)/);
  const purchases = source('FutariKakeibo/ProPurchases.swift');
  assert.match(purchases, /let saved = try ledger\.updatePurchases\(grants, verificationFailed: unverified\)[\s\S]*?return saved \? active : nil/);
  assert.match(purchases, /if \(try\? await refresh\(including: transaction\)\) != nil \{\s*await transaction\.finish\(\)\s*\}/);
  assert.doesNotMatch(purchases, /if await refresh\(\) == nil/);
});

test('different offline receipt photos can be viewed, replaced or cleared with a stale-write guard', () => {
  assert.match(cloudMethod('receiptPhotos'), /Set\(rows\.compactMap\(\\\.receiptJPEG\)\)/);
  assert.match(cloudMethod('setReceipt'), /guard receiptPhotos\(from: copies\) == previous else \{ throw ReceiptPhotoError\.changed \}/);
  assert.match(cloudMethod('setReceipt'), /for expense in copies where expense\.receiptJPEG != nil[\s\S]*?expense\.receiptJPEG = nil[\s\S]*?let attachment = LedgerExpenseRow\(context: context\)[\s\S]*?attachment\.receiptJPEG = photo\.jpeg/);
  const detail = source('FutariKakeibo/ExpenseDetail.swift');
  assert.match(detail, /if receipts\.count > 1 \{\s*Text\("写真が同時に追加されました。確認して1枚に差し替えてください"/);
  assert.match(detail, /ForEach\(Array\(receipts\), id: \\.self\)[\s\S]*?viewedPhoto = photo/);
  assert.match(detail, /if let deleteCandidate \{ save\(nil, replacing: deleteCandidate\) \}/);
  assert.match(detail, /save\(photo, replacing: previous\)/);
  assert.match(detail, /Label\(receipts\.isEmpty \? "写真を追加" : "写真を差し替え"/);
});

test('receipt replacement removes superseded photo rows while retaining an expense anchor', () => {
  const save = cloudMethod('setReceipt');
  assert.match(save, /let anchor = copies\.first\(where: \{ \$0\.receiptJPEG == nil \}\) \?\? copies\[0\]/);
  assert.match(save, /if expense === anchor \|\| expense\.recurringID != nil[\s\S]*?expense\.receiptJPEG = nil[\s\S]*?else \{[\s\S]*?canDeleteRecord[\s\S]*?context\.delete\(expense\)/);
  assert.match(save, /attachment\.payload = anchor\.payload/);
});

test('a joined share with unresolved membership exits the loading notice and can retry the merge', () => {
  assert.match(cloudMethod('refresh'), /if member\(for: joined\.0, share: shares\[joined\.1\.objectID\]\) != \.second \{\s*joinMergeFailed = true\s*\} else if let edits/);
  assert.match(cloudMethod('updateNotice'), /if joinMergeFailed \{[\s\S]*?再試行してください[\s\S]*?awaitingZone != nil/);
  assert.match(cloudMethod('retry'), /await checkAccount\(\)/);
});

test('solo merge creates one expense and one row per distinct photo and skips imported IDs on retry', () => {
  const merge = cloudMethod('mergeSoloEntries');
  assert.match(merge, /Dictionary\(grouping:[\s\S]*?for \(id, copies\) in sourceEntries where !ids\.contains\(id\)/);
  assert.match(merge, /try insert\(copy, in: destination, store: store, context: context\)\s*for photo in receiptPhotos\(from: copies\)/);
  assert.match(merge, /receiptJPEG: photo/);
  assert.match(merge, /destinationCategories\[category\] == name \? category : nil/);
});

test('first entry saves before partner acceptance, which copies solo records by stable ID', () => {
  const start = cloudMethod('startRecording');
  assert.match(start, /guard canStartRecording, let snapshot/);
  assert.match(cloudMethod('add'), /try write\(to: book\)[\s\S]*?try insert\(expense, in: row, store: store/);
  assert.match(cloudMethod('invite'), /container\.share\(\[row\], to: nil\)/);
  assert.match(cloudMethod('accept'), /container\.acceptShareInvitations[\s\S]*?awaitingZone = zone/);
  assert.match(cloudMethod('refresh'), /mergeSoloEntries\(from: solo, into: joined\.1[\s\S]*?remember\(joined\.0\)[\s\S]*?awaitingZone = nil/);
  const merge = cloudMethod('mergeSoloEntries');
  assert.match(merge, /expenseRequest\(in: destination\)[\s\S]*?expenseRequest\(in: source\)[\s\S]*?!ids\.contains\(id\)/);
  assert.match(merge, /Expense\(id: expense\.id,[\s\S]*?payer: expense\.payer\.other[\s\S]*?try insert\(copy, in: destination/);
  assert.match(merge, /\.ratio\(first: second, second: first\)[\s\S]*?abs\(expense\.amount\) - firstYen/);
  assert.match(merge, /edits\[monthKey\(month\)\]\?\.value == "1" \{ addedToSettledMonth = true \}[\s\S]*?try context\.save\(\)/);
  assert.doesNotMatch(merge, /context\.delete|insertEdit/);

  const owner = expense('owner', 201, february, 'groceries');
  const solo = createExpense({
    amount: 101, date: february, category: 'groceries', payer: 'first',
    split: { kind: 'ratio', first: 60, second: 40 },
  });
  const joined = { id: 'solo', ...createExpense({
    ...solo, payer: 'second', split: { kind: 'ratio', first: 40, second: 60 },
  }) };
  assert.equal(joined.firstShare, solo.amount - solo.firstShare);
  assert.deepEqual(bookSettlement(book({ expenses: [owner, joined, joined] }), dates),
    { from: 'second', to: 'first', amount: 60 });
});

test('departure mid-month keeps both payers in the settlement and ends the departed grant', () => {
  const departure = Date.parse('2026-02-15T12:00:00+09:00');
  const former = expense('former', 101, localDay(departure - 1), 'groceries', 'second');
  const after = expense('after', 201, localDay(departure), 'groceries');
  const grants = [{ bookID, member: 'guest', originalID: 'lifetime',
    purchasedAt: departure - 1, expiresAt: null, revoked: false }];
  assert.equal(bookAccess(grants, bookID, 'guest', departure - 1).plan, 'pro');
  assert.equal(bookAccess(grants, bookID, null, departure).plan, 'free');
  assert.deepEqual(bookSettlement(book({ expenses: [former, after] }), dates),
    { from: 'second', to: 'first', amount: 50 });
  assert.match(cloudMethod('refresh'), /\.acceptanceStatus == \.accepted[\s\S]*?let expenses = try self\.expenses\(in: row/);
});

test('Swift message literals do not expose raw CloudKit errors or interpolate technical errors', () => {
  const roots = ['FutariKakeibo', 'FutariDomain', 'FutariWidget'];
  const literal = /"(?:\\.|[^"\\\r\n])*"/g;
  const rawError = /\b(?:CKError(?:Domain)?|NS(?:Cocoa|Underlying)Error(?:Domain)?|localizedDescription)\b|\\\(\s*(?:error|ckError|failureError)\b|The operation couldn[’']t be completed|Server Rejected Request/i;
  for (const root of roots) {
    for (const entry of readdirSync(new URL('../Sources/' + root + '/', import.meta.url))) {
      if (!entry.endsWith('.swift')) continue;
      const swift = source(root + '/' + entry);
      for (const match of swift.matchAll(literal)) {
        assert.doesNotMatch(match[0], rawError, entry);
      }
      assert.doesNotMatch(swift, /\b(?:Text|Label|alert|accessibilityLabel|notice\s*=|message\s*=|failure\s*=)\s*\(?[^\n]*(?:\.localizedDescription|String\(describing:\s*error|\.recordName|\.zoneName)/);
    }
  }
  assert.match(cloudMethod('observePartner'), /\.pending[\s\S]*?相手にリンクを開いてもらってください[\s\S]*?再招待してください/);
  assert.match(cloudMethod('refresh'), /共有が終了しました。共有するには招待を受け直してください/);
  assert.match(source('FutariKakeibo/ExpenseDetail.swift'), /catch ReceiptPhotoError\.changed[\s\S]*?写真を確認してからやり直してください/);
});

test('invite failures select distinct Japanese recovery steps in both invite flows', () => {
  const cloud = source('FutariKakeibo/CloudLedger.swift');
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  const messages = cloud.slice(cloud.indexOf('var message: String'), cloud.indexOf('var nextAction: String'));
  const actions = cloud.slice(cloud.indexOf('var nextAction: String'), cloud.indexOf('static func classify'));
  for (const [issue, explanation, action] of [
    ['signedOut', /サインインしていない/, /設定.*サインイン/],
    ['expired', /期限切れ/, /新しいリンクを依頼/],
    ['accountMismatch', /国や地域.*可能性/, /メールアドレス・国や地域を確認/],
    ['otherPartner', /パートナーは1人/, /メールアドレスを確認/],
    ['retry', /処理できません/, /通信を確認して再試行/],
  ]) {
    const valueFor = (body) => body.match(new RegExp(`case \\.${issue}: return "([^"]+)"`))?.[1] ?? '';
    assert.match(valueFor(messages), explanation);
    assert.match(valueFor(messages), /^[^。]+。$/);
    assert.match(valueFor(actions), action);
  }
  assert.match(cloud, /account == \.noAccount \? \.signedOut/);
  assert.match(cloud, /case \.notAuthenticated: return \.signedOut/);
  assert.match(cloud, /case \.unknownItem: return accepting \? \.expired/);
  assert.match(cloud, /case \.permissionFailure, \.serverRejectedRequest: return \.accountMismatch/);
  assert.match(cloud, /case \.unresolvedPartner: return \.accountMismatch/);
  assert.match(cloudMethod('accept'), /inviteIssue = sharingAccountIssue[\s\S]*?InviteIssue\.classify\(error, accepting: true\)[\s\S]*?failedInvite = issue == \.expired \? nil : metadata[\s\S]*?inviteIssue = issue/);
  assert.match(cloudMethod('retryInvite'), /await checkAccount\(\)[\s\S]*?await accept\(failedInvite\)/);
  assert.match(settings, /InviteIssue\.classify\(error, accepting: false\)/);
  assert.match(settings, /ledger\.sharingAccountIssue \?\? failure[\s\S]*?InviteRecovery\(issue: issue\)/);
  assert.match(settings, /Text\(issue\.message\)\s*Text\(issue\.nextAction\)/);
  assert.match(app, /ledger\.inviteIssue[\s\S]*?InviteRecovery\(issue: issue\)[\s\S]*?if ledger\.canRetryInvite[\s\S]*?await ledger\.retryInvite\(\)/);
});

test('settlement, empty states and accessibility text are wired into the Swift views', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  const tools = source('FutariKakeibo/PaidBookTools.swift');
  const receipt = source('FutariKakeibo/ExpenseDetail.swift');
  assert.match(app, /Text\("\\\(honorific\(names\[payment\.from\]\)\)が\\\(honorific\(names\[payment\.to\]\)\)に\\\(payment\.amount\.yen\)支払えば精算完了です。"\)/);
  assert.match(app, /SettlementAmount\(value: result, names: snapshot\.names\)\s*\.accessibilityIdentifier\("settlement-amount"\)\s*DisclosureGroup\("1円の端数の扱い"\) \{\s*Text\("折半と比率では、支払った人が端数の1円を負担します。返金では、受け取った人に端数の1円を割り当てます。固定額では、指定した人以外が残額を負担します。"/);
  assert.match(app, /accessibilityLabel\(expense\.spokenAmount\(names: names\)\)[\s\S]*?expense\.payerCaption\(names: names\)/);
  assert.match(app, /if typeSize\.isAccessibilitySize \{\s*VStack/);
  assert.match(app, /Button\("この月の支出を記録"\) \{ showingEntry = true \}/);
  assert.match(app, /budgets\.isEmpty \? "費目別予算を設定"/);
  assert.match(tools, /家計簿で支出を記録してください[\s\S]*?DisclosureGroup\("月ごとの支出額"\)[\s\S]*?value\.amount\.yen/);
  assert.match(tools, /品目名[\s\S]*?追加/);
  assert.match(receipt, /accessibilityLabel\(expense\.spokenAmount\(names: snapshot\.names\)\)/);
});

test('home leads with the selected Japan month settlement in its largest font', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  const home = app.slice(app.indexOf('private struct Home: View'), app.indexOf('struct FirstExpensePrompt: View'));
  const header = home.slice(home.indexOf('private func settlementHeader'), home.indexOf('private func settlementTitle'));
  assert.match(home, /let currentMonth = Month\(containing: ScreenshotDemo\.day \?\? Month\.localDay\(context\.date\)\)\s*let month = selectedMonth \?\? currentMonth/);
  assert.match(home, /List \{\s*if let snapshot = ledger\.snapshot \{\s*if snapshot\.expenses\.isEmpty && snapshot\.settlementDates\[month\] == nil \{\s*FirstExpensePrompt\([^\n]+\)[\s\S]*?\} else \{\s*settlementHeader\(month: month, currentMonth: currentMonth, snapshot: snapshot\)/);
  assert.match(header, /return layout \{\s*NavigationLink \{[\s\S]*?\} label: \{\s*VStack\([^\n]+\) \{\s*Text\(settlementTitle\(in: month, snapshot: snapshot\)\)\s*\.font\(\.largeTitle\.weight\(\.bold\)\)/);
  const styles = Array.from(home.matchAll(/\.font\(\.(\w+)/g), ([, style]) => style);
  assert.equal(styles.filter(style => style === 'largeTitle').length, 1);
  assert.ok(styles.every(style => ['largeTitle', 'headline', 'subheadline', 'footnote'].includes(style)));
  assert.equal((home.match(/\.font\(/g) ?? []).length, styles.length);
  assert.match(header, /Menu \{\s*Button\("前の月"\) \{ selectedMonth = month\.advanced\(by: -1\) \}\s*Button\("次の月"\) \{ selectedMonth = month\.advanced\(by: 1\) \}/);
  const title = home.slice(home.indexOf('private func settlementTitle'));
  assert.match(title, /return payment\.from == member\s*\? ".*支払う"\s*: ".*受け取る"/);
  assert.match(home, /case \.open\(nil\)\?: return "精算なし"/);
  assert.match(home, /HomeSpending\(month: month, snapshot: snapshot\)/);
  assert.match(home, /let totals = try\? Ledger\.totals\(for: snapshot\.expenses, in: month\)[\s\S]*?SectorMark\(angle: \.value\("支出", totals\[category, default: 0\]\)/);
  assert.match(home, /Ledger\.spendingTotal\(for: snapshot\.expenses, in: month\)[\s\S]*?value: total\.yen/);
  assert.match(home, /let expense = recentExpense\(in: month, snapshot: snapshot\)[\s\S]*?Text\(expense\.label \?\? snapshot\.title\(for: expense\.category\)\)/);
  assert.match(home, /func recentExpense[\s\S]*?month\.dates\.contains\(\$0\.date\)[\s\S]*?return partnerExpense\s*\}\s*return records\.first/);
  assert.match(cloudMethod('write'), /try context\.save\(\)[\s\S]*?refresh\(\)/);
});

test('an empty book can open either the first expense form or the Pro budget settings', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  const budget = source('FutariKakeibo/ProSettings.swift');
  const prompt = app.slice(app.indexOf('struct FirstExpensePrompt: View'), app.indexOf('private enum MonthlySettlement'));
  assert.match(app, /if snapshot\.expenses\.isEmpty && snapshot\.settlementDates\[month\] == nil \{\s*FirstExpensePrompt\(canRecord: ledger\.canStartRecording, record: startExpense\)/);
  assert.match(app, /FirstExpensePrompt\([^\n]+\)\s*if ledger\.plan\.allowsProFeatures \{\s*NavigationLink \{\s*BudgetSettings\(ledger: ledger, book: snapshot\.book, month: month\)/);
  const budgetSettings = budget.slice(budget.indexOf('struct BudgetSettings'), budget.indexOf('struct BudgetProgressRow'));
  assert.match(budgetSettings, /snapshot\.book == book \{\s*budgetRows\(snapshot\)/);
  assert.doesNotMatch(budgetSettings, /expenses\.isEmpty/);
  assert.match(budgetSettings, /if limits\.isEmpty, !previousLimits\.isEmpty \{\s*Button\("前月の予算を引き継ぐ"\) \{\s*do \{ try ledger\.copyPreviousBudget/);
  assert.match(cloudMethod('copyPreviousBudget'), /try write\(to: book\)[\s\S]*?limitsByMonth\[month\.advanced\(by: -1\)\][\s\S]*?guard !previous\.isEmpty,[\s\S]*?\(limitsByMonth\[month\][\s\S]*?for \(category, limit\) in previous[\s\S]*?insertEdit\(key, value: String\(limit\)/);
  assert.match(prompt, /Text\("この家計簿にはまだ支出の記録がありません。"\)\s*RecordExpenseButton/);
  assert.match(prompt, /Button\(action: record\) \{\s*Label\("支出を記録", systemImage: "plus"\)[\s\S]*?\.buttonStyle\(\.borderedProminent\)/);
  assert.match(app, /\.sheet\(item: \$enteringExpense\) \{ snapshot in\s*EntryForm\(snapshot: snapshot, repository: ledger\)/);
  assert.match(app, /func startExpense\(\)[\s\S]*?try ledger\.startRecording\(\)/);
  assert.match(cloudMethod('member'), /isOwner: !book\.isGuest/);
  assert.match(source('FutariKakeibo/BookRepository.swift'), /if isOwner \{ return \.first \}/);
});

test('home gets the settlement date from the latest closed-month edit', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(cloudMethod('setSettled'), /insertEdit\(key, value: settled \? "1" : "0"[^)\n]*after: previous\?\.time\)/);
  assert.match(cloudMethod('refresh'), /for \(key, edit\) in edits where key\.hasPrefix\("month\/"\) && edit\.value == "1" \{\s*guard let seconds = Int\(key\.dropFirst\(6\)\), let date = edit\.time/);
  assert.match(cloudMethod('refresh'), /expenses: expenses, settlementDates: settlementDates/);
  assert.match(app, /case \.settled\?: return "精算済み"/);
  assert.match(app, /if let date = snapshot\.settlementDates\[month\] \{\s*Text\(Month\.localDay\(date\)\.formatted\(japaneseDate\.year\(\)\.month\(\)\.day\(\)\)\)/);
});

test('budget progress covers under, exactly at, over, refunds and zero budget', () => {
  for (const [limit, spent, remaining, overspend, percentageUsed, progress, displayPercentage] of [
    [2000, 1500, 500, 0, 75, 0.75, 25],
    [2000, 2000, 0, 0, 100, 1, 0],
    [2000, 2500, 0, 500, 125, 1, -25],
    [2000, 2001, 0, 1, 100.05, 1, -1],
    [2000, -100, 2100, 0, 0, 0, 105],
    [0, 0, 0, 0, 0, 0, null],
    [0, 500, 0, 500, null, 1, null],
  ]) {
    assert.deepEqual(budgetProgress(limit, spent), {
      limit, spent, remaining, overspend, percentageUsed, progress, displayPercentage,
    });
  }
  const remaining = budgetProgress(218_000, 180_244);
  assert.deepEqual([remaining.spent, remaining.remaining, remaining.displayPercentage], [180_244, 37_756, 17]);
  const over = budgetProgress(40_000, 81_098);
  assert.deepEqual([over.spent, over.overspend, over.displayPercentage], [81_098, 41_098, -103]);
});

test('Swift puts the configured budget total above categories and shows accessible overspend', () => {
  const ledger = source('FutariDomain/Ledger.swift');
  const budget = source('FutariKakeibo/ProSettings.swift');
  assert.match(ledger, /func budgetProgress\(limit: Int, spent: Int\) -> BudgetProgress/);
  assert.match(ledger, /let displayPercentage = limit > 0 \? \(100 \* Double\(balance\) \/ Double\(limit\)\)\.rounded\(\.down\) : nil/);
  assert.match(ledger, /BudgetProgress\(limit: limit, spent: spent/);
  assert.match(ledger, /return budgetProgress\(limit: limit, spent: spent\)/);
  assert.match(ledger, /limits\.keys\.reduce\(0\) \{ try sum\(\$0, totals\[\$1, default: 0\]\) \}/);
  assert.match(budget, /Ledger\.budgetTotal\(limits: limits, totals: totals\)[\s\S]*?BudgetProgressRow\(title: "予算の合計", progress: total\)[\s\S]*?ForEach\(categories/);
  assert.match(budget, /Ledger\.budgetProgress\(limit: limit, spent: totals\[category, default: 0\]\)/);
  assert.match(budget, /Text\(progress\.overspend > 0 \? "超過 \\\(progress\.overspend\.yen\)" : "残り \\\(progress\.remaining\.yen\)"\)/);
  assert.match(budget, /ProgressView\(value: progress\.progress\)/);
  assert.match(budget, /"予算 \\\(progress\.limit\.yen\)"/);
  assert.match(budget, /"支払済 \\\(progress\.spent\.yen\)"/);
  assert.match(budget, /Text\(progress\.displayPercentage\.map[\s\S]*?\.foregroundStyle\(tone\)/);

  const colors = [...budget.matchAll(/Color\(red: ([\d.]+)(?: \/ (255))?, green: ([\d.]+) \/ 255, blue: ([\d.]+) \/ 255\)/g)];
  assert.equal(colors.length, 4);
  const luminance = rgb => rgb.map(channel => channel <= 0.04045
    ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4)
    .reduce((sum, linear, index) => sum + linear * [0.2126, 0.7152, 0.0722][index], 0);
  for (const [index, [, red, divisor, green, blue]] of colors.entries()) {
    const foreground = luminance([red / (divisor ?? 1), green / 255, blue / 255]);
    const background = luminance(index % 2 === 0 ? [0.2, 0.2, 0.2] : [0.9, 0.9, 0.9]);
    assert.ok((Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05) >= 4.5);
  }
});

test('the paywall explains shared two-person value, all major Pro features and free sharing before plans or purchase', () => {
  const paywall = source('FutariKakeibo/ProPaywall.swift');
  const firstPrice = paywall.indexOf('ForEach(ProProduct.allCases');
  assert.ok(firstPrice > 0);
  for (const benefit of [
    '1契約で共有家計簿のふたりともProを使えます',
    '家計簿を追加',
    '予算と残額',
    '毎月の支出を自動で記録',
    '買い物リスト',
    '支出推移グラフ',
    'CSV書き出し',
    'ウィジェット',
    '精算日の通知',
    'iCloudでの共有と同期は無料',
  ]) {
    const offset = paywall.indexOf(benefit);
    assert.ok(offset >= 0 && offset < firstPrice, benefit);
  }
  assert.ok(paywall.indexOf('Button(purchaseButtonTitle)') > firstPrice);
  assert.match(paywall, /isEligibleForIntroOffer/);
  assert.match(paywall, /selection == \.yearly && yearlyIntroEligible \? "14日間無料で始める" : "購入手続きへ"/);
  assert.match(paywall, /return products\[option\]\?\.displayPrice/);
  const invite = cloudMethod('invite');
  assert.match(invite, /guard canShare/);
  assert.doesNotMatch(invite, /allowsProFeatures|proRequired/);
});

test('the first entry uses a focused amount and two defaulted pickers before optional details', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /enteringExpense = try ledger\.startRecording\(\)/);
  assert.match(app, /category = Category\.groceries/);
  assert.match(app, /_payer = State\(initialValue: expense\?\.payer \?\? snapshot\.member \?\? \.first\)/);
  assert.match(app, /TextField\("金額（円）"[\s\S]*?Picker\("支払った人"[\s\S]*?Picker\("費目"[\s\S]*?DisclosureGroup\(isRecurring[\s\S]*?defaultFocus\(\$amountFocused, true\)/);
});

test('the collapsed entry details show the active split mode', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  const entry = app.slice(app.indexOf('struct EntryForm'), app.indexOf('struct EditNames'));
  assert.match(entry, /@State private var mode = Mode\.equal/);
  assert.match(entry, /DisclosureGroup\(isRecurring.*?分け方 \\\(mode\.rawValue\)/);
  assert.match(entry, /Picker\("分け方", selection: \$mode\)/);
});

test('the settings offer free sharing before Pro controls', () => {
  const share = settings.indexOf('if ledger.canShare');
  const invite = settings.indexOf('NavigationLink("パートナーを招待")');
  const paid = settings.indexOf('if ledger.plan.allowsProFeatures');
  assert.ok(share >= 0 && share < invite && invite < paid);
});

test('a generated invitation tells the owner to send the link', () => {
  const invite = settings.slice(settings.indexOf('struct InvitePartner'));
  assert.match(invite, /if let link, ledger\.canShare \{\s*ShareLink\(item: link\)[\s\S]*?Text\("リンクを相手に送ってください。相手が承諾すると共有が始まります。"\)\s*\.font\(\.footnote\)\.foregroundStyle\(\.secondary\)\s*\} else \{/);
});

test('settlement review identifies the same month it updates', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /SettlementReview\(ledger: ledger, book: book, month: month\)/);
  const review = app.slice(app.indexOf('struct SettlementReview'), app.indexOf('struct EntryForm'));
  assert.match(review, /SettlementAmount\(value: result, names: snapshot\.names\)[\s\S]*?\} header: \{\s*Text\(month\.start\.formatted\(japaneseDate\.year\(\)\.month\(\)\)\)/);
  assert.match(review, /ledger\.setSettled\(!isSettled, month: month, in: book\)/);
});

test('price lookup failures appear by retry and clear on a new lookup', () => {
  const paywall = source('FutariKakeibo/ProPaywall.swift');
  assert.match(paywall, /if priceLoadFailed \{\s*Text\("価格を取得できませんでした"\)[\s\S]*?Button\("価格を再読み込み"\)/);
  const load = paywall.slice(paywall.indexOf('private func loadProducts'), paywall.indexOf('private func buy'));
  assert.match(load, /priceLoadFailed = false[\s\S]*?try await ledger\.purchases\.products\(\)[\s\S]*?catch \{\s*priceLoadFailed = true/);
  assert.doesNotMatch(load, /\bstatus\s*=/);
});

test('monthly recurring lookup queries only candidate IDs in the destination book', () => {
  const generation = cloudMethod('generateRecurring');
  assert.doesNotMatch(generation, /expenses\(in:/);
  assert.match(generation, /expenseRequest\(in: row, recurringIDs: ids\)/);
  assert.match(cloudMethod('expenseRequest'), /book == %@ AND recurringID IN %@/);
  assert.match(cloudMethod('insert'), /row\.recurringID = recurring \? expense\.id : nil/);
  const model = source('FutariKakeibo/BookModel.swift');
  assert.match(model, /attribute\("recurringID", \.UUIDAttributeType\)/);
  const previous = source('FutariKakeibo/FutariLedgerMigration.xcdatamodeld/FutariLedgerV2.xcdatamodel/contents');
  assert.match(previous, /name="receiptJPEG" optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/);
  assert.doesNotMatch(previous, /name="recurringID"/);
});

test('duplicate fallback and custom titles have distinguishable switcher labels', () => {
  for (const title of [null, '旅行']) {
    const guests = [{ id: bookID, title }, { id: otherBookID, title }];
    const titles = guests.map(guest => guest.title ?? '共有の家計簿');
    titles.push(`1. ${titles[0]}`);
    const labels = titles.map((value, index) => `${index + 1}. ${value}`);
    assert.equal(new Set(labels).size, titles.length);
  }
  assert.match(cloudMethod('title'), /book\.isGuest \? "共有の家計簿"/);
  assert.match(settings, /ForEach\(Array\(ledger\.books\.enumerated\(\)\), id: \\.element\)/);
  assert.match(settings, /Set\(titles\)\.count != titles\.count/);
  assert.match(settings, /"\\\(index \+ 1\)\. \\\(titles\[index\]\)"/);
});

test('the Swift recurring ID uses the same book/template/month key and UUID bits as the mirror', () => {
  const swift = source('FutariDomain/RecurringEntry.swift');
  assert.match(swift, /"\\\(bookID\.uuidString\)\/\\\(templateID\.uuidString\)\/\\\(seconds\)"/);
  assert.match(swift, /SHA256\.hash\(data: Data\(identity\.utf8\)\)\)?\.prefix\(16\)/);
  assert.match(swift, /bytes\[6\] = \(bytes\[6\] & 0x0F\) \| 0x80/);
  assert.match(swift, /bytes\[8\] = \(bytes\[8\] & 0x3F\) \| 0x80/);
  assert.match(swift, /guard !isSettled else \{ return \[\] \}/);
});

test('one Plan seam gates every paid feature and defaults to free', () => {
  const files = ['FutariDomain/Plan.swift', 'FutariKakeibo/CloudLedger.swift',
    'FutariKakeibo/BookSettings.swift', 'FutariKakeibo/FutariKakeiboApp.swift', 'FutariKakeibo/ProSettings.swift']
    .map(source);
  assert.equal(files.join('\n').match(/enum Plan\b/g)?.length, 1);
  assert.match(files[0], /Plan\.init\(rawValue:\)\) \?\? \.free/);
  for (const name of ['addTemplate', 'writeProEdit']) {
    const body = files[1].slice(files[1].indexOf(`func ${name}(`));
    assert.match(body, /^[^\n]*\n\s*guard plan\.allowsProFeatures else \{ throw BookError\.proRequired \}/);
  }
  assert.match(files[1], /generateRecurring\(in: available\.filter \{ access\(for: \$0\.0\)\.plan\.allowsProFeatures \}/);
  for (const feature of ['定期入力', '家計簿を追加']) {
    assert.ok(files[2].includes(`ProLock("${feature}", ledger: ledger)`));
  }
  assert.ok(files[3].includes('ProLock("費目別予算", ledger: ledger)'));
  assert.match(files[4], /\.sheet\(isPresented: \$showingPaywall\) \{\s*ProPaywall\(ledger: ledger\)/);
});

test('settling one book leaves another book’s opposing balance open', () => {
  const home = book({ expenses: [expense('home', 600, february, 'groceries')] });
  const trip = book({ id: otherBookID, expenses: [expense('trip', 600, february, 'transport', 'second')] });
  assert.deepEqual(bookSettlement(home, dates), { from: 'second', to: 'first', amount: 300 });
  assert.deepEqual(bookSettlement(trip, dates), { from: 'first', to: 'second', amount: 300 });
  assert.equal(bookSettlement(book({ ...home, settled: [february] }), dates), null);
  assert.deepEqual(bookSettlement(trip, dates), { from: 'first', to: 'second', amount: 300 });
});

test('a writable guest sees how their first payment is shared even in a populated ledger', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /if let snapshot = ledger\.snapshot, !snapshot\.expenses\.isEmpty, snapshot\.book\.isGuest,\s*let member = snapshot\.member, ledger\.canStartRecording,\s*!snapshot\.expenses\.contains\(where: \{ \$0\.payer == member \}\) \{\s*Text\("自分の支払いを記録すると、ふたりの家計簿に反映されます"\)/);
});

test('free settings offer an opt-in local recording reminder with selectable time and can cancel it', () => {
  const paid = settings.indexOf('if ledger.plan.allowsProFeatures');
  const reminder = settings.indexOf('RecordingReminder()');
  assert.ok(reminder >= 0 && reminder < paid);
  assert.match(settings, /@AppStorage\("ledger\.recordingHour"\) private var hour = 20/);
  assert.match(settings, /@AppStorage\("ledger\.recordingMinute"\) private var minute = 0/);
  assert.match(settings, /DatePicker\("通知時刻", selection: timeBinding, displayedComponents: \.hourAndMinute\)/);
  assert.match(settings, /if enabled \{[\s\S]*?requestAuthorization\([\s\S]*?DateComponents\(hour: hour, minute: minute\)[\s\S]*?repeats: true[\s\S]*?try await center\.add\(UNNotificationRequest\(identifier: reminderID[\s\S]*?else \{\s*center\.removePendingNotificationRequests\(withIdentifiers: \[reminderID\]\)/);
  assert.match(settings, /catch \{\s*reminderFailure = true/);
});

test('home links the other member’s latest dated payment or refund to its synced expense', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /let expense = recentExpense\(in: month, snapshot: snapshot\)[\s\S]*?ExpenseDetail\(ledger: ledger, book: snapshot\.book, expenseID: expense\.id\)[\s\S]*?expense\.payerCaption\(names: snapshot\.names\)/);
  assert.match(app, /let records = snapshot\.expenses\.filter \{ month\.dates\.contains\(\$0\.date\) \}[\s\S]*?records\.first\(where: \{ \$0\.payer == member\.other \}\)/);
  assert.match(cloudMethod('expenses'), /\.sorted \{ \$0\.date > \$1\.date \}/);
});

test('home links to the previous month while its recorded expenses are unsettled', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /let previous = month\.advanced\(by: -1\)\s*if month == currentMonth, snapshot\.settlementDates\[previous\] == nil,\s*snapshot\.expenses\.contains\(where: \{ previous\.dates\.contains\(\$0\.date\) \}\) \{\s*NavigationLink \{\s*MonthDetail\(month: previous, ledger: ledger, book: snapshot\.book\)/);
});

test('zero-balance month can be closed with guidance that no transfer is needed', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(app, /case \.open\(nil\):\s*Text\("送金は不要です。精算済みにすると、この月の記録が締まります。"\)/);
  assert.match(app, /case \.open\(\.some\(_\)\):\s*Text\("支払いを確認してから/);
});

test('widget shows settlement for free users, opens quick entry and home invites unshared owners', () => {
  const publishing = source('FutariKakeibo/WidgetPublishing.swift');
  const widget = source('FutariWidget/LedgerWidget.swift');
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  assert.match(publishing, /if let snapshot, let member = snapshot\.member, let bookTitle \{/);
  assert.match(publishing, /budgetRemaining: isPro \? \(try\? remaining\(in: month, snapshot: snapshot\)\) : nil/);
  assert.match(publishing, /amountOwed: try\? owed\(by: member, in: month, snapshot: snapshot\)/);
  assert.match(publishing, /proExpiresAt: isPro \? access\.expiresAt : \.distantPast/);
  assert.match(widget, /\.widgetURL\(URL\(string: "futarikakeibo:\/\/record"\)\)/);
  assert.doesNotMatch(widget, /有料プランで使う/);
  assert.match(widget, /if entry\.pro, let budgetRemaining = summary\.budgetRemaining \{\s*amount\("今月の予算残額", budgetRemaining\)\s*\}\s*amount\("今月の支払う精算額", summary\.amountOwed\)/);
  assert.match(app, /openURLContexts[\s\S]*?futarikakeibo[\s\S]*?requestQuickRecord\(\)/);
  assert.match(app, /pendingQuickRecord[\s\S]*?consumeQuickRecord\(\)[\s\S]*?startExpense\(\)/);
  assert.match(app, /!snapshot\.expenses\.isEmpty,\s*!snapshot\.book\.isGuest, ledger\.canShare, !ledger\.isBookShared, ledger\.partnerNotice == nil[\s\S]*?InvitePartner\(ledger: ledger, book: snapshot\.book\)/);
});

test('home spending shows matched color swatches without hiding the legend and month detail colors budget status', () => {
  const app = source('FutariKakeibo/FutariKakeiboApp.swift');
  const spending = app.slice(app.indexOf('private struct HomeSpending: View'), app.indexOf('struct FirstExpensePrompt: View'));
  assert.doesNotMatch(spending, /\.chartLegend\(\.hidden\)/);
  assert.match(spending, /SectorMark\([\s\S]*?\.foregroundStyle\(swatchColor\(for: category, in: positive\)/);
  assert.match(spending, /if showChart, let swatch = swatchColor\(for: category, in: positive\) \{\s*RoundedRectangle\([\s\S]*?\.fill\(swatch\)[\s\S]*?\}\s*YenRow\(title: snapshot\.title\(for: category\), value: totals\[category, default: 0\]\.yen\)/);
  const detail = app.slice(app.indexOf('private struct MonthDetail: View'), app.indexOf('private struct SettlementReview: View'));
  assert.match(detail, /Text\(remaining < 0 \? "超過 \\\(\(-remaining\)\.yen\)" : "残り \\\(remaining\.yen\)"\)\s*\.font\(\.footnote\)\s*\.foregroundStyle\(budgetTone\(overspend: remaining < 0, colorScheme: colorScheme\)\)/);
  assert.match(app, /YenRow\(\s*title: "今月の予算",[\s\S]*?\.foregroundStyle\(budgetTone\(overspend: progress\.overspend > 0, colorScheme: colorScheme\)\)/);
});

test('late deleted receipt rows and orphaned recurring rows are hidden and purged while keeping deletion markers', () => {
  const original = expense('lunch', 600, february, 'dining');
  const other = expense('groceries', 200, february, 'groceries', 'second');
  const deleted = changeExpense(book({ expenses: [original, other] }), original.id);
  const latePhotoRow = { ...original, receiptJPEG: true };
  const withLatePhoto = { ...deleted, expenses: [latePhotoRow, ...deleted.expenses] };
  assert.deepEqual(bookExpenses(withLatePhoto), [other]);
  const cleanedPhoto = purgeDeletedExpenses(withLatePhoto);
  assert.deepEqual(cleanedPhoto.purged, [latePhotoRow]);
  assert.deepEqual(cleanedPhoto.book.expenses, [other]);
  assert.ok(cleanedPhoto.book.deletedExpenses.has(original.id));

  const rent = expense(rentID, 100, january, 'housing');
  const templateBook = book({ templates: [rent] });
  const [generated] = missingRecurring(templateBook, february);
  const regeneratedBeforeMarker = { ...templateBook, expenses: [generated] };
  const lateMarkerArrived = { ...regeneratedBeforeMarker, deletedExpenses: new Set([generated.id]) };
  assert.deepEqual(bookExpenses(lateMarkerArrived), []);
  assert.deepEqual(missingRecurring(lateMarkerArrived, february), []);
  const cleanedRecurring = purgeDeletedExpenses(lateMarkerArrived);
  assert.deepEqual(cleanedRecurring.purged, [generated]);
  assert.deepEqual(cleanedRecurring.book.expenses, []);
  assert.ok(cleanedRecurring.book.deletedExpenses.has(generated.id));

  const purge = cloudMethod('purgeDeletedExpenseRows');
  assert.match(purge, /edits\.keys\.contains\(where: \{ \$0\.hasPrefix\("deletedExpense\/"\) \}\)/);
  assert.match(purge, /\(try\? expenseFields\(for: row, decoder: decoder\)\.id\) \?\? row\.recurringID/);
  assert.match(purge, /edits\[deletedExpenseKey\(id\)\] != nil/);
  assert.match(purge, /!book\.isGuest \|\| container\.canDeleteRecord\(forManagedObjectWith: row\.objectID\)/);
  assert.match(purge, /context\.delete\(row\)/);
  assert.match(cloudMethod('refresh'), /for \(book, row\) in available[\s\S]*?try purgeDeletedExpenseRows\(in: row, book: book, edits: edits/);
});

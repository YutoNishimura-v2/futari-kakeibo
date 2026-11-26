import { createExpense, monthStart } from './ledger.mjs';

export function memberForParticipant({ isOwner, isPrivatePartner }) {
  if (isOwner) return 'first';
  return isPrivatePartner ? 'second' : null;
}

function decodeLegacy(entry) {
  const { id, amount, date, categoryKey, payerKey, splitKey, firstValue, label } = entry;
  let split;
  switch (splitKey) {
    case 'equal':
      split = { kind: 'equal' };
      break;
    case 'ratio':
      split = { kind: 'ratio', first: firstValue, second: 100 - firstValue };
      break;
    case 'fixed':
      split = { kind: 'fixed', firstYen: firstValue };
      break;
    default:
      throw new RangeError('invalid split rule');
  }
  return { id, ...createExpense({ amount, date, category: categoryKey, payer: payerKey, split, label }) };
}

export function migrateLegacy(book, legacy, importedOnDevice = false) {
  if (importedOnDevice) return book;
  if (!legacy.expenses.length && !legacy.settled.length
      && (legacy.names.first ?? 'わたし') === 'わたし'
      && (legacy.names.second ?? 'パートナー') === 'パートナー') return book;
  const ids = new Set(book.expenses.map(({ id }) => id));
  const additions = legacy.expenses.map(decodeLegacy).filter(({ id }) => !ids.has(id));
  const values = {
    first: legacy.names.first ?? 'わたし',
    second: legacy.names.second ?? 'パートナー',
  };
  for (const date of legacy.settled) values[`month/${monthStart(date) / 1000}`] = '1';
  if (book.migrated && additions.length === 0
      && Object.keys(values).every((key) => Object.hasOwn(book.values, key))) return book;
  return {
    migrated: true,
    expenses: [...book.expenses, ...additions],
    values: { ...values, ...book.values },
  };
}

// The caller supplies owned books in stable ID order.
export function ownedBookPlan(books, selectedID, mayCreate) {
  const current = books.find(({ id }) => id === selectedID);
  const shared = books.find((book) => book.shared);
  const selected = current && (current.shared || !current.empty) ? current
    : shared ?? books.find((book) => !book.empty)
      ?? (mayCreate ? current ?? books[0] : undefined);
  return { selected: selected?.id ?? null, create: mayCreate && books.length === 0 };
}

export function partnerSlot(partners, target) {
  if (partners.some(({ id, status }) => status === 'accepted' && id !== target)) return null;
  const same = partners.find(({ id, status }) => id === target && ['accepted', 'pending'].includes(status));
  return {
    keep: same?.id ?? null,
    remove: partners.filter(({ id, status }) => status === 'pending' && id !== target).map(({ id }) => id),
  };
}

export function editTime(now, previous) {
  return Math.max(now, previous === undefined ? -Infinity : previous + 1);
}

export function latestEdits(edits) {
  const latest = new Map();
  for (const edit of edits) {
    const previous = latest.get(edit.key);
    if (!previous || edit.time > previous.time
        || (edit.time === previous.time && edit.id.toUpperCase() > previous.id.toUpperCase())) {
      latest.set(edit.key, edit);
    }
  }
  return latest;
}

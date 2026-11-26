import { createHash } from 'node:crypto';
import { createExpense, monthStart, monthlyTotals, settlement } from './ledger.mjs';

export function budgetRemaining(book, month, category, limit) {
  return limit - (monthlyTotals(bookExpenses(book), month)[category] ?? 0);
}

export function budgetProgress(limit, spent) {
  const balance = limit - spent;
  const overspend = Math.max(0, -balance);
  const used = Math.max(0, spent);
  const percentageUsed = limit > 0 ? 100 * used / limit : (used === 0 ? 0 : null);
  const progress = Math.min(1, (percentageUsed ?? 100) / 100);
  const displayPercentage = limit > 0 ? Math.floor(100 * balance / limit) : null;
  return { limit, spent, remaining: Math.max(0, balance), overspend, percentageUsed, progress, displayPercentage };
}

export function recurringID(bookID, templateID, month) {
  const identity = `${bookID.toUpperCase()}/${templateID.toUpperCase()}/${monthStart(month) / 1000}`;
  const bytes = createHash('sha256').update(identity).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
}

export function missingRecurring(book, month, sync) {
  if (sync && sync.account !== 'noAccount'
      && (sync.account !== 'available' || !sync.importedStores.has(sync.store))) return [];
  const start = monthStart(month);
  if (book.settled.has(start)) return [];
  const seen = new Set([...book.expenses.map(({ id }) => id), ...(book.deletedExpenses ?? [])]);
  const missing = [];
  for (const template of book.templates) {
    if (monthStart(template.date) > start) continue;
    const id = recurringID(book.id, template.id, start);
    if (seen.has(id)) continue;
    seen.add(id);
    missing.push({ id, ...createExpense({ ...template, date: start }) });
  }
  return missing;
}

export function bookExpenses(book) {
  const seen = new Set();
  return book.expenses.flatMap(expense => {
    const { id } = expense;
    if (seen.has(id) || book.deletedExpenses?.has(id)) return [];
    seen.add(id);
    return [book.expenseEdits?.get(id) ?? expense];
  });
}

// Mirror the repository's stable-ID edits and deletion markers.
export function changeExpense(book, id, replacement) {
  const current = bookExpenses(book).find(expense => expense.id === id);
  if (!current || (replacement && replacement.id !== id)) throw new Error('expense changed');
  if (book.settled.has(monthStart(current.date))
      || (replacement && book.settled.has(monthStart(replacement.date)))) throw new Error('settled');
  if (replacement) {
    const expenseEdits = new Map(book.expenseEdits);
    expenseEdits.set(id, { id, ...createExpense(replacement) });
    return { ...book, expenseEdits };
  }
  return {
    ...book,
    expenses: book.expenses.filter(expense => expense.id !== id),
    deletedExpenses: new Set([...(book.deletedExpenses ?? []), id]),
  };
}

export function bookSettlement(book, dates) {
  return settlement(bookExpenses(book), dates, book.settled);
}

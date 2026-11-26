import { monthStart } from './ledger.mjs';
import { latestEdits } from './shared-book.mjs';

function advanceMonth(month, offset) {
  const date = new Date(month);
  return date.setUTCMonth(date.getUTCMonth() + offset);
}

export function monthlySpending(expenses, starting, count) {
  const start = monthStart(starting);
  const end = advanceMonth(start, count);
  const totals = new Map();
  for (const expense of expenses) {
    if (expense.date < start || expense.date >= end) continue;
    const month = monthStart(expense.date);
    const total = (totals.get(month) ?? 0) + expense.amount;
    if (!Number.isSafeInteger(total)) throw new RangeError('total too large');
    totals.set(month, total);
  }
  return Array.from({ length: count }, (_, offset) => {
    const month = advanceMonth(start, offset);
    return { month, amount: totals.get(month) ?? 0 };
  });
}

export function csv(rows) {
  return Buffer.from('\uFEFF' + rows.map(
    (row) => row.map((cell) => '"' + cell.replaceAll('"', '""') + '"').join(',') + '\r\n'
  ).join(''), 'utf8');
}

// Work with UTC civil-calendar fixtures. iOS uses the device's Gregorian civil calendar.
export function settlementDate(day, month) {
  if (!Number.isInteger(day) || day < 1 || day > 31) return null;
  const start = monthStart(month);
  const lastDay = new Date(advanceMonth(start, 1) - 1).getUTCDate();
  const date = new Date(start);
  date.setUTCDate(Math.min(day, lastDay));
  return date.setUTCHours(9);
}

export function mergeShopping(edits, bookID) {
  const latest = latestEdits(edits.filter((edit) => edit.bookID === bookID));
  const prefix = 'shopping/name/';
  return [...latest].filter(([key, row]) => key.startsWith(prefix) && row.value)
    .map(([key, row]) => {
      const id = key.slice(prefix.length);
      return { id, name: row.value, checked: latest.get('shopping/checked/' + id)?.value === '1' };
    });
}

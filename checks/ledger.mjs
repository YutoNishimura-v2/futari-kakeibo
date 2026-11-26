const maximumYen = Number.MAX_SAFE_INTEGER;
const members = ['first', 'second'];
const categories = [
  'groceries', 'dining', 'household', 'housing', 'utilities', 'transport', 'leisure', 'other',
];
const graphemes = new Intl.Segmenter('ja', { granularity: 'grapheme' });

export function firstShare(amount, payer, split) {
  if (!Number.isSafeInteger(amount) || amount === 0) throw new RangeError('invalid amount');
  const magnitude = Math.abs(amount);
  if (!members.includes(payer)) throw new RangeError('invalid member');
  let firstPercent;
  switch (split.kind) {
    case 'equal':
      firstPercent = 50;
      break;
    case 'ratio':
      if (!Number.isInteger(split.first) || split.first < 0 || split.first > 100
          || split.second !== 100 - split.first) throw new RangeError('invalid ratio');
      firstPercent = split.first;
      break;
    case 'fixed':
      if (!Number.isSafeInteger(split.firstYen) || split.firstYen < 0 || split.firstYen > magnitude) {
        throw new RangeError('invalid fixed amount');
      }
      return amount < 0 && split.firstYen !== 0 ? -split.firstYen : split.firstYen;
    default:
      throw new RangeError('invalid split rule');
  }
  // Round down the non-payer's share. The payer's share includes the remainder.
  const otherPercent = payer === 'first' ? 100 - firstPercent : firstPercent;
  const otherShare = Number(BigInt(magnitude) * BigInt(otherPercent) / 100n);
  const share = payer === 'first' ? magnitude - otherShare : otherShare;
  return amount < 0 && share !== 0 ? -share : share;
}

export function createExpense({ amount, date, category, payer, split, label }) {
  const share = firstShare(amount, payer, split);
  if (!Number.isSafeInteger(date) || !Number.isFinite(new Date(date).valueOf())) {
    throw new RangeError('invalid date');
  }
  if (!categories.includes(category)) throw new RangeError('invalid category');
  const cleaned = label?.trim() ?? '';
  if ([...graphemes.segment(cleaned)].length > 30) throw new RangeError('label too long');
  return Object.freeze({
    amount, date, category, payer, split: Object.freeze({ ...split }),
    label: cleaned || null, firstShare: share,
  });
}

// Encode the JST date as a UTC day label, matching Month.localDay in Swift.
export function localDay(instant) {
  const day = new Date(instant + 9 * 60 * 60 * 1000);
  day.setUTCHours(0, 0, 0, 0);
  return day.valueOf();
}

export function monthStart(date) {
  const month = new Date(date);
  month.setUTCDate(1);
  month.setUTCHours(0, 0, 0, 0);
  return month.valueOf();
}

export function settlement(expenses, { start, end }, settledMonths = new Set()) {
  let firstOwes = 0;
  let secondOwes = 0;
  for (const expense of expenses) {
    if (expense.date < start || expense.date >= end || settledMonths.has(monthStart(expense.date))) continue;
    if (expense.payer === 'first') {
      secondOwes = sum(secondOwes, expense.amount - expense.firstShare);
    } else {
      firstOwes = sum(firstOwes, expense.firstShare);
    }
  }
  const net = sum(firstOwes, -secondOwes);
  if (net === 0) return null;
  return {
    from: net > 0 ? 'first' : 'second',
    to: net > 0 ? 'second' : 'first',
    amount: Math.abs(net),
  };
}

export function monthlyTotals(expenses, month) {
  const start = monthStart(month);
  const followingMonth = new Date(start);
  const end = followingMonth.setUTCMonth(followingMonth.getUTCMonth() + 1);
  const totals = {};
  for (const expense of expenses) {
    if (expense.date >= start && expense.date < end) {
      totals[expense.category] = sum(totals[expense.category] ?? 0, expense.amount);
    }
  }
  return totals;
}

function sum(left, right) {
  const total = left + right;
  if (total < -maximumYen || total > maximumYen) throw new RangeError('total too large');
  return total;
}

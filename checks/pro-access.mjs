function supersedes(next, previous) {
  if (next.purchasedAt !== previous.purchasedAt) return next.purchasedAt > previous.purchasedAt;
  if (next.revoked !== previous.revoked) return next.revoked;
  return (next.expiresAt ?? Infinity) > (previous.expiresAt ?? Infinity);
}

export function bookAccess(edits, bookID, partnerID, now) {
  const grants = new Map();
  for (const edit of edits) {
    if (edit.bookID !== bookID || (edit.member !== 'owner' && edit.member !== partnerID)) continue;
    const key = JSON.stringify([edit.member, edit.originalID]);
    const previous = grants.get(key);
    if (!previous || supersedes(edit, previous)) grants.set(key, edit);
  }
  let latest = now;
  for (const { purchasedAt, expiresAt, revoked } of grants.values()) {
    if (revoked || purchasedAt > now) continue;
    if (expiresAt === null) return { plan: 'pro', expiresAt: null };
    latest = Math.max(latest, expiresAt);
  }
  return latest > now ? { plan: 'pro', expiresAt: latest } : { plan: 'free', expiresAt: null };
}

// PK (oda karşılaşması) saf mantığı.
export const PK_MIN_SECONDS = 60;
export const PK_MAX_SECONDS = 1800;
export const PK_INVITE_TTL_SECONDS = 60;

export function validDuration(value) {
  const n = Number(value);
  return Number.isInteger(n) && n >= PK_MIN_SECONDS && n <= PK_MAX_SECONDS;
}

export function decideWinner(scoreA, scoreB) {
  const a = BigInt(scoreA); const b = BigInt(scoreB);
  if (a > b) return 'a';
  if (b > a) return 'b';
  return 'draw';
}

export function remainingSeconds(endsAt, now = new Date()) {
  if (!endsAt) return 0;
  return Math.max(0, Math.ceil((new Date(endsAt).getTime() - now.getTime()) / 1000));
}

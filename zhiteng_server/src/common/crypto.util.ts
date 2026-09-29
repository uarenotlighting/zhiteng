import { createHash, randomBytes, timingSafeEqual } from 'crypto';

export function sha256(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

export function safeEqual(a: string, b: string): boolean {
  const aa = Buffer.from(a);
  const bb = Buffer.from(b);
  if (aa.length !== bb.length) return false;
  return timingSafeEqual(aa, bb);
}

/** Local-dev reversible encoding — replace with KMS envelope encryption before production. */
export function encodeSensitive(plain: string | null | undefined): string | null {
  if (plain == null || plain === '') return null;
  return Buffer.from(plain, 'utf8').toString('base64');
}

export function decodeSensitive(encoded: string | null | undefined): string | null {
  if (encoded == null || encoded === '') return null;
  return Buffer.from(encoded, 'base64').toString('utf8');
}

export function parseDurationToMs(input: string): number {
  const match = /^(\d+)(ms|s|m|h|d)$/.exec(input.trim());
  if (!match) {
    throw new Error(`Invalid duration: ${input}`);
  }
  const value = Number(match[1]);
  const unit = match[2];
  switch (unit) {
    case 'ms':
      return value;
    case 's':
      return value * 1000;
    case 'm':
      return value * 60_000;
    case 'h':
      return value * 3_600_000;
    case 'd':
      return value * 86_400_000;
    default:
      throw new Error(`Invalid duration unit: ${unit}`);
  }
}

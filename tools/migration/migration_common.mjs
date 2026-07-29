import { createHash } from 'node:crypto';

export const EXPORT_VERSION = 1;

export class MigrationError extends Error {
  constructor(code, details = {}) {
    super(code);
    this.name = 'MigrationError';
    this.code = code;
    this.details = details;
  }
}

export function fail(code, details = {}) {
  throw new MigrationError(code, details);
}

export function cleanString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

export function normalizedName(value) {
  return cleanString(value).toLocaleLowerCase('en-US');
}

export function finiteNumber(value, fallback = 0) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function roundCurrency(value) {
  return Math.round((finiteNumber(value) + Number.EPSILON) * 100) / 100;
}

export function timestampToIso(value, fallback) {
  if (value == null) return fallback;

  if (typeof value?.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (
    typeof value?._seconds === 'number' ||
    typeof value?.seconds === 'number'
  ) {
    const seconds = value._seconds ?? value.seconds;
    const nanoseconds = value._nanoseconds ?? value.nanoseconds ?? 0;
    return new Date(seconds * 1000 + nanoseconds / 1_000_000).toISOString();
  }
  if (value instanceof Date) return value.toISOString();

  if (typeof value === 'string') {
    const trimmed = value.trim();
    const firebaseLocalDateTime =
      /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(trimmed);
    const normalized = firebaseLocalDateTime
      ? `${trimmed.replace(' ', 'T')}+08:00`
      : trimmed;
    const parsed = new Date(normalized);
    if (!Number.isNaN(parsed.valueOf())) return parsed.toISOString();
  }

  return fallback;
}

export function stableFriendId(normalizedFriendName) {
  const digest = createHash('sha256')
    .update(normalizedFriendName, 'utf8')
    .digest('hex')
    .slice(0, 32);
  return `friend-${digest}`;
}

export function checksum(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function sanitizeError(error, step = 'migration') {
  return {
    error: 'MigrationError',
    step,
    code: cleanString(error?.code) || cleanString(error?.name) || 'unknown',
    status: Number.isInteger(error?.status) ? error.status : undefined,
  };
}

export function chunked(values, size = 500) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}


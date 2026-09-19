const crypto = require('node:crypto');

const XP_RULES_VERSION = 'ccs-xp-v1.0';
const XP_TIME_ZONE = 'Europe/Riga';
const WEEKLY_XP_LIMIT = 3000;
const MAX_LEVEL = 100;

function xpRequiredForLevel(level) {
  const safeLevel = Math.min(MAX_LEVEL, Math.max(1, Math.floor(level)));
  return 25 * Math.pow(safeLevel - 1, 2);
}

function calculateLevel(totalXp) {
  if (!Number.isFinite(totalXp) || totalXp <= 0) {
    return 1;
  }

  const level = Math.floor(Math.sqrt(totalXp / 25)) + 1;
  return Math.min(MAX_LEVEL, Math.max(1, level));
}

function normalizeAwardInput(input) {
  const userId = cleanRequiredString(input.userId, 'userId');
  const action = cleanRequiredString(input.action, 'action');
  const objectType = cleanRequiredString(input.objectType, 'objectType');
  const objectId = cleanRequiredString(input.objectId, 'objectId');
  const stage = cleanRequiredString(input.stage, 'stage');
  const amount = Math.floor(input.amount);

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error(`XP amount must be a positive integer for ${action}`);
  }

  return {
    ...input,
    userId,
    action,
    objectType,
    objectId,
    stage,
    amount,
    status: input.status || 'confirmed',
  };
}

function buildXpUniqueKey(input) {
  const normalized = normalizeAwardInput(input);
  return [
    normalized.userId,
    normalized.action,
    normalized.objectType,
    normalized.objectId,
    normalized.stage,
  ].join('|');
}

function buildXpTransactionId(input) {
  return crypto
    .createHash('sha256')
    .update(buildXpUniqueKey(input))
    .digest('hex');
}

function weekKeyFor(date = new Date(), timeZone = XP_TIME_ZONE) {
  const parts = zonedDateParts(date, timeZone);
  const weekdayOffset = weekdayOffsetFromMonday(parts.weekday);
  const monday = new Date(
    Date.UTC(parts.year, parts.month - 1, parts.day - weekdayOffset),
  );

  return formatDateKey(
    monday.getUTCFullYear(),
    monday.getUTCMonth() + 1,
    monday.getUTCDate(),
  );
}

function defaultXpConfig() {
  return {
    levelsEnabled: false,
    awardsEnabled: false,
    enabledUserIds: [],
    weeklyLimit: WEEKLY_XP_LIMIT,
    timeZone: XP_TIME_ZONE,
    rulesVersion: XP_RULES_VERSION,
  };
}

function cleanRequiredString(value, fieldName) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Missing XP field: ${fieldName}`);
  }

  return value.trim();
}

function zonedDateParts(date, timeZone) {
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone,
    weekday: 'short',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });

  const parts = Object.fromEntries(
    formatter.formatToParts(date).map((part) => [part.type, part.value]),
  );

  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    weekday: String(parts.weekday),
  };
}

function weekdayOffsetFromMonday(weekday) {
  const offsets = {
    Mon: 0,
    Tue: 1,
    Wed: 2,
    Thu: 3,
    Fri: 4,
    Sat: 5,
    Sun: 6,
  };

  const offset = offsets[weekday];
  if (offset === undefined) {
    throw new Error(`Unsupported weekday value: ${weekday}`);
  }

  return offset;
}

function formatDateKey(year, month, day) {
  return [
    String(year).padStart(4, '0'),
    String(month).padStart(2, '0'),
    String(day).padStart(2, '0'),
  ].join('-');
}

module.exports = {
  XP_RULES_VERSION,
  XP_TIME_ZONE,
  WEEKLY_XP_LIMIT,
  MAX_LEVEL,
  xpRequiredForLevel,
  calculateLevel,
  normalizeAwardInput,
  buildXpUniqueKey,
  buildXpTransactionId,
  weekKeyFor,
  defaultXpConfig,
};

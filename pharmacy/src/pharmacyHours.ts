export type PharmacyOpenStatus = 'open' | 'closed' | 'unknown';

const days = [
  ['dimanche', 'dim', 'sunday', 'sun'], ['lundi', 'lun', 'monday', 'mon'],
  ['mardi', 'mar', 'tuesday', 'tue'], ['mercredi', 'mer', 'wednesday', 'wed'],
  ['jeudi', 'jeu', 'thursday', 'thu'], ['vendredi', 'ven', 'friday', 'fri'],
  ['samedi', 'sam', 'saturday', 'sat'],
];
const dayIndex = new Map(days.flatMap((names, i) => names.map(name => [name, i] as const)));
const everyDay = days.map((_, i) => i);
const allDay = /^(?:24\s*\/\s*(?:7|24)|24\s*(?:heures?|h)(?:\s*(?:\/|sur)\s*24\s*h?)?)$/;
const closed = /^(?:fermee?|closed)$/;
const nextDayClause = new RegExp(
  String.raw`(\d(?:\s*(?:h|am|pm))?|fermee?|closed)\s*,\s*(?=(?:du\s+)?(?:${days.flat().join('|')})\b)`, 'g',
);

type Interval = { start: number; end: number };
type Rule = { days: number[]; intervals: Interval[] };

function parseDays(text: string): number[] | null {
  if (!text || text === 'daily') return everyDay;
  const result = new Set<number>();
  for (const group of text.split(/\s*(?:,|&|\bet\b|\band\b)\s*/)) {
    const range = /^(?:du |le |les )?([a-z]+)\s*(?:(?:-|au|a|to)\s*([a-z]+))?$/.exec(group);
    if (!range) return null;
    const start = dayIndex.get(range[1]);
    const end = dayIndex.get(range[2] ?? range[1]);
    if (start === undefined || end === undefined) return null;
    for (let day = start; ; day = (day + 1) % 7) {
      result.add(day);
      if (day === end) break;
    }
  }
  return [...result];
}

function minutes(text: string): number | null {
  const time = /^(\d{1,2})(?:\s*:\s*(\d{2})|\s*h(?:\s*(\d{2}))?)?\s*(am|pm)?$/.exec(text.trim());
  if (!time) return null;
  let hour = Number(time[1]);
  const minute = Number(time[2] ?? time[3] ?? 0);
  if (minute >= 60 || hour > 24 || (hour === 24 && minute !== 0)) return null;
  if (time[4]) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (time[4] === 'pm' ? 12 : 0);
  }
  return hour * 60 + minute;
}

function parseRule(text: string): Rule | null {
  const body = text.search(/\d|\b(?:fermee?|closed)\b/);
  if (body < 0) return null;
  const prefix = text.slice(0, body).trim().replace(/\bde$/, '').replace(/[\s,:·]+$/, '');
  const weekdays = parseDays(prefix);
  if (!weekdays) return null;
  const hours = text.slice(body).trim().replace(/[\s,]*(?:et |and )?daily$/, '').trim();
  if (closed.test(hours)) return { days: weekdays, intervals: [] };
  if (allDay.test(hours)) return { days: weekdays, intervals: [{ start: 0, end: 1440 }] };
  const intervals: Interval[] = [];
  for (const part of hours.split(/\s*(?:,|\/|&|\bet\b|\band\b)\s*/)) {
    const bounds = part.trim().split(/\s*(?:-|\ba\b|\bto\b)\s*/);
    if (bounds.length !== 2) return null;
    const start = minutes(bounds[0]);
    const end = minutes(bounds[1]);
    if (start === null || end === null || start >= 1440 || start === end) return null;
    // An omitted AM/PM, or a bare "8–5", does not establish an overnight shift.
    if (/[ap]m$/.test(bounds[0]) !== /[ap]m$/.test(bounds[1])) return null;
    if (end < start && start <= 12 * 60 && bounds.every(time => /^\d{1,2}$/.test(time))) return null;
    intervals.push({ start, end });
  }
  return { days: weekdays, intervals };
}

let clock: Intl.DateTimeFormat | undefined;
function localTime(now: Date) {
  // The catalogue serves Haitian pharmacies, including when the buyer's device is abroad.
  clock ??= new Intl.DateTimeFormat('en-GB', {
    timeZone: 'America/Port-au-Prince', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  });
  const parts = clock.formatToParts(now);
  const value = (type: Intl.DateTimeFormatPartTypes) => parts.find(part => part.type === type)?.value;
  return { day: dayIndex.get(value('weekday')?.toLowerCase() ?? ''), minute: Number(value('hour')) * 60 + Number(value('minute')) };
}

export function pharmacyOpenStatus(openingHours: string | null | undefined, now: Date): PharmacyOpenStatus {
  if (!openingHours?.trim() || !Number.isFinite(now.getTime())) return 'unknown';
  const text = openingHours.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[‐‑–—−]/g, '-').replace(/([a-z])\./g, '$1').replace(/[^\S\n]+/g, ' ')
    .replace(/\b(?:tous les jours|every day|daily|7\s*(?:j(?:ours?)?)?\s*(?:\/|sur)\s*7)\b/g, 'daily')
    .replace(nextDayClause, '$1;');
  const rules: Rule[] = [];
  for (const clause of text.split(/[;\n|]+/).filter(part => part.trim())) {
    const rule = parseRule(clause.trim().replace(/^(?:ouverte?|open)\s+/, ''));
    // Free text can contain exceptions, holidays, or on-call conditions.
    if (!rule) return 'unknown';
    rules.push(rule);
  }
  try {
    const { day, minute } = localTime(now);
    if (day === undefined || !Number.isFinite(minute)) return 'unknown';
    const intervalsFor = (weekday: number) => {
      const matching = rules.filter(rule => rule.days.includes(weekday));
      const specific = matching.filter(rule => rule.days.length < 7);
      return (specific.length ? specific : matching).flatMap(rule => rule.intervals);
    };
    const openToday = intervalsFor(day).some(({ start, end }) => minute >= start && (end < start || minute < end));
    const fromYesterday = intervalsFor((day + 6) % 7).some(({ start, end }) => end < start && minute < end);
    if (openToday || fromYesterday) return 'open';
    // A stand-alone closing notice only describes the days it names.
    if (rules.some(rule => rule.intervals.length || rule.days.includes(day))) return 'closed';
  } catch {
    // Without the pharmacy's local clock the status cannot be confirmed.
  }
  return 'unknown';
}

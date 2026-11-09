import assert from 'node:assert/strict';
import { test } from 'node:test';
import { pharmacyOpenStatus } from './pharmacyHours';

const at = (schedule: string | null, timestamp: string) => pharmacyOpenStatus(schedule, new Date(timestamp));

test('the registration default and sample catalogue use Haitian local time, including summer time', () => {
  for (const schedule of ['Lun–Sam, 8 h–18 h', 'Lun–sam 8 h à 18 h']) {
    assert.equal(at(schedule, '2026-01-05T12:59:00Z'), 'closed');
    assert.equal(at(schedule, '2026-01-05T13:00:00Z'), 'open');
    assert.equal(at(schedule, '2026-07-06T12:00:00Z'), 'open');
    assert.equal(at(schedule, '2026-07-06T22:00:00Z'), 'closed');
    assert.equal(at(schedule, '2026-01-11T16:00:00Z'), 'closed');
  }
});

test('a Saturday night shift covers Sunday at 1 am and ends at the advertised minute', () => {
  const schedule = 'samedi 20h30 - 2h15; dimanche fermé';
  assert.equal(at(schedule, '2026-01-11T01:29:00Z'), 'closed');
  assert.equal(at(schedule, '2026-01-11T06:00:00Z'), 'open');
  assert.equal(at(schedule, '2026-01-11T07:15:00Z'), 'closed');
  assert.equal(at(schedule, '2026-01-10T06:00:00Z'), 'closed');
  assert.equal(at('Ven au lun, 22 h - 6 h', '2026-01-13T06:00:00Z'), 'open');
});

test('24-hour schedules and explicit day exceptions keep their exact scope', () => {
  const oneAM = '2026-01-11T06:00:00Z';
  for (const schedule of ['24/7', 'Ouvert 24 h sur 24', '24h/24, 7j/7', 'Ouvert 24h/24 et 7 jours sur 7',
    '24/24, 7j/7', '24 heures sur 24 et 7 jours sur 7', 'Tous les jours 00:00–24:00']) {
    assert.equal(at(schedule, oneAM), 'open');
  }
  assert.equal(at('Lun-Sam 24h/24', oneAM), 'closed');
  assert.equal(at('Tous les jours 24h/24, dimanche fermé', oneAM), 'closed');
  assert.equal(at('Dimanche fermé', '2026-01-05T15:00:00Z'), 'unknown');
});

test('weekday lists, lunch breaks, and distinct weekend hours are applied separately', () => {
  const schedule = 'lun, mar et mer : 8h-12h, 13h30-18h; Sam 9:00-14:00';
  assert.equal(at(schedule, '2026-01-05T17:15:00Z'), 'closed');
  assert.equal(at(schedule, '2026-01-06T18:30:00Z'), 'open');
  assert.equal(at(schedule, '2026-01-08T15:00:00Z'), 'closed');
  assert.equal(at(schedule, '2026-01-10T15:00:00Z'), 'open');
  assert.equal(at('Mon-Fri 9AM–5PM, Sat 10AM–12PM', '2026-01-10T17:00:00Z'), 'closed');
});

test('vague, incomplete and conditional hours do not confirm availability', () => {
  for (const schedule of [null, '', 'Sur appel', 'Ouvert', '7j/7', 'Dim 6h', '8h–25h', '8:99-18:30', '8–5 PM', '8–5',
    'Lundi : 8h–8h', 'Ouvert 24h/24 sauf les jours fériés', '07h–19h, sur rendez-vous uniquement']) {
    assert.equal(at(schedule, '2026-01-05T15:00:00Z'), 'unknown', schedule ?? 'null');
  }
  assert.equal(pharmacyOpenStatus('24/7', new Date(NaN)), 'unknown');
});

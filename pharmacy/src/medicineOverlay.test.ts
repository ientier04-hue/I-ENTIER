import assert from 'node:assert/strict';
import { test } from 'node:test';
import { medicineOverlay } from './medicineOverlay';

const origin = { x: 5, y: 10, width: 90, height: 78 };

test('a pending details measurement cannot cover a picker or reopen a dismissed card', () => {
  const request = Symbol();
  const measuring = medicineOverlay({ kind: 'closed' }, { type: 'measure', request });
  const measured = { type: 'measured', request, origin } as const;
  for (const picker of ['format', 'pharmacy'] as const) {
    const opened = medicineOverlay(measuring, { type: 'openPicker', picker });
    assert.deepEqual(medicineOverlay(opened, measured), { kind: picker });
    const dismissed = medicineOverlay(opened, { type: 'close' });
    assert.deepEqual(medicineOverlay(dismissed, measured), { kind: 'closed' });
  }
});

test('only the most recent details tap supplies the animation origin', () => {
  const first = Symbol();
  const last = Symbol();
  const measuring = medicineOverlay({ kind: 'closed' }, { type: 'measure', request: first });
  const latest = medicineOverlay(measuring, { type: 'measure', request: last });
  const stale = { type: 'measured', request: first, origin: { ...origin, y: 0 } } as const;
  assert.equal(medicineOverlay(latest, stale), latest);
  const opened = medicineOverlay(latest, { type: 'measured', request: last, origin });
  assert.deepEqual(medicineOverlay(opened, stale), { kind: 'details', origin });
  assert.deepEqual(medicineOverlay(opened, { type: 'close' }), { kind: 'closed' });
});

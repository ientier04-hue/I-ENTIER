import assert from 'node:assert/strict';
import test from 'node:test';
import { scanImage } from './prescriptionScan';
import { initialScan, transitionScan } from './scanWorkflow';

const image = { ...scanImage(btoa('\xff\xd8\xffsample')), id: 'first' };
const reading = transitionScan(initialScan, { type: 'picked', attempt: 0, image });
const review = transitionScan(reading, {
  type: 'ocr', attempt: reading.attempt,
  event: { type: 'result', text: '2,5 ml', confidence: 90 },
});

test('Android recovery and superseded picker callbacks cannot replace the active selection', () => {
  const selecting = transitionScan(initialScan, { type: 'pick', allowReopen: false });
  assert.equal(transitionScan(selecting, { type: 'pick', allowReopen: false }), selecting);
  assert.equal(transitionScan(selecting, { type: 'picked', attempt: 0, image }), selecting);
  const reopened = transitionScan(selecting, { type: 'pick', allowReopen: true });
  assert.equal(transitionScan(reopened, { type: 'picked', attempt: selecting.attempt, image }), reopened);
  const accepted = transitionScan(reopened, { type: 'picked', attempt: reopened.attempt, image });
  assert.equal(accepted.phase, 'reading');
  assert.equal(accepted.draft?.image, image);
});

test('only the active OCR attempt can finish after cancellation, timeout, or rereading', () => {
  const cancelled = transitionScan(reading, { type: 'stopReading', attempt: reading.attempt });
  const late = { type: 'ocr', attempt: reading.attempt, event: { type: 'result', text: 'late', confidence: 10 } } as const;
  assert.equal(transitionScan(cancelled, late), cancelled);
  const retry = transitionScan(cancelled, { type: 'reread' });
  assert.equal(transitionScan(retry, late), retry);
  assert.equal(transitionScan(retry, { type: 'stopReading', attempt: reading.attempt }), retry);
  const timeout = transitionScan(retry, { type: 'stopReading', attempt: retry.attempt, error: 'timeout' });
  assert.equal(timeout.phase, 'ready');
  assert.equal(transitionScan(timeout, { ...late, attempt: retry.attempt }), timeout);
});

test('manual corrections survive cancellation, an empty reread and a failed save', () => {
  const corrected = transitionScan(review, { type: 'edit', text: '1/2 cp' });
  const picking = transitionScan(corrected, { type: 'pick', allowReopen: false });
  const cancelled = transitionScan(picking, { type: 'pickerClosed', attempt: picking.attempt });
  assert.equal(cancelled.draft, corrected.draft);
  const reread = transitionScan(cancelled, { type: 'reread' });
  const empty = transitionScan(reread, {
    type: 'ocr', attempt: reread.attempt, event: { type: 'result', text: '  ', confidence: 0 },
  });
  assert.equal(empty.draft, corrected.draft);
  assert.match(empty.error, /Aucun texte/);
  const saving = transitionScan(empty, { type: 'save' });
  assert.equal(saving.phase, 'saving');
  assert.equal(transitionScan(saving, { type: 'save' }), saving);
  assert.equal(transitionScan(saving, { type: 'pick', allowReopen: true }), saving);
  assert.equal(transitionScan(saving, { type: 'edit', text: '' }), saving);
  const failed = transitionScan(saving, { type: 'saveFailed', error: 'retry' });
  assert.equal(failed.phase, 'ready');
  assert.equal(transitionScan(failed, { type: 'save' }).draft, corrected.draft);
});

test('a web picker that never signals cancellation cannot block saving or replace a saved draft', () => {
  const picking = transitionScan(review, { type: 'pick', allowReopen: true });
  const saving = transitionScan(picking, { type: 'save' });
  assert.equal(saving.phase, 'saving');
  assert.equal(transitionScan(saving, { type: 'picked', attempt: picking.attempt, image }), saving);
});

test('empty, reading and blank transcription states cannot submit', () => {
  const blank = transitionScan(review, { type: 'edit', text: '\u0001' });
  for (const state of [initialScan, reading, blank]) {
    assert.equal(transitionScan(state, { type: 'save' }), state);
  }
});

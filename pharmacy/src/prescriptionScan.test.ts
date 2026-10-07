import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanTranscription, scanImage, MAX_IMAGE_BYTES } from './prescriptionScan';
import { ocrDocument, parseOcrEvent } from './ocr/document';
test('preserves medication units, decimal separators and line breaks', () => {
  assert.equal(cleanTranscription('  Amoxicilline 500 mg\r\n1/2 cp — 2,5 ml\u0000  '),'Amoxicilline 500 mg\n1/2 cp — 2,5 ml');
});
test('rejects unsupported, malformed and oversized images before OCR/upload', () => {
  assert.throws(() => scanImage(btoa('<svg>bad</svg>')));
  assert.throws(() => scanImage('invalid!'));
  assert.throws(() => scanImage('A'.repeat(Math.ceil(MAX_IMAGE_BYTES/3)*4+4)));
});
test('uses image bytes rather than a misleading filename or MIME', () => {
  const value = scanImage(btoa('\xff\xd8\xff\xe0test'));
  assert.equal(value.mime,'image/jpeg');
  assert.equal(value.extension,'jpg');
});
test('validates OCR messages and clamps progress', () => {
  assert.equal(parseOcrEvent('{'), null);
  assert.equal(parseOcrEvent('{"type":"result","text":4,"confidence":50}'), null);
  assert.deepEqual(parseOcrEvent('{"type":"progress","progress":5}'), {type:'progress',progress:1});
  assert.equal(parseOcrEvent(JSON.stringify({type:'result',text:'A'.repeat(21000),confidence:70}))?.type,'result');
});
test('does not allow document data to inject scripts', () => {
  assert.throws(() => ocrDocument('</script><script>alert(1)</script>'));
  assert.match(ocrDocument('data:image/jpeg;base64,/9j/4A=='), /rotateAuto:true/);
});

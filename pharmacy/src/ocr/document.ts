// The same isolated browser OCR pipeline runs in an iframe (web) or WebView (mobile).
// Only engine/language assets are fetched; the document never leaves this context.
export function ocrDocument(image: string) {
  if (!/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(image)) throw new Error('Image non prise en charge.');
  return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>
<script>
const send = (data) => { const message = JSON.stringify(data); if(window.ReactNativeWebView) window.ReactNativeWebView.postMessage(message); else parent.postMessage(message, '*'); };
window.onerror = () => send({type:'error'});
</script>
<script src="https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js" onerror="send({type:'error'})"></script>
<script>
(async () => {
let worker;
try {
 const image = new Image(); image.src = ${JSON.stringify(image)}; await image.decode();
 const scale = Math.min(1, 2400 / Math.max(image.width, image.height));
 const canvas = document.createElement('canvas'); canvas.width = Math.round(image.width * scale); canvas.height = Math.round(image.height * scale);
 const ctx = canvas.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0,0,canvas.width,canvas.height); ctx.drawImage(image,0,0,canvas.width,canvas.height);
 worker = await Tesseract.createWorker('fra+eng', 1, { logger: m => { if(m.status === 'recognizing text') send({type:'progress',progress:m.progress}); } });
 const {data} = await worker.recognize(canvas, {rotateAuto:true});
 send({type:'result',text:data.text,confidence:data.confidence});
} catch (_) { send({type:'error'}); } finally { if(worker) await worker.terminate(); }
})();
</script></body></html>`;
}
export type OcrEvent = { type: 'progress'; progress: number } | { type: 'result'; text: string; confidence: number } | { type: 'error' };
export type OcrProps = { image: string; onEvent: (event: OcrEvent) => void };
export function parseOcrEvent(raw: string): OcrEvent | null {
  try {
    const event = JSON.parse(raw);
    if(event.type === 'error') return {type:'error'};
    if(event.type === 'result' && typeof event.text === 'string' && Number.isFinite(event.confidence)) return {type:'result', text:event.text.slice(0,20000),confidence:event.confidence};
    if(event.type === 'progress' && Number.isFinite(event.progress)) return {type:'progress',progress:Math.max(0, Math.min(1,event.progress))};
  } catch { /* Ignore malformed bridge messages. */ }
  return null;
}

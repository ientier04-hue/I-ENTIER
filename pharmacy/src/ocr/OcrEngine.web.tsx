import { useEffect, useMemo, useRef } from 'react';
import { ocrDocument, parseOcrEvent, type OcrProps } from './document';
export default function OcrEngine({image,onEvent}: OcrProps) {
  const frame = useRef<HTMLIFrameElement>(null);
  const html = useMemo(() => ocrDocument(image), [image]);
  useEffect(() => {
    const listener = (event: MessageEvent) => {
      if(event.source !== frame.current?.contentWindow || typeof event.data !== 'string') return;
      const parsed = parseOcrEvent(event.data); if(parsed) onEvent(parsed);
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, [onEvent]);
  return <iframe ref={frame} title="Reconnaissance de l’ordonnance" srcDoc={html} sandbox="allow-scripts allow-same-origin" style={{position:'absolute',width:1,height:1,opacity:0,border:0,pointerEvents:'none'}} />;
}

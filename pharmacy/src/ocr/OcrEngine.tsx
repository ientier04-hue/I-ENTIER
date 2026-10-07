import { useMemo } from 'react';
import { WebView } from 'react-native-webview';
import { ocrDocument, parseOcrEvent, type OcrProps } from './document';
export default function OcrEngine({image,onEvent}: OcrProps) {
  const source = useMemo(() => ({html:ocrDocument(image)}), [image]);
  return <WebView source={source} originWhitelist={['*']} javaScriptEnabled style={{width:1,height:1,opacity:0}}
    onShouldStartLoadWithRequest={request => request.url === 'about:blank'}
    onError={() => onEvent({type:'error'})}
    onMessage={event => {const parsed = parseOcrEvent(event.nativeEvent.data); if(parsed) onEvent(parsed);}} />;
}

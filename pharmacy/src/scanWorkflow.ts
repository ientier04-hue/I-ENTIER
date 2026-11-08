import type { OcrEvent } from './ocr/document';
import { cleanTranscription, type scanImage } from './prescriptionScan';

export type ScanPhoto = ReturnType<typeof scanImage> & { id: string };
type Draft = { image: ScanPhoto; text: string };

export type ScanState = { attempt: number; error: string } & (
  | { phase: 'ready' | 'picking'; draft: Draft | null }
  | { phase: 'reading'; draft: Draft; progress: number }
  | { phase: 'saving'; draft: Draft }
);

export const initialScan: ScanState = { phase: 'ready', draft: null, attempt: 0, error: '' };

type ScanEvent =
  | { type: 'pick'; allowReopen: boolean }
  | { type: 'picked'; attempt: number; image: ScanPhoto }
  | { type: 'pickerClosed'; attempt: number; error?: string }
  | { type: 'reread' }
  | { type: 'ocr'; attempt: number; event: OcrEvent }
  | { type: 'stopReading'; attempt: number; error?: string }
  | { type: 'edit'; text: string }
  | { type: 'save' }
  | { type: 'saveFailed'; error: string };

export function transitionScan(state: ScanState, action: ScanEvent): ScanState {
  if ('attempt' in action && action.attempt !== state.attempt) return state;

  switch (action.type) {
    case 'pick':
      if (state.phase !== 'ready' && !(state.phase === 'picking' && action.allowReopen)) return state;
      return { ...state, phase: 'picking', attempt: state.attempt + 1, error: '' };
    case 'picked':
    case 'pickerClosed': {
      // Android may restore the last picker result before the first user action.
      if (state.phase !== 'picking' && !(state.phase === 'ready' && state.attempt === 0)) return state;
      if (action.type === 'pickerClosed') {
        return { ...state, phase: 'ready', error: action.error ?? '' };
      }
      return { phase: 'reading', attempt: state.attempt + 1, draft: { image: action.image, text: '' }, progress: 0, error: '' };
    }
    case 'reread':
      if ((state.phase !== 'ready' && state.phase !== 'picking') || !state.draft) return state;
      return { phase: 'reading', draft: state.draft, attempt: state.attempt + 1, progress: 0, error: '' };
    case 'ocr': {
      if (state.phase !== 'reading') return state;
      const event = action.event;
      if (event.type === 'progress') return { ...state, progress: event.progress };
      const text = event.type === 'result' ? cleanTranscription(event.text) : '';
      const error = event.type === 'error'
        ? 'Lecture impossible. Vérifiez la connexion et réessayez.'
        : text ? '' : 'Aucun texte détecté. Reprenez une photo plus nette.';
      return { phase: 'ready', attempt: state.attempt, draft: text ? { ...state.draft, text } : state.draft, error };
    }
    case 'stopReading':
      if (state.phase !== 'reading') return state;
      return { phase: 'ready', attempt: state.attempt, draft: state.draft, error: action.error ?? '' };
    case 'edit':
      if ((state.phase !== 'ready' && state.phase !== 'picking') || !state.draft) return state;
      return { ...state, draft: { ...state.draft, text: action.text } };
    case 'save':
      if ((state.phase !== 'ready' && state.phase !== 'picking') || !state.draft || !cleanTranscription(state.draft.text)) return state;
      return { phase: 'saving', attempt: state.attempt + 1, draft: state.draft, error: '' };
    case 'saveFailed':
      if (state.phase !== 'saving') return state;
      return { ...state, phase: 'ready', error: action.error };
  }
}

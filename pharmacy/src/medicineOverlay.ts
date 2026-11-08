export type HeroRect = { x: number; y: number; width: number; height: number };
type Picker = 'format' | 'pharmacy';

export type MedicineOverlay =
  | { kind: 'closed' | Picker }
  | { kind: 'measuring'; request: symbol }
  | { kind: 'details'; origin: HeroRect };

type OverlayEvent =
  | { type: 'openPicker'; picker: Picker }
  | { type: 'measure'; request: symbol }
  | { type: 'measured'; request: symbol; origin: HeroRect }
  | { type: 'close' };

export function medicineOverlay(state: MedicineOverlay, event: OverlayEvent): MedicineOverlay {
  switch (event.type) {
    case 'openPicker':
      return { kind: event.picker };
    case 'measure':
      return { kind: 'measuring', request: event.request };
    case 'measured':
      // Native layout may finish after another picker opened or a newer tap.
      return state.kind === 'measuring' && state.request === event.request
        ? { kind: 'details', origin: event.origin } : state;
    case 'close':
      return { kind: 'closed' };
  }
}

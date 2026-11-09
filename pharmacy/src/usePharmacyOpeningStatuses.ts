import { useLayoutEffect, useState } from 'react';
import { AppState, type AppStateStatus } from 'react-native';
import { useIsFocused } from 'expo-router';
import type { Pharmacy } from './pharmacies';
import { pharmacyOpenStatus } from './pharmacyHours';

type OpeningStatuses = ReadonlyMap<string, ReturnType<typeof pharmacyOpenStatus>>;
const emptyStatuses: OpeningStatuses = new Map();
const minuteMs = 60_000;

export function usePharmacyOpeningStatuses(pharmacies: readonly Pharmacy[]): OpeningStatuses {
  const focused = useIsFocused();
  const [statuses, setStatuses] = useState(emptyStatuses);

  useLayoutEffect(() => {
    if (!focused || !pharmacies.length) return;
    let timer: ReturnType<typeof setTimeout>;

    function update() {
      const now = new Date();
      timer = setTimeout(update, minuteMs - now.getTime() % minuteMs);
      const next = new Map(pharmacies.map(p => [p.pharmacy_id, pharmacyOpenStatus(p.opening_hours, now)]));
      setStatuses(previous => {
        if (previous.size !== next.size) return next;
        for (const [id, status] of next) {
          if (previous.get(id) !== status) return next;
        }
        return previous;
      });
    }

    function handleAppState(state: AppStateStatus) {
      clearTimeout(timer);
      if (state === 'active') update();
    }
    const subscription = AppState.addEventListener('change', handleAppState);
    handleAppState(AppState.currentState ?? 'active');
    return () => {
      clearTimeout(timer);
      subscription?.remove();
    };
  }, [pharmacies, focused]);

  return pharmacies.length ? statuses : emptyStatuses;
}

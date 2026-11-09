import { useCallback, useEffect, useState } from 'react';
import { db } from './api';
import { pharmacyHistoryWindowMs, type PharmacyPreferences } from './catalog';

type PharmacyPurchaseHistory = PharmacyPreferences['history'];

const emptyHistory: PharmacyPurchaseHistory = new Map();
const orderStatuses = ['pending', 'accepted', 'preparing', 'ready', 'completed'];
const pageSize = 200;

async function loadHistory(uid: string, signal: AbortSignal): Promise<PharmacyPurchaseHistory> {
  const now = Date.now();
  const until = new Date(now).toISOString();
  const since = new Date(now - pharmacyHistoryWindowMs).toISOString();
  const history = new Map<string, { count: number; lastOrderedAt: number }>();

  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await db.from('pharmacy_orders')
      .select('pharmacy_id,created_at')
      .eq('patient_id', uid).in('status', orderStatuses)
      .gte('created_at', since).lte('created_at', until)
      .order('created_at', { ascending: false }).order('order_id')
      .range(offset, offset + pageSize - 1).abortSignal(signal);
    if (error) throw error;
    for (const order of data) {
      const previous = history.get(order.pharmacy_id);
      history.set(order.pharmacy_id, {
        count: (previous?.count ?? 0) + 1,
        lastOrderedAt: previous?.lastOrderedAt ?? Date.parse(order.created_at),
      });
    }
    if (data.length < pageSize) return history;
  }
}

export function usePharmacyPurchaseHistory(uid: string | undefined, isCurrent: () => boolean) {
  const [snapshot, setSnapshot] = useState<{ uid: string; history: PharmacyPurchaseHistory } | null>(null);
  const [revision, setRevision] = useState(0);
  const refreshHistory = useCallback(() => setRevision(value => value + 1), []);

  useEffect(() => {
    if (!uid || !isCurrent()) return;
    const controller = new AbortController();
    void loadHistory(uid, controller.signal).then(history => {
      if (!controller.signal.aborted && isCurrent()) setSnapshot({ uid, history });
    }).catch(() => {
      // History is optional. Keep any previous result for this patient.
    });
    return () => controller.abort();
  }, [uid, isCurrent, revision]);

  return { history: snapshot && snapshot.uid === uid ? snapshot.history : emptyHistory, refreshHistory };
}

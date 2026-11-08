import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useIsFocused } from 'expo-router';
import { db } from './api';

export type Prescription = {
  prescription_id: string;
  file_name: string;
  storage_path: string;
  transcription?: string;
  doctor_name_snapshot: string;
};
export type Order = {
  order_id: string;
  order_number: string;
  status: string;
  total_amount: number;
};

type Collection = 'prescriptions' | 'orders';
type Status = 'idle' | 'loading' | 'error' | 'ready';
type FileRead = { owner: string; collection: Collection; revision: number };
type FileView = {
  request: FileRead;
  status: Status;
  error: string;
  prescriptions: Prescription[];
  orders: Order[];
};

function prependNewRows(additions: Prescription[], rows: Prescription[]) {
  const ids = new Set(rows.map(row => row.prescription_id));
  return [...additions.filter(row => !ids.has(row.prescription_id)), ...rows];
}

export function usePatientFile(uid: string | undefined, tab: string, purchaseView: string, isCurrent: () => boolean) {
  const collection: Collection | null = tab === 'Ordonnances' ? 'prescriptions'
    : tab === 'Panier' && purchaseView === 'orders' ? 'orders' : null;
  const [view, setView] = useState<FileView | null>(null);
  const [revision, setRevision] = useState(0);
  const activeRead = useRef<{ request: FileRead; additions: Prescription[] | null } | null>(null);

  const focused = useIsFocused();
  const profile = useRef<{ owner: string; request: Promise<void> } | null>(null);
  const ensureProfile = useCallback(async () => {
    if (!uid || !isCurrent()) throw new Error('Veuillez réessayer dans un instant.');
    if (profile.current?.owner !== uid) {
      const request = Promise.resolve(db.from('patient_profiles').upsert(
        { patient_id: uid }, { onConflict: 'patient_id', ignoreDuplicates: true },
      )).then(({ error }) => {
        if (error) throw error;
      }).catch(() => {
        if (profile.current?.request === request) profile.current = null;
        throw new Error('Impossible de préparer votre dossier.');
      });
      profile.current = { owner: uid, request };
    }
    await profile.current.request;
    if (!isCurrent()) throw new Error('Veuillez réessayer dans un instant.');
  }, [uid, isCurrent]);

  useEffect(() => {
    if (uid) void ensureProfile().catch(() => {
      // The next file read or submission retries preparation and reports its own failure.
    });
  }, [uid, ensureProfile]);

  const retry = useCallback(() => setRevision(value => value + 1), []);

  const request = useMemo(() => focused && uid && collection ? { owner: uid, collection, revision } : null,
    [focused, uid, collection, revision]);
  useEffect(() => {
    if (!request || !isCurrent()) return;
    const fileRead = request;
    let active = true;
    const additions: Prescription[] = [];
    activeRead.current = { request: fileRead, additions };
    async function load() {
      await ensureProfile();
      if (!active || !isCurrent()) return;
      if (fileRead.collection === 'prescriptions') {
        const result = await db.from('prescriptions')
          .select('prescription_id,file_name,storage_path,doctor_name_snapshot,transcription')
          .eq('patient_id', fileRead.owner).eq('status', 'available').order('created_at', { ascending: false });
        if (result.error) throw new Error('Impossible de charger votre dossier.');
        if (active && isCurrent()) {
          setView({ request: fileRead, status: 'ready', error: '', orders: [],
            prescriptions: prependNewRows(additions, result.data || []) });
        }
      } else {
        const result = await db.from('pharmacy_orders').select('order_id,order_number,status,total_amount')
          .eq('patient_id', fileRead.owner).order('created_at', { ascending: false });
        if (result.error) throw new Error('Impossible de charger votre dossier.');
        if (active && isCurrent()) {
          setView({ request: fileRead, status: 'ready', error: '', orders: result.data || [], prescriptions: [] });
        }
      }
    }
    void load().catch(error => {
      if (active && isCurrent()) {
        setView(previous => ({
          request: fileRead, status: 'error', error: error instanceof Error ? error.message : 'Impossible de charger votre dossier.',
          orders: previous?.request.owner === fileRead.owner ? previous.orders : [],
          prescriptions: previous?.request.owner === fileRead.owner ? previous.prescriptions : additions,
        }));
      }
    }).finally(() => {
      if (active && activeRead.current) activeRead.current.additions = null;
    });
    return () => {
      active = false;
      activeRead.current = null;
    };
  }, [request, ensureProfile, isCurrent]);

  const addPrescription = useCallback((row: Prescription) => {
    const read = activeRead.current;
    if (!read || read.request.collection !== 'prescriptions' || read.request.owner !== uid || !isCurrent()) return;
    const request = read.request;
    // A GET already in flight may have taken its snapshot before this upload committed.
    read.additions?.unshift(row);
    setView(previous => {
      const visible = previous?.request.owner === uid && previous.request.collection === 'prescriptions' ? previous : null;
      return {
        request, status: visible?.request === request ? visible.status : 'loading',
        error: visible?.request === request ? visible.error : '',
        orders: [], prescriptions: prependNewRows([row], visible?.prescriptions ?? []),
      };
    });
  }, [uid, isCurrent]);

  const visible = view?.request.owner === uid && view?.request.collection === collection ? view : null;
  const settled = visible && visible.request === request ? visible : null;
  return {
    prescriptions: visible?.prescriptions ?? [],
    orders: visible?.orders ?? [],
    status: settled?.status ?? (request ? 'loading' : 'idle'),
    error: settled?.error ?? '',
    ensureProfile, addPrescription, retry,
  };
}

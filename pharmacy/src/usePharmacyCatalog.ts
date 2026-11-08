import { useCallback, useEffect, useRef, useState } from 'react';
import { db } from './api';
import type { Product } from './cart';
import type { Pharmacy, PharmacyRating } from './pharmacies';

type Catalog = {
  phase: 'loading' | 'ready' | 'refreshing' | 'failed';
  products: Product[];
  pharmacies: Pharmacy[];
};

async function fetchCatalog() {
  const [products, pharmacies] = await Promise.all([
    db.from('v_public_medicine_products').select('*').order('name'),
    db.from('pharmacies')
      .select('pharmacy_id,display_name,address,phone,opening_hours,latitude,longitude,delivery_available,photo_url')
      .eq('public_enabled', true).eq('operational_status', 'active').order('display_name'),
  ]);
  if (products.error || pharmacies.error) throw new Error('Impossible de charger la pharmacie.');
  return { products: products.data || [], pharmacies: pharmacies.data || [] };
}

export function usePharmacyCatalog(uid: string | undefined, isCurrent: () => boolean, onError: (message: string) => void) {
  const [catalog, setCatalog] = useState<Catalog>({ phase: 'loading', products: [], pharmacies: [] });
  const [ratings, setRatings] = useState<Record<string, PharmacyRating>>({});
  const request = useRef(0);
  const ratingRequests = useRef(new Map<string, symbol>());

  const loadRatings = useCallback(async (ids: string[]) => {
    if (!ids.length || !isCurrent()) return;
    const token = Symbol();
    ids.forEach(id => ratingRequests.current.set(id, token));
    const { data, error } = await db.rpc('pharmacy_rating_summaries', { p_pharmacy_ids: ids });
    if (!isCurrent() || !ids.some(id => ratingRequests.current.get(id) === token)) return;
    if (error) throw new Error('Impossible de charger les notes des pharmacies.');
    const latest = (data as PharmacyRating[] || []).filter(r => ratingRequests.current.get(r.pharmacy_id) === token);
    setRatings(current => ({ ...current, ...Object.fromEntries(latest.map(r => [r.pharmacy_id, r])) }));
  }, [isCurrent]);

  const load = useCallback(() => {
    if (!uid || !isCurrent()) return;
    const id = ++request.current;
    void fetchCatalog().then(({ products, pharmacies }) => {
      if (id !== request.current || !isCurrent()) return;
      setCatalog({ phase: 'ready', products, pharmacies });
      void loadRatings(pharmacies.map(p => p.pharmacy_id)).catch(error => {
        if (id === request.current && isCurrent()) onError(error.message);
      });
    }).catch(() => {
      if (id !== request.current || !isCurrent()) return;
      setCatalog(current => ({ ...current, phase: 'failed' }));
    });
  }, [uid, isCurrent, loadRatings, onError]);

  useEffect(() => {
    void load();
  }, [load]);

  function refresh() {
    setCatalog(current => ({ ...current, phase: current.products.length || current.pharmacies.length ? 'refreshing' : 'loading' }));
    void load();
  }

  async function ratePharmacy(pharmacyId: string, rating: number) {
    if (!isCurrent() || !uid || !Number.isInteger(rating) || rating < 1 || rating > 5)
      throw new Error('Choisissez une note de 1 à 5.');
    const { error } = await db.from('pharmacy_ratings').upsert({ pharmacy_id: pharmacyId, user_id: uid, rating }, { onConflict: 'pharmacy_id,user_id' });
    if (error) throw new Error('Impossible d’enregistrer la note. Réessayez.');
    try { await loadRatings([pharmacyId]); }
    catch { if (isCurrent()) onError('Note enregistrée. Actualisez pour voir la moyenne.'); }
  }

  return { ...catalog, ratings, refresh, ratePharmacy };
}

import type { Product } from './cart';
import type { PharmacyOpenStatus } from './pharmacyHours';
import { compareDistance } from './pharmacies';

export function medicineKey(product: Product) {
  return `${product.pharmacy_id}:${product.medicine_id || product.product_id}`;
}
export function medicineOfferKey(product: Product) {
  return product.medicine_id || product.medicine_slug || product.product_id;
}
export function isOrderableOffer(product: Product) {
  return product.stock_quantity > 0 && product.selling_price > 0 && Number.isFinite(Number(product.selling_price));
}
export function groupMedicineOffers(products: Product[]) {
  const groups = new Map<string, Product[]>();
  for (const variants of groupMedicines(products)) {
    const key = medicineOfferKey(variants[0]);
    const group = groups.get(key);
    if (group) group.push(...variants);
    else groups.set(key, [...variants]);
  }
  return [...groups.values()];
}
export function availablePharmacyOffers(variants: Product[], current: Product) {
  const offers = new Map<string, Product>();
  for (const product of variants) {
    if (!isOrderableOffer(product) || offers.has(product.pharmacy_id)) continue;
    const matches = product.variant_id && current.variant_id
      ? product.variant_id === current.variant_id
      : (product.dosage_form || '') === (current.dosage_form || '')
        && (product.strength || '') === (current.strength || '') && product.pack_size === current.pack_size;
    if (matches) offers.set(product.pharmacy_id, product);
  }
  return [...offers.values()];
}
export type PharmacyPreferences = {
  distances: ReadonlyMap<string, number | null>;
  favorites: ReadonlySet<string>;
  history: ReadonlyMap<string, { count: number; lastOrderedAt: number }>;
  openingStatuses: ReadonlyMap<string, PharmacyOpenStatus>;
  reviewScores: ReadonlyMap<string, number | null>;
  preferNearby: boolean;
};
export type PharmacyOfferReason = 'cheapest' | 'nearest' | 'favorite' | 'recent' | 'open' | 'wellRated';

const openingRank = { open: 0, unknown: 1, closed: 2 } as const;

// In seller lists, keep the current choice first only within its opening status.
export function comparePharmacyOptions(a: string, b: string, preferences: PharmacyPreferences, selectedId?: string) {
  const { openingStatuses, reviewScores, distances, preferNearby } = preferences;
  return openingRank[openingStatuses.get(a) ?? 'unknown'] - openingRank[openingStatuses.get(b) ?? 'unknown']
    || Number(b === selectedId) - Number(a === selectedId)
    || (preferNearby ? compareDistance(distances.get(a) ?? null, distances.get(b) ?? null) : 0)
    || (reviewScores.get(b) ?? 0) - (reviewScores.get(a) ?? 0);
}

export const pharmacyHistoryWindowMs = 90 * 24 * 60 * 60 * 1000;
const comparablePriceMargin = 0.10;

export function preferredPharmacyOffer(offers: readonly Product[], preferences: PharmacyPreferences, manualPharmacyId?: string | null):
  { offer: Product; reason: PharmacyOfferReason | null } | undefined {
  const now = Date.now();
  const available = offers.filter(isOrderableOffer).map(offer => {
    const id = offer.pharmacy_id;
    const distance = preferences.distances.get(id);
    const orders = preferences.history.get(id);
    const hasHabit = orders && orders.count >= 2
      && orders.lastOrderedAt >= now - pharmacyHistoryWindowMs && orders.lastOrderedAt <= now;
    const history = hasHabit ? orders : null;
    return { offer, price: Number(offer.selling_price), favorite: preferences.favorites.has(id), history,
      opening: preferences.openingStatuses.get(id) ?? 'unknown', review: preferences.reviewScores.get(id) ?? null,
      distance: distance != null && Number.isFinite(distance) && distance >= 0 ? distance : null };
  });
  if (!available.length) return undefined;
  if (available.length === 1) {
    const [only] = available;
    return { offer: only.offer, reason: only.opening === 'open' ? 'open' : only.favorite ? 'favorite'
      : only.history ? 'recent' : only.review !== null ? 'wellRated' : null };
  }

  const currency = available[0].offer.currency;
  const comparablePrices = !!currency && available.every(({ offer }) => offer.currency === currency);
  const minimumPrice = Math.min(...available.map(row => row.price));
  const cheapest = comparablePrices && available.some(row => row.price > minimumPrice) ? minimumPrice : null;
  const minimumDistance = Math.min(...available.map(row => row.distance ?? Infinity));
  const nearest = available.every(row => row.distance !== null) && available.some(row => row.distance! > minimumDistance)
    ? minimumDistance : null;

  type Candidate = typeof available[number];
  let candidates = available;
  const reasons: PharmacyOfferReason[] = [];
  function narrow(reason: PharmacyOfferReason, matches: (row: Candidate) => boolean) {
    const next = candidates.filter(matches);
    if (next.length && next.length < candidates.length) {
      candidates = next;
      reasons.unshift(reason);
    }
  }

  // Hours take precedence even over an explicit nearby search or a large price gap.
  const bestOpening = Math.min(...candidates.map(row => openingRank[row.opening]));
  narrow('open', row => openingRank[row.opening] === bestOpening);
  const closestInTier = Math.min(...candidates.map(row => row.distance ?? Infinity));
  const tierDistancesKnown = candidates.every(row => row.distance !== null);
  if (preferences.preferNearby && Number.isFinite(closestInTier)) narrow('nearest', row => row.distance === closestInTier);
  const tierCurrency = candidates[0].offer.currency;
  const tierPricesComparable = !!tierCurrency && candidates.every(row => row.offer.currency === tierCurrency);
  if (tierPricesComparable) {
    const budget = Math.min(...candidates.map(row => row.price)) * (1 + comparablePriceMargin);
    narrow('cheapest', row => row.price <= budget);
  }
  narrow('favorite', row => row.favorite);
  const mostOrders = Math.max(...candidates.map(row => row.history?.count ?? 0));
  if (mostOrders > 0) {
    narrow('recent', row => row.history?.count === mostOrders);
    const latest = Math.max(...candidates.map(row => row.history!.lastOrderedAt));
    narrow('recent', row => row.history?.lastOrderedAt === latest);
  }
  const bestReview = Math.max(...candidates.map(row => row.review ?? 0));
  if (bestReview > 0) narrow('wellRated', row => row.review === bestReview);
  if (!preferences.preferNearby && tierDistancesKnown) narrow('nearest', row => row.distance === closestInTier);
  if (tierPricesComparable) {
    const bestPrice = Math.min(...candidates.map(row => row.price));
    narrow('cheapest', row => row.price === bestPrice);
  }
  const recommended = candidates.reduce((best, row) => row.offer.pharmacy_id < best.offer.pharmacy_id ? row : best);
  const selected = available.find(row => row.offer.pharmacy_id === manualPharmacyId) ?? recommended;
  const advantages: Record<PharmacyOfferReason, boolean> = {
    open: selected.opening === 'open',
    wellRated: selected.review !== null,
    cheapest: selected.price === cheapest,
    nearest: nearest !== null && selected.distance === nearest,
    favorite: selected.favorite,
    recent: selected.history !== null,
  };
  // A tie-break within a subset can only claim a superlative if it holds across all offers.
  const priority: PharmacyOfferReason[] = [...(selected === recommended ? reasons : []), 'cheapest', 'nearest', 'favorite', 'recent', 'wellRated', 'open'];
  return { offer: selected.offer, reason: priority.find(reason => advantages[reason]) ?? null };
}
export function groupMedicines(products: Product[]) {
  const groups = new Map<string, Product[]>();
  for (const product of products) {
    const key = medicineKey(product);
    groups.set(key, [...(groups.get(key) || []), product]);
  }
  const forms = ['Comprimé', 'Gélule', 'Sirop', 'Gouttes', 'Suspension'];
  return [...groups.values()].map(group => group.sort((a, b) =>
    Number(Number(b.stock_quantity) > 0) - Number(Number(a.stock_quantity) > 0)
    || Number(Number(b.selling_price) > 0) - Number(Number(a.selling_price) > 0)
    || forms.indexOf(a.dosage_form || '') - forms.indexOf(b.dosage_form || '')
    || (a.strength || '').localeCompare(b.strength || '', 'fr', {numeric:true})
    || a.pack_size.localeCompare(b.pack_size, 'fr', {numeric:true})
  ));
}
export function chooseVariant(variants: Product[], current: Product, field: 'dosage_form' | 'strength' | 'pack_size', value: string) {
  // A form change must never create a dosage/form combination absent from inventory.
  const available = variants.filter(p => p[field] === value && (field === 'dosage_form' || p.dosage_form === current.dosage_form) && (field !== 'pack_size' || p.strength === current.strength));
  const samePharmacy = available.filter(p => p.pharmacy_id === current.pharmacy_id);
  const candidates = samePharmacy.length ? samePharmacy : available;
  return candidates.find(p => p.strength === current.strength && p.pack_size === current.pack_size)
    || candidates.find(p => p.strength === current.strength)
    || candidates[0] || current;
}
export const formatPrice = (p: Product) => Number(p.selling_price) > 0
  ? `${Number(p.selling_price).toLocaleString('fr-FR')} ${p.currency}` : 'Prix à confirmer';

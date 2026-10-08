import type { Product } from './cart';

export function medicineKey(product: Product) {
  return `${product.pharmacy_id}:${product.medicine_id || product.product_id}`;
}
export function medicineOfferKey(product: Product) {
  return product.medicine_id || product.medicine_slug || product.product_id;
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
export function matchingPharmacyOffers(variants: Product[], current: Product) {
  const offers = new Map<string, Product>();
  for (const product of variants) {
    const matches = product.variant_id && current.variant_id
      ? product.variant_id === current.variant_id
      : (product.dosage_form || '') === (current.dosage_form || '')
        && (product.strength || '') === (current.strength || '') && product.pack_size === current.pack_size;
    if (matches && !offers.has(product.pharmacy_id)) offers.set(product.pharmacy_id, product);
  }
  return [...offers.values()];
}
export function preferredPharmacyOffer(offers: Product[], distances: Map<string, number | null>) {
  return [...offers].sort((a, b) => {
    const available = (p: Product) => Number(p.stock_quantity) > 0 && Number(p.selling_price) > 0;
    const stockOrder = Number(available(b)) - Number(available(a));
    if (stockOrder) return stockOrder;
    const aDistance = distances.get(a.pharmacy_id) ?? Infinity;
    const bDistance = distances.get(b.pharmacy_id) ?? Infinity;
    if (aDistance !== bDistance) return aDistance - bDistance;
    const aPrice = Number(a.selling_price) > 0 ? Number(a.selling_price) : Infinity;
    const bPrice = Number(b.selling_price) > 0 ? Number(b.selling_price) : Infinity;
    return a.currency === b.currency && aPrice !== bPrice ? aPrice - bPrice : 0;
  })[0];
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

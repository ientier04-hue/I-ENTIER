import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compareDistance, distanceKm, formatDistance } from './pharmacies';
import { groupMedicines } from './catalog';
import type { Product } from './cart';

test('proximity orders pharmacy offers without combining their inventory', () => {
  const origin = { latitude: 18.54, longitude: -72.33 };
  const near = distanceKm(origin, { latitude: 18.541, longitude: -72.33 });
  const far = distanceKm(origin, { latitude: 18.55, longitude: -72.33 });
  assert.ok(near !== null && near > 0.1 && near < 0.12);
  assert.ok(far !== null && far > 1.1 && far < 1.12);
  const base: Product = { product_id: 'far-tablet', medicine_id: 'same-medicine', pharmacy_id: 'far', pharmacy_name: 'Far', name: 'Médicament', active_ingredient: '', category: '', pack_size: '20', selling_price: 100, currency: 'HTG', stock_quantity: 2, requires_prescription: false };
  const offers = [base, { ...base, product_id: 'near-tablet', pharmacy_id: 'near' }, { ...base, product_id: 'unknown-tablet', pharmacy_id: 'unknown' }];
  const distances = new Map([['near', near], ['far', far]]);
  const groups = groupMedicines(offers).sort((a, b) => compareDistance(distances.get(a[0].pharmacy_id) ?? null, distances.get(b[0].pharmacy_id) ?? null));
  assert.deepEqual(groups.map(group => group[0].pharmacy_id), ['near', 'far', 'unknown']);
  assert.deepEqual(groups.map(group => group.length), [1, 1, 1]);
});

test('missing and invalid coordinates never appear as a nearby pharmacy', () => {
  const origin = { latitude: 0, longitude: 0 };
  assert.equal(distanceKm(null, origin), null);
  assert.equal(distanceKm(origin, { latitude: null, longitude: null }), null);
  assert.equal(distanceKm(origin, { latitude: 91, longitude: 0 }), null);
  assert.equal(distanceKm(origin, { latitude: NaN, longitude: 0 }), null);
  assert.equal(distanceKm(origin, origin), 0);
  assert.equal(compareDistance(null, null), 0);
  assert.equal(formatDistance(null), null);
  assert.equal(formatDistance(0.45), '450 m');
  assert.equal(formatDistance(1.24), '1,2 km');
});

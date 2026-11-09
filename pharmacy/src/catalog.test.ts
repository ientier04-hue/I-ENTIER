import { test } from 'node:test';
import assert from 'node:assert/strict';
import { availablePharmacyOffers, chooseVariant, comparePharmacyOptions, groupMedicines, groupMedicineOffers, isOrderableOffer, preferredPharmacyOffer, type PharmacyPreferences } from './catalog';
import { pharmacyOpenStatus } from './pharmacyHours';
import { pharmacyReviewScore } from './pharmacies';
import { changeQuantity, orderLines, type Product } from './cart';
const tablet: Product = {product_id:'tablet',medicine_id:'m',pharmacy_id:'p',pharmacy_name:'Pharmacie',name:'Analgine',active_ingredient:'Acétaminophène',category:'Douleur',strength:'500 mg',dosage_form:'Comprimé',pack_size:'20 comprimés',selling_price:830,currency:'HTG',stock_quantity:3,requires_prescription:false};
const syrup: Product = {...tablet,product_id:'syrup',dosage_form:'Sirop',strength:'160 mg/5 ml',pack_size:'120 ml',stock_quantity:1};
const drops: Product = {...tablet,product_id:'drops',dosage_form:'Gouttes',strength:'100 mg/ml',pack_size:'15 ml',stock_quantity:0};
test('changing form selects a real presentation, never a synthetic dosage', () => {
  assert.equal(chooseVariant([tablet,syrup,drops],tablet,'dosage_form','Sirop'),syrup);
  assert.equal(chooseVariant([tablet,syrup,drops],syrup,'strength','500 mg'),syrup);
  assert.equal(chooseVariant([tablet,syrup,drops],syrup,'pack_size','20 comprimés'),syrup);
});
test('groups variants within one pharmacy and preserves unrelated legacy products', () => {
  const otherPharmacy = {...tablet,pharmacy_id:'other'};
  const legacy = {...tablet,medicine_id:null,product_id:'legacy'};
  assert.deepEqual(groupMedicines([tablet,syrup,otherPharmacy,legacy]).map(g => g.length),[2,1,1]);
});
test('different forms remain independent cart and order lines; sample stock cannot be bought', () => {
  const variants = [tablet,syrup,drops];
  let cart = changeQuantity({},tablet,2,variants);
  cart = changeQuantity(cart,syrup,1,variants);
  assert.deepEqual(orderLines(cart,variants),[{product_id:'tablet',quantity:2},{product_id:'syrup',quantity:1}]);
  assert.throws(() => changeQuantity(cart,drops,1,variants),/Stock/);
  assert.throws(() => changeQuantity(cart,syrup,1,variants),/Stock/);
});
test('one medicine card contains pharmacy offers for only the selected presentation', () => {
  const otherTablet = {...tablet, product_id:'other-tablet', pharmacy_id:'other', selling_price:900, stock_quantity:1};
  const otherSyrup = {...syrup, product_id:'other-syrup', pharmacy_id:'other'};
  const groups = groupMedicineOffers([tablet, syrup, otherTablet, otherSyrup]);
  assert.equal(groups.length, 1);
  assert.deepEqual(availablePharmacyOffers(groups[0], tablet).map(p => p.product_id), ['tablet', 'other-tablet']);
  assert.equal(chooseVariant(groups[0], otherTablet, 'dosage_form', 'Sirop').product_id, 'other-syrup');
  const cart = changeQuantity({}, otherTablet, 1, groups[0]);
  assert.deepEqual(orderLines(cart, groups[0]), [{product_id:'other-tablet', quantity:1}]);
  assert.throws(() => changeQuantity(cart, otherTablet, 1, groups[0]), /Stock/);
  assert.throws(() => changeQuantity(cart, tablet, 1, groups[0]), /première pharmacie/);
});
test('pharmacies with another variant or unrelated legacy products are not merged into an offer', () => {
  const known = {...tablet, variant_id:'variant-1'};
  const different = {...tablet, product_id:'different', pharmacy_id:'other', variant_id:'variant-2'};
  assert.deepEqual(availablePharmacyOffers([known, different], known), [known]);
  const legacy = {...tablet, medicine_id:null, product_id:'legacy'};
  assert.equal(groupMedicineOffers([tablet, legacy]).length, 2);
});

const noPreferences: PharmacyPreferences = {
  distances: new Map(), favorites: new Set(), history: new Map(), openingStatuses: new Map(), reviewScores: new Map(), preferNearby: false,
};
const cheap = { ...tablet, product_id: 'a-1', pharmacy_id: 'a', selling_price: 100 };
const favorite = { ...tablet, product_id: 'b-1', pharmacy_id: 'b', selling_price: 110 };
const premium = { ...tablet, product_id: 'c-1', pharmacy_id: 'c', selling_price: 180 };

test('at 1 am a night pharmacy beats a cheaper, closer, well-reviewed favorite, but a manual choice stays pinned', () => {
  const atOne = new Date('2026-01-06T06:00:00Z'); // Tuesday 01:00 in Port-au-Prince
  const day = pharmacyOpenStatus('Lun–sam 8 h à 18 h', atOne);
  const night = pharmacyOpenStatus('Lun 22h–6h', atOne);
  const preferences: PharmacyPreferences = { ...noPreferences, preferNearby: true, favorites: new Set(['a']),
    reviewScores: new Map([['a', 4.9]]), distances: new Map([['a', 0.1], ['b', 1], ['c', 3]]),
    openingStatuses: new Map([['a', day], ['c', night]]) };
  const offers = [cheap, favorite, premium];
  assert.deepEqual(preferredPharmacyOffer(offers, preferences), { offer: premium, reason: 'open' });
  assert.equal(preferredPharmacyOffer(offers, preferences, 'a')?.offer, cheap);
  assert.deepEqual([...offers].sort((a, b) => comparePharmacyOptions(a.pharmacy_id, b.pharmacy_id, preferences, 'a')),
    [premium, favorite, cheap]);
  // If the only open seller runs out, unknown hours are preferable to a confirmed closure.
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, { ...premium, stock_quantity: 0 }], preferences),
    { offer: favorite, reason: null });
  assert.equal(preferredPharmacyOffer([cheap], preferences)?.offer, cheap);
});

test('distance and price compete within the open group even when a closed pharmacy is closer and cheaper', () => {
  const preferences: PharmacyPreferences = { ...noPreferences, preferNearby: true,
    openingStatuses: new Map([['a', 'closed'], ['b', 'open'], ['c', 'open']]),
    distances: new Map([['a', 0.1], ['b', 1.2], ['c', 1]]) };
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, premium], preferences), { offer: premium, reason: 'open' });
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, premium], { ...preferences, preferNearby: false }),
    { offer: favorite, reason: 'open' });
});

test('reliable reviews can decide between affordable open offers, while an outlier price or a single vote cannot', () => {
  const reviewed = { ...favorite, selling_price: 105 };
  const goodReviews = pharmacyReviewScore({ average_rating: 4.7, rating_count: 40 });
  const singleReview = pharmacyReviewScore({ average_rating: 5, rating_count: 1 });
  const preferences: PharmacyPreferences = { ...noPreferences, openingStatuses: new Map([['a', 'open'], ['b', 'open']]),
    reviewScores: new Map([['a', singleReview], ['b', goodReviews]]) };
  assert.deepEqual(preferredPharmacyOffer([cheap, reviewed], preferences), { offer: reviewed, reason: 'wellRated' });
  assert.deepEqual(preferredPharmacyOffer([cheap, { ...reviewed, selling_price: 125 }], preferences),
    { offer: cheap, reason: 'cheapest' });
  assert.deepEqual(preferredPharmacyOffer([cheap, reviewed], { ...preferences, reviewScores: new Map() }),
    { offer: cheap, reason: 'cheapest' });
});

test('a favorite can win within ten percent of the lowest price, and a large premium cannot', () => {
  const preferences = { ...noPreferences, favorites: new Set(['b', 'c']) };
  assert.deepEqual(preferredPharmacyOffer([premium, favorite, cheap], preferences), { offer: favorite, reason: 'favorite' });
  const overBudget = { ...favorite, selling_price: 110.01 };
  assert.deepEqual(preferredPharmacyOffer([overBudget, premium, cheap], preferences), { offer: cheap, reason: 'cheapest' });
  const outOfStock = { ...favorite, stock_quantity: 0 };
  assert.deepEqual(preferredPharmacyOffer([outOfStock, cheap], preferences, 'b'), { offer: cheap, reason: null });
  assert.equal(preferredPharmacyOffer([outOfStock, { ...cheap, selling_price: 0 }], preferences), undefined);
});

test('nearby mode prioritizes the closest pharmacy, while default mode also considers the price gap', () => {
  const distances = new Map([['a', 3], ['b', 0], ['c', 1]]);
  const preferences = { ...noPreferences, distances };
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite], preferences), { offer: favorite, reason: 'nearest' });
  assert.deepEqual(preferredPharmacyOffer([cheap, premium], preferences), { offer: cheap, reason: 'cheapest' });
  assert.deepEqual(preferredPharmacyOffer([cheap, premium], { ...preferences, preferNearby: true }), { offer: premium, reason: 'nearest' });
  // The closest pharmacy is outside the price band; neither remaining pharmacy is the closest overall.
  const outside = { ...favorite, selling_price: 200 };
  const eligible = { ...premium, selling_price: 104 };
  assert.deepEqual(preferredPharmacyOffer([outside, eligible, cheap], preferences), { offer: cheap, reason: 'cheapest' });
});

test('habits use repeated recent orders, breaking equal counts by last purchase', () => {
  const day = 86400000;
  const now = Date.now();
  const highFrequency = { count: 3, lastOrderedAt: now - 5 * day };
  const latest = { count: 2, lastOrderedAt: now - day };
  const third = { ...premium, selling_price: 108 };
  const preferences = { ...noPreferences, history: new Map([['b', highFrequency], ['c', latest]]) };
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, third], preferences), { offer: favorite, reason: 'recent' });
  preferences.history.set('b', { ...highFrequency, count: 2 });
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, third], preferences), { offer: third, reason: 'recent' });
  preferences.history.set('b', { ...highFrequency, lastOrderedAt: now - 91 * day });
  preferences.history.set('c', { ...latest, count: 1 });
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, third], preferences), { offer: cheap, reason: 'cheapest' });
});

test('unknown distances, mixed currencies or equal terms do not earn comparative labels', () => {
  const otherCurrency = { ...favorite, currency: 'USD', selling_price: 1 };
  const options = [otherCurrency, cheap];
  const preferences = { ...noPreferences, preferNearby: true, distances: new Map([['b', 0]]) };
  assert.deepEqual(preferredPharmacyOffer(options, preferences), { offer: otherCurrency, reason: null });
  assert.deepEqual(preferredPharmacyOffer(options, noPreferences), { offer: cheap, reason: null });
  assert.deepEqual(preferredPharmacyOffer([...options].reverse(), noPreferences), { offer: cheap, reason: null });
  const partlyLocated = { ...preferences, distances: new Map([['b', 2], ['c', 1]]) };
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, premium], partlyLocated), { offer: premium, reason: null });
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, premium], { ...partlyLocated, preferNearby: false }),
    { offer: cheap, reason: 'cheapest' });
  const same = { ...favorite, selling_price: cheap.selling_price };
  const equidistant = { ...preferences, distances: new Map([['a', 1], ['b', 1]]) };
  assert.deepEqual(preferredPharmacyOffer([same, cheap], equidistant), { offer: cheap, reason: null });
  assert.deepEqual(preferredPharmacyOffer([favorite], { ...preferences, favorites: new Set(['b']) }), { offer: favorite, reason: 'favorite' });
});

test('an explicit pharmacy retains its own advantage and never inherits the recommendation label', () => {
  const preferences = { ...noPreferences, favorites: new Set(['b']), distances: new Map([['a', 1], ['b', 2], ['c', 3]]) };
  const offers = [cheap, favorite, premium];
  assert.deepEqual(preferredPharmacyOffer(offers, preferences, 'b'), { offer: favorite, reason: 'favorite' });
  assert.deepEqual(preferredPharmacyOffer(offers, preferences, 'a'), { offer: cheap, reason: 'cheapest' });
  assert.deepEqual(preferredPharmacyOffer(offers, preferences, 'c'), { offer: premium, reason: null });
  assert.deepEqual(preferredPharmacyOffer(offers, preferences, 'removed'), { offer: favorite, reason: 'favorite' });
  const secondFavorite = { ...premium, selling_price: 108 };
  const twoFavorites = { ...preferences, favorites: new Set(['b', 'c']) };
  assert.deepEqual(preferredPharmacyOffer([cheap, favorite, secondFavorite], twoFavorites),
    { offer: secondFavorite, reason: 'favorite' });
});

test('only counts pharmacies with a purchasable offer for the selected presentation', () => {
  const soldOut = {...tablet, stock_quantity:0};
  const unpriced = {...tablet, product_id:'unpriced', selling_price:0};
  const otherSeller = {...tablet, pharmacy_id:'second', product_id:'second-tablet'};
  assert.deepEqual(availablePharmacyOffers([soldOut, syrup, unpriced], tablet), []);
  assert.deepEqual(availablePharmacyOffers([unpriced, soldOut, otherSeller, tablet], tablet), [otherSeller, tablet]);
});

test('a format or medicine without a purchasable offer disappears and returns when restocked', () => {
  const otherMedicine = {...syrup, product_id:'other', medicine_id:'other', stock_quantity:0};
  const cards = (products: Product[]) => groupMedicineOffers(products.filter(isOrderableOffer));
  assert.deepEqual(cards([drops, tablet, otherMedicine]), [[tablet]]);
  const restocked = {...otherMedicine, stock_quantity:1};
  assert.deepEqual(cards([drops, tablet, restocked]), [[tablet], [restocked]]);
});

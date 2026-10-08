import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chooseVariant, groupMedicines, groupMedicineOffers, matchingPharmacyOffers, preferredPharmacyOffer } from './catalog';
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
  assert.deepEqual(matchingPharmacyOffers(groups[0], tablet).map(p => p.product_id), ['tablet', 'other-tablet']);
  assert.equal(chooseVariant(groups[0], otherTablet, 'dosage_form', 'Sirop').product_id, 'other-syrup');
  const cart = changeQuantity({}, otherTablet, 1, groups[0]);
  assert.deepEqual(orderLines(cart, groups[0]), [{product_id:'other-tablet', quantity:1}]);
  assert.throws(() => changeQuantity(cart, otherTablet, 1, groups[0]), /Stock/);
  assert.throws(() => changeQuantity(cart, tablet, 1, groups[0]), /première pharmacie/);
});
test('pharmacies with another variant or unrelated legacy products are not merged into an offer', () => {
  const known = {...tablet, variant_id:'variant-1'};
  const different = {...tablet, product_id:'different', pharmacy_id:'other', variant_id:'variant-2'};
  assert.deepEqual(matchingPharmacyOffers([known, different], known), [known]);
  const legacy = {...tablet, medicine_id:null, product_id:'legacy'};
  assert.equal(groupMedicineOffers([tablet, legacy]).length, 2);
});

test('default pharmacy is nearest when known, otherwise cheapest, with available stock first', () => {
  const cheap = {...tablet, product_id:'cheap', pharmacy_id:'cheap', selling_price:400};
  const near = {...tablet, product_id:'near', pharmacy_id:'near', selling_price:900};
  assert.equal(preferredPharmacyOffer([near, cheap], new Map()), cheap);
  assert.equal(preferredPharmacyOffer([cheap, near], new Map([['near', 0.2], ['cheap', 3]])), near);
  assert.equal(preferredPharmacyOffer([cheap, near], new Map([['near', 0]])), near);
  assert.equal(preferredPharmacyOffer([{...near, stock_quantity:0}, cheap], new Map([['near', 0.2]])), cheap);
  assert.equal(preferredPharmacyOffer([{...near, selling_price:0}, cheap], new Map()), cheap);
});

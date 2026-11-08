import { test } from "node:test";
import assert from "node:assert/strict";
import { changeQuantity, orderLines, removeMissingProducts, type Product } from "./cart";
const product: Product = {
  product_id: "a",
  pharmacy_id: "p",
  pharmacy_name: "Pharmacie",
  name: "Produit",
  active_ingredient: "",
  category: "",
  pack_size: "",
  selling_price: 10,
  currency: "HTG",
  stock_quantity: 2,
  requires_prescription: false,
};
test("limite le stock et interdit deux pharmacies", () => {
  assert.deepEqual(changeQuantity({}, product, 1, [product]), { a: 1 });
  assert.throws(() => changeQuantity({ a: 2 }, product, 1, [product]), /Stock/);
  const other = { ...product, product_id: "b", pharmacy_id: "q" };
  assert.throws(
    () => changeQuantity({ a: 1 }, other, 1, [product, other]),
    /première/,
  );
  assert.deepEqual(changeQuantity({ a: 1 }, product, -1, [product]), {});
});
test("ne bloque pas sur le statut ordonnance et revalide le stock", () => {
  assert.deepEqual(
    orderLines({ a: 1 }, [{ ...product, requires_prescription: true }]),
    [{ product_id: "a", quantity: 1 }],
  );
  assert.throws(() => orderLines({ a: 3 }, [product]), /stock/);
  assert.throws(() => orderLines({ unknown: 1 }, [product]), /stock/);
  assert.deepEqual(orderLines({ a: 2 }, [product]), [
    { product_id: "a", quantity: 2 },
  ]);
});

test("une référence retirée du catalogue peut être retirée du panier", () => {
  const cart = { a: 2, removed: 1 };
  const reconciled = removeMissingProducts(cart, [product]);
  assert.deepEqual(reconciled, { a: 2 });
  assert.deepEqual(cart, { a: 2, removed: 1 });
  assert.deepEqual(orderLines(reconciled, [product]), [{ product_id: "a", quantity: 2 }]);
  assert.equal(removeMissingProducts(reconciled, [product]), reconciled);
  assert.deepEqual(removeMissingProducts(cart, []), {});
});

test("les quantités peuvent être réduites après une baisse de stock", () => {
  const reduced = changeQuantity({ a: 5 }, product, -1, [product]);
  assert.deepEqual(reduced, { a: 4 });
  assert.throws(() => orderLines(reduced, [product]), /stock/);
  assert.throws(() => changeQuantity(reduced, product, 1, [product]), /Stock/);
  const withinStock = changeQuantity(reduced, product, -2, [product]);
  assert.deepEqual(orderLines(withinStock, [product]), [{ product_id: "a", quantity: 2 }]);
});

test("un prix retiré empêche la commande et permet de vider le panier", () => {
  const unpriced = { ...product, selling_price: 0 };
  assert.throws(() => changeQuantity({}, unpriced, 1, [unpriced]), /indisponible/);
  assert.throws(() => orderLines({ a: 1 }, [unpriced]), /prix/);
  const cart = changeQuantity({ a: 2 }, unpriced, -1, [unpriced]);
  assert.deepEqual(cart, { a: 1 });
  assert.deepEqual(changeQuantity(cart, unpriced, -1, [unpriced]), {});
});

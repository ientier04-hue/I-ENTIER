import { test } from "node:test";
import assert from "node:assert/strict";
import { changeQuantity, orderLines, type Product } from "./cart";
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

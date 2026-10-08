export type Product = {
  medicine_id?: string | null;
  variant_id?: string | null;
  medicine_slug?: string | null;
  laboratory?: string | null;
  image_url?: string | null;
  source_url?: string | null;
  strength?: string;
  dosage_form?: string;
  product_id: string;
  pharmacy_id: string;
  pharmacy_name: string;
  name: string;
  active_ingredient: string;
  category: string;
  pack_size: string;
  selling_price: number;
  currency: string;
  stock_quantity: number;
  requires_prescription: boolean;
};
export type Cart = Record<string, number>;
export function changeQuantity(
  cart: Cart,
  product: Product,
  delta: number,
  products: Product[],
): Cart {
  const quantity = (cart[product.product_id] ?? 0) + delta;
  if (quantity <= 0) {
    const next = { ...cart };
    delete next[product.product_id];
    return next;
  }
  if (quantity > Number(product.stock_quantity))
    throw new Error("Stock insuffisant.");
  if (
    products.some(
      (p) => cart[p.product_id] && p.pharmacy_id !== product.pharmacy_id,
    )
  )
    throw new Error("Finalisez le panier de la première pharmacie.");
  return { ...cart, [product.product_id]: quantity };
}
export function orderLines(
  cart: Cart,
  products: Product[],
) {
  const entries = Object.entries(cart);
  if (!entries.length) throw new Error("Votre panier est vide.");
  const selected = entries.map(([id, quantity]) => {
    const p = products.find((p) => p.product_id === id);
    if (
      !p ||
      !Number.isInteger(quantity) ||
      quantity < 1 ||
      quantity > Number(p.stock_quantity)
    )
      throw new Error("Le stock a changé. Actualisez votre panier.");
    return p;
  });
  if (new Set(selected.map((p) => p.pharmacy_id)).size !== 1)
    throw new Error("Une seule pharmacie par commande.");
  return entries.map(([product_id, quantity]) => ({ product_id, quantity }));
}

import { isOrderableOffer } from "./catalog";

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

export function removeMissingProducts(cart: Cart, products: Product[]): Cart {
  const ids = Object.keys(cart);
  if (!ids.length) return cart;
  const availableIds = new Set(products.map((p) => p.product_id));
  const missing = ids.filter((id) => !availableIds.has(id));
  if (!missing.length) return cart;
  const next = { ...cart };
  for (const id of missing) delete next[id];
  return next;
}

export function changeQuantity(
  cart: Cart,
  product: Product,
  delta: number,
  products: Product[],
): Cart {
  if (!Number.isInteger(delta)) throw new Error("Quantité invalide.");
  if (!delta) return cart;
  const quantity = (cart[product.product_id] ?? 0) + delta;
  if (quantity <= 0) {
    const next = { ...cart };
    delete next[product.product_id];
    return next;
  }
  // A stock or price change must never prevent reducing an existing line.
  if (delta < 0) return { ...cart, [product.product_id]: quantity };
  if (quantity > Number(product.stock_quantity))
    throw new Error("Stock insuffisant.");
  if (!isOrderableOffer(product)) throw new Error("Cette offre est indisponible.");
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
    if (!isOrderableOffer(p))
      throw new Error("Le prix de ce produit est à confirmer. Retirez-le du panier.");
    return p;
  });
  if (new Set(selected.map((p) => p.pharmacy_id)).size !== 1)
    throw new Error("Une seule pharmacie par commande.");
  return entries.map(([product_id, quantity]) => ({ product_id, quantity }));
}

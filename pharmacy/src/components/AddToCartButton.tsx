import { StyleSheet, Text } from 'react-native';
import type { Product } from '../cart';
import { isOrderableOffer } from '../catalog';
import { MotionPressable } from './Motion';
import { Icon } from './Overview';

export function AddToCartButton({ product, quantity, busy, onAdd }: {
  product: Product; quantity: number; busy: boolean; onAdd: () => void;
}) {
  const disabled = busy || !isOrderableOffer(product) || quantity >= product.stock_quantity;
  return <MotionPressable accessibilityRole="button"
    accessibilityLabel={`Ajouter ${product.name} au panier, ${product.pharmacy_name}`}
    accessibilityValue={{ text: `${quantity} dans le panier` }} disabled={disabled}
    onPress={onAdd} style={[s.button, disabled && s.disabled]}>
    <Icon name="cart" size={22} color="#245B47"/>
    {quantity > 0 && <Text style={s.count}>{quantity}</Text>}
  </MotionPressable>;
}

const s = StyleSheet.create({
  button: { width: 44, height: 44, borderRadius: 14, backgroundColor: '#F2F6EF', alignItems: 'center', justifyContent: 'center' },
  count: { position: 'absolute', top: 0, right: 0, minWidth: 16, paddingHorizontal: 3, borderRadius: 8, overflow: 'hidden', lineHeight: 16, textAlign: 'center', fontSize: 10, fontWeight: '700', backgroundColor: '#245B47', color: '#FFFFFF' },
  disabled: { opacity: 0.45 },
});

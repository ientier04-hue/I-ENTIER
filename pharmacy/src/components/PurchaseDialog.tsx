import { useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { Product } from '../cart';
import { formatPrice, isOrderableOffer } from '../catalog';
import { Icon } from './Overview';

type Props = {
  product: Product;
  busy: boolean;
  error: string;
  onConfirm: (quantity: number) => void;
  onClose: () => void;
};

export function PurchaseDialog({ product, busy, error, onConfirm, onClose }: Props) {
  const [quantity, setQuantity] = useState(1);
  const insets = useSafeAreaInsets();
  const max = Math.floor(Number(product.stock_quantity));
  const valid = isOrderableOffer(product) && quantity <= max;
  const format = [product.dosage_form, product.strength, product.pack_size].filter(Boolean).join(' · ');
  const total = formatPrice({ ...product, selling_price: Number(product.selling_price) * quantity });
  const close = () => { if (!busy) onClose(); };

  return <Modal transparent animationType="none" onRequestClose={close}>
    <View style={[s.backdrop, { paddingTop: insets.top + 16, paddingBottom: insets.bottom + 16 }]}>
      <Pressable accessible={false} tabIndex={-1} style={StyleSheet.absoluteFill} onPress={close}/>
      <View accessibilityViewIsModal onAccessibilityEscape={close} style={s.panel}>
        <ScrollView bounces={false} contentContainerStyle={s.content}>
          <View style={s.row}>
            <View style={s.identity}>
              <Text accessibilityRole="header" style={s.title}>{product.name}</Text>
              {!!format && <Text style={s.detail}>{format}</Text>}
              <Text style={s.detail}>{product.pharmacy_name}</Text>
            </View>
            <Pressable accessibilityRole="button" accessibilityLabel="Fermer la commande" disabled={busy}
              onPress={close} style={s.close}><Icon name="close" size={20}/></Pressable>
          </View>
          <View style={s.row}>
            <Text style={s.label}>Quantité</Text>
            <View style={s.stepper}>
              <Pressable accessibilityRole="button" accessibilityLabel="Diminuer la quantité" disabled={busy || quantity <= 1}
                onPress={() => setQuantity(q => Math.max(1, q - 1))} style={[s.step, (busy || quantity <= 1) && s.disabled]}><Text style={s.sign}>−</Text></Pressable>
              <Text accessibilityLiveRegion="polite" style={s.quantity}>{quantity}</Text>
              <Pressable accessibilityRole="button" accessibilityLabel="Augmenter la quantité" disabled={busy || quantity >= max}
                onPress={() => setQuantity(q => Math.min(max, q + 1))} style={[s.step, (busy || quantity >= max) && s.disabled]}><Text style={s.sign}>+</Text></Pressable>
            </View>
          </View>
          <View style={[s.row, s.totalRow]}>
            <Text style={s.label}>Total</Text>
            <Text accessibilityLiveRegion="polite" style={s.total}>{total}</Text>
          </View>
          {!!error && <Text accessibilityRole="alert" style={s.error}>{error}</Text>}
          <Pressable accessibilityRole="button" disabled={busy || !valid} onPress={() => onConfirm(quantity)}
            style={({ pressed }) => [s.confirm, (busy || !valid || pressed) && s.disabled]}>
            <Text style={s.confirmText}>{busy ? 'Envoi…' : 'Confirmer la commande'}</Text>
          </Pressable>
        </ScrollView>
      </View>
    </View>
  </Modal>;
}

const s = StyleSheet.create({
  backdrop: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingHorizontal: 18, backgroundColor: 'rgba(6,30,24,0.58)' },
  panel: { width: '100%', maxWidth: 380, maxHeight: '100%', borderRadius: 22, overflow: 'hidden', backgroundColor: '#FFFFFF' },
  content: { padding: 20, gap: 18 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10 },
  identity: { flex: 1, gap: 4 },
  title: { fontSize: 21, fontWeight: '700', color: '#193B2D' },
  detail: { fontSize: 14, color: '#536B5C' },
  close: { width: 44, height: 44, alignSelf: 'flex-start', alignItems: 'center', justifyContent: 'center' },
  label: { fontSize: 15, fontWeight: '600', color: '#354F40' },
  stepper: { flexDirection: 'row', alignItems: 'center', borderRadius: 12, backgroundColor: '#EFF5EC' },
  step: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  sign: { fontSize: 22, color: '#245B47' },
  quantity: { minWidth: 24, textAlign: 'center', fontSize: 16, fontWeight: '700', color: '#193B2D' },
  totalRow: { paddingTop: 14, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: '#CEDACC' },
  total: { flexShrink: 1, fontSize: 22, fontWeight: '700', color: '#193B2D', textAlign: 'right' },
  confirm: { minHeight: 48, alignItems: 'center', justifyContent: 'center', borderRadius: 12, backgroundColor: '#164D39' },
  confirmText: { color: '#FFFFFF', fontWeight: '700', fontSize: 15 },
  error: { color: '#973F32', fontSize: 14 },
  disabled: { opacity: 0.45 },
});

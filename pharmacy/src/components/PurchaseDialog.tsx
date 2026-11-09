import { useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { Product } from '../cart';
import { formatPrice, isOrderableOffer } from '../catalog';
import { Icon } from './Overview';

const paymentMethods = ['MONCASH', 'NATCASH', 'Cash'] as const;
type PurchasePaymentMethod = (typeof paymentMethods)[number];
export type PurchaseDetails = {
  quantity: number;
  paymentMethod: PurchasePaymentMethod;
  whatsappContact: string;
};

function normalizeWhatsAppContact(input: string): string | null {
  const contact = input.trim();
  if (contact.startsWith('@')) {
    return /^@[\p{L}\p{N}_][\p{L}\p{M}\p{N}._-]*$/u.test(contact) ? contact : null;
  }
  const phone = contact.replace(/[\s().-]/g, '');
  return /^\+?[0-9]{7,15}$/.test(phone) ? phone : null;
}

type Props = {
  product: Product;
  busy: boolean;
  error: string;
  onConfirm: (details: PurchaseDetails) => void;
  onClose: () => void;
};

export function PurchaseDialog({ product, busy, error, onConfirm, onClose }: Props) {
  const [quantity, setQuantity] = useState(1);
  const [paymentMethod, setPaymentMethod] = useState<PurchasePaymentMethod | null>(null);
  const [contactInput, setContactInput] = useState('');
  const [contactTouched, setContactTouched] = useState(false);
  const whatsappContact = normalizeWhatsAppContact(contactInput);
  const insets = useSafeAreaInsets();
  const max = Math.floor(Number(product.stock_quantity));
  const valid = isOrderableOffer(product) && quantity <= max;
  const format = [product.dosage_form, product.strength, product.pack_size].filter(Boolean).join(' · ');
  const total = formatPrice({ ...product, selling_price: Number(product.selling_price) * quantity });
  const canConfirm = valid && !busy && paymentMethod !== null && whatsappContact !== null;
  const close = () => { if (!busy) onClose(); };

  return <Modal transparent animationType="none" onRequestClose={close}>
    <View style={[s.backdrop, { paddingTop: insets.top + 16, paddingBottom: insets.bottom + 16 }]}>
      <Pressable accessible={false} tabIndex={-1} style={StyleSheet.absoluteFill} onPress={close}/>
      <View accessibilityViewIsModal onAccessibilityEscape={close} style={s.panel}>
        <ScrollView bounces={false} automaticallyAdjustKeyboardInsets keyboardShouldPersistTaps="handled" contentContainerStyle={s.content}>
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
          <View style={s.fieldGroup}>
            <Text style={s.label}>Moyen de paiement</Text>
            <View accessibilityRole="radiogroup" accessibilityLabel="Moyen de paiement" style={s.methods}>
              {paymentMethods.map(method => {
                const selected = method === paymentMethod;
                return <Pressable key={method} accessibilityRole="radio" accessibilityLabel={method}
                  aria-checked={selected} disabled={busy}
                  onPress={() => setPaymentMethod(method)} style={[s.method, selected && s.selectedMethod]}>
                  <Text style={[s.methodText, selected && s.selectedMethodText]}>{method}</Text>
                </Pressable>;
              })}
            </View>
          </View>
          <View style={s.fieldGroup}>
            <Text style={s.label}>Contact WhatsApp</Text>
            <TextInput accessibilityLabel="Contact WhatsApp" placeholder="Numéro ou @identifiant"
              autoCapitalize="none" autoCorrect={false} spellCheck={false} returnKeyType="done"
              editable={!busy} maxLength={80} value={contactInput} onChangeText={setContactInput}
              onBlur={() => setContactTouched(true)} style={s.contactInput}/>
            {contactTouched && !!contactInput.trim() && !whatsappContact &&
              <Text accessibilityRole="alert" style={s.error}>Entrez un numéro valide ou un identifiant commençant par @.</Text>}
          </View>
          <View style={[s.row, s.totalRow]}>
            <Text style={s.label}>Total</Text>
            <Text accessibilityLiveRegion="polite" style={s.total}>{total}</Text>
          </View>
          {!!error && <Text accessibilityRole="alert" style={s.error}>{error}</Text>}
          <Pressable accessibilityRole="button" disabled={!canConfirm}
            onPress={() => { if (canConfirm) onConfirm({ quantity, paymentMethod, whatsappContact }); }}
            style={({ pressed }) => [s.confirm, (!canConfirm || pressed) && s.disabled]}>
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
  fieldGroup: { gap: 8 },
  contactInput: { minHeight: 44, paddingHorizontal: 12, paddingVertical: 10, borderWidth: 1, borderColor: '#CEDACC', borderRadius: 12, color: '#193B2D', fontSize: 16 },
  methods: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  method: { flexGrow: 1, minHeight: 44, paddingHorizontal: 8, paddingVertical: 8, alignItems: 'center', justifyContent: 'center', borderRadius: 12, backgroundColor: '#F2F6EF' },
  selectedMethod: { backgroundColor: '#245B47' },
  methodText: { color: '#354F40', fontSize: 13, fontWeight: '600' },
  selectedMethodText: { color: '#FFFFFF' },
  totalRow: { paddingTop: 14, borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: '#CEDACC' },
  total: { flexShrink: 1, fontSize: 22, fontWeight: '700', color: '#193B2D', textAlign: 'right' },
  confirm: { minHeight: 48, alignItems: 'center', justifyContent: 'center', borderRadius: 12, backgroundColor: '#164D39' },
  confirmText: { color: '#FFFFFF', fontWeight: '700', fontSize: 15 },
  error: { color: '#973F32', fontSize: 14 },
  disabled: { opacity: 0.45 },
});

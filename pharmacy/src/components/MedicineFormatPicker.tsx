import { Modal, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useReducedMotion } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { Product } from '../cart';
import { matchingPharmacyOffers, preferredPharmacyOffer } from '../catalog';
import { Icon } from './Overview';

export function medicinePresentations(variants: Product[]): Product[][] {
  const presentations: Product[][] = [];
  const seen = new Set<string>();
  for (const variant of variants) {
    if (seen.has(variant.product_id)) continue;
    const offers = matchingPharmacyOffers(variants, variant);
    if (offers.every(offer => seen.has(offer.product_id))) continue;
    presentations.push(offers);
    for (const offer of offers) seen.add(offer.product_id);
  }
  return presentations;
}

type Props = {
  product: Product;
  presentations: Product[][];
  distances: Map<string, number | null>;
  onSelect: (offer: Product) => void;
  onClose: () => void;
};

export function MedicineFormatPicker({ product, presentations, distances, onSelect, onClose }: Props) {
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReducedMotion();
  return (
    <Modal transparent animationType={reduceMotion ? 'none' : 'fade'} onRequestClose={onClose}
      statusBarTranslucent navigationBarTranslucent>
      <View style={[st.backdrop, width >= 650 && st.centered, {
        paddingTop: insets.top + 12, paddingBottom: insets.bottom + 12,
        paddingLeft: insets.left + 12, paddingRight: insets.right + 12,
      }]}>
        <Pressable style={StyleSheet.absoluteFill} accessible={false} tabIndex={-1} onPress={onClose}/>
        <View style={st.panel} accessibilityViewIsModal onAccessibilityEscape={onClose}>
          <ScrollView keyboardShouldPersistTaps="handled" bounces={false}>
            <View style={st.header}>
              <View style={st.headerCopy}>
                <Text style={st.medicine}>{product.name}</Text>
                <Text accessibilityRole="header" style={st.title}>Choisir le format</Text>
              </View>
              <Pressable accessibilityRole="button" accessibilityLabel="Fermer les formats"
                onPress={onClose} style={st.close}>
                <Icon name="close" size={20} color="#FFFFFF"/>
              </Pressable>
            </View>
            <View accessibilityRole="radiogroup" accessibilityLabel="Formats" style={st.list}>
              {presentations.map(offers => {
                const sample = offers[0];
                const selected = offers.some(offer => offer.product_id === product.product_id);
                const available = offers.filter(offer => offer.stock_quantity > 0);
                const samePharmacy = available.find(offer => offer.pharmacy_id === product.pharmacy_id && offer.selling_price > 0);
                const next = selected && product.stock_quantity > 0 ? product
                  : samePharmacy ?? preferredPharmacyOffer(available, distances) ?? sample;
                const format = [sample.dosage_form, sample.strength].filter(Boolean).join(' · ');
                const title = format || sample.pack_size || sample.name;
                const pack = format ? sample.pack_size : '';
                const availability = available.length
                  ? `Disponible dans ${available.length} pharmacie${available.length > 1 ? 's' : ''}`
                  : 'En rupture';
                return (
                  <Pressable key={sample.product_id} accessibilityRole="radio" aria-checked={selected}
                    accessibilityLabel={[title, pack, availability].filter(Boolean).join(', ')}
                    onPress={() => onSelect(next)} style={({ pressed }) => [st.row, selected && st.selected, pressed && st.pressed]}>
                    <View style={[st.radio, selected && st.radioSelected]}>
                      {selected && <View style={st.mark}/>}
                    </View>
                    <View style={st.format}>
                      <Text style={st.form}>{title}</Text>
                      {!!pack && <Text style={st.pack}>{pack}</Text>}
                      <Text style={[st.stock, !available.length && st.unavailable]}>{availability}</Text>
                    </View>
                  </Pressable>
                );
              })}
            </View>
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const st = StyleSheet.create({
  backdrop: { flex: 1, justifyContent: 'flex-end', alignItems: 'center', backgroundColor: 'rgba(6,30,24,0.66)' },
  centered: { justifyContent: 'center' },
  panel: { width: '100%', maxWidth: 480, maxHeight: '94%', borderRadius: 26, overflow: 'hidden', backgroundColor: '#FFFFFF' },
  header: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: 20, backgroundColor: '#104B39' },
  headerCopy: { flex: 1, gap: 4 },
  medicine: { color: '#DEFFA4', fontSize: 14, fontWeight: '600' },
  title: { color: '#FFFFFF', fontSize: 25, letterSpacing: -0.6, fontWeight: '700' },
  close: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 22, backgroundColor: '#29674F' },
  list: { padding: 12, gap: 8 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 13, padding: 14, minHeight: 56, borderRadius: 16, borderWidth: 1, borderColor: '#DCE5DE' },
  selected: { backgroundColor: '#F0F9E7', borderColor: '#71A479' },
  pressed: { opacity: 0.75 },
  radio: { width: 20, height: 20, borderRadius: 10, borderWidth: 1.5, borderColor: '#869D90', alignItems: 'center', justifyContent: 'center' },
  radioSelected: { borderColor: '#196348' },
  mark: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#196348' },
  format: { flex: 1, gap: 3 },
  form: { color: '#193B2D', fontSize: 16, fontWeight: '700' },
  pack: { color: '#435D50', fontSize: 14 },
  stock: { color: '#226346', fontSize: 12, fontWeight: '500', marginTop: 2 },
  unavailable: { color: '#706D65' },
});

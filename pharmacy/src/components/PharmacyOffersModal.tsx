import { Modal, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useReducedMotion } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { Product } from '../cart';
import { formatPrice } from '../catalog';
import { formatDistance, type Pharmacy } from '../pharmacies';
import { Icon, StockBadge } from './Overview';
import { ProductPhoto } from './ProductPhoto';

type Props = {
  product: Product;
  offers: Product[];
  pharmacies: Map<string, Pharmacy>;
  distances: Map<string, number | null>;
  onSelect: (offer: Product) => void;
  onClose: () => void;
};

export function PharmacyOffersModal({ product, offers, pharmacies, distances, onSelect, onClose }: Props) {
  const insets = useSafeAreaInsets();
  const wide = useWindowDimensions().width >= 650;
  const reduceMotion = useReducedMotion();
  const presentation = [product.dosage_form, product.strength, product.pack_size].filter(Boolean).join(' · ');

  return <Modal transparent animationType={reduceMotion ? 'none' : 'fade'} onRequestClose={onClose}
    statusBarTranslucent navigationBarTranslucent>
    <View style={[st.overlay, wide && st.center, { paddingTop: insets.top + 12, paddingBottom: insets.bottom + 12 }]}>
      <Pressable accessible={false} tabIndex={-1} style={StyleSheet.absoluteFill} onPress={onClose}/>
      <View accessibilityViewIsModal onAccessibilityEscape={onClose} style={st.panel}>
        <ScrollView bounces={false} keyboardShouldPersistTaps="handled">
          <View style={st.header}>
            <View style={st.titleRow}>
              <Text accessibilityRole="header" style={st.title}>Choisir la pharmacie</Text>
              <Pressable accessibilityRole="button" accessibilityLabel="Fermer la liste des pharmacies"
                onPress={onClose} style={st.close}><Icon name="close" color="#E4EEDF" size={20}/></Pressable>
            </View>
            <View style={st.product}>
              <ProductPhoto product={product}/>
              <View style={st.info}>
                <Text style={st.productName}>{product.name}</Text>
                {!!presentation && <Text style={st.presentation}>{presentation}</Text>}
              </View>
            </View>
          </View>
          <View style={st.rows} accessibilityRole="radiogroup" accessibilityLabel="Pharmacies">
            {offers.map(offer => {
              const selected = offer.product_id === product.product_id;
              const pharmacy = pharmacies.get(offer.pharmacy_id);
              const name = pharmacy?.display_name || offer.pharmacy_name;
              const distance = formatDistance(distances.get(offer.pharmacy_id) ?? null);
              const location = [distance && `≈ ${distance}`, pharmacy?.address].filter(Boolean).join(' · ');
              const price = formatPrice(offer);
              return <Pressable key={offer.pharmacy_id} accessible accessibilityRole="radio" aria-checked={selected}
                accessibilityLabel={[name, price, 'en stock', location].filter(Boolean).join(', ')}
                onPress={() => onSelect(offer)} style={({ pressed }) => [st.row, selected && st.selected, pressed && st.pressed]}>
                <View style={st.identity}>
                  <View style={st.info}>
                    <Text style={st.name}>{name}</Text>
                    {!!location && <Text style={st.location}>{location}</Text>}
                  </View>
                  <View style={[st.radio, selected && st.radioActive]}>{selected && <View style={st.radioDot}/>}</View>
                </View>
                <View style={st.terms}>
                  <Text style={st.price}>{price}</Text>
                  <StockBadge quantity={offer.stock_quantity}/>
                </View>
              </Pressable>;
            })}
          </View>
        </ScrollView>
      </View>
    </View>
  </Modal>;
}

const st = StyleSheet.create({
  overlay: { flex: 1, backgroundColor: 'rgba(6, 30, 24, 0.66)', justifyContent: 'flex-end', alignItems: 'center', paddingHorizontal: 12 },
  center: { justifyContent: 'center' },
  panel: { width: '100%', maxWidth: 480, maxHeight: '94%', borderRadius: 26, overflow: 'hidden', backgroundColor: '#FFFFFF' },
  header: { backgroundColor: '#173F32', paddingHorizontal: 20, paddingTop: 12, paddingBottom: 18, gap: 8 },
  titleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  title: { flex: 1, fontSize: 23, fontWeight: '700', letterSpacing: -0.7, color: '#FFFFFF' },
  close: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 22, backgroundColor: '#29523F' },
  product: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  info: { flex: 1, gap: 4 },
  productName: { fontSize: 15, fontWeight: '500', color: '#DDE9D9' },
  presentation: { fontSize: 15, fontWeight: '700', color: '#E5F5BB' },
  rows: { padding: 14, gap: 9 },
  row: { padding: 16, gap: 14, borderRadius: 17, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#DBE5DE' },
  selected: { backgroundColor: '#F2F7E8', borderColor: '#447552' },
  pressed: { opacity: 0.8 },
  identity: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  name: { fontWeight: '700', fontSize: 16, color: '#173D2F' },
  location: { color: '#4E6659', fontSize: 13 },
  radio: { width: 20, height: 20, borderRadius: 10, borderWidth: 1.5, borderColor: '#9AAF9F', alignItems: 'center', justifyContent: 'center' },
  radioActive: { borderColor: '#24573D', backgroundColor: '#24573D' },
  radioDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#E4F5BD' },
  terms: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  price: { color: '#193B2D', fontWeight: '700', fontSize: 17 },
});

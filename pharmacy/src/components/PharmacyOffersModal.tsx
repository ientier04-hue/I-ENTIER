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
            <View pointerEvents="none" style={st.halo}/>
            <View style={st.titleRow}>
              <Text accessibilityRole="header" style={st.title}>{offers.length} pharmacies</Text>
              <Pressable accessibilityRole="button" accessibilityLabel="Fermer la liste des pharmacies"
                onPress={onClose} style={st.close}><Icon name="close" color="#FFFFFF" size={20}/></Pressable>
            </View>
            <View style={st.product}>
              <ProductPhoto product={product}/>
              <View style={st.info}>
                <Text style={st.productName}>{product.name}</Text>
                {!!presentation && <Text style={st.presentation}>{presentation}</Text>}
              </View>
            </View>
          </View>
          <View style={st.rows}>
            {offers.map(offer => {
              const selected = offer.product_id === product.product_id;
              const pharmacy = pharmacies.get(offer.pharmacy_id);
              const name = pharmacy?.display_name || offer.pharmacy_name;
              const distance = formatDistance(distances.get(offer.pharmacy_id) ?? null);
              const location = [distance && `≈ ${distance}`, pharmacy?.address].filter(Boolean).join(' · ');
              return <Pressable key={offer.pharmacy_id} accessibilityRole="radio" aria-checked={selected}
                accessibilityLabel={`${name}, ${formatPrice(offer)}, ${offer.stock_quantity > 0 ? 'en stock' : 'indisponible'}`}
                onPress={() => onSelect(offer)} style={({ pressed }) => [st.row, selected && st.selected, pressed && st.pressed]}>
                <View style={st.identity}>
                  <View style={st.info}>
                    <Text style={st.name}>{name}</Text>
                    {!!location && <Text style={st.location}>{location}</Text>}
                  </View>
                  <View style={[st.radio, selected && st.radioActive]}>{selected && <View style={st.radioDot}/>}</View>
                </View>
                <View style={st.terms}>
                  <Text style={st.price}>{formatPrice(offer)}</Text>
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
  header: { backgroundColor: '#104B39', padding: 20, gap: 14, overflow: 'hidden' },
  halo: { position: 'absolute', right: -66, top: -114, width: 248, height: 248, borderRadius: 124, borderWidth: 28, borderColor: '#23664A' },
  titleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  title: { flex: 1, fontSize: 28, fontWeight: '800', letterSpacing: -1, color: '#E2FFA2' },
  close: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 22, backgroundColor: '#29674F' },
  product: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  info: { flex: 1, gap: 4 },
  productName: { fontSize: 18, fontWeight: '700', color: '#FFFFFF' },
  presentation: { fontSize: 13, color: '#D4EBDD' },
  rows: { padding: 14, gap: 9 },
  row: { padding: 16, gap: 14, borderRadius: 17, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#DBE5DE' },
  selected: { backgroundColor: '#F0F9E7', borderColor: '#71A479' },
  pressed: { opacity: 0.8 },
  identity: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  name: { fontWeight: '700', fontSize: 16, color: '#173D2F' },
  location: { color: '#4E6659', fontSize: 13 },
  radio: { width: 20, height: 20, borderRadius: 10, borderWidth: 1.5, borderColor: '#9AAF9F', alignItems: 'center', justifyContent: 'center' },
  radioActive: { borderColor: '#1C694C' },
  radioDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#1C694C' },
  terms: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  price: { color: '#193B2D', fontWeight: '700', fontSize: 17 },
});

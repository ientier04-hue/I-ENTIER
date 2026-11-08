import { Pressable, StyleSheet, Text, View } from 'react-native';
import { formatDistance } from '../pharmacies';
import { Icon } from './Overview';

export function PharmacyIdentity({ name, address, distance, delivery, favorite, onOpenCart, compact = false, offerPrice, offerCount = 0, selected = false, onSelect }: {
  name: string; address?: string; distance: number | null; delivery?: boolean | null;
  favorite: boolean; onOpenCart?: () => void; compact?: boolean;
  offerPrice?: string; offerCount?: number; selected?: boolean; onSelect?: () => void;
}) {
  const distanceLabel = formatDistance(distance);
  const deliveryLabel = delivery === true ? 'Livraison disponible' : delivery === false ? 'Livraison indisponible' : 'Livraison non renseignée';
  const cartButton = onOpenCart && <Pressable accessibilityRole="button" accessibilityLabel="Ouvrir le panier"
    onPress={onOpenCart} style={st.cartShortcut}>
    <Icon name="cart" size={compact ? 19 : 22} color="#245B47"/>
  </Pressable>;
  const showsCount = compact && offerCount > 1;
  if (compact) return <View style={[st.compact, selected && st.compactSelected]}>
    <Pressable onPress={onSelect} disabled={!onSelect}
      accessibilityRole={showsCount ? 'button' : onSelect ? 'radio' : undefined}
      accessibilityState={onSelect && !showsCount ? { checked: selected } : undefined}
      accessibilityLabel={showsCount ? `Voir les ${offerCount} pharmacies` : `${name}${distanceLabel ? `, à environ ${distanceLabel}` : ''}${offerPrice ? `, ${offerPrice}` : ''}`}
      style={[st.offer, showsCount && st.countButton]}>
      {showsCount ? <>
        <Icon name="store" size={17} color="#DDFBA2"/>
        <Text style={st.countText}>{offerCount} pharmacies</Text>
        <Icon name="chevron" size={14} color="#DDFBA2"/>
      </> : <>
        {selected && onSelect ? <Text style={st.offerCheck}>✓</Text> : <Icon name="store" size={15} color="#52675A"/>}
        <Text numberOfLines={1} style={st.compactName}>{name}</Text>
      </>}
      {distanceLabel && !showsCount && <Text style={st.distanceText}>≈ {distanceLabel}</Text>}
      {!!offerPrice && <Text style={st.offerPrice}>{offerPrice}</Text>}
    </Pressable>
    <View accessible accessibilityLabel={deliveryLabel} style={st.compactDelivery}>
      <Icon name={delivery === false ? 'truckOff' : 'truck'} size={18} color={delivery === true ? '#42754B' : '#8D9585'}/>
      {delivery == null && <Text style={st.unknownDelivery}>?</Text>}
    </View>
    {cartButton}
  </View>;
  return <View style={st.container}>
    <View style={st.identity}>
      <View style={st.store}><Icon name="store" size={19} color="#246B56"/></View>
      <View style={st.text}>
        <Text style={st.name}>{name}</Text>
        <View style={st.meta}>
          {distanceLabel && <View accessible accessibilityLabel={`À environ ${distanceLabel}, à vol d’oiseau`} style={st.distance}><Icon name="pin" size={13} color="#52675A"/><Text style={st.distanceText}>≈ {distanceLabel}</Text></View>}
          {!!address && <Text numberOfLines={1} style={st.address}>{address}</Text>}
        </View>
      </View>
      {cartButton}
    </View>
    <View style={st.badges}>
      {favorite && <View style={st.favoriteBadge}><Text style={st.favoriteText}>Favorite</Text></View>}
      <View accessible accessibilityLabel={deliveryLabel} style={[st.delivery, delivery === true && st.deliveryAvailable]}>
        <Icon name={delivery === false ? 'truckOff' : 'truck'} size={17} color={delivery === true ? '#42754B' : '#7F8578'}/>
        <Text style={[st.deliveryText, delivery === true && st.deliveryTextAvailable]}>{delivery === true ? 'Livraison' : delivery === false ? 'Retrait uniquement' : 'À confirmer'}</Text>
      </View>
    </View>
  </View>;
}

const st = StyleSheet.create({
  compact: { flexDirection: 'row', alignItems: 'center', gap: 4, minHeight: 44, borderRadius: 10, paddingLeft: 6 },
  compactSelected: { backgroundColor: '#F3F6EB' },
  offer: { flex: 1, minWidth: 0, minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 6 },
  countButton: { backgroundColor: '#175842', borderRadius: 12, paddingHorizontal: 12, justifyContent: 'space-between' },
  countText: { flex: 1, color: '#FFFFFF', fontSize: 14, fontWeight: '700' },
  offerPrice: { fontSize: 11, fontWeight: '600', color: '#35472B' },
  offerCheck: { width: 15, fontSize: 14, color: '#52675A', fontWeight: '700', textAlign: 'center' },
  compactName: { flex: 1, minWidth: 0, color: '#526744', fontSize: 12, fontWeight: '500' },
  compactDelivery: { width: 24, height: 24, alignItems: 'center', justifyContent: 'center' },
  unknownDelivery: { position: 'absolute', right: -2, top: -3, color: '#8D9585', backgroundColor: '#FFFFFF', fontSize: 10, fontWeight: '700' },
  container: { backgroundColor: '#F3F6EB', borderRadius: 17, padding: 12, gap: 7 },
  identity: { flexDirection: 'row', alignItems: 'center', gap: 9 },
  store: { width: 32, height: 36, alignItems: 'center', justifyContent: 'center' },
  text: { flex: 1, minWidth: 0, gap: 5 },
  name: { color: '#35472B', fontSize: 14, fontWeight: '600', lineHeight: 20 },
  meta: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 6 },
  distance: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  distanceText: { color: '#52675A', fontSize: 11, fontWeight: '600' },
  address: { color: '#818876', fontSize: 11, flexShrink: 1 },
  cartShortcut: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  badges: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 6, paddingLeft: 3 },
  favoriteBadge: { paddingHorizontal: 9, paddingVertical: 5, borderRadius: 8, backgroundColor: '#F4EBCF' },
  favoriteText: { color: '#8A6927', fontSize: 10, fontWeight: '600' },
  delivery: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 9, paddingVertical: 4, borderRadius: 8, backgroundColor: '#E9EDE2' },
  deliveryAvailable: { backgroundColor: '#E1EEDF' },
  deliveryText: { color: '#767E6D', fontSize: 10, fontWeight: '500' },
  deliveryTextAvailable: { color: '#42754B' },
});

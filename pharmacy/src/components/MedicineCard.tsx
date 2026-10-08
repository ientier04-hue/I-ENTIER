import React, { useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { ProductPhoto } from './ProductPhoto';
import { MedicineDetails, type HeroRect } from './MedicineDetails';
import type { Cart, Product } from '../cart';
import { chooseVariant, formatPrice, matchingPharmacyOffers, preferredPharmacyOffer } from '../catalog';
import { Icon } from './Overview';
import { PharmacyIdentity } from './PharmacyIdentity';
import { formatDistance, type Pharmacy } from '../pharmacies';

function Quantity({ product, quantity, busy, onAdjust }: { product: Product; quantity: number; busy: boolean; onAdjust: (p: Product, delta: number) => void }) {
  return <View style={st.quantity}>
    <Pressable accessibilityRole="button" accessibilityLabel={`Retirer un ${product.name}`} disabled={busy || quantity === 0} onPress={() => onAdjust(product, -1)} style={[st.step, (busy || quantity === 0) && st.disabled]}><Text style={st.stepText}>−</Text></Pressable>
    <Text accessibilityLiveRegion="polite" style={st.quantityText}>{quantity}</Text>
    <Pressable accessibilityRole="button" accessibilityLabel={`Ajouter ${product.name} ${product.dosage_form || ''} ${product.strength || ''}`} disabled={busy || quantity >= Number(product.stock_quantity) || Number(product.selling_price) <= 0} onPress={() => onAdjust(product, 1)} style={[st.step, (busy || quantity >= Number(product.stock_quantity) || Number(product.selling_price) <= 0) && st.disabled]}><Text style={st.stepText}>+</Text></Pressable>
  </View>;
}
export function MedicineCard({ variants, cart, busy, favorite, onFavorite, onAdjust, inCart = false, pharmacies, distances, pharmacyFavorites, onPharmacyFavorite, pharmacyFavoritesReady }: {
  variants: Product[]; cart: Cart; busy: boolean; favorite: boolean;
  onFavorite: () => void; onAdjust: (product: Product, delta: number) => string | null; inCart?: boolean;
  pharmacies: Map<string, Pharmacy>; distances: Map<string, number | null>; pharmacyFavorites: string[]; onPharmacyFavorite: (id: string) => void; pharmacyFavoritesReady: boolean;
}) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [picker, setPicker] = useState<'dosage_form' | 'strength' | 'pack_size' | null>(null);
  const [details, setDetails] = useState<HeroRect | null>(null);
  const photoRef = useRef<View>(null);
  const openDetails = () => photoRef.current?.measureInWindow((x, y, width, height) => {
    setDetails({ x, y, width, height });
  });
  const [allOffers, setAllOffers] = useState(false);
  const p = variants.find(v => v.product_id === selectedId)
    || preferredPharmacyOffer(matchingPharmacyOffers(variants, variants[0]), distances) || variants[0];
  const offers = matchingPharmacyOffers(variants, p);
  const otherOffers = offers.filter(offer => offer.product_id !== p.product_id);
  const pharmacyName = pharmacies.get(p.pharmacy_id)?.display_name || p.pharmacy_name;
  const pharmacyIdentity = (product: Product, compact = false) => {
    const pharmacy = pharmacies.get(product.pharmacy_id);
    return <PharmacyIdentity key={product.product_id} compact={compact}
      name={pharmacy?.display_name || product.pharmacy_name} address={pharmacy?.address}
      distance={distances.get(product.pharmacy_id) ?? null} delivery={pharmacy?.delivery_available}
      favorite={pharmacyFavorites.includes(product.pharmacy_id)} onFavorite={() => onPharmacyFavorite(product.pharmacy_id)} disabled={!pharmacyFavoritesReady}
      selected={compact && product.product_id === p.product_id}/>;
  };
  const options = (field: 'dosage_form' | 'strength' | 'pack_size') => [...new Set(variants
    .filter(v => field === 'dosage_form' || (v.dosage_form === p.dosage_form && (field !== 'pack_size' || v.strength === p.strength)))
    .map(v => v[field] || '').filter(Boolean))];
  const labels = { dosage_form: 'Forme', strength: 'Dosage', pack_size: 'Conditionnement' };
  const selectors = <View style={st.selectors}>{(['dosage_form', 'strength', 'pack_size'] as const).map(field => p[field] ? <Pressable key={field} accessibilityRole="button" accessibilityLabel={`${labels[field]} : ${p[field]}`} disabled={inCart || options(field).length < 2} onPress={() => setPicker(field)} style={st.selector}>
    <Text style={st.selectorText}>{p[field]}</Text>{!inCart && options(field).length > 1 && <Icon name="chevron" size={14} color="#777F76"/>}
  </Pressable> : null)}</View>;
  const heart = <Pressable accessibilityRole="button" accessibilityLabel={favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'} accessibilityState={{selected: favorite}} onPress={onFavorite} style={st.iconButton}><Icon name="heart" color={favorite ? '#D85B73' : '#8D958B'} size={24}/>{favorite && <View style={st.favoriteDot}/>}</Pressable>;
  return <View style={[st.card, inCart && st.cartCard]}>
    <View style={st.cardHeader}>
      <Pressable accessibilityRole="button" accessibilityLabel={`Voir ${p.name}`} onPress={openDetails}><View ref={photoRef} collapsable={false}><ProductPhoto product={p}/></View></Pressable>
      <View style={st.content}>
        <View style={st.between}><Pressable accessibilityRole="button" style={st.nameLink} onPress={openDetails}><Text style={st.name}>{p.name}</Text></Pressable>{heart}</View>
        {!!p.laboratory && <Text style={st.laboratory}>{p.laboratory}</Text>}
      </View>
    </View>
    <View style={st.purchaseRow}>
      <View style={st.priceAndOffers}><Text style={st.price}>{formatPrice(p)}</Text>
        <View style={st.pricePharmacy}><Text numberOfLines={1} style={st.pricePharmacyName}>{pharmacyName}</Text>
        {otherOffers.length > 0 && <Pressable accessibilityRole="button" accessibilityLabel={`${allOffers ? 'Masquer' : 'Afficher'} ${otherOffers.length} autre${otherOffers.length > 1 ? 's' : ''} pharmacie${otherOffers.length > 1 ? 's' : ''}`} accessibilityState={{ expanded: allOffers }} onPress={() => setAllOffers(value => !value)} style={st.moreOffers}><Text style={st.moreOffersText}>{`${allOffers ? '−' : '+'} ${otherOffers.length} Pharmacie${otherOffers.length > 1 ? 's' : ''}`}</Text></Pressable>}
        </View>
      </View>
      <Quantity product={p} quantity={cart[p.product_id] || 0} busy={busy} onAdjust={onAdjust}/>
    </View>
    {allOffers && otherOffers.length > 0 && <View style={st.otherOffers}>{otherOffers.map(offer => <Pressable key={offer.product_id} accessibilityRole="button" accessibilityLabel={`Choisir ${offer.pharmacy_name}, ${formatPrice(offer)}`} onPress={() => { setSelectedId(offer.product_id); setAllOffers(false); }} style={st.otherOffer}>
      <Text numberOfLines={1} style={st.otherOfferName}>{pharmacies.get(offer.pharmacy_id)?.display_name || offer.pharmacy_name}</Text>
      <Text style={st.pharmacyDistance}>{formatDistance(distances.get(offer.pharmacy_id) ?? null)}</Text>
      <Text style={st.otherOfferPrice}>{Number(offer.stock_quantity) > 0 ? formatPrice(offer) : 'Indisponible'}</Text>
    </Pressable>)}</View>}
    {selectors}
    <View style={st.offers}>{pharmacyIdentity(p, true)}</View>
    {(Number(p.stock_quantity) <= 0 || inCart) && <View style={st.between}>
      {Number(p.stock_quantity) <= 0 && <Text style={st.availability}>Indisponible</Text>}
      {inCart && <Pressable accessibilityRole="button" accessibilityLabel={`Supprimer ${p.name} du panier`} onPress={() => onAdjust(p, -(cart[p.product_id] || 0))} disabled={busy} style={[st.iconButton, st.removeButton]}><Icon name="close" size={20} color="#8D958B"/></Pressable>}
    </View>}
    {details && <MedicineDetails product={p} variants={variants} origin={details}
      cart={cart} busy={busy} favorite={favorite} onFavorite={onFavorite}
      onAdjust={onAdjust} onSelect={setSelectedId} onClose={() => setDetails(null)}
      inCart={inCart} pharmacies={pharmacies} distances={distances}
      pharmacyFavorites={pharmacyFavorites} onPharmacyFavorite={onPharmacyFavorite}
      pharmacyFavoritesReady={pharmacyFavoritesReady}/>}
    <Modal visible={picker !== null} transparent animationType="slide" onRequestClose={() => setPicker(null)}>
      <View style={st.overlay}>
        <Pressable style={StyleSheet.absoluteFill} accessibilityRole="button" accessibilityLabel="Fermer" onPress={() => setPicker(null)}/>
        <View style={st.sheet} accessibilityViewIsModal>
          <View style={st.handle}/>
          <View style={st.sheetHeader}><Text style={st.sheetTitle}>{picker ? labels[picker] : ''}</Text><Pressable accessibilityRole="button" accessibilityLabel="Fermer" onPress={() => setPicker(null)} style={st.iconButton}><Icon name="close"/></Pressable></View>
          <ScrollView contentContainerStyle={st.sheetBody}>
            {picker && options(picker).map(value => <Pressable key={value} accessibilityRole="radio" accessibilityState={{checked: p[picker] === value}} onPress={() => { setSelectedId(chooseVariant(variants, p, picker, value).product_id); setPicker(null); }} style={[st.option, p[picker] === value && st.selectedOption]}><Text style={st.selectorText}>{value}</Text>{p[picker] === value && <Text style={st.check}>✓</Text>}</Pressable>)}
          </ScrollView>
        </View>
      </View>
    </Modal>
  </View>;
}
const st = StyleSheet.create({
  card: { gap:8, padding:14, borderRadius:22, backgroundColor:'#FFFFFF', borderWidth:1, borderColor:'#E9EDDF', flexGrow:1, flexShrink:1, minWidth:0, flexBasis:300, maxWidth:620 },
  offers: { borderTopWidth: 1, borderColor: '#EEF1E7', paddingTop: 4, gap: 2 },
  purchaseRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  priceAndOffers: { flexDirection: 'row', alignItems: 'center', gap: 10, flex: 1, minWidth: 0 },
  pricePharmacy: { flex: 1, minWidth: 0 },
  pricePharmacyName: { fontSize: 11, fontWeight: '500', color: '#526744' },
  otherOffers: { gap: 2 },
  otherOffer: { minHeight: 44, flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 8, borderRadius: 10, backgroundColor: '#F5F7EF' },
  otherOfferName: { flex: 1, fontSize: 12, color: '#526744' },
  otherOfferPrice: { fontSize: 12, fontWeight: '600', color: '#35472B' },
  pharmacyDistance: { fontSize: 11, color: '#63764D' },
  moreOffers: { minHeight: 44, justifyContent: 'center', paddingHorizontal: 2 },
  moreOffersText: { fontSize: 12, color: '#63764D', fontWeight: '500' },
  cardHeader: {flexDirection:'row',alignItems:'center',gap:10},
  nameLink: {flex:1,minWidth:0},
  removeButton: {marginLeft:'auto'},
  cartCard: {flexBasis:'auto',maxWidth:'100%'},
  content:{flex:1,minWidth:0,gap:0},
  between:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',gap:8},
  name:{fontSize:17,fontWeight:'600',color:'#22291F',lineHeight:23},
  laboratory:{fontSize:11,color:'#868D80'},price:{flexShrink:1,fontSize:23,fontWeight:'700',color:'#283126',letterSpacing:-.8},
  selectors:{flexDirection:'row',flexWrap:'wrap',gap:6},selector:{flexDirection:'row',alignItems:'center',gap:8,paddingHorizontal:10,minHeight:44,borderRadius:12,backgroundColor:'#F5F6F3'},
  selectorText:{fontSize:13,color:'#343D2D',fontWeight:'500'},
  iconButton:{width:44,height:44,alignItems:'center',justifyContent:'center'},favoriteDot:{position:'absolute',bottom:4,width:4,height:4,borderRadius:2,backgroundColor:'#D85B73'},
  quantity:{flexShrink:0,flexDirection:'row',alignItems:'center',borderWidth:1,borderColor:'#D9DECf',borderRadius:14},
  step:{width:40,height:44,alignItems:'center',justifyContent:'center'},stepText:{fontSize:25,color:'#79A731',fontWeight:'400'},quantityText:{fontSize:15,minWidth:21,textAlign:'center',color:'#263020',fontWeight:'600'},disabled:{opacity:.25},availability:{fontSize:11,color:'#8A8E85'},
  overlay:{flex:1,backgroundColor:'rgba(29,37,25,.32)',justifyContent:'flex-end',alignItems:'center'},
  sheet:{width:'100%',maxWidth:560,maxHeight:'90%',backgroundColor:'#FFF',borderTopLeftRadius:30,borderTopRightRadius:30,paddingTop:10,paddingBottom:26},handle:{width:36,height:4,borderRadius:4,backgroundColor:'#DDE2D5',alignSelf:'center'},
  sheetHeader:{flexDirection:'row',justifyContent:'space-between',alignItems:'center',paddingHorizontal:22,paddingVertical:6},sheetTitle:{fontSize:16,fontWeight:'600',color:'#293223'},sheetBody:{padding:22,paddingTop:8,gap:16},
  option:{minHeight:54,paddingHorizontal:16,borderRadius:14,flexDirection:'row',justifyContent:'space-between',alignItems:'center',backgroundColor:'#F7F8F3'},selectedOption:{backgroundColor:'#EDF6D8',borderWidth:1,borderColor:'#ADCB75'},check:{color:'#6C932E'},
});

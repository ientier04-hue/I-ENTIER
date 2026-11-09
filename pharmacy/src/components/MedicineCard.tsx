import { useMemo, useReducer, useRef, useState } from 'react';
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import type { Cart, Product } from '../cart';
import { availablePharmacyOffers, comparePharmacyOptions, formatPrice, isOrderableOffer, preferredPharmacyOffer, type PharmacyPreferences } from '../catalog';
import type { Pharmacy } from '../pharmacies';
import { medicineOverlay } from '../medicineOverlay';
import { MedicineDetails } from './MedicineDetails';
import { AddToCartButton } from './AddToCartButton';
import { MedicineFormatPicker, medicinePresentations } from './MedicineFormatPicker';
import { MotionCard, MotionPressable, SelectionPulse } from './Motion';
import { Icon } from './Overview';
import { PharmacyOffersModal } from './PharmacyOffersModal';
import { ProductPhoto } from './ProductPhoto';

// Keep web cards in the grid when their content changes height after a format change.
const CardContainer = Platform.OS === 'web' ? View : MotionCard;
const reasonLabels = { cheapest: 'Moins cher', nearest: 'Plus proche', favorite: 'Favori', recent: 'Achat récent',
  open: 'Ouverte', wellRated: 'Bien notée', closed: 'Fermée' } as const;

type Props = {
  variants: Product[];
  cart: Cart;
  busy: boolean;
  favorite: boolean;
  favoriteReady: boolean;
  onFavorite: () => void;
  onBuy: (product: Product) => void;
  onAdjust: (product: Product, delta: number) => string | null;
  inCart?: boolean;
  index?: number;
  pharmacies: Map<string, Pharmacy>;
  preferences: PharmacyPreferences;
};

function ChoiceRow({ label, value, icon, onPress, actionLabel }: {
  label: string; value: string; icon: 'pill' | 'store'; onPress?: () => void; actionLabel?: string;
}) {
  const body = <>
    <Icon name={icon} size={18} color="#577165"/>
    <View style={st.field}>
      <Text style={st.fieldLabel}>{label}</Text>
      <Text style={st.fieldValue}>{value}</Text>
    </View>
    {onPress && <View style={st.disclosure}><Icon name="chevron" size={15} color="#245B47"/></View>}
  </>;
  return onPress
    ? <Pressable accessibilityRole="button" accessibilityLabel={actionLabel} accessibilityValue={{ text: value }}
        onPress={onPress} style={({ pressed }) => [st.choice, pressed && st.pressed]}>{body}</Pressable>
    : <View style={st.choice}>{body}</View>;
}

export function MedicineCard({ variants, cart, busy, favorite, favoriteReady, onFavorite, onBuy, onAdjust, inCart = false, pharmacies,
  preferences, index = 0 }: Props) {
  const [selection, setSelection] = useState<{ presentation: Product; pharmacyId: string | null } | null>(null);
  const [overlay, dispatch] = useReducer(medicineOverlay, { kind: 'closed' });
  const photoRef = useRef<View>(null);
  const presentations = useMemo(() => medicinePresentations(variants), [variants]);
  const offers = useMemo(() => {
    const matching = selection && availablePharmacyOffers(variants, selection.presentation);
    return matching?.length ? matching : availablePharmacyOffers(variants, variants[0]);
  }, [selection, variants]);
  const manualPharmacyId = selection?.pharmacyId;
  const choice = useMemo(() => inCart ? undefined : preferredPharmacyOffer(offers, preferences, manualPharmacyId),
    [inCart, offers, preferences, manualPharmacyId]);
  const p = choice?.offer ?? variants[0];
  const reason = !inCart && preferences.openingStatuses.get(p.pharmacy_id) === 'closed' ? 'closed' : choice?.reason;
  const showSellerList = overlay.kind === 'pharmacy' || overlay.kind === 'details';
  const sortedOffers = useMemo(() => showSellerList ? [...offers].sort((a, b) =>
    comparePharmacyOptions(a.pharmacy_id, b.pharmacy_id, preferences, p.pharmacy_id)) : offers,
  [offers, showSellerList, preferences, p.pharmacy_id]);
  const pharmacy = pharmacies.get(p.pharmacy_id);
  const seller = pharmacy?.display_name || p.pharmacy_name;
  const format = [p.dosage_form, p.strength, p.pack_size].filter(Boolean).join(' · ');
  const multipleFormats = !inCart && presentations.length > 1;
  const multiplePharmacies = !inCart && offers.length > 1;
  if ((overlay.kind === 'format' && !multipleFormats) || (overlay.kind === 'pharmacy' && !multiplePharmacies)) {
    dispatch({ type: 'close' });
  }
  const quantity = cart[p.product_id] || 0;
  const available = isOrderableOffer(p);
  const canAdd = !busy && available && quantity < p.stock_quantity;
  const addLabel = ['Ajouter', p.name, p.dosage_form, p.strength].filter(Boolean).join(' ');

  function openDetails() {
    if (!photoRef.current) return;
    const request = Symbol();
    dispatch({ type: 'measure', request });
    photoRef.current.measureInWindow((x, y, width, height) =>
      dispatch({ type: 'measured', request, origin: { x, y, width, height } }));
  }
  function closeOverlay() { dispatch({ type: 'close' }); }
  function selectFormat(presentation: Product) {
    setSelection(previous => ({ presentation, pharmacyId: previous?.pharmacyId ?? null }));
  }
  function selectPharmacy(offer: Product) {
    setSelection({ presentation: offer, pharmacyId: offer.pharmacy_id });
  }
  function offerForFormat(presentation: Product) {
    return preferredPharmacyOffer(availablePharmacyOffers(variants, presentation), preferences, manualPharmacyId)?.offer ?? presentation;
  }

  return <CardContainer {...(Platform.OS === 'web' ? {} : { index })} testID="medicine-card" style={[st.card, inCart && st.cartCard]}>
    <View style={st.header}>
      <Pressable accessibilityRole="button" accessibilityLabel={`Voir ${p.name}`} onPress={openDetails}
        style={({ pressed }) => [st.product, pressed && st.pressed]}>
        <View ref={photoRef} collapsable={false}><ProductPhoto product={p} card/></View>
        <View style={st.heading}>
          {!!p.laboratory && <Text style={st.lab}>{p.laboratory}</Text>}
          <Text style={st.name}>{p.name}</Text>
        </View>
      </Pressable>
      <MotionPressable accessibilityRole="button" accessibilityLabel={favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'}
        accessibilityState={{ selected: favorite, disabled: !favoriteReady }} disabled={!favoriteReady} onPress={onFavorite} style={[st.heart, favorite && st.heartActive]}>
        <SelectionPulse active={favorite}><Icon name="heart" size={21} color={favorite ? '#A63650' : '#455E50'} filled={favorite}/></SelectionPulse>
      </MotionPressable>
    </View>

    <View style={st.choices}>
      {(!!format || multipleFormats) && <>
        <ChoiceRow label="Format" value={format || 'Non renseigné'} icon="pill"
          onPress={multipleFormats ? () => dispatch({ type: 'openPicker', picker: 'format' }) : undefined} actionLabel={`Choisir le format de ${p.name}`}/>
        <View style={st.divider}/>
      </>}
      <ChoiceRow label={multiplePharmacies ? `${offers.length} pharmacies` : 'Pharmacie'} value={seller} icon="store"
        onPress={multiplePharmacies ? () => dispatch({ type: 'openPicker', picker: 'pharmacy' }) : undefined} actionLabel={`Voir les ${offers.length} pharmacies`}/>
    </View>

    <View style={st.purchase}>
      <View style={st.priceBlock}>
        <View style={st.priceRow}>
          <Text style={st.price}>{formatPrice(p)}</Text>
          {!!reason && <Text style={[st.reason, reason === 'closed' && st.closedReason]}>{reasonLabels[reason]}</Text>}
        </View>
        <View style={st.status}>
          <View style={[st.dot, !available && st.soldOutDot]}/>
          <Text style={[st.statusText, !available && st.soldOutText]}>{available ? 'En stock' : 'Indisponible'}</Text>
        </View>
      </View>
      <View style={st.actions}>
        {inCart ? <>
          <View style={st.stepper}>
            <MotionPressable accessibilityRole="button" accessibilityLabel={`Retirer un ${p.name}`} disabled={busy}
              onPress={() => onAdjust(p, -1)} style={st.step}><Text style={st.stepText}>−</Text></MotionPressable>
            <Text accessibilityLiveRegion="polite" style={st.qty}>{quantity}</Text>
            <MotionPressable accessibilityRole="button" accessibilityLabel={addLabel} disabled={!canAdd}
              onPress={() => onAdjust(p, 1)} style={[st.step, !canAdd && st.disabled]}><Text style={st.stepText}>+</Text></MotionPressable>
          </View>
          <MotionPressable accessibilityRole="button" accessibilityLabel={`Supprimer ${p.name} du panier`}
            disabled={busy} onPress={() => onAdjust(p, -quantity)} style={st.remove}><Icon name="close" size={19}/></MotionPressable>
        </> : <>
          <MotionPressable accessibilityRole="button" accessibilityLabel={`Acheter ${p.name}`} disabled={busy || !available}
            onPress={() => onBuy(p)} style={[st.add, (busy || !available) && st.unavailable]}>
            <Text style={[st.addText, (busy || !available) && st.soldOutText]}>Acheter</Text>
          </MotionPressable>
          <AddToCartButton product={p} quantity={quantity} busy={busy} onAdd={() => onAdjust(p, 1)}/>
        </>}
      </View>
    </View>

    {overlay.kind === 'format' && <MedicineFormatPicker product={p} presentations={presentations}
      onSelect={format => { selectFormat(format); closeOverlay(); }} onClose={closeOverlay}/>}
    {overlay.kind === 'pharmacy' && <PharmacyOffersModal product={p} offers={sortedOffers}
      pharmacies={pharmacies} preferences={preferences} onSelect={offer => { selectPharmacy(offer); closeOverlay(); }} onClose={closeOverlay}/>}
    {overlay.kind === 'details' && <MedicineDetails product={p} variants={variants} offers={sortedOffers} origin={overlay.origin}
      cart={cart} busy={busy} favorite={favorite} favoriteReady={favoriteReady} onFavorite={onFavorite}
      onAdjust={onAdjust} onSelectFormat={selectFormat} onSelectPharmacy={selectPharmacy} offerForFormat={offerForFormat} onClose={closeOverlay}
      inCart={inCart} pharmacies={pharmacies} preferences={preferences} onBuy={onBuy}/>}
  </CardContainer>;
}

const st = StyleSheet.create({
  card: { flexBasis: 310, flexGrow: 1, flexShrink: 1, minWidth: 0, maxWidth: 620, borderWidth: 1, borderColor: '#D9E3D9', borderRadius: 24, backgroundColor: '#FFFFFF', padding: 16, gap: 14 },
  cartCard: { flexBasis: 'auto', maxWidth: '100%' },
  header: { flexDirection: 'row', alignItems: 'flex-start', gap: 2 },
  product: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 13, minHeight: 80 },
  heading: { flex: 1, gap: 4 },
  name: { fontSize: 23, lineHeight: 27, letterSpacing: -0.8, fontWeight: '700', color: '#153829' },
  lab: { fontSize: 10, fontWeight: '700', lineHeight: 15, textTransform: 'uppercase', letterSpacing: 1, color: '#596E5D' },
  heart: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  heartActive: { backgroundColor: '#FFF0F3' },
  choices: { borderRadius: 16, paddingHorizontal: 12, backgroundColor: '#F2F6EF', marginTop: 'auto' },
  choice: { minHeight: 58, flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 9 },
  field: { flex: 1, gap: 2 },
  fieldLabel: { color: '#536B5C', fontSize: 12, fontWeight: '500' },
  fieldValue: { color: '#233F31', fontSize: 14, fontWeight: '600', lineHeight: 19 },
  disclosure: { width: 27, height: 27, alignItems: 'center', justifyContent: 'center', backgroundColor: '#FFFFFF', borderRadius: 14 },
  pressed: { opacity: 0.75 },
  divider: { height: StyleSheet.hairlineWidth, backgroundColor: '#CEDACC' },
  purchase: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8 },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  priceBlock: { flexGrow: 1, flexShrink: 1, gap: 3 },
  priceRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 6 },
  price: { fontSize: 23, letterSpacing: -0.8, fontWeight: '700', color: '#153829' },
  reason: { color: '#355D43', backgroundColor: '#EDF4E8', borderRadius: 8, overflow: 'hidden', paddingHorizontal: 6, paddingVertical: 2, fontSize: 11, lineHeight: 15, fontWeight: '600' },
  closedReason: { color: '#704B35', backgroundColor: '#F7EFE8' },
  status: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#408458' },
  soldOutDot: { backgroundColor: '#92857C' },
  statusText: { fontSize: 12, color: '#40644D' },
  add: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, borderRadius: 14, minHeight: 46, paddingHorizontal: 18, backgroundColor: '#164D39' },
  unavailable: { backgroundColor: '#EDF0EB' },
  addText: { fontSize: 14, fontWeight: '700', color: '#FFFFFF' },
  soldOutText: { color: '#646D65' },
  stepper: { flexDirection: 'row', alignItems: 'center', borderRadius: 14, backgroundColor: '#E8F2E3' },
  step: { width: 44, height: 46, alignItems: 'center', justifyContent: 'center' },
  stepText: { fontSize: 23, color: '#245A41' },
  qty: { fontSize: 15, minWidth: 18, textAlign: 'center', fontWeight: '700', color: '#193E2B' },
  disabled: { opacity: 0.35 },
  remove: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
});

import { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Easing, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { Cart, Product } from '../cart';
import { chooseVariant, formatPrice, isOrderableOffer, type PharmacyPreferences } from '../catalog';
import { openingLabel, type Pharmacy } from '../pharmacies';
import type { HeroRect } from '../medicineOverlay';
import { Icon } from './Overview';
import { PharmacyIdentity } from './PharmacyIdentity';
import { AddToCartButton } from './AddToCartButton';
import { ProductPhoto } from './ProductPhoto';

type Props = {
  product: Product; variants: Product[]; offers: Product[]; origin: HeroRect; cart: Cart; busy: boolean;
  favorite: boolean; favoriteReady: boolean; onFavorite: () => void;
  onSelectPharmacy: (offer: Product) => void; onSelectFormat: (presentation: Product) => void;
  offerForFormat: (presentation: Product) => Product;
  onAdjust: (product: Product, delta: number) => string | null; onClose: () => void;
  inCart: boolean; pharmacies: Map<string, Pharmacy>; preferences: PharmacyPreferences;
  onBuy: (product: Product) => void;
};

export function MedicineDetails({ product: p, variants, offers, origin, cart, busy, favorite, favoriteReady, onFavorite,
  onSelectPharmacy, onSelectFormat, offerForFormat, onAdjust, onClose, inCart, pharmacies, preferences, onBuy }: Props) {
  const { width, height } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const wide = width >= 700;
  const [progress] = useState(() => new Animated.Value(0));
  const root = useRef<View>(null);
  const photo = useRef<View>(null);
  const started = useRef(false);
  const closing = useRef(false);
  const [target, setTarget] = useState<HeroRect | null>(null);
  const [rootOrigin, setRootOrigin] = useState({ x: 0, y: 0 });
  const [ready, setReady] = useState(false);
  const [reduceMotion, setReduceMotion] = useState<boolean | null>(null);
  const [section, setSection] = useState<'details' | 'pharmacies'>('details');
  const [feedback, setFeedback] = useState<string | null>(null);
  const [purchaseAfterDismiss, setPurchaseAfterDismiss] = useState<Product | null>(null);
  const quantity = cart[p.product_id] || 0;
  const unavailable = !isOrderableOffer(p);
  const cannotAdd = busy || unavailable || quantity >= Number(p.stock_quantity);
  const showOffers = offers.length > 0 && section === 'pharmacies';
  const pharmacy = pharmacies.get(p.pharmacy_id);

  useEffect(() => {
    let active = true;
    AccessibilityInfo.isReduceMotionEnabled().then(value => { if (active) setReduceMotion(value); }).catch(() => { if (active) setReduceMotion(true); });
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => { active = false; subscription.remove(); progress.stopAnimation(); };
  }, [progress]);
  useEffect(() => {
    if (!target || reduceMotion === null || started.current || closing.current) return;
    started.current = true;
    const animation = Animated.timing(progress, { toValue: 1, duration: reduceMotion ? 0 : 380, easing: Easing.out(Easing.cubic), useNativeDriver: Platform.OS !== 'web' });
    animation.start(({ finished }) => { if (finished) setReady(true); });
  }, [target, reduceMotion, progress]);

  function measurePhoto() {
    root.current?.measureInWindow((rx, ry) => {
      photo.current?.measureInWindow((x, y, w, h) => {
        if (w <= 0 || h <= 0) return;
        setRootOrigin({ x: rx, y: ry });
        setTarget({ x: x - rx, y: y - ry, width: w, height: h });
      });
    });
  }
  function close() {
    if (closing.current) return;
    closing.current = true;
    // The photo may have scrolled away; keep dismissal independent of its position.
    setReady(true);
    Animated.timing(progress, { toValue: 0, duration: reduceMotion ? 0 : 180, useNativeDriver: Platform.OS !== 'web' }).start(({ finished }) => { if (finished) onClose(); });
  }
  function adjust(delta: number) { setFeedback(onAdjust(p, delta)); }
  const identity = (product: Product, compact = false) => {
    const location = pharmacies.get(product.pharmacy_id);
    return <PharmacyIdentity key={product.product_id} compact={compact}
      name={location?.display_name || product.pharmacy_name} address={location?.address}
      opening={openingLabel(preferences.openingStatuses.get(product.pharmacy_id))}
      distance={preferences.distances.get(product.pharmacy_id) ?? null} delivery={location?.delivery_available}
      favorite={preferences.favorites.has(product.pharmacy_id)}
      cartButton={!inCart && <AddToCartButton product={product} quantity={cart[product.product_id] || 0} busy={busy}
        onAdd={() => setFeedback(onAdjust(product, 1))}/>}
      selected={product.product_id === p.product_id} offerPrice={compact ? formatPrice(product) : undefined}
      onSelect={compact && !inCart ? () => { onSelectPharmacy(product); setFeedback(null); } : undefined}/>;
  };
  const fields = [
    ['Principe actif', p.active_ingredient], ['Catégorie', p.category], ['Laboratoire', p.laboratory],
    ['Forme', p.dosage_form], ['Dosage', p.strength], ['Conditionnement', p.pack_size],
    ['Disponibilité', unavailable ? 'Indisponible' : `${p.stock_quantity} en stock`],
    ['Ordonnance', p.requires_prescription ? 'Requise' : 'Non requise'],
  ];
  function openPurchase(offer: Product) {
    onClose();
    onBuy(offer);
  }
  return <Modal transparent animationType="none" visible={!purchaseAfterDismiss}
    onDismiss={() => { if (purchaseAfterDismiss) openPurchase(purchaseAfterDismiss); }}
    statusBarTranslucent navigationBarTranslucent onRequestClose={close} onShow={measurePhoto}>
    <View ref={root} style={st.overlay} collapsable={false}>
      <Animated.View style={[StyleSheet.absoluteFill, st.backdrop, { opacity: progress }]}/>
      <Pressable style={StyleSheet.absoluteFill} accessibilityRole="button" accessibilityLabel="Fermer les détails" onPress={close}/>
      <Animated.View accessibilityViewIsModal style={[st.panel, wide && st.widePanel, { opacity: progress, paddingTop: wide ? 12 : insets.top, paddingBottom: wide ? 12 : insets.bottom }]}>
        <View style={st.header}>
          <Pressable accessibilityRole="button" accessibilityLabel="Retour aux médicaments" onPress={close} style={st.roundButton}><View style={st.backIcon}><Icon name="chevron" color="#35472B"/></View></Pressable>
          <Text style={st.headerTitle}>Détails du médicament</Text>
          <Pressable accessibilityRole="button" accessibilityLabel={favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'} accessibilityState={{ selected: favorite, disabled: !favoriteReady }} disabled={!favoriteReady} onPress={onFavorite} style={st.roundButton}><Icon name="heart" color={favorite ? '#D85B73' : '#52675A'} filled={favorite}/></Pressable>
        </View>
        <ScrollView scrollEnabled={ready} showsVerticalScrollIndicator={false} contentContainerStyle={st.scroll}>
          <View ref={photo} collapsable={false} onLayout={measurePhoto} style={[st.hero, { height: Math.min(300, height * .3) }]}>
            <View style={[st.fill, { opacity: ready ? 1 : 0 }]}><ProductPhoto product={p} large/></View>
          </View>
          <View style={st.body}>
            <View style={st.titleRow}>
              <View style={st.titleCopy}><Text style={st.name}>{p.name}</Text>{!!p.laboratory && <Text style={st.muted}>{p.laboratory}</Text>}</View>
              {inCart && <View style={st.quantity}>
                <Pressable accessibilityRole="button" accessibilityLabel={`Retirer un ${p.name}`} disabled={busy || quantity === 0} onPress={() => adjust(-1)} style={[st.step, (busy || quantity === 0) && st.disabled]}><Text style={st.stepText}>−</Text></Pressable>
                <Text accessibilityLiveRegion="polite" style={st.quantityText}>{quantity}</Text>
                <Pressable accessibilityRole="button" accessibilityLabel={`Ajouter un ${p.name}`} disabled={cannotAdd} onPress={() => adjust(1)} style={[st.step, cannotAdd && st.disabled]}><Text style={st.stepText}>+</Text></Pressable>
              </View>}
            </View>
            {(['dosage_form', 'strength', 'pack_size'] as const).map(field => {
              const values = [...new Set(variants.filter(v => field === 'dosage_form' || (v.dosage_form === p.dosage_form && (field !== 'pack_size' || v.strength === p.strength))).map(v => v[field]).filter(Boolean))];
              if (!values.length) return null;
              return <View key={field} style={st.variantGroup}>
                <Text style={st.label}>{({ dosage_form: 'Forme', strength: 'Dosage', pack_size: 'Conditionnement' })[field]}</Text>
                <View style={st.choices}>{values.map(value => {
                  const candidate = chooseVariant(variants, p, field, value!);
                  const packPrice = field === 'pack_size' ? formatPrice(inCart ? p : offerForFormat(candidate)) : '';
                  const selected = p[field] === value;
                  return <Pressable key={value} accessibilityRole="radio" accessibilityLabel={`${value}${field === 'pack_size' ? `, ${packPrice}` : ''}`} accessibilityState={{ checked: selected, disabled: inCart }} disabled={inCart} onPress={() => { onSelectFormat(candidate); setFeedback(null); }} style={[st.choice, field === 'pack_size' && st.packChoice, selected && st.selectedChoice]}>
                    {field === 'pack_size' && <><View style={[st.radio, selected && st.radioSelected]}>{selected && <View style={st.radioDot}/>}</View><Text style={st.packPrice}>{packPrice}</Text></>}
                    <Text style={[st.choiceText, selected && st.selectedText]}>{value}</Text>
                  </Pressable>;
                })}</View>
              </View>;
            })}
            {offers.length > 0 && <View style={st.tabs}>
              {([{ key: 'details', label: 'Détails' }, { key: 'pharmacies', label: `Pharmacies · ${offers.length}` }] as const).map(item => <Pressable key={item.key} accessibilityRole="tab" accessibilityState={{ selected: section === item.key }} onPress={() => setSection(item.key)} style={[st.tab, section === item.key && st.activeTab]}><Text style={[st.tabText, section === item.key && st.selectedText]}>{item.label}</Text></Pressable>)}
            </View>}
            {showOffers ? <View style={st.offerList}>{offers.map(offer => identity(offer, true))}</View> : <View>{fields.filter(([, value]) => !!value).map(([label, value]) => <View key={label} style={st.infoRow}><Text style={st.infoLabel}>{label}</Text><Text style={st.infoValue}>{value}</Text></View>)}</View>}
            {identity(p)}
            {showOffers && !!pharmacy?.opening_hours && <View style={st.infoRow}><Text style={st.infoLabel}>Horaires</Text><Text style={st.infoValue}>{pharmacy.opening_hours}</Text></View>}
          </View>
        </ScrollView>
        <View style={st.footer}>
          {!!feedback && <Text accessibilityRole="alert" style={st.error}>{feedback}</Text>}
          <View style={st.footerRow}>
            <View style={st.total}><Text style={st.muted}>{inCart ? `Panier · ${quantity}` : 'Prix'}</Text><Text style={st.price}>{inCart ? formatPrice({ ...p, selling_price: Number(p.selling_price) * quantity }) : formatPrice(p)}</Text></View>
            {!inCart && <Pressable accessibilityRole="button" accessibilityLabel={`Acheter ${p.name}`} disabled={busy || unavailable}
              onPress={() => Platform.OS === 'ios' ? setPurchaseAfterDismiss(p) : openPurchase(p)} style={({ pressed }) => [st.addButton, (busy || unavailable) && st.disabled, pressed && st.pressed]}>
              <Text style={st.addText}>{unavailable ? 'Indisponible' : 'Acheter'}</Text>
            </Pressable>}
          </View>
        </View>
      </Animated.View>
      {!ready && target && <Animated.View pointerEvents="none" accessible={false} accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={[st.flyingPhoto, { left: target.x, top: target.y, width: target.width, height: target.height, transform: [
        { translateX: progress.interpolate({ inputRange: [0, 1], outputRange: [origin.x - rootOrigin.x + origin.width / 2 - target.x - target.width / 2, 0] }) },
        { translateY: progress.interpolate({ inputRange: [0, 1], outputRange: [origin.y - rootOrigin.y + origin.height / 2 - target.y - target.height / 2, 0] }) },
        { scale: progress.interpolate({ inputRange: [0, 1], outputRange: [Math.max(.01, Math.min(origin.width / target.width, origin.height / target.height)), 1] }) },
      ] }]}><ProductPhoto product={p} large/></Animated.View>}
    </View>
  </Modal>;
}

const st = StyleSheet.create({
  overlay: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  backdrop: { backgroundColor: 'rgba(29,37,25,.35)' },
  panel: { width: '100%', height: '100%', backgroundColor: '#F5F8EC', overflow: 'hidden' },
  widePanel: { maxWidth: 560, height: '94%', maxHeight: 1000, borderRadius: 30 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8, paddingHorizontal: 18, paddingVertical: 10 },
  headerTitle: { fontSize: 15, fontWeight: '600', color: '#1D322A', flexShrink: 1, textAlign: 'center' },
  roundButton: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' },
  backIcon: { transform: [{ rotate: '90deg' }] },
  scroll: { flexGrow: 1 }, hero: { marginHorizontal: 22 }, fill: { flex: 1 },
  flyingPhoto: { position: 'absolute' },
  body: { flexGrow: 1, backgroundColor: '#FFFFFF', padding: 22, gap: 20, borderTopLeftRadius: 30, borderTopRightRadius: 30 },
  titleRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 12 },
  titleCopy: { flex: 1, minWidth: 130, gap: 5 }, name: { fontSize: 25, fontWeight: '600', color: '#263020', letterSpacing: -.6 },
  muted: { fontSize: 12, color: '#868D80' },
  quantity: { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderColor: '#D9DECF', borderRadius: 14 },
  step: { width: 40, height: 44, alignItems: 'center', justifyContent: 'center' }, stepText: { fontSize: 25, color: '#246B56' }, quantityText: { minWidth: 21, textAlign: 'center', color: '#263020', fontSize: 15, fontWeight: '600' },
  variantGroup: { gap: 10 }, label: { fontSize: 13, fontWeight: '600', color: '#343D2D' },
  choices: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 }, choice: { minHeight: 44, paddingHorizontal: 14, paddingVertical: 12, borderRadius: 14, backgroundColor: '#F5F6F3', borderWidth: 1, borderColor: '#F5F6F3', alignItems: 'center', justifyContent: 'center' },
  packChoice: { flexGrow: 1, flexBasis: 100, gap: 8 }, selectedChoice: { backgroundColor: '#F0F6E4', borderColor: '#AAC5AD' }, choiceText: { fontSize: 12, color: '#77816D', textAlign: 'center' }, selectedText: { color: '#246B56', fontWeight: '600' },
  packPrice: { fontSize: 15, fontWeight: '600', color: '#1D322A' }, radio: { width: 15, height: 15, borderRadius: 8, borderWidth: 1, borderColor: '#A3AB9C', alignItems: 'center', justifyContent: 'center' }, radioSelected: { borderColor: '#246B56' }, radioDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#246B56' },
  tabs: { flexDirection: 'row', padding: 4, borderRadius: 24, backgroundColor: '#F5F6F3' }, tab: { flex: 1, minHeight: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 22, borderWidth: 1, borderColor: 'transparent' }, activeTab: { backgroundColor: '#FFFFFF', borderColor: '#AAC5AD' }, tabText: { fontSize: 13, color: '#77816D' },
  infoRow: { flexDirection: 'row', gap: 14, paddingVertical: 12, borderBottomWidth: 1, borderColor: '#EFF1EA' }, infoLabel: { fontSize: 13, color: '#818976', flex: 1 }, infoValue: { fontSize: 13, color: '#323C2A', flex: 1.3, textAlign: 'right', lineHeight: 19 }, offerList: { gap: 6 },
  footer: { backgroundColor: '#FFFFFF', paddingHorizontal: 22, paddingVertical: 16, gap: 12, borderTopWidth: 1, borderColor: '#EFF1EA' }, footerRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 12 }, total: { flexGrow: 1, gap: 5 }, price: { fontSize: 23, fontWeight: '700', color: '#1D322A', letterSpacing: -.7 },
  addButton: { flexGrow: 1, flexDirection: 'row', gap: 9, justifyContent: 'center', alignItems: 'center', backgroundColor: '#637F3C', borderRadius: 25, paddingHorizontal: 20, minHeight: 50 }, addText: { color: '#FFFFFF', fontWeight: '600', fontSize: 13 }, disabled: { opacity: .35 }, pressed: { opacity: .75 }, error: { color: '#8B422E', fontSize: 13 },
});

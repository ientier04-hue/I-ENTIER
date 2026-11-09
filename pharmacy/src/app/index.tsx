import React, { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Linking,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  useWindowDimensions,
  Text,
  TextInput,
  View,
} from "react-native";
import { StatusBar } from "expo-status-bar";
import * as ImagePicker from "expo-image-picker";
import * as Crypto from "expo-crypto";
import * as Location from "expo-location";
import { db, supabase } from "../api";
import { router, useIsFocused, useLocalSearchParams } from "expo-router";
import { Cart, Product, changeQuantity, orderLines, removeMissingProducts } from "../cart";
import { styles as s } from "../theme";
import { useStoredFavorites } from "../useStoredFavorites";
import { useGuestAccess } from "../useGuestAccess";
import { usePharmacyCatalog } from "../usePharmacyCatalog";
import { usePatientFile } from "../usePatientFile";
import { MedicineCard } from "../components/MedicineCard";
import { PurchaseDialog } from "../components/PurchaseDialog";
import { groupMedicineOffers, isOrderableOffer, medicineKey, medicineOfferKey } from "../catalog";
import { compareDistance, distanceKm, type Coordinates } from "../pharmacies";
import { PharmacyCard } from "../components/PharmacyCard";
import { OrderProgress, Icon } from "../components/Overview";

const tabs = [
  "Médicaments",
  "Favoris",
  "Pharmacies",
  "Ordonnances",
  "Panier",
] as const;
type Tab = (typeof tabs)[number];
const money = (value: number, currency = "HTG") =>
  `${Number(value).toLocaleString("fr-FR")} ${currency}`;
function Button({
  title,
  onPress,
  disabled = false,
  secondary = false,
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  secondary?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [s.button, secondary && s.secondary, disabled && s.disabled, pressed && s.pressed]}
    >
      <Text style={[s.buttonText, secondary && s.secondaryText]}>
        {title}
      </Text>
    </Pressable>
  );
}
function Emblem() {
  return <View accessible={false} style={s.emblem}><View style={s.crossH}/><View style={s.crossV}/></View>;
}
type Operation = 'order' | 'upload' | 'openDocument' | 'directions' | 'call';

export default function App() {
  const guest = useGuestAccess();
  return <PharmacyHome key={guest.access.generation} {...guest}/>;
}

function PharmacyHome({ access, retry: retrySession, isCurrent: sameGuest }: ReturnType<typeof useGuestAccess>) {
  const mounted = useRef(false);
  useLayoutEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  const isCurrent = useCallback(() => mounted.current && sameGuest(), [sameGuest]);
  const { uid } = access;
  const { width } = useWindowDimensions();
  const desktop = width >= 850;
  const compactSearch = desktop && width < 950;
  const searchWidth = Math.min(280, Math.max(220, width - 750));
  const params = useLocalSearchParams<{ tab?: string; q?: string; view?: string }>();
  const tab: Tab = params.tab === "Commandes"
    ? "Panier"
    : tabs.includes(params.tab as Tab)
      ? (params.tab as Tab)
      : "Médicaments";
  const purchaseView = params.tab === "Commandes" || params.view === "orders"
    ? "orders"
    : "cart";
  const focused = useIsFocused();
  const visiblePage = useRef<string | null>(null);
  useLayoutEffect(() => {
    visiblePage.current = focused ? (tab === 'Panier' ? purchaseView : tab) : null;
  }, [focused, tab, purchaseView]);
  const scroll = useRef<ScrollView>(null);
  const [searchExpanded, setSearchExpanded] = useState(false);
  const [purchaseId, setPurchaseId] = useState<string | null>(null);
  const setTab = (value: Tab | "Commandes") => {
    router.setParams({
      tab: value === "Commandes" ? "Panier" : value,
      view: value === "Commandes" ? "orders" : value === "Panier" ? "cart" : params.view,
    });
    setMessage('');
    setSearchExpanded(false);
    setPurchaseId(null);
  };
  useEffect(() => { scroll.current?.scrollTo({ y: 0, animated: false }); }, [tab, purchaseView]);
  const [query, setQuery] = useState(params.q || "");
  const [pharmacyQuery, setPharmacyQuery] = useState('');
  const [pharmacyFilter, setPharmacyFilter] = useState<string | null>(null);
  const [pharmacyMode, setPharmacyMode] = useState<'all' | 'nearby' | 'favorites'>('all');
  const [position, setPosition] = useState<Coordinates | null>(null);
  const [locating, setLocating] = useState(false);
  const locationRequest = useRef(0);
  const [category, setCategory] = useState("Tous");
  const [cart, setCart] = useState<Cart>({});
  const cartRef = useRef(cart);
  const [note, setNote] = useState("");
  const [message, setMessage] = useState("");
  const [operation, setOperation] = useState<Operation | null>(null);
  const lock = useRef<Operation | null>(null);
  const busy = operation !== null;
  const { products, pharmacies, ratings, phase, refresh, ratePharmacy } = usePharmacyCatalog(uid, isCurrent, setMessage);
  const loading = access.phase === 'connecting' || (!!uid && phase === 'loading');
  const { prescriptions, orders, status: fileStatus, error: fileError, retry: retryFile, ensureProfile, addPrescription } =
    usePatientFile(uid, tab, purchaseView, isCurrent);
  const medicineSaved = useStoredFavorites(uid ? `medicine-favorites:${uid}` : null, setMessage, 'Impossible de conserver les favoris.');
  const pharmacySaved = useStoredFavorites(uid ? `pharmacy-favorites:${uid}` : null, setMessage, 'Impossible de conserver les pharmacies favorites.');
  const favorites = medicineSaved.favorites;
  const pharmacyFavorites = pharmacySaved.favorites;
  const toggleFavorite = (variants: Product[]) => {
    const keys = products.filter(p => medicineOfferKey(p) === medicineOfferKey(variants[0])).map(medicineKey);
    medicineSaved.toggle(keys);
  };
  function updateCart(next: Cart) {
    cartRef.current = next;
    setCart(next);
  }
  function selectPharmacies(mode: 'all' | 'favorites', pharmacyId: string | null = null) {
    locationRequest.current++;
    setLocating(false);
    setPharmacyMode(mode);
    setPharmacyFilter(pharmacyId);
    setMessage('');
  }
  async function locate() {
    const id = ++locationRequest.current;
    const currentRequest = () => isCurrent() && locationRequest.current === id;
    setLocating(true);
    setMessage('');
    try {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (!currentRequest()) return;
      if (permission.status !== 'granted') throw new Error('Localisation non autorisée. Vous pouvez choisir une pharmacie ou vos favoris.');
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        const current = await Promise.race([
          Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }),
          new Promise<never>((_, reject) => { timeout = setTimeout(() => reject(new Error('Position indisponible. Réessayez.')), 15000); }),
        ]);
        if (!currentRequest()) return;
        setPosition(current.coords);
        setPharmacyMode('nearby');
        setPharmacyFilter(null);
      } finally { clearTimeout(timeout); }
    } catch (error) {
      if (currentRequest()) setMessage(error instanceof Error && /Localisation non autorisée|Position indisponible/.test(error.message) ? error.message : 'Position indisponible. Réessayez.');
    } finally {
      if (currentRequest()) setLocating(false);
    }
  }
  async function run(kind: Operation, task: () => Promise<void>) {
    if (lock.current || !isCurrent()) return;
    lock.current = kind;
    setOperation(kind);
    setMessage("");
    try {
      await task();
    } catch (e) {
      if (isCurrent()) setMessage(e instanceof Error ? e.message : "Une erreur est survenue. Réessayez.");
    } finally {
      lock.current = null;
      if (isCurrent()) setOperation(null);
    }
  }
  function adjust(p: Product, delta: number) {
    try {
      updateCart(changeQuantity(cartRef.current, p, delta, products));
      setMessage("");
      return null;
    } catch (e) {
      setMessage((e as Error).message);
      return (e as Error).message;
    }
  }
  const pickerRequest = useRef<symbol | null>(null);
  async function pickPrescription() {
    if (!uid || lock.current || (Platform.OS !== 'web' && pickerRequest.current)) return;
    // Some browsers omit cancellation. A waiting file dialog must not lock checkout.
    const request = Symbol();
    pickerRequest.current = request;
    const stillPicking = () => pickerRequest.current === request && isCurrent() && visiblePage.current === 'Ordonnances';
    try {
      const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.8, base64: true });
      if (!result.canceled && stillPicking()) await run('upload', () => upload(result.assets[0]));
    } catch {
      if (stillPicking()) setMessage('Impossible d’ouvrir la galerie. Réessayez.');
    } finally {
      if (pickerRequest.current === request) pickerRequest.current = null;
    }
  }
  async function upload(file: ImagePicker.ImagePickerAsset) {
    if (!uid || !isCurrent()) return;
    const bytes = file.base64
      ? Uint8Array.from(atob(file.base64), (c) => c.charCodeAt(0)).buffer
      : await (await fetch(file.uri)).arrayBuffer();
    if (bytes.byteLength > 10 * 1024 * 1024)
      throw new Error("Image trop volumineuse (10 Mo maximum).");
    await ensureProfile();
    if (!isCurrent()) return;
    const id = Crypto.randomUUID();
    const extension =
      file.mimeType === "image/png"
        ? "png"
        : file.mimeType === "image/webp"
          ? "webp"
          : "jpg";
    const path = `${uid}/${id}.${extension}`;
    const { error } = await supabase.storage
      .from("prescriptions")
      .upload(path, bytes, { contentType: file.mimeType || "image/jpeg" });
    if (error) throw new Error("Impossible d’enregistrer l’image.");
    if (!isCurrent()) return;
    const record = {
      prescription_id: id,
      patient_id: uid,
      source: "scan",
      status: "available",
      file_name: file.fileName || `Ordonnance.${extension}`,
      storage_path: `prescriptions/${path}`,
    };
    const saved = await db.from("prescriptions").insert(record);
    if (saved.error) {
      // A transport failure may have happened after the insert committed.
      if (saved.status >= 400 && saved.status < 500 && saved.status !== 409 && isCurrent())
        await supabase.storage.from("prescriptions").remove([path]);
      throw new Error("Impossible d’enregistrer l’ordonnance.");
    }
    if (!isCurrent()) return;
    addPrescription({ ...record, doctor_name_snapshot: "" });
    setMessage("Ordonnance ajoutée.");
  }
  const selected = products.filter((p) => cart[p.product_id]);
  const purchaseOffer = purchaseId ? products.find(p => p.product_id === purchaseId) : undefined;
  function checkout(direct?: { offer: Product; quantity: number }) {
    const pharmacy = direct?.offer ?? selected[0];
    if (!uid || !pharmacy) return;
    const origin = visiblePage.current;
    void run('order', async () => {
      const lines = orderLines(direct ? { [direct.offer.product_id]: direct.quantity } : cartRef.current, products);
      await ensureProfile();
      if (!isCurrent()) return;
      const { data, error, status } = await db.rpc('place_pharmacy_order', {
        p_pharmacy_id: pharmacy.pharmacy_id,
        p_items: lines,
        p_prescription_id: null,
        p_customer_name: '',
        p_customer_phone: '',
        p_note: direct ? '' : note.trim(),
      });
      if (error) {
        throw new Error(!status || status >= 500
          ? 'Envoi non confirmé. Vérifiez Mes commandes avant de réessayer.'
          : 'Commande refusée. Vérifiez la disponibilité des produits.');
      }
      if (!isCurrent()) return;
      if (direct) {
        setPurchaseId(null);
      } else {
        updateCart({});
        setNote('');
      }
      refresh();
      if (origin && visiblePage.current === origin) setTab('Commandes');
      else if (visiblePage.current === 'orders') retryFile();
      setMessage(`Commande ${data || ''} transmise.`);
    });
  }
  const hasMissingLines = selected.length < Object.keys(cart).length;
  const availableProducts = useMemo(() => products.filter(isOrderableOffer), [products]);
  const favoriteMedicines = useMemo(() => {
    const savedKeys = new Set(favorites);
    return new Set(products.filter(p => savedKeys.has(medicineKey(p))).map(medicineOfferKey));
  }, [favorites, products]);
  const total = selected.reduce(
    (sum, p) => sum + Number(p.selling_price) * cart[p.product_id],
    0,
  );
  const normalized = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase().trim();
  const pharmacyById = new Map(pharmacies.map(p => [p.pharmacy_id, p]));
  const distances = new Map(pharmacies.map(p => [p.pharmacy_id, distanceKm(position, p)]));
  const comparePharmacies = (a: string, b: string) => pharmacyMode === 'nearby'
    ? compareDistance(distances.get(a) ?? null, distances.get(b) ?? null) : 0;
  const matchesPharmacyMode = (id: string) => pharmacyMode !== 'favorites' || pharmacyFavorites.includes(id);
  const visiblePharmacies = pharmacies.filter(p => matchesPharmacyMode(p.pharmacy_id)).sort((a, b) => comparePharmacies(a.pharmacy_id, b.pharmacy_id)).filter(p => normalized(`${p.display_name} ${p.address}`).includes(normalized(pharmacyQuery)));
  const filteredPharmacy = pharmacies.find(p => p.pharmacy_id === pharmacyFilter);
  const visible = availableProducts.filter(
    (p) =>
      (!pharmacyFilter || p.pharmacy_id === pharmacyFilter) &&
      (category === "Tous" || (p.category || "Autres") === category) &&
      normalized(`${p.name} ${p.active_ingredient} ${p.pharmacy_name} ${p.laboratory || ""} ${p.strength || ""} ${p.dosage_form || ""}`).includes(normalized(query)),
  );
  const groups = groupMedicineOffers(visible);
  const favoriteGroups = groupMedicineOffers(availableProducts.filter(p => favoriteMedicines.has(medicineOfferKey(p))));
  const waitingForFavorites = pharmacyMode === 'favorites' && !!uid && !pharmacySaved.ready;
  const renderMedicine = (variants: Product[], inCart = false, index = 0) => <MedicineCard
    key={inCart ? variants[0].product_id : medicineOfferKey(variants[0])}
    pharmacies={pharmacyById}
    distances={distances}
    pharmacyFavorites={pharmacyFavorites}
    favoriteReady={medicineSaved.ready} index={index} variants={variants} cart={cart} busy={busy} inCart={inCart}
    favorite={favoriteMedicines.has(medicineOfferKey(variants[0]))}
    onFavorite={() => toggleFavorite(variants)} onAdjust={adjust}
    onBuy={offer => { setMessage(''); setPurchaseId(offer.product_id); }}
  />;
  const pharmacyFilters = <View style={s.pharmacyFilters}>{([
    { value: 'all', label: 'Toutes', icon: 'store' },
    { value: 'nearby', label: locating ? 'Localisation…' : 'À proximité', icon: 'pin' },
    { value: 'favorites', label: 'Mes pharmacies', icon: 'star' },
  ] as const).map(item => <Pressable key={item.value} accessibilityRole="button" accessibilityState={{ selected: pharmacyMode === item.value, disabled: item.value === 'nearby' && locating }} disabled={item.value === 'nearby' && locating} onPress={() => {
    if (item.value === 'nearby') { void locate(); return; }
    selectPharmacies(item.value);
  }} style={[s.pharmacyChip, pharmacyMode === item.value && s.pharmacyChipActive]}>
    <Icon name={item.icon} size={16} color={pharmacyMode === item.value ? '#F5F8EF' : '#52675A'}/>
    <Text style={[s.pharmacyChipText, pharmacyMode === item.value && s.pharmacyChipTextActive]}>{item.label}</Text>
  </Pressable>)}</View>;
  const fileFeedback = fileStatus === 'error' ? <View style={s.card}>
    <Text accessibilityRole="alert" style={s.message}>{fileError}</Text><Button title="Réessayer" secondary onPress={retryFile}/>
  </View> : (fileStatus === 'loading' || access.phase === 'connecting') ? <ActivityIndicator color="#242C26"/> : null;
  const medicineSearchField =
    <View style={[s.searchRow, s.medicineSearchField]}>
      <TextInput
        accessibilityLabel="Rechercher un médicament"
        placeholder={desktop ? "Rechercher…" : "Rechercher un médicament…"}
        value={query}
        onChangeText={setQuery}
        onSubmitEditing={() => { if (compactSearch) setSearchExpanded(false); }}
        autoFocus={compactSearch && searchExpanded}
        style={[s.input, s.searchInput]}
        returnKeyType="search"
      />
      {!!query && <Pressable accessibilityRole="button" accessibilityLabel="Effacer la recherche" onPress={() => setQuery('')} style={s.clearSearch}><Text style={s.clearText}>×</Text></Pressable>}
    </View>;
  const scanButton =
    <Pressable accessibilityRole="button" accessibilityLabel="Scanner une ordonnance" onPress={() => router.push('/scan')} style={s.scanButton}>
      <Icon name="scan" color="#246B56" size={25}/>
    </Pressable>;
  const medicineSearch = <View style={s.medicineSearch}>{medicineSearchField}{scanButton}</View>;
  return (
    <SafeAreaView style={s.root}>
      <StatusBar style="dark" />
      <ScrollView
        ref={scroll}
        contentContainerStyle={[s.page, desktop && s.pageWide]}
        keyboardShouldPersistTaps="handled"
      >
        <View style={[s.header, desktop && s.topHeader]}>
          <View style={s.brand}>
            <Emblem/>
            <View>
              <Text style={s.title}>Pharmacie</Text>
              <Text style={s.brandCaption}>I-ENTIER</Text>
            </View>
          </View>
          {desktop && <View style={s.catalogNavRow}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={s.catalogTabs}>
              {tabs.map((t) => (
                <Pressable
                  accessibilityRole="tab"
                  accessibilityState={{ selected: tab === t }}
                  key={t}
                  onPress={() => setTab(t)}
                  style={[s.tab, s.catalogTab, tab === t && s.activeTab]}
                >
                  <Text style={[s.tabText, tab === t && s.activeTabText]}>{t}</Text>
                </Pressable>
              ))}
            </ScrollView>
            {tab === 'Médicaments' && (compactSearch ? <>
              <View style={s.medicineSearch}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={searchExpanded ? "Fermer la recherche" : query ? `Ouvrir la recherche : ${query}` : "Ouvrir la recherche"}
                  accessibilityState={{ expanded: searchExpanded }}
                  onPress={() => setSearchExpanded(open => !open)}
                  style={[s.scanButton, !!query && s.searchIconActive]}
                >
                  <Icon name="search" color="#246B56" size={24}/>
                </Pressable>
                {scanButton}
              </View>
              {searchExpanded && <View style={s.searchPopover}>
                {medicineSearchField}
                <Pressable accessibilityRole="button" accessibilityLabel="Fermer la recherche" onPress={() => setSearchExpanded(false)} style={s.searchCloseButton}>
                  <Icon name="close" color="#246B56" size={22}/>
                </Pressable>
              </View>}
            </> : <View style={[s.medicineSearchDesktop, { width: searchWidth }]}>{medicineSearch}</View>)}
          </View>}
        </View>
        {access.phase === 'unavailable' && <View style={s.card}>
          <Text accessibilityRole="alert" style={s.message}>Pharmacie indisponible. Réessayez.</Text>
          <Button title="Réessayer" secondary onPress={retrySession}/>
        </View>}
        {uid && phase === 'failed' && (tab === 'Médicaments' || tab === 'Pharmacies' || tab === 'Favoris') && <View style={s.card}>
          <Text accessibilityRole="alert" style={s.message}>Impossible de charger la pharmacie.</Text>
          {tab !== 'Médicaments' && <Button title="Actualiser" secondary onPress={refresh}/>}
        </View>}
        {!!message && !purchaseOffer && (
          <Text accessibilityRole="alert" style={s.message}>
            {message}
          </Text>
        )}
        <>
            {tab === "Médicaments" && (
              <>
                {!desktop && medicineSearch}
                {!!filteredPharmacy && <Button title={`${filteredPharmacy.display_name}  ×`} secondary onPress={() => setPharmacyFilter(null)}/>}
                <ScrollView
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  style={s.tabs}
                >
                  {[
                    "Tous",
                    ...new Set(availableProducts.map((p) => p.category || "Autres")),
                  ].map((c) => (
                    <Button
                      key={c}
                      title={c}
                      secondary={c !== category}
                      onPress={() => setCategory(c)}
                    />
                  ))}
                </ScrollView>
                {loading ? (
                  <ActivityIndicator color="#242C26" />
                ) : (
                  <View style={s.grid}>
                    {groups.map((group, index) => renderMedicine(group, false, index))}
                  </View>
                )}
                {uid && phase === 'ready' && !visible.length && (
                  <View style={s.card}><Text style={s.heading}>{query || pharmacyFilter || category !== 'Tous' ? 'Aucun résultat' : 'Aucun médicament disponible'}</Text>{(!!query || !!pharmacyFilter || category !== 'Tous') && <Button title="Réinitialiser les filtres" secondary onPress={() => {setQuery('');setCategory('Tous');setPharmacyFilter(null);}}/>}</View>
                )}
              </>
            )}
            {tab === "Favoris" && <>
              <Text style={s.heading}>Mes favoris</Text>
              <View style={s.grid}>{favoriteGroups.map((group, index) => renderMedicine(group, false, index))}</View>
              {(loading || (!!uid && !medicineSaved.ready)) && <ActivityIndicator color="#242C26"/>}
              {uid && phase === 'ready' && medicineSaved.ready && !favoriteGroups.length && <Text style={s.empty}>Aucun favori pour le moment.</Text>}
            </>}
            {tab === "Pharmacies" && (
              <>
                <View style={s.header}><Text style={s.heading}>Les pharmacies</Text><Text style={s.muted}>{loading ? '…' : visiblePharmacies.length}</Text></View>
                <View style={s.searchRow}><TextInput style={[s.input,s.searchInput]} accessibilityLabel="Rechercher une pharmacie" placeholder="Nom, ville ou quartier" value={pharmacyQuery} onChangeText={setPharmacyQuery} returnKeyType="search"/>{!!pharmacyQuery && <Pressable style={s.clearSearch} accessibilityRole="button" accessibilityLabel="Effacer la recherche de pharmacie" onPress={() => setPharmacyQuery('')}><Text style={s.clearText}>×</Text></Pressable>}</View>
                {pharmacyFilters}
                {(loading || waitingForFavorites) && <ActivityIndicator color="#202923"/>}
                <View style={s.grid}>{visiblePharmacies.map((p, index) => <PharmacyCard index={index} key={p.pharmacy_id}
                  pharmacy={p} distance={distances.get(p.pharmacy_id) ?? null}
                  favorite={pharmacyFavorites.includes(p.pharmacy_id)} favoriteReady={pharmacySaved.ready}
                  onFavorite={() => pharmacySaved.toggle([p.pharmacy_id])} rating={ratings[p.pharmacy_id]}
                  onRate={value => ratePharmacy(p.pharmacy_id, value)} busy={busy}
                  onOpen={() => {selectPharmacies('all', p.pharmacy_id);setQuery('');setCategory('Tous');setTab('Médicaments');}}
                  onDirections={() => run('directions', async () => {await Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(p.address + ' ' + p.display_name)}`);})}
                  onCall={() => run('call', async () => {await Linking.openURL(`tel:${p.phone.replace(/[^+0-9]/g, '')}`);})}
                />)}</View>
                {uid && phase === 'ready' && !waitingForFavorites && !visiblePharmacies.length && <View style={s.card}><Text style={s.heading}>{pharmacyMode === 'favorites' ? 'Aucune pharmacie favorite' : pharmacyQuery ? 'Aucune pharmacie trouvée' : 'Aucune pharmacie disponible'}</Text>{!!pharmacyQuery && <Button title="Effacer la recherche" secondary onPress={() => setPharmacyQuery('')}/>}</View>}
              </>
            )}
            {tab === "Ordonnances" && (
                <>
                  <View style={s.header}>
                    <Text style={s.heading}>Mes ordonnances</Text>
                    <Button
                      title="Ajouter"
                      disabled={busy || !uid}
                      onPress={pickPrescription}
                    />
                  </View>
                  {prescriptions.map((p) => (
                    <View key={p.prescription_id} style={s.card}>
                      <View style={s.documentIcon}><Icon name="document" size={28}/></View>
                      <Text style={s.heading}>
                        {p.file_name || p.doctor_name_snapshot || "Ordonnance"}
                      </Text>
                      {!!p.transcription && <Text selectable style={s.muted}>{p.transcription}</Text>}
                      {!!p.storage_path && (
                        <Button
                          title="Ouvrir"
                          secondary
                          onPress={() =>
                            run('openDocument', async () => {
                              const [bucket, ...parts] =
                                p.storage_path.split("/");
                              const { data, error } = await supabase.storage
                                .from(bucket)
                                .createSignedUrl(parts.join("/"), 60);
                              if (error)
                                throw new Error("Document indisponible.");
                              if (isCurrent() && visiblePage.current === 'Ordonnances') await Linking.openURL(data.signedUrl);
                            })
                          }
                        />
                      )}
                    </View>
                  ))}
                  {fileFeedback}
                  {fileStatus === 'ready' && !prescriptions.length && (
                    <Text style={s.empty}>Aucune ordonnance.</Text>
                  )}
                </>
              )}
            {tab === "Panier" && (
              <View style={s.purchaseSwitch}>
                {([
                  { value: "cart", label: "Mon panier" },
                  { value: "orders", label: "Mes commandes" },
                ] as const).map(item => (
                  <Pressable
                    key={item.value}
                    accessibilityRole="tab"
                    accessibilityState={{ selected: purchaseView === item.value }}
                    onPress={() => setTab(item.value === "orders" ? "Commandes" : "Panier")}
                    style={({ pressed }) => [s.purchaseTab, purchaseView === item.value && s.purchaseTabActive, pressed && s.pressed]}
                  >
                    <Text style={[s.purchaseTabText, purchaseView === item.value && s.purchaseTabTextActive]}>{item.label}</Text>
                  </Pressable>
                ))}
              </View>
            )}
            {tab === "Panier" && purchaseView === "orders" && (
                <>
                  <Text style={s.heading}>Mes commandes</Text>
                  {orders.map((o) => (
                    <View key={o.order_id} style={s.card}>
                      <Text style={s.heading}>{o.order_number}</Text>
                      <OrderProgress status={o.status}/>
                      <Text style={s.price}>{money(o.total_amount)}</Text>
                    </View>
                  ))}
                  {fileFeedback}
                  {fileStatus === 'ready' && !orders.length && (
                    <Text style={s.empty}>Aucune commande.</Text>
                  )}
                </>
              )}
            {tab === "Panier" && purchaseView === "cart" && (
              <>
                <Text style={s.heading}>Mon panier</Text>
                {selected.map(p => renderMedicine([p], true))}
                {hasMissingLines && <Button title="Retirer les produits indisponibles" secondary disabled={busy}
                  onPress={() => updateCart(removeMissingProducts(cartRef.current, products))}/>}
                {!Object.keys(cart).length ? (
                  <View style={s.card}><Text style={s.heading}>Votre panier est vide.</Text><Button title="Parcourir les médicaments" onPress={() => setTab('Médicaments')}/></View>
                ) : selected.length > 0 && (
                  <View style={s.card}>
                    <Text style={s.price}>
                      {money(total, selected[0]?.currency)}
                    </Text>
                    <TextInput
                      placeholder="Note à la pharmacie"
                      accessibilityLabel="Note à la pharmacie"
                      maxLength={500}
                      value={note}
                      editable={operation !== "order"}
                      onChangeText={setNote}
                      style={s.input}
                    />
                    <Button
                      title={
                        operation === "order" ? "Envoi…" : "Commander"
                      }
                      disabled={busy || hasMissingLines}
                      onPress={() => checkout()}
                    />
                  </View>
                )}
              </>
            )}
          </>
      </ScrollView>
      {!desktop && <View style={s.mobileDock}>
        {Object.values(cart).some(q => q > 0) && tab !== 'Panier' && <Pressable accessibilityRole="button" onPress={() => setTab('Panier')} style={s.cartDock}><Text style={s.cartDockText}>Voir mon panier · {Object.values(cart).reduce((a,b) => a+b,0)}</Text><Text style={s.cartDockText}>→</Text></Pressable>}
        <View style={s.bottomNav}>{tabs.map((t,i) => <Pressable key={t} accessibilityRole="tab" accessibilityState={{selected:tab === t}} accessibilityLabel={t} onPress={() => setTab(t)} style={({pressed}) => [s.navItem,pressed && s.pressed]}>
          <View style={[s.navIcon,tab === t && s.navIconActive]}><Icon name={(['pill','heart','store','document','bag'] as const)[i]} size={21} color={tab === t ? '#FFFFFF' : '#59634E'}/>{t === 'Panier' && Object.keys(cart).length > 0 && <View style={s.cartDot}/>}</View>
          <Text numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.85} style={[s.navLabel,tab === t && s.navLabelActive]}>{(['Catalogue','Favoris','Pharmacies','Documents','Panier'] as const)[i]}</Text>
        </Pressable>)}</View>
      </View>}
      {focused && purchaseOffer && <PurchaseDialog key={purchaseOffer.product_id} product={purchaseOffer}
        busy={busy} error={message}
        onClose={() => { if (!lock.current) { setPurchaseId(null); setMessage(''); } }}
        onConfirm={quantity => checkout({ offer: purchaseOffer, quantity })}/>}
    </SafeAreaView>
  );
}

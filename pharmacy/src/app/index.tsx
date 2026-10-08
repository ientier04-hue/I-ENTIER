import React, { useCallback, useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  AppState,
  Linking,
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
import { Session } from "@supabase/supabase-js";
import { db, supabase, ensureGuestSession } from "../api";
import { router, useLocalSearchParams } from "expo-router";
import { Cart, Product, changeQuantity, orderLines } from "../cart";
import { styles as s } from "../theme";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { MedicineCard } from "../components/MedicineCard";
import { groupMedicineOffers, medicineKey, medicineOfferKey } from "../catalog";
import { compareDistance, distanceKm, type Coordinates, type Pharmacy, type PharmacyRating } from "../pharmacies";
import { PharmacyCard } from "../components/PharmacyCard";
import { OrderProgress, Icon } from "../components/Overview";

type Prescription = {
  prescription_id: string;
  file_name: string;
  storage_path: string;
  transcription?: string;
  doctor_name_snapshot: string;
};
type Order = {
  order_id: string;
  order_number: string;
  status: string;
  total_amount: number;
};
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
export default function App() {
  const { width } = useWindowDimensions();
  const desktop = width >= 850;
  const params = useLocalSearchParams<{ tab?: string; q?: string; view?: string }>();
  const tab: Tab = params.tab === "Commandes"
    ? "Panier"
    : tabs.includes(params.tab as Tab)
      ? (params.tab as Tab)
      : "Médicaments";
  const purchaseView = params.tab === "Commandes" || params.view === "orders"
    ? "orders"
    : "cart";
  const scroll = useRef<ScrollView>(null);
  const setTab = (value: Tab | "Commandes") => {
    router.setParams({
      tab: value === "Commandes" ? "Panier" : value,
      view: value === "Commandes" ? "orders" : value === "Panier" ? "cart" : params.view,
    });
    setMessage('');
  };
  useEffect(() => { scroll.current?.scrollTo({ y: 0, animated: false }); }, [tab, purchaseView]);
  const [query, setQuery] = useState(params.q || "");
  const [pharmacyQuery, setPharmacyQuery] = useState('');
  const [pharmacyFilter, setPharmacyFilter] = useState<string | null>(null);
  const [pharmacyMode, setPharmacyMode] = useState<'all' | 'nearby' | 'favorites'>('all');
  const [position, setPosition] = useState<Coordinates | null>(null);
  const [locating, setLocating] = useState(false);
  const locationRequest = useRef(false);
  const [pharmacyFavorites, setPharmacyFavorites] = useState<string[]>([]);
  const [pharmacyFavoritesOwner, setPharmacyFavoritesOwner] = useState<string | null>(null);
  const [favorites, setFavorites] = useState<string[]>([]);
  const [favoritesOwner, setFavoritesOwner] = useState<string | null>(null);
  const [category, setCategory] = useState("Tous");
  const [products, setProducts] = useState<Product[]>([]);
  const [pharmacies, setPharmacies] = useState<Pharmacy[]>([]);
  const [ratings, setRatings] = useState<Record<string, PharmacyRating>>({});
  const [prescriptions, setPrescriptions] = useState<Prescription[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [cart, setCart] = useState<Cart>({});
  const [note, setNote] = useState("");
  const [session, setSession] = useState<Session | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const lock = useRef(false);
  const previousUser = useRef<string | undefined>(undefined);
  const uid = session?.user.id;
  useEffect(() => {
    let active = true;
    if (uid) AsyncStorage.getItem(`medicine-favorites:${uid}`).then(value => {
      if (!active) return;
      const parsed: unknown = value ? JSON.parse(value) : [];
      setFavorites(Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === 'string') : []);
      setFavoritesOwner(uid);
    }).catch(() => { if (active) setFavoritesOwner(uid); });
    return () => { active = false; };
  }, [uid]);
  useEffect(() => {
    if (uid && favoritesOwner === uid) AsyncStorage.setItem(`medicine-favorites:${uid}`, JSON.stringify(favorites)).catch(() => setMessage('Impossible de conserver les favoris.'));
  }, [favorites, favoritesOwner, uid]);
  const toggleFavorite = (variants: Product[]) => {
    if (favoritesOwner !== uid) return;
    const keys = products.filter(p => medicineOfferKey(p) === medicineOfferKey(variants[0])).map(medicineKey);
    setFavorites(current => keys.some(key => current.includes(key))
      ? current.filter(id => !keys.includes(id)) : [...current, ...new Set(keys)]);
  };
  useEffect(() => {
    let active = true;
    if (uid) AsyncStorage.getItem(`pharmacy-favorites:${uid}`).then(value => {
      if (!active) return;
      const parsed: unknown = value ? JSON.parse(value) : [];
      setPharmacyFavorites(Array.isArray(parsed) ? parsed.filter((id): id is string => typeof id === 'string') : []);
      setPharmacyFavoritesOwner(uid);
    }).catch(() => { if (active) { setPharmacyFavorites([]); setPharmacyFavoritesOwner(uid); } });
    return () => { active = false; };
  }, [uid]);
  useEffect(() => {
    if (uid && pharmacyFavoritesOwner === uid) AsyncStorage.setItem(`pharmacy-favorites:${uid}`, JSON.stringify(pharmacyFavorites)).catch(() => setMessage('Impossible de conserver les pharmacies favorites.'));
  }, [pharmacyFavorites, pharmacyFavoritesOwner, uid]);
  const togglePharmacyFavorite = (id: string) => {
    if (!uid || pharmacyFavoritesOwner !== uid) return;
    setPharmacyFavorites(current => current.includes(id) ? current.filter(value => value !== id) : [...current, id]);
  };
  async function locate() {
    if (locationRequest.current) return;
    locationRequest.current = true;
    setLocating(true);
    setMessage('');
    try {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (permission.status !== 'granted') throw new Error('Localisation non autorisée. Vous pouvez choisir une pharmacie ou vos favoris.');
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        const current = await Promise.race([
          Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced }),
          new Promise<never>((_, reject) => { timeout = setTimeout(() => reject(new Error('Position indisponible. Réessayez.')), 15000); }),
        ]);
        setPosition(current.coords);
        setPharmacyMode('nearby');
        setPharmacyFilter(null);
      } finally { clearTimeout(timeout); }
    } catch (error) {
      setMessage(error instanceof Error && /Localisation non autorisée|Position indisponible/.test(error.message) ? error.message : 'Position indisponible. Réessayez.');
    } finally {
      locationRequest.current = false;
      setLocating(false);
    }
  }
  async function run(task: () => Promise<void>) {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setMessage("");
    try {
      await task();
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Une erreur est survenue. Réessayez.",
      );
    } finally {
      lock.current = false;
      setBusy(false);
    }
  }
  const loadRatings = useCallback(async (ids: string[]) => {
    if (!ids.length || !uid) return;
    const { data, error } = await db.rpc('pharmacy_rating_summaries', { p_pharmacy_ids: ids });
    if (error) throw new Error('Impossible de charger les notes des pharmacies.');
    if (previousUser.current !== uid) return;
    setRatings(current => ({ ...current, ...Object.fromEntries((data as PharmacyRating[] || []).map(rating => [rating.pharmacy_id, rating])) }));
  }, [uid, setRatings]);
  async function ratePharmacy(pharmacyId: string, rating: number) {
    if (!uid || !Number.isInteger(rating) || rating < 1 || rating > 5) throw new Error('Choisissez une note de 1 à 5.');
    const { error } = await db.from('pharmacy_ratings').upsert({ pharmacy_id: pharmacyId, user_id: uid, rating }, { onConflict: 'pharmacy_id,user_id' });
    if (error) throw new Error('Impossible d’enregistrer la note. Réessayez.');
    try { await loadRatings([pharmacyId]); }
    catch { setMessage('Note enregistrée. Actualisez pour voir la moyenne.'); }
  }
  const refresh = useCallback(async () => {
    try {
      const [catalog, locations] = await Promise.all([
        db.from("v_public_medicine_products").select("*").order("name"),
        db
          .from("pharmacies")
          .select("pharmacy_id,display_name,address,phone,opening_hours,latitude,longitude,delivery_available,photo_url")
          .eq("public_enabled", true)
          .eq("operational_status", "active")
          .order("display_name"),
      ]);
      if (catalog.error || locations.error)
        throw new Error("Impossible de charger la pharmacie.");
      if (previousUser.current !== uid) return;
      setProducts(catalog.data || []);
      setPharmacies(locations.data || []);
      await loadRatings((locations.data || []).map(p => p.pharmacy_id));
    } finally {
      setLoading(false);
    }
  }, [loadRatings, uid, setProducts, setPharmacies, setLoading]);
  useEffect(() => {
    const updateSession = (value: Session | null) => {
      if (previousUser.current !== value?.user.id) {
        setFavorites([]); setFavoritesOwner(null);
        setPharmacyFavorites([]); setPharmacyFavoritesOwner(null);
        setPharmacyMode('all'); setPharmacyFilter(null); setPosition(null);
        setCart({}); setPrescriptions([]); setOrders([]);
        setProducts([]); setPharmacies([]); setRatings({}); setNote(''); setMessage('');
        setLoading(Boolean(value));
        previousUser.current = value?.user.id;
      }
      setSession(value);
    };
    ensureGuestSession().then(updateSession).catch(() => {
      setLoading(false);
      setMessage('Pharmacie indisponible. Réessayez.');
    });
    const { data } = supabase.auth.onAuthStateChange((_event, value) => updateSession(value));
    const appState = AppState.addEventListener("change", (state) => {
      if (state === "active") supabase.auth.startAutoRefresh();
      else supabase.auth.stopAutoRefresh();
    });
    return () => {
      data.subscription.unsubscribe();
      appState.remove();
    };
  }, []);
  useEffect(() => {
    if (uid) refresh().catch((e) => setMessage(e.message));
  }, [uid, refresh]);
  useEffect(() => {
    let active = true;
    if (uid)
      Promise.resolve(
        db
          .from("patient_profiles")
          .upsert(
            { patient_id: uid },
            { onConflict: "patient_id", ignoreDuplicates: true },
          ),
      )
        .then(({ error }) => {
          if (error) throw new Error("Impossible de préparer votre dossier.");
          return Promise.all([
            db
              .from("prescriptions")
              .select(
                "prescription_id,file_name,storage_path,doctor_name_snapshot,transcription",
              )
              .eq("patient_id", uid)
              .eq("status", "available")
              .order("created_at", { ascending: false }),
            db
              .from("pharmacy_orders")
              .select("order_id,order_number,status,total_amount")
              .eq("patient_id", uid)
              .order("created_at", { ascending: false }),
          ]);
        })
        .then(([rx, history]) => {
          if (!active) return;
          if (rx.error || history.error) {
            setMessage("Impossible de charger votre dossier.");
            return;
          }
          setPrescriptions(rx.data || []);
          setOrders(history.data || []);
        })
        .catch((e) => {
          if (active) setMessage(e.message);
        });
    return () => {
      active = false;
    };
  }, [uid, tab, purchaseView]);
  function adjust(p: Product, delta: number) {
    try {
      setCart(changeQuantity(cart, p, delta, products));
      setMessage("");
      return null;
    } catch (e) {
      setMessage((e as Error).message);
      return (e as Error).message;
    }
  }
  async function upload() {
    if (!uid) throw new Error('Veuillez réessayer dans un instant.');
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ["images"],
      quality: 0.8,
      base64: true,
    });
    if (result.canceled) return;
    const file = result.assets[0];
    const bytes = file.base64
      ? Uint8Array.from(atob(file.base64), (c) => c.charCodeAt(0)).buffer
      : await (await fetch(file.uri)).arrayBuffer();
    if (bytes.byteLength > 10 * 1024 * 1024)
      throw new Error("Image trop volumineuse (10 Mo maximum).");
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
      await supabase.storage.from("prescriptions").remove([path]);
      throw new Error("Impossible d’enregistrer l’ordonnance.");
    }
    setPrescriptions((previous) => [
      { ...record, doctor_name_snapshot: "" },
      ...previous,
    ]);
    setMessage("Ordonnance ajoutée.");
  }
  const selected = products.filter((p) => cart[p.product_id]);
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
  const visible = products.filter(
    (p) =>
      matchesPharmacyMode(p.pharmacy_id) &&
      (!pharmacyFilter || p.pharmacy_id === pharmacyFilter) &&
      (category === "Tous" || (p.category || "Autres") === category) &&
      normalized(`${p.name} ${p.active_ingredient} ${p.pharmacy_name} ${p.laboratory || ""} ${p.strength || ""} ${p.dosage_form || ""}`).includes(normalized(query)),
  );
  const groups = groupMedicineOffers([...visible].sort((a, b) => comparePharmacies(a.pharmacy_id, b.pharmacy_id)));
  const favoriteGroups = groupMedicineOffers(products).filter(group => group.some(p => favorites.includes(medicineKey(p))));
  const renderMedicine = (variants: Product[], inCart = false) => <MedicineCard
    key={inCart ? variants[0].product_id : medicineOfferKey(variants[0])}
    pharmacies={pharmacyById}
    distances={distances}
    pharmacyFavorites={pharmacyFavorites}
    pharmacyFavoritesReady={!!uid && pharmacyFavoritesOwner === uid}
    onPharmacyFavorite={togglePharmacyFavorite}
    variants={variants} cart={cart} busy={busy} inCart={inCart}
    favorite={products.some(p => medicineOfferKey(p) === medicineOfferKey(variants[0]) && favorites.includes(medicineKey(p)))}
    onFavorite={() => toggleFavorite(variants)} onAdjust={adjust}
  />;
  const pharmacyFilters = <View style={s.pharmacyFilters}>{([
    { value: 'all', label: 'Toutes', icon: 'store' },
    { value: 'nearby', label: locating ? 'Localisation…' : 'À proximité', icon: 'pin' },
    { value: 'favorites', label: 'Mes pharmacies', icon: 'star' },
  ] as const).map(item => <Pressable key={item.value} accessibilityRole="button" accessibilityState={{ selected: pharmacyMode === item.value, disabled: locating }} disabled={locating} onPress={() => {
    if (item.value === 'nearby') { void locate(); return; }
    setPharmacyMode(item.value); setPharmacyFilter(null); setMessage('');
  }} style={[s.pharmacyChip, pharmacyMode === item.value && s.pharmacyChipActive]}>
    <Icon name={item.icon} size={16} color={pharmacyMode === item.value ? '#F5F8EF' : '#63764D'}/>
    <Text style={[s.pharmacyChipText, pharmacyMode === item.value && s.pharmacyChipTextActive]}>{item.label}</Text>
  </Pressable>)}</View>;
  return (
    <SafeAreaView style={s.root}>
      <StatusBar style="dark" />
      <ScrollView
        ref={scroll}
        contentContainerStyle={[s.page, desktop && s.pageWide]}
        keyboardShouldPersistTaps="handled"
      >
        <View style={s.header}>
          <View style={s.brand}>
            <Emblem/>
            <View>
              <Text style={s.title}>Pharmacie</Text>
              <Text style={s.brandCaption}>I-ENTIER</Text>
            </View>
          </View>
          <Button
            title={`Panier · ${Object.values(cart).reduce((a, b) => a + b, 0)}`}
            onPress={() => setTab("Panier")}
          />
        </View>
        {desktop && <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={s.tabs}
        >
          {tabs.map((t) => (
            <Pressable
              accessibilityRole="tab"
              accessibilityState={{ selected: tab === t }}
              key={t}
              onPress={() => {
                setTab(t);
                setMessage("");
              }}
              style={[s.tab, tab === t && s.activeTab]}
            >
              <Text style={[s.tabText, tab === t && s.activeTabText]}>
                {t}
              </Text>
            </Pressable>
          ))}
        </ScrollView>}
        {!!message && (
          <Text accessibilityRole="alert" style={s.message}>
            {message}
          </Text>
        )}
        <>
            {tab === "Médicaments" && (
              <>
                <View style={{flexDirection:"row",alignItems:"center",gap:10}}><View style={[s.searchRow,{flex:1}]}><TextInput
                  accessibilityLabel="Rechercher un médicament" placeholder="Rechercher un médicament…"
                  value={query} onChangeText={setQuery} style={[s.input, s.searchInput]} returnKeyType="search"
                />{!!query && <Pressable accessibilityRole="button" accessibilityLabel="Effacer la recherche" onPress={() => setQuery('')} style={s.clearSearch}><Text style={s.clearText}>×</Text></Pressable>}</View>
                  <Pressable accessibilityRole="button" accessibilityLabel="Scanner une ordonnance" onPress={() => router.push('/scan')} style={s.scanButton}><Icon name="scan" color="#4F6D2D" size={25}/></Pressable>
                </View>
                {pharmacyFilters}
                {!query && !pharmacyFilter && pharmacyMode === 'all' && <Pressable accessibilityRole="button" accessibilityLabel="Voir les médicaments Laboratoires 4C" onPress={() => {setQuery('Laboratoires 4C');setCategory('Tous');}} style={s.catalogBanner}>
                  <View style={{flex:1,gap:12}}><Text style={s.eyebrow}>LABORATOIRES 4C</Text><Text style={s.heroTitle}>Votre santé,
à portée de main.</Text><View style={s.bannerAction}><Text style={s.bannerActionText}>Découvrir  ↗</Text></View></View>
                  <View style={s.bannerIcon}><Icon name="pill" color="#709645" size={72}/></View>
                </Pressable>}
                {!!filteredPharmacy && <Button title={`${filteredPharmacy.display_name}  ×`} secondary onPress={() => setPharmacyFilter(null)}/>}
                <Text style={s.heading}>Catégories</Text>
                <ScrollView
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  style={s.tabs}
                >
                  {[
                    "Tous",
                    ...new Set(products.map((p) => p.category || "Autres")),
                  ].map((c) => (
                    <Button
                      key={c}
                      title={c}
                      secondary={c !== category}
                      onPress={() => setCategory(c)}
                    />
                  ))}
                </ScrollView>
                <View style={s.header}>
                  <Text style={s.heading}>{groups.length} médicament{groups.length > 1 ? "s" : ""}</Text>
                  <Button
                    title="Actualiser"
                    secondary
                    disabled={busy}
                    onPress={() => run(async () => { await ensureGuestSession(); await refresh(); })}
                  />
                </View>
                {loading ? (
                  <ActivityIndicator color="#242C26" />
                ) : (
                  <View style={s.grid}>
                    {groups.map(group => renderMedicine(group))}
                  </View>
                )}
                {!loading && !visible.length && (
                  <View style={s.card}><Text style={s.heading}>{pharmacyMode === 'favorites' ? 'Aucun médicament dans vos pharmacies favorites' : query || pharmacyFilter || category !== 'Tous' ? 'Aucun résultat' : 'Aucun médicament disponible'}</Text>{(!!query || !!pharmacyFilter || category !== 'Tous' || pharmacyMode !== 'all') && <Button title="Réinitialiser les filtres" secondary onPress={() => {setQuery('');setCategory('Tous');setPharmacyFilter(null);setPharmacyMode('all');}}/>}</View>
                )}
              </>
            )}
            {tab === "Favoris" && <>
              <Text style={s.heading}>Mes favoris</Text>
              <View style={s.grid}>{favoriteGroups.map(group => renderMedicine(group))}</View>
              {!favoriteGroups.length && <Text style={s.empty}>Aucun favori pour le moment.</Text>}
            </>}
            {tab === "Pharmacies" && (
              <>
                <View style={s.header}><Text style={s.heading}>Les pharmacies</Text><Text style={s.muted}>{loading ? '…' : visiblePharmacies.length}</Text></View>
                <View style={s.searchRow}><TextInput style={[s.input,s.searchInput]} accessibilityLabel="Rechercher une pharmacie" placeholder="Nom, ville ou quartier" value={pharmacyQuery} onChangeText={setPharmacyQuery} returnKeyType="search"/>{!!pharmacyQuery && <Pressable style={s.clearSearch} accessibilityRole="button" accessibilityLabel="Effacer la recherche de pharmacie" onPress={() => setPharmacyQuery('')}><Text style={s.clearText}>×</Text></Pressable>}</View>
                {pharmacyFilters}
                {loading && <ActivityIndicator color="#202923"/>}
                <View style={s.grid}>{visiblePharmacies.map((p) => <PharmacyCard key={p.pharmacy_id}
                  pharmacy={p} distance={distances.get(p.pharmacy_id) ?? null}
                  favorite={pharmacyFavorites.includes(p.pharmacy_id)} favoriteReady={!!uid && pharmacyFavoritesOwner === uid}
                  onFavorite={() => togglePharmacyFavorite(p.pharmacy_id)} rating={ratings[p.pharmacy_id]}
                  onRate={value => ratePharmacy(p.pharmacy_id, value)} busy={busy}
                  onOpen={() => {setPharmacyFilter(p.pharmacy_id);setPharmacyMode('all');setQuery('');setCategory('Tous');setTab('Médicaments');}}
                  onDirections={() => run(async () => {await Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(p.address + ' ' + p.display_name)}`);})}
                  onCall={() => run(async () => {await Linking.openURL(`tel:${p.phone.replace(/[^+0-9]/g, '')}`);})}
                />)}</View>
                {!loading && !visiblePharmacies.length && <View style={s.card}><Text style={s.heading}>{pharmacyMode === 'favorites' ? 'Aucune pharmacie favorite' : pharmacyQuery ? 'Aucune pharmacie trouvée' : 'Aucune pharmacie disponible'}</Text>{!!pharmacyQuery && <Button title="Effacer la recherche" secondary onPress={() => setPharmacyQuery('')}/>}</View>}
              </>
            )}
            {tab === "Ordonnances" && (
                <>
                  <View style={s.header}>
                    <Text style={s.heading}>Mes ordonnances</Text>
                    <Button
                      title="Ajouter"
                      disabled={busy}
                      onPress={() => run(upload)}
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
                            run(async () => {
                              const [bucket, ...parts] =
                                p.storage_path.split("/");
                              const { data, error } = await supabase.storage
                                .from(bucket)
                                .createSignedUrl(parts.join("/"), 60);
                              if (error)
                                throw new Error("Document indisponible.");
                              await Linking.openURL(data.signedUrl);
                            })
                          }
                        />
                      )}
                    </View>
                  ))}
                  {!prescriptions.length && (
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
                  {!orders.length && (
                    <Text style={s.empty}>Aucune commande.</Text>
                  )}
                </>
              )}
            {tab === "Panier" && purchaseView === "cart" && (
              <>
                <Text style={s.heading}>Mon panier</Text>
                {selected.map(p => renderMedicine([p], true))}
                {!selected.length ? (
                  <View style={s.card}><Text style={s.heading}>Votre panier est vide.</Text><Button title="Parcourir les médicaments" onPress={() => setTab('Médicaments')}/></View>
                ) : (
                  <View style={s.card}>
                    <Text style={s.price}>
                      {money(total, selected[0]?.currency)}
                    </Text>
                    <TextInput
                      placeholder="Note à la pharmacie"
                      accessibilityLabel="Note à la pharmacie"
                      maxLength={500}
                      value={note}
                      onChangeText={setNote}
                      style={s.input}
                    />
                    <Button
                      title={
                        busy ? "Envoi…" : "Commander"
                      }
                      disabled={busy}
                      onPress={() => {
                        if (!uid) {
                          setMessage('Veuillez réessayer dans un instant.');
                          return;
                        }
                        run(async () => {
                          const lines = orderLines(
                            cart,
                            products,
                          );
                          const { data, error } = await db.rpc(
                            "place_pharmacy_order",
                            {
                              p_pharmacy_id: selected[0].pharmacy_id,
                              p_items: lines,
                              p_prescription_id: null,
                              p_customer_name: "",
                              p_customer_phone: "",
                              p_note: note.trim(),
                            },
                          );
                          if (error)
                            throw new Error(
                              "Commande refusée. Vérifiez la disponibilité des produits.",
                            );
                          setCart({});
                          setNote("");
                          setTab("Commandes");
                          setMessage(`Commande ${data || ""} transmise.`);
                        });
                      }}
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
        </Pressable>)}</View>
      </View>}
    </SafeAreaView>
  );
}

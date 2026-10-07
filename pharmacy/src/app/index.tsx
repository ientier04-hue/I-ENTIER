import React, { useEffect, useRef, useState } from "react";
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
import { Session } from "@supabase/supabase-js";
import { db, supabase, ensureGuestSession } from "../api";
import { router, useLocalSearchParams } from "expo-router";
import { Cart, Product, changeQuantity, orderLines } from "../cart";
import { styles as s } from "../theme";
import { MedicalArtwork } from "../components/MedicalArtwork";
import { QuickAccess, CatalogCharts, OrderProgress, StockBadge, Icon } from "../components/Overview";

type Prescription = {
  prescription_id: string;
  file_name: string;
  storage_path: string;
  transcription?: string;
  doctor_name_snapshot: string;
};
type Pharmacy = {
  pharmacy_id: string;
  display_name: string;
  address: string;
  phone: string;
  opening_hours: string;
};
type Order = {
  order_id: string;
  order_number: string;
  status: string;
  total_amount: number;
};
const tabs = [
  "Médicaments",
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
function Capsule({ compact = false }: { compact?: boolean }) {
  const { width } = useWindowDimensions();
  return <View pointerEvents="none" accessible={false} style={[compact ? s.smallArt : s.art, !compact && width < 380 && s.narrowArt]}>
    <View style={[s.orbit, compact && s.smallOrbit]} />
    <View style={[s.capsule, compact && s.smallCapsule]}>
      <View style={s.capsuleTop}><View style={s.capsuleShine}/></View>
      <View style={s.capsuleBottom}><View style={s.capsuleMark}/></View>
    </View>
    {!compact && <View style={s.artSpark}><Text style={s.artSparkText}>✳</Text></View>}
  </View>;
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
  const [showCharts, setShowCharts] = useState(false);
  const [category, setCategory] = useState("Tous");
  const [products, setProducts] = useState<Product[]>([]);
  const [pharmacies, setPharmacies] = useState<Pharmacy[]>([]);
  const [prescriptions, setPrescriptions] = useState<Prescription[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [cart, setCart] = useState<Cart>({});
  const [prescriptionId, setPrescriptionId] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [session, setSession] = useState<Session | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const lock = useRef(false);
  const previousUser = useRef<string | undefined>(undefined);
  const uid = session?.user.id;
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
  async function refresh() {
    try {
      const [catalog, locations] = await Promise.all([
        db.from("v_public_pharmacy_products").select("*").order("name"),
        db
          .from("pharmacies")
          .select("pharmacy_id,display_name,address,phone,opening_hours")
          .eq("public_enabled", true)
          .eq("operational_status", "active")
          .order("display_name"),
      ]);
      if (catalog.error || locations.error)
        throw new Error("Impossible de charger la pharmacie.");
      setProducts(catalog.data || []);
      setPharmacies(locations.data || []);
    } finally {
      setLoading(false);
    }
  }
  useEffect(() => {
    const updateSession = (value: Session | null) => {
      if (previousUser.current !== value?.user.id) {
        setCart({}); setPrescriptionId(null); setPrescriptions([]); setOrders([]);
        setProducts([]); setPharmacies([]); setNote(''); setMessage('');
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

  }, [uid]);
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
    } catch (e) {
      setMessage((e as Error).message);
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
  const visiblePharmacies = pharmacies.filter(p => normalized(`${p.display_name} ${p.address}`).includes(normalized(pharmacyQuery)));
  const filteredPharmacy = pharmacies.find(p => p.pharmacy_id === pharmacyFilter);
  const visible = products.filter(
    (p) =>
      (!pharmacyFilter || p.pharmacy_id === pharmacyFilter) &&
      (category === "Tous" || (p.category || "Autres") === category) &&
      normalized(`${p.name} ${p.active_ingredient} ${p.pharmacy_name}`).includes(normalized(query)),
  );
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
                <View style={s.hero}>
                  <Text style={s.eyebrow}>VOTRE PHARMACIE</Text>
                  <Text style={s.heroTitle}>Prenez soin de vous.</Text>
                  <View style={s.heroArt}><MedicalArtwork/></View>
                  <View style={{flexDirection:"row",alignItems:"center",gap:10}}><View style={[s.searchRow,{flex:1}]}><TextInput
                    accessibilityLabel="Rechercher un médicament"
                    placeholder="Rechercher un médicament"
                    value={query}
                    onChangeText={setQuery}
                    style={[s.input, s.searchInput]}
                    returnKeyType="search"
                  />{!!query && <Pressable accessibilityRole="button" accessibilityLabel="Effacer la recherche" onPress={() => setQuery('')} style={s.clearSearch}><Text style={s.clearText}>×</Text></Pressable>}</View><Pressable accessibilityRole="button" accessibilityLabel="Scanner une ordonnance" onPress={() => router.push('/scan')} style={({pressed}) => [{width:52,height:52,borderRadius:12,backgroundColor:'#1C2028',alignItems:'center',justifyContent:'center'},pressed && s.pressed]}><Icon name="scan" color="#00BFA9" size={25}/></Pressable></View>
                </View>
                {!!filteredPharmacy && <Button title={`${filteredPharmacy.display_name}  ×`} secondary onPress={() => setPharmacyFilter(null)}/>}
                <QuickAccess pharmacies={pharmacies.length} prescriptions={prescriptions.length} orders={orders.length} onOpen={setTab}/>
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
                  <Text style={s.heading}>{visible.length} produit{visible.length > 1 ? "s" : ""}</Text>
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
                    {visible.map((p) => (
                      <View key={p.product_id} style={[s.card, s.product]}>
                        <View style={s.productArt}>
                          <StockBadge quantity={Number(p.stock_quantity)}/>
                          <Capsule compact/>
                        </View>
                        <Text style={s.muted}>{p.pharmacy_name}</Text>
                        <Text style={s.heading}>{p.name}</Text>
                        <Text style={s.muted}>
                          {p.active_ingredient} {p.pack_size}
                        </Text>
                        {p.requires_prescription && (
                          <Text style={s.badge}>Sur ordonnance</Text>
                        )}
                        <Text style={s.price}>
                          {money(p.selling_price, p.currency)}
                        </Text>
                        <Button
                          title={
                            cart[p.product_id]
                              ? `Ajouter · ${cart[p.product_id]}`
                              : "Ajouter"
                          }
                          disabled={busy}
                          onPress={() => adjust(p, 1)}
                        />
                      </View>
                    ))}
                  </View>
                )}
                {!loading && !query && !pharmacyFilter && <><Pressable accessibilityRole="button" accessibilityState={{expanded:showCharts}} onPress={() => setShowCharts(!showCharts)} style={s.chartToggle}><Text style={s.heading}>Explorer le catalogue</Text><Text style={s.clearText}>{showCharts ? '−' : '+'}</Text></Pressable>{showCharts && <CatalogCharts products={products} category={category} onCategory={value => {setCategory(value); scroll.current?.scrollTo({y:0,animated:true}); }}/>}</>}
                {!loading && !visible.length && (
                  <View style={s.card}><Text style={s.heading}>{query || pharmacyFilter || category !== 'Tous' ? 'Aucun résultat' : 'Aucun médicament disponible'}</Text>{(!!query || !!pharmacyFilter || category !== 'Tous') && <Button title="Réinitialiser les filtres" secondary onPress={() => {setQuery('');setCategory('Tous');setPharmacyFilter(null);}}/>}</View>
                )}
              </>
            )}
            {tab === "Pharmacies" && (
              <>
                <View style={s.header}><Text style={s.heading}>Les pharmacies</Text><Text style={s.muted}>{loading ? '…' : visiblePharmacies.length}</Text></View>
                <View style={s.searchRow}><TextInput style={[s.input,s.searchInput]} accessibilityLabel="Rechercher une pharmacie" placeholder="Nom, ville ou quartier" value={pharmacyQuery} onChangeText={setPharmacyQuery} returnKeyType="search"/>{!!pharmacyQuery && <Pressable style={s.clearSearch} accessibilityRole="button" accessibilityLabel="Effacer la recherche de pharmacie" onPress={() => setPharmacyQuery('')}><Text style={s.clearText}>×</Text></Pressable>}</View>
                {loading && <ActivityIndicator color="#202923"/>}
                {visiblePharmacies.map((p) => (
                  <View key={p.pharmacy_id} style={s.card}>
                    <View style={s.header}><View style={s.facilityIcon}><Icon name="store" size={26}/></View><Text style={s.facilityInitial}>{p.display_name.slice(0,2).toUpperCase()}</Text></View>
                    <Text style={s.heading}>{p.display_name}</Text>
                    <Text>{p.address}</Text>
                    <Text style={s.muted}>{p.opening_hours}</Text>
                    <Button title="Voir les médicaments" onPress={() => {setPharmacyFilter(p.pharmacy_id);setQuery('');setCategory('Tous');setTab('Médicaments');}}/>
                    {!!p.address && <Button title="Itinéraire ↗" secondary onPress={() => run(async () => {await Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(p.address + ' ' + p.display_name)}`);})}/>}
                    <Button
                      title="Appeler"
                      disabled={!p.phone || busy}
                      secondary
                      onPress={() =>
                        run(async () => {
                          await Linking.openURL(
                            `tel:${p.phone.replace(/[^+0-9]/g, "")}`,
                          );
                        })
                      }
                    />
                  </View>
                ))}
                {!loading && !visiblePharmacies.length && <View style={s.card}><Text style={s.heading}>{pharmacyQuery ? 'Aucune pharmacie trouvée' : 'Aucune pharmacie disponible'}</Text>{!!pharmacyQuery && <Button title="Effacer la recherche" secondary onPress={() => setPharmacyQuery('')}/>}</View>}
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
                {selected.map((p) => (
                  <View style={s.card} key={p.product_id}>
                    <Text style={s.heading}>{p.name}</Text>
                    <Text>{money(p.selling_price, p.currency)}</Text>
                    <View style={s.row}>
                      <Button
                        title="−"
                        secondary
                        disabled={busy}
                        onPress={() => adjust(p, -1)}
                      />
                      <Text>{cart[p.product_id]}</Text>
                      <Button
                        title="+"
                        secondary
                        disabled={busy}
                        onPress={() => adjust(p, 1)}
                      />
                    </View>
                  </View>
                ))}
                {!selected.length ? (
                  <View style={s.card}><Text style={s.heading}>Votre panier est vide.</Text><Button title="Parcourir les médicaments" onPress={() => setTab('Médicaments')}/></View>
                ) : (
                  <View style={s.card}>
                    <Text style={s.price}>
                      {money(total, selected[0]?.currency)}
                    </Text>
                    {selected.some((p) => p.requires_prescription) && (
                      <>
                        <Text style={s.heading}>Ordonnance</Text>
                        {prescriptions.map((p) => (
                          <Button
                            key={p.prescription_id}
                            title={`${p.prescription_id === prescriptionId ? "✓ " : ""}${p.file_name || "Ordonnance"}`}
                            secondary
                            onPress={() => setPrescriptionId(p.prescription_id)}
                          />
                        ))}
                        <Button
                          title="Ajouter une ordonnance"
                          secondary
                          disabled={busy}
                          onPress={() => run(upload)}
                        />
                      </>
                    )}
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
                            prescriptionId,
                          );
                          const { data, error } = await db.rpc(
                            "place_pharmacy_order",
                            {
                              p_pharmacy_id: selected[0].pharmacy_id,
                              p_items: lines,
                              p_prescription_id: prescriptionId,
                              p_customer_name: "",
                              p_customer_phone: "",
                              p_note: note.trim(),
                            },
                          );
                          if (error)
                            throw new Error(
                              "Commande refusée. Vérifiez le stock et l’ordonnance.",
                            );
                          setCart({});
                          setNote("");
                          setPrescriptionId(null);
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
          <View style={[s.navIcon,tab === t && s.navIconActive]}><Icon name={(['pill','store','document','bag'] as const)[i]} size={21} color={tab === t ? '#00BFA9' : '#1C2028'}/>{t === 'Panier' && Object.keys(cart).length > 0 && <View style={s.cartDot}/>}</View>
        </Pressable>)}</View>
      </View>}
    </SafeAreaView>
  );
}

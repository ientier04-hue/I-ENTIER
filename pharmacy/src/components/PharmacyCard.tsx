import React, { useRef, useState } from 'react';
import { ActivityIndicator, Image, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Path, Rect } from 'react-native-svg';
import { formatDistance, type Pharmacy, type PharmacyRating } from '../pharmacies';
import { Icon } from './Overview';

function PharmacyPlaceholder() {
  return <Svg width="100%" height="100%" viewBox="0 0 400 240" preserveAspectRatio="xMidYMid slice" accessibilityLabel="Illustration de pharmacie">
    <Rect width="400" height="240" fill="#E4EDD9"/>
    <Circle cx="365" cy="25" r="110" fill="#D4E3BD"/>
    <Path d="M0 210h400v30H0z" fill="#CFDABF"/>
    <Rect x="42" y="36" width="316" height="174" rx="5" fill="#F8FAF4"/>
    <Rect x="42" y="36" width="316" height="37" rx="5" fill="#789550"/>
    <Path d="M192 43h15v8h8v14h-8v8h-15v-8h-8V51h8z" fill="#F3F8E7"/>
    {[56, 270].map(x => <React.Fragment key={x}>
      <Rect x={x} y="87" width="74" height="102" fill="#D6E4CE"/>
      {[104, 134, 164].map((y, row) => <React.Fragment key={y}>
        {[0,1,2,3].map(i => <Rect key={i} x={x+7+i*16} y={y-11} width="10" height={row === 1 ? 20 : 15} rx="2" fill={['#F8FAF4','#96B58A','#C8AC73','#AEC8C3'][(i+row)%4]}/>)}
        <Path d={`M${x} ${y+10}h74`} stroke="#8AA57C" strokeWidth="3"/>
      </React.Fragment>)}
    </React.Fragment>)}
    <Rect x="146" y="82" width="108" height="128" fill="#6A8570"/>
    <Rect x="153" y="89" width="42" height="114" fill="#D7E8DE"/>
    <Rect x="204" y="89" width="43" height="114" fill="#C2D9CD"/>
    <Path d="m153 150 42-47M204 170l43-50" stroke="#EAF3EB" strokeWidth="9" opacity=".65"/>
    <Path d="M189 145v14M210 145v14" stroke="#6A8570" strokeWidth="3"/>
    <Rect x="28" y="188" width="28" height="24" rx="4" fill="#B5A68A"/>
    <Circle cx="42" cy="177" r="22" fill="#92AF73"/>
    <Circle cx="35" cy="162" r="14" fill="#A4BD8B"/>
  </Svg>;
}
function Stars({ value, size = 21 }: { value: number; size?: number }) {
  return <View style={st.stars}>{[0,1,2,3,4].map(i => <View key={i} style={{width:size,height:size}}>
    <Icon name="star" color="#E5B331" size={size}/>
    <View style={{position:'absolute',left:0,top:0,width:size*Math.max(0,Math.min(1,value-i)),height:size,overflow:'hidden'}}><Icon name="star" color="#E5B331" size={size} filled/></View>
  </View>)}</View>;
}
export function PharmacyCard({ pharmacy, distance, favorite, favoriteReady, onFavorite, rating, onRate, onOpen, onDirections, onCall, busy }: {
  pharmacy: Pharmacy; distance: number | null; favorite: boolean; favoriteReady: boolean;
  onFavorite: () => void; rating?: PharmacyRating; onRate: (value: number) => Promise<void>;
  onOpen: () => void; onDirections: () => void; onCall: () => void; busy: boolean;
}) {
  const [failedPhoto, setFailedPhoto] = useState<string | null>(null);
  const [rateOpen, setRateOpen] = useState(false);
  const [draft, setDraft] = useState(0);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const saveLock = useRef(false);
  const distanceLabel = formatDistance(distance);
  const closeRating = () => { if (!saveLock.current) setRateOpen(false); };
  const openRating = () => { setDraft(rating?.my_rating || 0); setError(''); setRateOpen(true); };
  async function save() {
    if (saveLock.current || draft < 1 || draft > 5) return;
    saveLock.current = true; setSaving(true); setError('');
    try { await onRate(draft); setRateOpen(false); }
    catch (e) { setError(e instanceof Error ? e.message : 'Impossible d’enregistrer la note.'); }
    finally { saveLock.current = false; setSaving(false); }
  }
  const average = Number(rating?.average_rating || 0);
  const count = Number(rating?.rating_count || 0);
  return <View style={st.card}>
    <View style={st.photo}>
      <Pressable accessibilityRole="button" accessibilityLabel={`Voir les médicaments de ${pharmacy.display_name}`} onPress={onOpen} style={StyleSheet.absoluteFill}>
        {pharmacy.photo_url && failedPhoto !== pharmacy.photo_url ? <Image source={{uri:pharmacy.photo_url}} resizeMode="cover" accessibilityLabel={pharmacy.display_name} style={st.image} onError={() => setFailedPhoto(pharmacy.photo_url || null)}/> : <PharmacyPlaceholder/>}
      </Pressable>
      <Pressable accessibilityRole="button" accessibilityLabel={`${favorite ? 'Retirer' : 'Ajouter'} ${pharmacy.display_name} ${favorite ? 'des' : 'aux'} favoris`} accessibilityState={{selected:favorite,disabled:!favoriteReady}} disabled={!favoriteReady} onPress={onFavorite} style={[st.bookmark, favorite && st.bookmarkActive]}><Icon name="bookmark" size={23} color={favorite ? '#526D34' : '#FFFFFF'} filled={favorite}/></Pressable>
    </View>
    <View style={st.body}>
      <Pressable accessibilityRole="button" onPress={onOpen}><Text style={st.name}>{pharmacy.display_name}</Text></Pressable>
      {!!pharmacy.address && <Text numberOfLines={2} style={st.address}>{pharmacy.address}</Text>}
      <View style={st.ratingRow}>
        <Pressable accessibilityRole="button" accessibilityLabel={count ? `Note ${average} sur 5, ${count} avis. Noter ${pharmacy.display_name}` : `Noter ${pharmacy.display_name}`} disabled={!rating} onPress={openRating} style={st.ratingButton}>
          <Stars value={average}/>
          <Text style={st.ratingText}>{!rating ? '—' : count ? <><Text style={st.ratingValue}>{average.toLocaleString('fr-FR',{maximumFractionDigits:1})}</Text> <Text style={st.count}>({count})</Text></> : 'Aucun avis'}</Text>
        </Pressable>
        <Pressable accessibilityRole="button" disabled={!rating} onPress={openRating} style={st.rateLink}><Text style={st.rateLinkText}>{rating?.my_rating ? 'Modifier' : 'Noter'}</Text></Pressable>
      </View>
      <View style={st.meta}>
        {distanceLabel && <View style={st.metaItem}><Icon name="pin" size={18} color="#8C9587"/><Text style={st.metaText}>≈ {distanceLabel}</Text></View>}
        {distanceLabel && pharmacy.delivery_available != null && <Text style={st.dot}>·</Text>}
        {pharmacy.delivery_available != null && <View style={st.metaItem}><Icon name={pharmacy.delivery_available ? 'truck' : 'truckOff'} size={20} color="#8C9587"/><Text style={st.metaText}>{pharmacy.delivery_available ? 'Livraison' : 'Retrait sur place'}</Text></View>}
      </View>
      {!!pharmacy.opening_hours && <Text style={st.hours}>{pharmacy.opening_hours}</Text>}
      <View style={st.actions}>
        <Pressable accessibilityRole="button" onPress={onOpen} style={st.catalog}><Text style={st.catalogText}>Voir les médicaments</Text><Text style={st.arrow}>↗</Text></Pressable>
        <Pressable accessibilityRole="button" accessibilityLabel={`Itinéraire vers ${pharmacy.display_name}`} disabled={busy || !pharmacy.address} onPress={onDirections} style={[st.actionIcon,!pharmacy.address && st.disabled]}><Icon name="directions" size={21} color="#63764D"/></Pressable>
        <Pressable accessibilityRole="button" accessibilityLabel={`Appeler ${pharmacy.display_name}`} disabled={busy || !pharmacy.phone} onPress={onCall} style={[st.actionIcon,!pharmacy.phone && st.disabled]}><Icon name="phone" size={19} color="#63764D"/></Pressable>
      </View>
    </View>
    <Modal visible={rateOpen} transparent animationType="slide" onRequestClose={closeRating}>
      <View style={st.overlay}>
        <Pressable style={StyleSheet.absoluteFill} accessibilityRole="button" accessibilityLabel="Fermer la notation" onPress={closeRating}/>
        <View style={st.sheet} accessibilityViewIsModal>
          <View style={st.sheetHeader}><Text style={st.sheetTitle}>Votre note</Text><Pressable accessibilityRole="button" accessibilityLabel="Fermer" disabled={saving} onPress={closeRating} style={st.actionIcon}><Icon name="close"/></Pressable></View>
          <Text style={st.sheetName}>{pharmacy.display_name}</Text>
          <View style={st.rateStars}>{[1,2,3,4,5].map(value => <Pressable key={value} accessibilityRole="radio" accessibilityLabel={`${value} étoile${value > 1 ? 's' : ''}`} accessibilityState={{checked:draft===value,disabled:saving}} disabled={saving} onPress={() => setDraft(value)} style={st.starTarget}><Icon name="star" size={34} color="#E5B331" filled={value<=draft}/></Pressable>)}</View>
          {!!error && <Text accessibilityRole="alert" style={st.error}>{error}</Text>}
          <Pressable accessibilityRole="button" accessibilityLabel="Enregistrer la note" disabled={!draft || saving} onPress={() => void save()} style={[st.submit,(!draft || saving) && st.disabled]}>{saving ? <ActivityIndicator color="#FFFFFF"/> : <Text style={st.submitText}>Enregistrer</Text>}</Pressable>
        </View>
      </View>
    </Modal>
  </View>;
}
const st = StyleSheet.create({
  card:{flex:1,flexBasis:320,maxWidth:500,minWidth:0,padding:12,borderRadius:32,backgroundColor:'#FFFFFF',borderWidth:1,borderColor:'#E7EDDF'},
  photo:{width:'100%',aspectRatio:1.65,borderRadius:23,overflow:'hidden',backgroundColor:'#E4EDD9'},image:{width:'100%',height:'100%'},
  bookmark:{position:'absolute',top:12,right:12,width:44,height:48,borderRadius:18,backgroundColor:'rgba(48,59,44,.36)',alignItems:'center',justifyContent:'center'},bookmarkActive:{backgroundColor:'#EFF5E5'},
  body:{paddingHorizontal:7,paddingTop:17,paddingBottom:7,gap:7},name:{fontSize:20,fontWeight:'600',letterSpacing:-.4,color:'#20291F'},address:{fontSize:14,color:'#747B70',lineHeight:21},
  ratingRow:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',flexWrap:'wrap',columnGap:8},ratingButton:{flexDirection:'row',alignItems:'center',gap:9,minHeight:44},stars:{flexDirection:'row',gap:3},ratingText:{fontSize:13,color:'#798071'},ratingValue:{fontWeight:'600',color:'#333D2E'},count:{color:'#798071'},rateLink:{minHeight:44,justifyContent:'center',paddingHorizontal:4},rateLinkText:{fontSize:12,fontWeight:'600',color:'#68833E'},
  meta:{flexDirection:'row',alignItems:'center',flexWrap:'wrap',gap:9},metaItem:{flexDirection:'row',alignItems:'center',gap:5},metaText:{fontSize:13,color:'#7E8777'},dot:{color:'#B9C0B3'},hours:{fontSize:12,color:'#87907F',lineHeight:18},
  actions:{flexDirection:'row',alignItems:'center',gap:7,paddingTop:8,marginTop:5,borderTopWidth:1,borderColor:'#EFF2E9'},catalog:{flex:1,minHeight:44,flexDirection:'row',alignItems:'center',justifyContent:'space-between',gap:5,paddingHorizontal:12,backgroundColor:'#F1F6E8',borderRadius:13},catalogText:{fontSize:12,fontWeight:'600',color:'#536D33'},arrow:{fontSize:18,color:'#536D33'},actionIcon:{width:44,height:44,alignItems:'center',justifyContent:'center',borderRadius:13,backgroundColor:'#F7F8F4'},disabled:{opacity:.4},
  overlay:{flex:1,backgroundColor:'rgba(29,37,25,.32)',justifyContent:'flex-end',alignItems:'center'},sheet:{width:'100%',maxWidth:500,padding:24,paddingBottom:36,borderTopLeftRadius:30,borderTopRightRadius:30,backgroundColor:'#FFFFFF',gap:14},sheetHeader:{flexDirection:'row',alignItems:'center',justifyContent:'space-between'},sheetTitle:{fontSize:21,fontWeight:'600',color:'#293223'},sheetName:{fontSize:15,color:'#6E7864'},rateStars:{flexDirection:'row',justifyContent:'center',gap:8,paddingVertical:16},starTarget:{width:44,height:48,alignItems:'center',justifyContent:'center'},submit:{minHeight:50,alignItems:'center',justifyContent:'center',backgroundColor:'#6D8C43',borderRadius:16},submitText:{fontSize:15,fontWeight:'600',color:'#FFFFFF'},error:{fontSize:13,color:'#A24335'},
});

import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Image, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import * as Crypto from 'expo-crypto';
import OcrEngine from '../ocr/OcrEngine';
import type { OcrEvent } from '../ocr/document';
import { cleanTranscription, scanImage } from '../prescriptionScan';
import { db, ensureGuestSession, supabase } from '../api';
import { styles as s } from '../theme';

function ScanButton({label,onPress,disabled=false}: {label:string;onPress:()=>void;disabled?:boolean}) {
  return <Pressable accessibilityRole="button" accessibilityState={{disabled}} disabled={disabled} onPress={onPress} style={({pressed}) => [s.button,disabled && s.disabled,pressed && s.pressed]}><Text style={s.buttonText}>{label}</Text></Pressable>;
}
type Scan = ReturnType<typeof scanImage> & {id:string};
export default function ScanPrescription() {
  const [image,setImage] = useState<Scan | null>(null);
  const [text,setText] = useState('');
  const [reading,setReading] = useState(false);
  const [saving,setSaving] = useState(false);
  const [progress,setProgress] = useState(0);
  const [error,setError] = useState('');
  const [attempt,setAttempt] = useState(0);
  const locked = useRef(false);
  const alive = useRef(true);
  useEffect(() => {alive.current = true; return () => {alive.current = false;};}, []);
  const acceptImage = useCallback((result: ImagePicker.ImagePickerResult) => {
    if(result.canceled || !alive.current) return;
    const base64 = result.assets[0].base64;
    if(!base64) throw new Error('Impossible de lire cette image. Choisissez une autre photo.');
    const scan = scanImage(base64);
    setImage({...scan,id:Crypto.randomUUID()});setText('');setError('');setProgress(0);setReading(true);setAttempt(v => v+1);
  }, []);
  useEffect(() => {
    if(Platform.OS !== 'android') return;
    let active = true;
    ImagePicker.getPendingResultAsync().then(result => {
      if(!active || !result) return;
      if('code' in result) throw new Error('Impossible de récupérer la photo. Réessayez.');
      acceptImage(result);
    }).catch(() => {if(active) setError('Impossible de récupérer la photo. Réessayez.');});
    return () => {active = false;};
  }, [acceptImage]);
  const onEvent = useCallback((event: OcrEvent) => {
    if(event.type === 'progress') setProgress(event.progress);
    else {
      setReading(false);
      if(event.type === 'error') setError('Lecture impossible. Vérifiez la connexion et réessayez.');
      else {
        const value = cleanTranscription(event.text); setText(value);
        if(!value) setError('Aucun texte détecté. Reprenez une photo plus nette.');
      }
    }
  }, []);
  useEffect(() => {
    if(!reading) return;
    const timer = setTimeout(() => {setReading(false);setError('Lecture trop longue. Réessayez avec une photo plus nette.');},120000);
    return () => clearTimeout(timer);
  }, [reading,attempt]);
  async function pick(camera: boolean) {
    if(locked.current || reading) return;
    setError('');
    try {
      if(camera && Platform.OS !== 'web') {
        const permission = await ImagePicker.requestCameraPermissionsAsync();
        if(!permission.granted) throw new Error('Accès à la caméra refusé. Autorisez-le dans les réglages ou choisissez une photo.');
      }
      // On web the picker must open directly from the user's click, before any await.
      const result = await (camera ? ImagePicker.launchCameraAsync : ImagePicker.launchImageLibraryAsync)({mediaTypes:['images'],base64:true,quality:1});
      acceptImage(result);
    } catch(e) {setError(e instanceof Error ? e.message : 'Impossible d’ouvrir la caméra.');}
  }
  async function save() {
    if(!image || !text.trim() || locked.current) return;
    locked.current = true;setSaving(true);setError('');
    try {
      const session = await ensureGuestSession();
      const uid = session.user.id;
      const profile = await db.from('patient_profiles').upsert({patient_id:uid},{onConflict:'patient_id',ignoreDuplicates:true});
      if(profile.error) throw new Error('Impossible de préparer votre dossier.');
      const path = `${uid}/${image.id}.${image.extension}`;
      // Fixed ID makes a retry after a lost response idempotent.
      const upload = await supabase.storage.from('prescriptions').upload(path,image.bytes.buffer as ArrayBuffer,{contentType:image.mime,upsert:true});
      if(upload.error) throw new Error('Impossible d’enregistrer la photo. Réessayez.');
      const record = {prescription_id:image.id,patient_id:uid,source:'scan',status:'available',file_name:`Ordonnance-${image.id.slice(0,8)}.${image.extension}`,storage_path:`prescriptions/${path}`,mime_type:image.mime,file_size_bytes:image.bytes.length,transcription:cleanTranscription(text)};
      const saved = await db.from('prescriptions').upsert(record,{onConflict:'prescription_id',ignoreDuplicates:true});
      if(saved.error) throw new Error('Impossible d’enregistrer la transcription. Votre texte est conservé, réessayez.');
      router.replace({pathname:'/',params:{tab:'Ordonnances'}});
    } catch(e) {setError(e instanceof Error ? e.message : 'Enregistrement impossible.');}
    finally {locked.current = false;setSaving(false);}
  }

  return <SafeAreaView style={s.root}>
    <ScrollView contentContainerStyle={[s.page,{maxWidth:800}]} keyboardShouldPersistTaps="handled">
      <View style={s.header}><Text style={s.heading}>Scanner une ordonnance</Text><ScanButton label="Fermer" onPress={() => router.canGoBack() ? router.back() : router.replace('/')} disabled={saving}/></View>
      <View style={[s.row,{flexWrap:'wrap'}]}><ScanButton label="Prendre une photo" onPress={() => {void pick(true);}} disabled={reading || saving}/><ScanButton label="Galerie" onPress={() => {void pick(false);}} disabled={reading || saving}/></View>
      {!!error && <Text accessibilityRole="alert" style={s.message}>{error}</Text>}
      {image && <Image source={{uri:image.uri}} resizeMode="contain" accessibilityLabel="Photo de l’ordonnance" style={{width:'100%',height:320,borderRadius:18,backgroundColor:'#fff'}}/>}
      {reading && <View style={s.row}><ActivityIndicator color="#00BFA9"/><Text accessibilityLiveRegion="polite">Lecture… {Math.round(progress*100)} %</Text><ScanButton label="Annuler" onPress={() => setReading(false)}/></View>}
      {image && !reading && <>
        <View style={s.header}><Text style={s.heading}>Transcription à vérifier</Text><ScanButton label="Relire la photo" onPress={() => {setError('');setProgress(0);setReading(true);setAttempt(v => v+1);}} disabled={saving}/></View>
        <TextInput accessibilityLabel="Transcription de l’ordonnance à vérifier" multiline value={text} onChangeText={setText} maxLength={20000} editable={!saving} style={[s.input,{minHeight:200,textAlignVertical:'top',lineHeight:24}]} />
        <ScanButton label={saving ? 'Enregistrement…' : 'Confirmer et enregistrer'} onPress={() => {void save();}} disabled={saving || !text.trim()}/>
      </>}
    </ScrollView>
    {reading && image && <View style={{position:'absolute',width:1,height:1,opacity:0}} pointerEvents="none"><OcrEngine key={attempt} image={image.uri} onEvent={onEvent}/></View>}
  </SafeAreaView>;
}

import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Image, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import * as Crypto from 'expo-crypto';
import OcrEngine from '../ocr/OcrEngine';
import type { OcrEvent } from '../ocr/document';
import { cleanTranscription, scanImage } from '../prescriptionScan';
import { initialScan, transitionScan } from '../scanWorkflow';
import { db, supabase } from '../api';
import { useGuestAccess } from '../useGuestAccess';
import { styles as s } from '../theme';

function ScanButton({label,onPress,disabled=false}: {label:string;onPress:()=>void;disabled?:boolean}) {
  return <Pressable accessibilityRole="button" accessibilityState={{disabled}} disabled={disabled} onPress={onPress} style={({pressed}) => [s.button,disabled && s.disabled,pressed && s.pressed]}><Text style={s.buttonText}>{label}</Text></Pressable>;
}
export default function ScanPrescription() {
  const { access, ensureOwner, owns } = useGuestAccess();
  return <ScanForm key={access.generation} ensureOwner={ensureOwner} owns={owns}/>;
}

function ScanForm({ ensureOwner, owns }: Pick<ReturnType<typeof useGuestAccess>, 'ensureOwner' | 'owns'>) {
  const [state, setState] = useState(initialScan);
  const current = useRef(initialScan);
  const alive = useRef(true);
  const pendingPhoto = useRef<ReturnType<typeof ImagePicker.getPendingResultAsync> | null>(null);
  useEffect(() => {alive.current = true; return () => {alive.current = false;};}, []);

  // Advance synchronously so a second tap cannot start another save before React renders.
  const send = useCallback((action: Parameters<typeof transitionScan>[1]) => {
    if (!alive.current) return null;
    const next = transitionScan(current.current, action);
    if (next === current.current) return null;
    current.current = next;
    setState(next);
    return next;
  }, []);

  const acceptImage = useCallback((result: ImagePicker.ImagePickerResult, attempt: number) => {
    if (!alive.current || current.current.attempt !== attempt) return;
    if (result.canceled) {
      send({ type: 'pickerClosed', attempt });
      return;
    }
    const base64 = result.assets[0]?.base64;
    if (!base64) throw new Error('Impossible de lire cette image. Choisissez une autre photo.');
    send({ type: 'picked', attempt, image: { ...scanImage(base64), id: Crypto.randomUUID() } });
  }, [send]);

  useEffect(() => {
    if (Platform.OS !== 'android') return;
    let active = true;
    // Strict Mode replays effects. Read the one-shot Android result only once.
    pendingPhoto.current ??= ImagePicker.getPendingResultAsync();
    pendingPhoto.current.then(result => {
      if (!active || !result) return;
      if ('code' in result) throw new Error('Impossible de récupérer la photo. Réessayez.');
      acceptImage(result, initialScan.attempt);
    }).catch(() => {
      if (active) send({ type: 'pickerClosed', attempt: initialScan.attempt, error: 'Impossible de récupérer la photo. Réessayez.' });
    }).finally(() => {
      if (active) pendingPhoto.current = null;
    });
    return () => {active = false;};
  }, [acceptImage, send]);

  const { attempt, error } = state;
  const image = state.draft?.image;
  const text = state.draft?.text ?? '';
  const reading = state.phase === 'reading';
  const saving = state.phase === 'saving';
  const pickingNative = state.phase === 'picking' && Platform.OS !== 'web';
  const onEvent = useCallback((event: OcrEvent) => {
    send({ type: 'ocr', attempt, event });
  }, [attempt, send]);

  useEffect(() => {
    if (!reading) return;
    const timer = setTimeout(() => send({ type: 'stopReading', attempt, error: 'Lecture trop longue. Réessayez avec une photo plus nette.' }), 120000);
    return () => clearTimeout(timer);
  }, [reading, attempt, send]);

  async function pick(camera: boolean) {
    // Some browsers never resolve a cancelled file dialog. A fresh click supersedes it.
    const selection = send({ type: 'pick', allowReopen: Platform.OS === 'web' });
    if (!selection) return;
    const attempt = selection.attempt;
    try {
      if (camera && Platform.OS !== 'web') {
        const permission = await ImagePicker.requestCameraPermissionsAsync();
        if (!alive.current || current.current.attempt !== attempt) return;
        if (!permission.granted) throw new Error('Accès à la caméra refusé. Autorisez-le dans les réglages ou choisissez une photo.');
      }
      // On web the picker must open directly from the user's click, before any await.
      const result = await (camera ? ImagePicker.launchCameraAsync : ImagePicker.launchImageLibraryAsync)({mediaTypes:['images'],base64:true,quality:1});
      acceptImage(result, attempt);
    } catch(e) {
      send({ type: 'pickerClosed', attempt, error: e instanceof Error ? e.message : 'Impossible d’ouvrir la caméra.' });
    }
  }
  async function save() {
    const submission = send({ type: 'save' });
    if (submission?.phase !== 'saving') return;
    const { image, text } = submission.draft;
    try {
      const uid = await ensureOwner();
      if (!owns(uid)) return;
      const profile = await db.from('patient_profiles').upsert({patient_id:uid},{onConflict:'patient_id',ignoreDuplicates:true});
      if(profile.error) throw new Error('Impossible de préparer votre dossier.');
      if (!owns(uid)) return;
      const path = `${uid}/${image.id}.${image.extension}`;
      // Fixed ID makes a retry after a lost response idempotent.
      const upload = await supabase.storage.from('prescriptions').upload(path,image.bytes.buffer as ArrayBuffer,{contentType:image.mime,upsert:true});
      if(upload.error) throw new Error('Impossible d’enregistrer la photo. Réessayez.');
      if (!owns(uid)) return;
      const record = {prescription_id:image.id,patient_id:uid,source:'scan',status:'available',file_name:`Ordonnance-${image.id.slice(0,8)}.${image.extension}`,storage_path:`prescriptions/${path}`,mime_type:image.mime,file_size_bytes:image.bytes.length,transcription:cleanTranscription(text)};
      const saved = await db.from('prescriptions').insert(record);
      if (!owns(uid)) return;
      if (saved.error?.code === '23505') {
        // A previous insert may have committed before its response was lost.
        const existing = await db.from('prescriptions').select('transcription')
          .eq('patient_id', uid).eq('prescription_id', image.id).single();
        if (existing.error) throw new Error('Impossible de vérifier l’ordonnance enregistrée. Réessayez.');
        if (existing.data.transcription !== record.transcription)
          throw new Error('Une autre transcription est déjà enregistrée pour cette photo. Vérifiez-la dans vos ordonnances.');
      } else if (saved.error) {
        throw new Error('Impossible d’enregistrer la transcription. Votre texte est conservé, réessayez.');
      }
      if (alive.current && owns(uid)) router.replace({pathname:'/',params:{tab:'Ordonnances'}});
    } catch(e) {
      send({ type: 'saveFailed', error: e instanceof Error ? e.message : 'Enregistrement impossible.' });
    }
  }

  return <SafeAreaView style={s.root}>
    <ScrollView contentContainerStyle={[s.page,{maxWidth:800}]} keyboardShouldPersistTaps="handled">
      <View style={s.header}><Text style={s.heading}>Scanner une ordonnance</Text><ScanButton label="Fermer" onPress={() => router.canGoBack() ? router.back() : router.replace('/')} disabled={saving}/></View>
      <View style={[s.row,{flexWrap:'wrap'}]}><ScanButton label="Prendre une photo" onPress={() => {void pick(true);}} disabled={reading || saving || pickingNative}/><ScanButton label="Galerie" onPress={() => {void pick(false);}} disabled={reading || saving || pickingNative}/></View>
      {!!error && <Text accessibilityRole="alert" style={s.message}>{error}</Text>}
      {image && <Image source={{uri:image.uri}} resizeMode="contain" accessibilityLabel="Photo de l’ordonnance" style={{width:'100%',height:320,borderRadius:18,backgroundColor:'#fff'}}/>}
      {reading && <View style={s.row}><ActivityIndicator color="#00BFA9"/><Text accessibilityLiveRegion="polite">Lecture… {Math.round(state.progress*100)} %</Text><ScanButton label="Annuler" onPress={() => send({ type: 'stopReading', attempt })}/></View>}
      {image && !reading && <>
        <View style={s.header}><Text style={s.heading}>Transcription à vérifier</Text><ScanButton label="Relire la photo" onPress={() => send({ type: 'reread' })} disabled={saving || pickingNative}/></View>
        <TextInput accessibilityLabel="Transcription de l’ordonnance à vérifier" multiline value={text} onChangeText={text => send({ type: 'edit', text })} maxLength={20000} editable={!saving && !pickingNative} style={[s.input,{minHeight:200,textAlignVertical:'top',lineHeight:24}]} />
        <ScanButton label={saving ? 'Enregistrement…' : 'Confirmer et enregistrer'} onPress={() => {void save();}} disabled={saving || pickingNative || !cleanTranscription(text)}/>
      </>}
    </ScrollView>
    {reading && image && <View style={{position:'absolute',width:1,height:1,opacity:0}} pointerEvents="none"><OcrEngine key={attempt} image={image.uri} onEvent={onEvent}/></View>}
  </SafeAreaView>;
}

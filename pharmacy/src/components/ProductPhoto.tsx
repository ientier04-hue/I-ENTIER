import { useState } from 'react';
import { Image, StyleSheet, View } from 'react-native';
import type { Product } from '../cart';
import { Icon } from './Overview';

const photos: Record<string, number> = {
  '4c-analgine': require('../../assets/medicines/analgine.jpg'),
  '4c-pediaphen': require('../../assets/medicines/pediaphen.jpg'),
  '4c-flaxan': require('../../assets/medicines/flaxan.jpg'),
  '4c-paracetamol': require('../../assets/medicines/paracetamol.jpg'),
};

export function ProductPhoto({ product, large = false }: { product: Product; large?: boolean }) {
  const [failedSource, setFailedSource] = useState<string | null>(null);
  const localPhoto = photos[product.medicine_slug || ''];
  const sourceKey = String(localPhoto || product.image_url || '');
  const source = failedSource === sourceKey ? undefined : localPhoto || (product.image_url ? { uri: product.image_url } : undefined);
  return <View style={[st.photo, large && st.large]}>
    {source ? <Image source={source} resizeMode="contain" style={st.image} accessibilityLabel={product.name} onError={() => setFailedSource(sourceKey)}/>
      : <Icon name="pill" size={large ? 72 : 34} color="#749257"/>}
  </View>;
}

const st = StyleSheet.create({
  photo: { width: 52, height: 60, borderRadius: 14, borderWidth: 1, borderColor: '#E5E8DF', padding: 5, backgroundColor: '#FAFBF8', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  large: { width: '100%', height: '100%', borderWidth: 0, borderRadius: 24, padding: 22, backgroundColor: '#F5F8EC' },
  image: { width: '100%', height: '100%' },
});

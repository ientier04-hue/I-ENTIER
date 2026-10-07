import Svg, { G, Rect, Path } from 'react-native-svg';

/** Flat vector artwork, shared by web and native builds. */
export function MedicalArtwork() {
  return <Svg width="100%" height={218} viewBox="0 0 380 230" accessible={false}>
    <G transform="translate(66 16)">
      <Rect x="85" y="18" width="76" height="40" rx="10" fill="none" stroke="#1C2028" strokeWidth="8"/>
      <Rect x="31" y="51" width="196" height="128" rx="12" fill="#FFFFFF" stroke="#B6D5CD" strokeWidth="2"/>
      <Path d="M32 104H226" stroke="#B6D5CD" strokeWidth="2"/>
      <Rect x="70" y="94" width="12" height="22" rx="3" fill="#1C2028"/>
      <Rect x="176" y="94" width="12" height="22" rx="3" fill="#1C2028"/>
      <Path d="M111 131h11v-11h14v11h11v14h-11v11h-14v-11h-11z" fill="#00BFA9"/>
    </G>
    <G transform="translate(300 133) rotate(32)">
      <Rect width="30" height="74" rx="15" fill="#FFFFFF" stroke="#B6D5CD" strokeWidth="2"/>
      <Path d="M0 37V15a15 15 0 0130 0v22z" fill="#00BFA9"/>
    </G>
    <Path d="M42 77h18M51 68v18M323 62h14M330 55v14" stroke="#00A38F" strokeWidth="3" strokeLinecap="round"/>
  </Svg>;
}

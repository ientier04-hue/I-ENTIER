import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';
import type { Product } from '../cart';

const ink = '#1C2028';
const lime = '#00BFA9';
const palette = ['#00BFA9', '#7EA6D3', '#ADBACF', '#78C5BE', '#A5B5C4'];
type Destination = 'Pharmacies' | 'Ordonnances' | 'Commandes';
type IconName = 'store' | 'document' | 'bag' | 'pill' | 'scan' | 'heart' | 'chevron' | 'close' | 'pin' | 'star' | 'truck' | 'truckOff' | 'bookmark' | 'phone' | 'directions';
export function Icon({ name, color = ink, size = 22, filled = false }: { name: IconName; color?: string; size?: number; filled?: boolean }) {
  const paths = {
    bookmark: 'M6 3h12v18l-6-4-6 4V3Z',
    phone: 'M7 3H3c0 10 8 18 18 18v-4l-5-2-2 2a17 17 0 01-7-7l2-2-2-5Z',
    directions: 'm12 2 10 10-10 10L2 12 10 2ZM7 15v-4h9M13 8l3 3-3 3',

    pin: 'M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1116 0ZM15 10a3 3 0 11-6 0 3 3 0 016 0',
    star: 'm12 3 2.8 5.7 6.3.9-4.6 4.5 1.1 6.3L12 17.4l-5.6 3 1.1-6.3L3 9.6l6.2-.9L12 3Z',
    truck: 'M3 5h11v12H8M3 5v12h1M14 9h4l3 4v4h-2M14 17h1M5 17a2 2 0 114 0 2 2 0 01-4 0M15 17a2 2 0 114 0 2 2 0 01-4 0M14 13h7',
    truckOff: 'M3 3l18 18M7 5h7v6M3 7v10h2M14 9h4l3 4v4h-2M9 17h6M5 17a2 2 0 114 0 2 2 0 01-4 0M15 17a2 2 0 114 0 2 2 0 01-4 0',
    heart: 'M20.8 4.6a5.5 5.5 0 00-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 00-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 000-7.8',
    chevron: 'M6 9l6 6 6-6',
    close: 'M6 6l12 12M18 6L6 18',
    scan: 'M8 3H3v5M16 3h5v5M21 16v5h-5M8 21H3v-5M7 8h10M7 12h10M7 16h6',
    store: 'M4 10v10h16V10M3 10l2-6h14l2 6M3 10c0 4 5 4 5 0 0 4 4 4 4 0 0 4 4 4 4 0 0 4 5 4 5 0M9 20v-6h6v6',
    document: 'M14 3H5v18h14V8L14 3v5h5M8 12h8M8 16h5',
    bag: 'M5 7h14l2 14H3L5 7M8 8V6a4 4 0 018 0v2',
    pill: 'M9 4a6 6 0 018 8l-6 7a6 6 0 01-8-8l6-7M7 8l9 8',
  };
  return <Svg width={size} height={size} viewBox="0 0 24 24"><Path d={paths[name]} fill={filled ? color : 'none'} stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round"/></Svg>;
}
export function QuickAccess({ pharmacies, prescriptions, orders, onOpen }: { pharmacies: number; prescriptions: number; orders: number; onOpen: (tab: Destination) => void }) {
  const items: { title: Destination; count: number; icon: IconName; color: string }[] = [
    { title: 'Pharmacies', count: pharmacies, icon: 'store', color: '#F4F5F7' },
    { title: 'Ordonnances', count: prescriptions, icon: 'document', color: '#F4F5F7' },
    { title: 'Commandes', count: orders, icon: 'bag', color: '#F4F5F7' },
  ];
  return <View style={st.shortcuts}>{items.map(item => <Pressable key={item.title} accessibilityRole="button" accessibilityLabel={`${item.title}, ${item.count}`} onPress={() => onOpen(item.title)} style={({ pressed }) => [st.shortcut, { backgroundColor: item.color }, pressed && st.pressed]}>
    <View style={st.between}><Icon name={item.icon}/><Text style={st.tinyArrow}>↗</Text></View>
    <Text style={st.shortcutNumber}>{String(item.count).padStart(2,'0')}</Text>
    <Text style={st.shortcutLabel}>{item.title}</Text>
  </Pressable>)}</View>;
}
export function CatalogCharts({ products, category, onCategory }: { products: Product[]; category: string; onCategory: (value: string) => void }) {
  const prescription = products.filter(p => p.requires_prescription).length;
  const free = products.length - prescription;
  const groups = Object.entries(products.reduce<Record<string, number>>((acc,p) => {
    const name = p.category || 'Autres'; acc[name] = (acc[name] || 0) + 1; return acc;
  }, {})).sort((a,b) => b[1]-a[1]);
  const circumference = 2 * Math.PI * 55;
  const share = products.length ? free / products.length : 0;
  return <View style={st.chartGrid}>
    <View style={[st.chartCard, st.dark]}>
      <View style={st.between}><Text style={[st.heading, st.white]}>Le catalogue</Text><View style={st.smallBadge}><Icon name="pill" color={lime} size={18}/></View></View>
      <View style={st.donutRow}>
        <View accessible accessibilityLabel={`${products.length} références : ${free} sans ordonnance, ${prescription} sur ordonnance`} style={st.donut}>
          <Svg width={148} height={148} viewBox="0 0 148 148" accessible={false}>
            <Circle cx={74} cy={74} r={55} fill="none" stroke="#DEE2E8" strokeWidth={15}/>
            {share > 0 && <Circle cx={74} cy={74} r={55} fill="none" stroke={lime} strokeWidth={15} strokeDasharray={`${share * circumference} ${circumference}`} rotation={-90} origin="74, 74"/>}
          </Svg>
          <View pointerEvents="none" style={st.donutCenter}><Text style={st.donutNumber}>{products.length}</Text><Text style={st.donutUnit}>référence{products.length > 1 ? 's' : ''}</Text></View>
        </View>
        <View style={st.legend}>
          <View style={st.legendItem}><View style={[st.dot,{backgroundColor:lime}]}/><Text style={st.legendText}>Sans ordonnance</Text><Text style={st.legendNumber}>{free}</Text></View>
          <View style={st.legendItem}><View style={[st.dot,{backgroundColor:'#B2BBC7'}]}/><Text style={st.legendText}>Sur ordonnance</Text><Text style={st.legendNumber}>{prescription}</Text></View>
        </View>
      </View>
    </View>
    <View style={st.chartCard}>
      <View style={st.between}><Text style={st.heading}>Par catégorie</Text><Text style={st.counter}>{groups.length.toString().padStart(2,'0')}</Text></View>
      <View style={st.bars}>{groups.map(([name,count],i) => <Pressable key={name} accessibilityRole="button" accessibilityLabel={`${name}, ${count} références, filtrer`} accessibilityState={{selected: category === name}} onPress={() => onCategory(category === name ? 'Tous' : name)} style={({pressed}) => [st.barItem, pressed && st.pressed]}>
        <View style={st.between}><Text style={[st.barLabel, category === name && {fontWeight:'800'}]}>{name}</Text><Text style={st.barValue}>{count}</Text></View>
        <View style={st.track}><View style={[st.bar, { width: `${count / products.length * 100}%`, backgroundColor: palette[i % palette.length] }]}/></View>
      </Pressable>)}{!groups.length && <Text style={st.noData}>Aucun produit disponible</Text>}</View>
      <Text style={st.chartFooter}>{products.length} référence{products.length > 1 ? 's' : ''} · catalogue publié</Text>
    </View>
  </View>;
}
const orderSteps = ['pending','accepted','preparing','ready','completed'];
const labels: Record<string,string> = { pending: 'Reçue', accepted:'Acceptée', preparing:'En préparation', ready:'Prête', completed:'Terminée', cancelled:'Annulée' };
export function OrderProgress({ status }: { status: string }) {
  const index = orderSteps.indexOf(status);
  return <View style={st.progress}>
    <View style={st.between}><View style={[st.orderBadge, status === 'cancelled' && {backgroundColor:'#F8E3DE'}]}><View style={[st.dot,{backgroundColor:status === 'cancelled' ? '#A84632' : '#009B88'}]}/><Text style={st.barLabel}>{labels[status] || status}</Text></View><Icon name="bag"/></View>
    {index >= 0 && <View accessible accessibilityLabel={`Étape ${index+1} sur 5 : ${labels[status]}`} style={st.steps}>{orderSteps.map((step,i) => <View key={step} style={[st.step,{backgroundColor:i <= index ? '#00BFA9' : '#E5E8EE'}]}/>)}</View>}
  </View>;
}
export function StockBadge({ quantity }: { quantity: number }) {
  return <View style={st.stock}><View style={[st.dot,{backgroundColor: quantity > 0 ? '#009B88' : '#9A9A8B'}]}/><Text style={st.stockText}>{quantity > 0 ? 'En stock' : 'Indisponible'}</Text></View>;
}
const st = StyleSheet.create({
  shortcuts: { flexDirection:'row', flexWrap:'wrap', gap:10 },
  shortcut: { flex:1, minWidth:86, padding:16, borderRadius: 12, gap:10,borderWidth: 1,borderColor: '#E0E5E7' },
  between: { flexDirection:'row', alignItems:'center', justifyContent:'space-between', gap:8 },
  shortcutNumber: { color:ink, fontSize:32, fontWeight:'500', letterSpacing:-1.6, marginTop:5 },
  shortcutLabel: { color:ink, fontSize:11, fontWeight:'600' },
  tinyArrow: {color:'#777C86', fontSize:18},
  pressed: { opacity:.72, transform:[{scale:.98}] },
  chartGrid: { flexDirection:'row', flexWrap:'wrap', gap:18 },
  chartCard: { flex:1, flexBasis:320, minWidth:240, padding:24, borderRadius: 12, backgroundColor:'#FFFFFF', borderWidth: 1, borderColor: '#E0E5E7', gap:22 },
  dark: {backgroundColor:'#F1F3F6', borderColor: '#E0E5E7'},
  heading: {fontSize:19, fontWeight:'600', color:ink, letterSpacing:-.6},
  white: {color:'#232832'},
  smallBadge: {width:32,height:32,alignItems:'center',justifyContent:'center',borderWidth:1,borderColor: '#E0E5E7',borderRadius:12},
  donutRow: {flexDirection:'row', flexWrap:'wrap', alignItems:'center', justifyContent:'center', gap:18},
  donut: {width:148,height:148},
  donutCenter: {position:'absolute',top:0,left:0,right:0,bottom:0,justifyContent:'center',alignItems:'center'},
  donutNumber: {color:'#232832',fontSize:39,fontWeight:'500',letterSpacing:-2},
  donutUnit: {color:'#757D8A',fontSize:10},
  legend: {gap:18,flexGrow:1},
  legendItem: {flexDirection:'row',alignItems:'center',gap:8},
  dot: {width:6,height:6,borderRadius:4},
  legendText: {color:'#676F7A',fontSize:11,flex:1},
  legendNumber: {color:'#232832',fontSize:17,fontWeight:'600'},
  counter: {color:'#717985',fontSize:18},
  bars: {gap:20,flex:1,justifyContent:'center'},
  barItem: {gap:10,minHeight:44,justifyContent:'center'},
  barLabel: {color:ink,fontSize:12,fontWeight:'500'},
  barValue: {color:ink,fontSize:13,fontWeight:'700'},
  track: {height:12,backgroundColor:'#E5E8EE',borderRadius:8,overflow:'hidden'},
  bar: {height:12,borderRadius:8},
  chartFooter: {fontSize:10,color:'#717985',borderTopWidth:1,borderColor: '#E0E5E7',paddingTop:16},
  noData: {color:'#717985',fontSize:13,paddingVertical:24},
  progress: {gap:18},
  orderBadge: {flexDirection:'row',alignItems:'center',gap:8,backgroundColor:'#E0F5F1',padding:10,borderRadius: 12},
  steps: {flexDirection:'row',gap:5},
  step: {height:6,flex:1,borderRadius:4},
  stock: {position:'absolute',top:12,left:12,flexDirection:'row',gap:6,alignItems:'center',backgroundColor:'#FFFFFF',paddingHorizontal:10,paddingVertical:7,borderRadius: 12,zIndex:2},
  stockText: {fontSize:10,fontWeight:'600',color:ink},
});

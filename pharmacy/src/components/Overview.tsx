import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';
import type { Product } from '../cart';

const ink = '#1C2028';
const lime = '#00BFA9';
const palette = ['#00BFA9', '#7EA6D3', '#ADBACF', '#78C5BE', '#A5B5C4'];
type Destination = 'Pharmacies' | 'Ordonnances' | 'Commandes';
type IconName = 'store' | 'document' | 'bag' | 'pill' | 'scan';
export function Icon({ name, color = ink, size = 22 }: { name: IconName; color?: string; size?: number }) {
  const paths = {
    scan: 'M8 3H3v5M16 3h5v5M21 16v5h-5M8 21H3v-5M7 8h10M7 12h10M7 16h6',
    store: 'M4 10v10h16V10M3 10l2-6h14l2 6M3 10c0 4 5 4 5 0 0 4 4 4 4 0 0 4 4 4 4 0 0 4 5 4 5 0M9 20v-6h6v6',
    document: 'M14 3H5v18h14V8L14 3v5h5M8 12h8M8 16h5',
    bag: 'M5 7h14l2 14H3L5 7M8 8V6a4 4 0 018 0v2',
    pill: 'M9 4a6 6 0 018 8l-6 7a6 6 0 01-8-8l6-7M7 8l9 8',
  };
  return <Svg width={size} height={size} viewBox="0 0 24 24" accessible={false}><Path d={paths[name]} fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round"/></Svg>;
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

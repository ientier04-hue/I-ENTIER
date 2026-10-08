export type Coordinates = { latitude: number; longitude: number };
export type Pharmacy = {
  pharmacy_id: string;
  display_name: string;
  address: string;
  phone: string;
  opening_hours: string;
  latitude: number | null;
  longitude: number | null;
  delivery_available: boolean | null;
};

export function distanceKm(origin: Coordinates | null, pharmacy?: Pick<Pharmacy, 'latitude' | 'longitude'>): number | null {
  if (!origin || !pharmacy || pharmacy.latitude == null || pharmacy.longitude == null) return null;
  const { latitude, longitude } = pharmacy;
  if (![origin.latitude, origin.longitude, latitude, longitude].every(Number.isFinite)
    || Math.abs(latitude) > 90 || Math.abs(origin.latitude) > 90
    || Math.abs(longitude) > 180 || Math.abs(origin.longitude) > 180) return null;
  const rad = (degrees: number) => degrees * Math.PI / 180;
  const a = Math.sin(rad(latitude - origin.latitude) / 2) ** 2
    + Math.cos(rad(origin.latitude)) * Math.cos(rad(latitude)) * Math.sin(rad(longitude - origin.longitude) / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
}

export function formatDistance(distance: number | null) {
  if (distance == null) return null;
  return distance < 1 ? `${Math.max(10, Math.round(distance * 100) * 10)} m`
    : `${distance.toLocaleString('fr-FR', { maximumFractionDigits: 1 })} km`;
}

export function compareDistance(a: number | null, b: number | null) {
  if (a == null) return b == null ? 0 : 1;
  return b == null ? -1 : a - b;
}

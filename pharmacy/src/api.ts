import "react-native-url-polyfill/auto";
import { createClient } from "@supabase/supabase-js";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";

export const supabase = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL ||
    "https://dktjnxbtyhxvapyheosh.supabase.co",
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    "sb_publishable_8dJgVAcokPBAdjY7pymzLA_OI6l7lOp",
  {
    auth: {
      storage: AsyncStorage,
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: Platform.OS === "web",
    },
  },
);
export const db = supabase.schema("ientier");

// Deduplicate startup requests (including React Strict Mode remounts).
let pendingGuest: Promise<import('@supabase/supabase-js').Session> | null = null;
export function ensureGuestSession() {
  if (!pendingGuest) {
    pendingGuest = (async () => {
      const existing = await supabase.auth.getSession();
      if (existing.error) throw existing.error;
      if (existing.data.session) return existing.data.session;
      const guest = await supabase.auth.signInAnonymously();
      if (guest.error) throw guest.error;
      if (!guest.data.session) throw new Error('Session indisponible.');
      return guest.data.session;
    })().finally(() => { pendingGuest = null; });
  }
  return pendingGuest;
}

import { createContext, createElement, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { AppState } from 'react-native';
import { ensureGuestSession, supabase } from './api';
import { createGuestSession, initialAccess, type GuestAccess } from './guestSession';

type GuestContextValue = {
  access: GuestAccess;
  retry: () => void;
  isCurrent: () => boolean;
  ensureOwner: () => Promise<string>;
  owns: (uid: string) => boolean;
};
const GuestContext = createContext<GuestContextValue | null>(null);

export function GuestProvider({ children }: { children: ReactNode }) {
  const [access, setAccess] = useState(initialAccess);
  const [session] = useState(() => createGuestSession(async () => (await ensureGuestSession()).user.id, setAccess));
  useEffect(() => {
    session.start();
    const { data } = supabase.auth.onAuthStateChange((event, value) => {
      // Bootstrap already restores the initial session. Later auth events take precedence.
      if (event !== 'INITIAL_SESSION') session.observe(value?.user.id);
    });
    void session.bootstrap().catch(() => {});
    const appState = AppState.addEventListener('change', state => {
      if (state === 'active') supabase.auth.startAutoRefresh();
      else supabase.auth.stopAutoRefresh();
    });
    return () => {
      session.stop();
      data.subscription.unsubscribe();
      appState.remove();
    };
  }, [session]);

  const generation = access.generation;
  const isCurrent = useCallback(() => session.isCurrent(generation), [session, generation]);
  const owns = useCallback((uid: string) => session.owns(generation, uid), [session, generation]);
  const ensureOwner = useCallback(() => session.ensureOwner(generation), [session, generation]);
  const retry = useCallback(() => { void ensureOwner().catch(() => {}); }, [ensureOwner]);
  return createElement(GuestContext.Provider, { value: { access, retry, isCurrent, ensureOwner, owns } }, children);
}

export function useGuestAccess() {
  const guest = useContext(GuestContext);
  if (!guest) throw new Error('GuestProvider is required.');
  return guest;
}

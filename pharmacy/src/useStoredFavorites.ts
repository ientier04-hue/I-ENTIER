import AsyncStorage from "@react-native-async-storage/async-storage";
import { useEffect, useRef, useState } from "react";
import { createFavoriteStorage } from "./favoriteStorage";

const storage = createFavoriteStorage(AsyncStorage);
const empty: string[] = [];

export function useStoredFavorites(
  key: string | null,
  onError: (message: string) => void,
  errorMessage: string,
) {
  const [snapshot, setSnapshot] = useState<{ key: string; favorites: string[] } | null>(null);
  const owner = useRef<{ key: string } | null>(null);

  useEffect(() => {
    if (!key) return;
    const current = { key };
    owner.current = current;
    storage.load(key).then(favorites => {
      if (owner.current === current) setSnapshot({ key, favorites });
    }).catch(() => {
      if (owner.current !== current) return;
      // Allow another read on the next tap; hydration alone never writes.
      setSnapshot({ key, favorites: [] });
      onError(errorMessage);
    });
    return () => { owner.current = null; };
  }, [key, onError, errorMessage]);

  const ready = snapshot !== null && snapshot.key === key;
  function toggle(ids: string[]) {
    const current = owner.current;
    if (!ready || !current || current.key !== key || !ids.length) return;
    storage.toggle(current.key, ids).then(favorites => {
      if (owner.current === current) setSnapshot({ key: current.key, favorites });
    }).catch(() => {
      if (owner.current === current) onError(errorMessage);
    });
  }

  return { favorites: ready ? snapshot.favorites : empty, ready, toggle };
}

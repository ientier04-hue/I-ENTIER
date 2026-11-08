type Storage = {
  getItem: (key: string) => Promise<string | null>;
  setItem: (key: string, value: string) => Promise<void>;
};

export function createFavoriteStorage(storage: Storage) {
  // A remounted screen must also wait for earlier edits to its storage key.
  const pending = new Map<string, Promise<string[]>>();

  function enqueue(key: string, work: () => Promise<string[]>) {
    const previous = pending.get(key);
    const result = previous ? previous.then(work, work) : Promise.resolve().then(work);
    pending.set(key, result);
    const release = () => {
      if (pending.get(key) === result) pending.delete(key);
    };
    void result.then(release, release);
    return result;
  }

  async function read(key: string) {
    const raw = await storage.getItem(key);
    if (raw === null) return [];
    const items: unknown = JSON.parse(raw);
    if (!Array.isArray(items)) throw new Error("Format de favoris invalide.");
    return items.filter((id): id is string => typeof id === "string");
  }

  return {
    load: (key: string) => enqueue(key, () => read(key)),
    toggle: (key: string, ids: string[]) => enqueue(key, async () => {
      const current = await read(key);
      const group = new Set(ids);
      const next = current.some(id => group.has(id))
        ? current.filter(id => !group.has(id))
        : [...current, ...group];
      await storage.setItem(key, JSON.stringify(next));
      return next;
    }),
  };
}

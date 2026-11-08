export type GuestAccess = {
  generation: number;
} & ({ phase: 'ready'; uid: string } | { phase: 'connecting' | 'unavailable'; uid?: undefined });

export const initialAccess: GuestAccess = { phase: 'connecting', generation: 0 };

export function createGuestSession(connect: () => Promise<string>, publish: (state: GuestAccess) => void) {
  let state = initialAccess;
  let active = false;
  let revision = 0;
  let pending: Promise<string> | null = null;

  function update(next: { phase: 'ready'; uid: string } | { phase: 'connecting' | 'unavailable'; uid?: undefined }) {
    if (next.phase === state.phase && next.uid === state.uid) return;
    // Initial sign-in preserves the draft. Leaving an established patient invalidates their work.
    const generation = state.generation + Number(!!state.uid && next.uid !== state.uid);
    state = { ...next, generation };
    publish(state);
  }
  function isCurrent(generation: number) {
    return active && state.generation === generation;
  }
  function owns(generation: number, uid: string) {
    return isCurrent(generation) && state.uid === uid;
  }
  async function ensureOwner(generation: number): Promise<string> {
    if (!isCurrent(generation)) throw new Error('Session indisponible.');
    if (state.uid) return state.uid;
    if (!pending) {
      const started = revision;
      update({ phase: 'connecting' });
      const request = connect().then(uid => {
        if (active && revision === started) update({ phase: 'ready', uid });
        if (!owns(generation, uid)) throw new Error('Session indisponible.');
        return uid;
      }).catch(() => {
        if (active && revision === started) update({ phase: 'unavailable' });
        throw new Error('Session indisponible. Réessayez.');
      }).finally(() => {
        if (pending === request) pending = null;
      });
      pending = request;
    }
    const uid = await pending;
    if (!owns(generation, uid)) throw new Error('Session indisponible.');
    return uid;
  }
  return {
    start() { active = true; },
    stop() { active = false; revision++; pending = null; },
    observe(uid?: string) {
      if (!active) return;
      revision++;
      update(uid ? { phase: 'ready', uid } : { phase: 'unavailable' });
    },
    bootstrap: () => ensureOwner(state.generation),
    ensureOwner, isCurrent, owns,
  };
}

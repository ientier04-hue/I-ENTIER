import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGuestSession, type GuestAccess } from './guestSession';

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return { promise, resolve };
}

test('offline bootstrap can retry from either screen without discarding an unowned draft', async () => {
  const states: GuestAccess[] = [];
  const signIn = deferred<string>();
  let calls = 0;
  const session = createGuestSession(() => ++calls === 1 ? Promise.reject(new Error('offline')) : signIn.promise,
    state => states.push(state));
  session.start();
  await assert.rejects(session.bootstrap());
  const retry = session.bootstrap();
  const save = session.ensureOwner(0);
  signIn.resolve('first');
  assert.deepEqual(await Promise.all([retry, save]), ['first', 'first']);
  assert.equal(calls, 2);
  assert.deepEqual(states.map(state => state.phase), ['unavailable', 'connecting', 'ready']);
  assert.ok(states.every(state => state.generation === 0));
});

test('a late restore cannot replace an authoritative sign-in, and A → B → A invalidates old operations', async () => {
  const restore = deferred<string>();
  const states: GuestAccess[] = [];
  const session = createGuestSession(() => restore.promise, state => states.push(state));
  session.start();
  const startup = session.bootstrap();
  session.observe('A');
  session.observe('A');
  restore.resolve('obsolete');
  await assert.rejects(startup);
  assert.ok(session.owns(0, 'A'));
  session.observe('B');
  session.observe('A');
  assert.ok(session.owns(2, 'A'));
  assert.equal(session.owns(0, 'A'), false);
  await assert.rejects(session.ensureOwner(0));
  assert.deepEqual(states.map(state => state.uid), ['A', 'B', 'A']);
});

test('a signed-out or stopped provider ignores its outstanding bootstrap', async () => {
  for (const change of ['signOut', 'stop'] as const) {
    const restore = deferred<string>();
    const states: GuestAccess[] = [];
    const session = createGuestSession(() => restore.promise, state => states.push(state));
    session.start();
    const startup = session.bootstrap();
    if (change === 'stop') session.stop();
    else session.observe(undefined);
    restore.resolve('old');
    await assert.rejects(startup);
    assert.equal(session.owns(0, 'old'), false);
    assert.ok(states.every(state => state.phase !== 'ready'));
  }
});

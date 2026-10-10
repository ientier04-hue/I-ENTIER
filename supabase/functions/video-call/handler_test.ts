import assert from 'node:assert/strict';
import { createHandler, type Call, type Dependencies } from './handler.ts';

const id = '00000000-0000-4000-8000-000000000001';
const call: Call = { id, patient_id: 'patient', provider_id: 'doctor', caller_id: 'patient', patient_name: 'Patient', provider_name: 'Doctor', room_name: 'private-room', status: 'accepted' };
function setup(overrides: Partial<Dependencies> = {}) {
  const commands: unknown[][] = [];
  const deps: Dependencies = {
    authenticate: async (token) => token === 'valid' ? 'patient' : null,
    configured: () => true,
    command: async (...args) => { commands.push(args); return call; },
    list: async () => [call], closeFinished: async () => {},
    connect: async () => ({ url: 'wss://test.livekit.cloud', token: 'private-token' }),
    ...overrides,
  };
  return { handler: createHandler(deps), commands };
}
function request(body: unknown, token = 'valid') {
  return new Request('https://test/video-call', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });
}

Deno.test('unauthenticated requests never execute database commands', async () => {
  const { handler, commands } = setup();
  assert.equal((await handler(request({ action: 'start', appointmentId: 'a' }, 'invalid'))).status, 401);
  assert.equal(commands.length, 0);
});
Deno.test('CORS preflight is supported without authenticating', async () => {
  const { handler } = setup({ authenticate: () => { throw new Error('must not authenticate'); } });
  const response = await handler(new Request('https://test', { method: 'OPTIONS' }));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
});
Deno.test('caller identity always comes from the verified session', async () => {
  const { handler, commands } = setup();
  assert.equal((await handler(request({ action: 'start', appointmentId: 'a', actor: 'doctor', room: 'injected' }))).status, 200);
  assert.deepEqual(commands[0], ['patient', 'start', 'a', undefined]);
});
Deno.test('malformed call identifiers cannot reach the database', async () => {
  const { handler, commands } = setup();
  assert.equal((await handler(request({ action: 'join', callId: 'injection' }))).status, 400);
  assert.equal(commands.length, 0);
});
Deno.test('missing LiveKit configuration cannot create an invitation', async () => {
  const { handler, commands } = setup({ configured: () => false });
  const response = await handler(request({ action: 'start', appointmentId: 'a' }));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, 'not_configured');
  assert.equal(commands.length, 0);
});
Deno.test('history remains readable before LiveKit is configured', async () => {
  const { handler } = setup({ configured: () => false });
  const response = await handler(request({ action: 'sync' }));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).configured, false);
});
Deno.test('no media token is issued before acceptance', async () => {
  const { handler } = setup({ command: async () => ({ ...call, status: 'ringing' }), connect: () => { throw new Error('must not connect'); } });
  const response = await handler(request({ action: 'join', callId: id }));
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error, 'call_finished');
});
Deno.test('a third identity cannot obtain a token', async () => {
  const { handler } = setup({ authenticate: async () => 'intruder' });
  assert.equal((await handler(request({ action: 'join', callId: id }))).status, 403);
});
Deno.test('a hangup during room creation does not return a token', async () => {
  let count = 0;
  const { handler } = setup({ command: async () => ({ ...call, status: ++count === 1 ? 'accepted' : 'ended' }) });
  const response = await handler(request({ action: 'join', callId: id }));
  assert.equal(response.status, 409);
  assert.equal((await response.json()).token, undefined);
});
Deno.test('accepted participants receive a non-cacheable connection', async () => {
  const { handler } = setup();
  const response = await handler(request({ action: 'join', callId: id }));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal((await response.json()).token, 'private-token');
});
Deno.test('database access errors use a bounded public error', async () => {
  const { handler } = setup({ command: async () => { throw new Error('not_allowed'); } });
  const response = await handler(request({ action: 'end', callId: id }));
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: 'not_allowed' });
});

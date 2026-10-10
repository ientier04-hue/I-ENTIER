export type Call = {
  id: string;
  caller_id: string;
  patient_id: string;
  provider_id: string;
  patient_name: string;
  provider_name: string;
  room_name: string;
  status: string;
  [key: string]: unknown;
};

export class CallError extends Error {
  constructor(public code: string, public status = 400) { super(code); }
}

export interface Dependencies {
  authenticate(token: string): Promise<string | null>;
  configured(): boolean;
  command(actor: string, action: string, appointmentId?: string, callId?: string): Promise<Call>;
  list(actor: string): Promise<Call[]>;
  closeFinished(actor: string): Promise<void>;
  connect(call: Call, actor: string): Promise<{ url: string; token: string }>;
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json',
};
const actions = new Set(['start', 'accept', 'decline', 'join', 'end', 'fail', 'heartbeat', 'sync']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const knownErrors = new Set(['not_allowed', 'appointment_unavailable', 'outside_call_window', 'participant_busy', 'rate_limited', 'invalid_action', 'call_finished']);

export function createHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return respond({ error: 'method_not_allowed' }, 405);
    try {
      const header = req.headers.get('Authorization') ?? '';
      if (!header.startsWith('Bearer ')) throw new CallError('unauthorized', 401);
      const actor = await deps.authenticate(header.slice(7));
      if (!actor) throw new CallError('unauthorized', 401);
      const raw = await req.text();
      if (raw.length > 4096) throw new CallError('invalid_request', 400);
      let input;
      try { input = JSON.parse(raw); } catch { throw new CallError('invalid_request'); }
      if (!input || typeof input !== 'object' || !actions.has(input.action)) throw new CallError('invalid_action');
      const { action, appointmentId, callId } = input;
      if (action === 'start' && (typeof appointmentId !== 'string' || !appointmentId.trim() || appointmentId.length > 160)) throw new CallError('invalid_request');
      if (!['start', 'sync'].includes(action) && (typeof callId !== 'string' || !uuid.test(callId))) throw new CallError('invalid_request');
      if (['start', 'accept', 'join'].includes(action) && !deps.configured()) throw new CallError('not_configured', 503);
      const call = await deps.command(actor, action, appointmentId, callId);
      // Closing rooms is retried on each sync and by the scheduled cleanup.
      await deps.closeFinished(actor);
      if (action === 'sync') return respond({ calls: await deps.list(actor), configured: deps.configured() });
      if (action === 'join') {
        if (call.status !== 'accepted') throw new CallError('call_finished', 409);
        if (![call.patient_id, call.provider_id].includes(actor)) throw new CallError('not_allowed', 403);
        const connection = await deps.connect(call, actor);
        // Re-check after the external request: an end/cancellation may have raced
        // with room creation. Never return a token for an already-ended call.
        const checked = await deps.command(actor, 'join', undefined, call.id);
        if (checked.status !== 'accepted') {
          await deps.closeFinished(actor);
          throw new CallError('call_finished', 409);
        }
        return respond({ call: checked, ...connection });
      }
      return respond({ call });
    } catch (error) {
      if (error instanceof CallError) return respond({ error: error.code }, error.status);
      const message = error instanceof Error ? error.message : '';
      if (knownErrors.has(message)) return respond({ error: message }, message === 'not_allowed' ? 403 : 409);
      // Never expose SDK errors, credentials, SDP or JWTs in responses/logs.
      console.error('video-call request failed');
      return respond({ error: 'service_unavailable' }, 503);
    }
  };
}

import { createClient } from 'npm:@supabase/supabase-js@2.95.3';
import { AccessToken, RoomServiceClient, TrackSource } from 'npm:livekit-server-sdk@2.19.1';
import type { Call, Dependencies } from '../video-call/handler.ts';

export const admin = createClient(
  Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);
export const db = admin.schema('ientier');
const livekitUrl = Deno.env.get('LIVEKIT_URL') ?? '';
const apiKey = Deno.env.get('LIVEKIT_API_KEY') ?? '';
const apiSecret = Deno.env.get('LIVEKIT_API_SECRET') ?? '';
const configured = () => /^wss:\/\//.test(livekitUrl) && !!apiKey && !!apiSecret;
const rooms = () => new RoomServiceClient(livekitUrl.replace(/^wss:/, 'https:'), apiKey, apiSecret);

export async function closeFinished(actor?: string) {
  if (!configured()) return;
  let query = db.from('video_calls').select('id,room_name')
    .not('ended_at', 'is', null).is('room_closed_at', null).order('ended_at').limit(50);
  if (actor) query = query.or(`patient_id.eq.${actor},provider_id.eq.${actor}`);
  const { data, error } = await query;
  if (error) throw new Error('database_unavailable');
  const service = rooms();
  for (const call of data ?? []) {
    try {
      // RemoveParticipant revokes the participant's existing token in Cloud.
      const participants = await service.listParticipants(call.room_name);
      for (const participant of participants) await service.removeParticipant(call.room_name, participant.identity);
      await service.deleteRoom(call.room_name);
    } catch (error) {
      if ((error as { code?: string }).code !== 'not_found') {
        console.error('video-call room cleanup pending');
        continue;
      }
    }
    await db.from('video_calls').update({ room_closed_at: new Date().toISOString() }).eq('id', call.id);
  }
}

export const dependencies: Dependencies = {
  configured,
  async authenticate(token) {
    const { data, error } = await admin.auth.getUser(token);
    return error || data.user?.is_anonymous ? null : data.user?.id ?? null;
  },
  async command(actor, action, appointmentId, callId) {
    const { data, error } = await db.rpc('video_call_command', {
      p_actor: actor, p_action: action, p_appointment_id: appointmentId ?? null, p_call_id: callId ?? null,
    });
    if (error) throw new Error(error.message);
    return data as Call;
  },
  async list(actor) {
    const { data, error } = await db.from('video_calls').select('*')
      .or(`patient_id.eq.${actor},provider_id.eq.${actor}`).order('created_at', { ascending: false }).limit(100);
    if (error) throw new Error('database_unavailable');
    return data as Call[];
  },
  closeFinished,
  async connect(call, actor) {
    await rooms().createRoom({ name: call.room_name, maxParticipants: 2, emptyTimeout: 90, departureTimeout: 30 });
    const token = new AccessToken(apiKey, apiSecret, {
      identity: actor,
      name: actor === call.patient_id ? call.patient_name : call.provider_name,
      ttl: '2m',
    });
    token.addGrant({
      roomJoin: true, room: call.room_name, canPublish: true, canSubscribe: true,
      canPublishData: false, canUpdateOwnMetadata: false,
      canPublishSources: [TrackSource.CAMERA, TrackSource.MICROPHONE],
    });
    return { url: livekitUrl, token: await token.toJwt() };
  },
};

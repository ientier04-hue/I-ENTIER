import { WebhookReceiver } from 'npm:livekit-server-sdk@2.19.1';
import { db } from '../_shared/video_calls.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const key = Deno.env.get('LIVEKIT_API_KEY');
  const secret = Deno.env.get('LIVEKIT_API_SECRET');
  if (!key || !secret) return new Response('Unavailable', { status: 503 });
  let event;
  try {
    event = await new WebhookReceiver(key, secret).receive(await req.text(), req.headers.get('Authorization') ?? undefined);
  } catch {
    return new Response('Unauthorized', { status: 401 });
  }
  if (event.event === 'room_finished' && event.room?.name) {
    const { error } = await db.from('video_calls').update({
      status: 'ended', ended_at: new Date().toISOString(), room_closed_at: new Date().toISOString(),
    }).eq('room_name', event.room.name).eq('status', 'accepted');
    if (error) return new Response('Retry', { status: 503 });
  }
  return new Response('ok');
});

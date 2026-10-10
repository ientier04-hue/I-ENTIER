import { closeFinished, db } from '../_shared/video_calls.ts';

Deno.serve(async (req) => {
  const secret = Deno.env.get('VIDEO_CALL_CLEANUP_SECRET');
  if (!secret || req.headers.get('Authorization') !== `Bearer ${secret}`) return new Response('Unauthorized', { status: 401 });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const { error } = await db.rpc('expire_video_calls');
  if (error) return new Response('Cleanup failed', { status: 503 });
  await closeFinished();
  return new Response('ok');
});

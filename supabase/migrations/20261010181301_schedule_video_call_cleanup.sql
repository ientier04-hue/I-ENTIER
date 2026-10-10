-- LiveKit rooms must be closed even when both applications have stopped.
-- The matching Edge Function secret is provisioned separately; no secret is
-- stored in migration history or in the cron command.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

SELECT cron.schedule(
  'ientier-video-call-cleanup',
  '* * * * *',
  $job$
    SELECT net.http_post(
      url := 'https://dktjnxbtyhxvapyheosh.supabase.co/functions/v1/video-call-cleanup',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || decrypted_secret
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 10000
    )
    FROM vault.decrypted_secrets
    WHERE name = 'ientier_video_call_cleanup_secret';
  $job$
);

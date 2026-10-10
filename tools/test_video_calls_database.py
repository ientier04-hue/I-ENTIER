"""Exercise the video-call migration in disposable PostgreSQL, never in Cloud."""
from pathlib import Path
import subprocess
import time
import uuid

root = Path(__file__).resolve().parents[1]
name = 'ientier-video-test-' + uuid.uuid4().hex[:8]


def command(args, sql=None):
    result = subprocess.run(args, input=sql, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-6000:] + result.stdout[-2000:])
    return result.stdout


def query(sql):
    return command(['docker', 'exec', '-i', name, 'psql', '-U', 'postgres',
                    '-v', 'ON_ERROR_STOP=1', '-q', '-t'], sql)


command(['docker', 'run', '--detach', '--rm', '--name', name, '--network', 'none',
         '--tmpfs', '/var/lib/postgresql/data', '-e',
         'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17'])
try:
    for _ in range(50):
        try:
            # The image briefly runs a socket-only server during initialization.
            # TCP readiness waits for the final server instead of that transient one.
            command(['docker', 'exec', name, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'])
            break
        except RuntimeError:
            time.sleep(.2)
    else:
        raise RuntimeError('Temporary PostgreSQL failed to start.')
    query("""
      CREATE ROLE anon NOLOGIN;
      CREATE ROLE authenticated NOLOGIN;
      CREATE ROLE service_role NOLOGIN BYPASSRLS;
      CREATE SCHEMA auth;
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
      $$;
      CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
        SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{"is_anonymous": false}')::jsonb
      $$;
      GRANT USAGE ON SCHEMA auth TO authenticated, service_role;
      GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, service_role;
      GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated, service_role;
      CREATE PUBLICATION supabase_realtime;
    """)
    query((root / 'supabase/migrations/202607260001_initial_ientier_schema.sql').read_text())
    query('GRANT USAGE ON SCHEMA ientier TO authenticated, service_role; '
          'GRANT ALL ON ALL TABLES IN SCHEMA ientier TO service_role;')
    for migration in sorted((root / 'supabase/migrations').glob('*video_calls*.sql')):
        query(migration.read_text())
    output = query((root / 'supabase/tests/video_calls.sql').read_text())
    assert 'All video call SQL assertions passed' in output
    print('PASS: migration, RLS, participant authorization, state transitions, expiration and rate limit.')
finally:
    command(['docker', 'stop', name])

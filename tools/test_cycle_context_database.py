"""Validate cycle observations, context and ownership in disposable PostgreSQL."""
from pathlib import Path
import re
import subprocess
import time
import uuid

root = Path(__file__).resolve().parents[1]
name = 'ientier-cycle-test-' + uuid.uuid4().hex[:8]


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
        SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
      $$;
      GRANT USAGE ON SCHEMA auth TO authenticated, service_role;
      GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, service_role;
      GRANT EXECUTE ON FUNCTION auth.jwt() TO authenticated, service_role;
    """)
    query((root / 'supabase/migrations/202607260001_initial_ientier_schema.sql').read_text())
    query('GRANT USAGE ON SCHEMA ientier TO authenticated, anon, service_role;')
    # Apply the real JWT identity binding and table grants used by cycle RLS,
    # without the unrelated Auth/Storage/Realtime infrastructure in this migration.
    integration = (root / 'supabase/migrations/202607260002_supabase_integration.sql').read_text()
    for pattern in [
        r'CREATE OR REPLACE FUNCTION ientier\.current_actor_id\(\).*?\$\$;',
        r'GRANT SELECT, INSERT, UPDATE, DELETE ON\s+ientier\.patient_profiles,.*?TO authenticated;',
    ]:
        statement = re.search(pattern, integration, re.DOTALL)
        assert statement is not None, 'Expected cycle Auth integration statement'
        query(statement.group())
    for suffix in ['cycle_personal_context.sql', 'cycle_context_permanent_accounts.sql',
                   'cycle_physiology_observations.sql']:
        migration = list((root / 'supabase/migrations').glob('*_' + suffix))
        assert len(migration) == 1, f'Expected one migration for {suffix}'
        if suffix == 'cycle_physiology_observations.sql':
            query("""
              INSERT INTO ientier.app_users(user_id) VALUES ('migration-existing-patient');
              INSERT INTO ientier.patient_profiles(patient_id) VALUES ('migration-existing-patient');
              INSERT INTO ientier.cycle_entries(cycle_entry_id, patient_id, entry_date,
                is_period, flow, note, stress_level, sleep_hours)
              VALUES ('migration-existing-entry', 'migration-existing-patient',
                DATE '2026-01-01', true, 'medium', 'Existing observation', 2, 7.5);
            """)
        query(migration[0].read_text())
    preserved = query("""
      SELECT is_period AND flow = 'medium' AND note = 'Existing observation'
        AND entry_date = DATE '2026-01-01' AND stress_level = 2 AND sleep_hours = 7.5
        AND basal_temperature_c IS NULL AND NOT temperature_disturbed
        AND lh_test = '' AND cervical_mucus = ''
      FROM ientier.cycle_entries WHERE cycle_entry_id = 'migration-existing-entry';
    """)
    assert preserved.strip() == 't', 'Migration must preserve existing journal data'
    query("""
      DELETE FROM ientier.patient_profiles WHERE patient_id = 'migration-existing-patient';
      DELETE FROM ientier.app_users WHERE user_id = 'migration-existing-patient';
    """)
    for sql_file, marker in [
        ('cycle_personal_context.sql', 'All cycle context SQL assertions passed'),
        ('cycle_physiology.sql', 'All cycle physiology SQL assertions passed'),
    ]:
        result = query((root / 'supabase/tests' / sql_file).read_text())
        assert marker in result
    print('PASS: context and physiology migrations, ownership, read/write isolation, '
          'round trips, clearing and validation.')
finally:
    command(['docker', 'stop', name])

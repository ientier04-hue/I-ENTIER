"""Run the actual E2EE migration and access tests in disposable PostgreSQL."""
from pathlib import Path
import argparse, subprocess, time, uuid
parser=argparse.ArgumentParser()
parser.add_argument("--without-traditional", action="store_true")
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
name='ientier-vault-test-'+uuid.uuid4().hex[:8]
def command(args,sql=None):
 r=subprocess.run(args,input=sql,text=True,capture_output=True)
 if r.returncode: raise RuntimeError(r.stderr[:1500]+r.stderr[-2000:]+r.stdout[-1000:])
 return r.stdout
def query(sql): return command(['docker','exec','-i',name,'psql','-U','postgres','-v','ON_ERROR_STOP=1','-q','-t'],sql)
command(['docker','run','--detach','--rm','--name',name,'--network','none','--tmpfs','/var/lib/postgresql/data','-e','POSTGRES_HOST_AUTH_METHOD=trust','postgres:17'])
try:
 for _ in range(80):
  try:
   command(['docker','exec',name,'pg_isready','-h','127.0.0.1','-U','postgres']); break
  except RuntimeError: time.sleep(.2)
 query('''
 CREATE ROLE authenticator NOLOGIN; CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN BYPASSRLS;
 CREATE SCHEMA auth;
 CREATE TABLE auth.users(id uuid PRIMARY KEY, email text,phone text,raw_user_meta_data jsonb,raw_app_meta_data jsonb,
 email_confirmed_at timestamptz,banned_until timestamptz,last_sign_in_at timestamptz,created_at timestamptz,updated_at timestamptz,is_anonymous boolean DEFAULT false);
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{"is_anonymous":false}')::jsonb $$;
 GRANT USAGE ON SCHEMA auth TO authenticated,service_role;
 CREATE PUBLICATION supabase_realtime;
 CREATE SCHEMA storage;
 CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 CREATE TABLE storage.objects(id uuid PRIMARY KEY,bucket_id text,name text);
 CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql AS $$ SELECT string_to_array($1,'/') $$;
 ''')
 suffixes=['initial_ientier_schema','supabase_integration','add_symptom_assessments','add_appointment_payment_method','appointment_lifecycle','finalize_supabase_native_schema','add_health_credit','add_maternal_child_health','add_traditional_medicine','add_pharmacy_operations','add_insurance_coverage_validation','allow_admin_insurance_monitoring','allow_admin_insurance_review','add_video_calls','add_video_consultation_actions','fix_consultation_appointment_trigger_context','restrict_consultation_to_identified_accounts','cycle_personal_context','cycle_context_permanent_accounts','cycle_physiology_observations','patient_e2ee_vault']
 for suffix in suffixes:
  if args.without_traditional and suffix == "add_traditional_medicine": continue
  paths=list((root/'supabase/migrations').glob('*_'+suffix+'.sql')); assert len(paths)==1,suffix
  query(paths[0].read_text())
 print('PASS: full vault migration applied ('+('without' if args.without_traditional else 'with')+' traditional tables)')
 test=root/'supabase/tests/patient_e2ee_vault.sql'
 if test.exists():
  output=query(test.read_text())
  print('\n'.join(line.strip() for line in output.splitlines() if 'PASS:' in line))
finally:
 command(['docker','stop',name])

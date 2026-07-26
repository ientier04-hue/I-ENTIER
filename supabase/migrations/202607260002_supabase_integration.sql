-- =============================================================================
-- i-ENTIER -- intégration Supabase
-- Dépend de 202607260001_initial_ientier_schema.sql.
-- =============================================================================

BEGIN;

-- L'identité applicative provient désormais du JWT émis par Supabase Auth.
CREATE OR REPLACE FUNCTION ientier.current_actor_id()
RETURNS VARCHAR(128)
LANGUAGE sql
STABLE
AS $$
  SELECT auth.uid()::TEXT::VARCHAR(128);
$$;

COMMENT ON FUNCTION ientier.current_actor_id() IS
  'Retourne l''identifiant Supabase Auth de la requête courante.';

-- Maintient la projection applicative de auth.users sans exposer cette table
-- système aux trois clients Flutter.
CREATE OR REPLACE FUNCTION ientier.sync_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, auth, public, pg_temp
AS $$
DECLARE
  metadata_name TEXT;
  metadata_photo TEXT;
BEGIN
  metadata_name := COALESCE(
    NULLIF(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''),
    NULLIF(btrim(NEW.raw_user_meta_data ->> 'name'), ''),
    ''
  );
  metadata_photo := COALESCE(
    NULLIF(btrim(NEW.raw_user_meta_data ->> 'avatar_url'), ''),
    NULLIF(btrim(NEW.raw_user_meta_data ->> 'picture'), '')
  );

  INSERT INTO ientier.app_users (
    user_id,
    email,
    display_name,
    photo_url,
    auth_provider,
    phone,
    email_verified,
    disabled_at,
    last_sign_in_at,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id::TEXT,
    NULLIF(NEW.email, ''),
    metadata_name,
    metadata_photo,
    COALESCE(NULLIF(NEW.raw_app_meta_data ->> 'provider', ''), 'email'),
    NULLIF(NEW.phone, ''),
    NEW.email_confirmed_at IS NOT NULL,
    CASE
      WHEN NEW.banned_until IS NOT NULL
       AND NEW.banned_until > CURRENT_TIMESTAMP
        THEN COALESCE(NEW.updated_at, CURRENT_TIMESTAMP)
      ELSE NULL
    END,
    NEW.last_sign_in_at,
    COALESCE(NEW.created_at, CURRENT_TIMESTAMP),
    COALESCE(NEW.updated_at, CURRENT_TIMESTAMP)
  )
  ON CONFLICT (user_id) DO UPDATE
  SET email = EXCLUDED.email,
      display_name = CASE
        WHEN ientier.app_users.display_name = ''
          THEN EXCLUDED.display_name
        ELSE ientier.app_users.display_name
      END,
      photo_url = COALESCE(
        EXCLUDED.photo_url,
        ientier.app_users.photo_url
      ),
      auth_provider = EXCLUDED.auth_provider,
      phone = COALESCE(EXCLUDED.phone, ientier.app_users.phone),
      email_verified = EXCLUDED.email_verified,
      disabled_at = EXCLUDED.disabled_at,
      last_sign_in_at = EXCLUDED.last_sign_in_at,
      updated_at = CURRENT_TIMESTAMP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_synced ON auth.users;
CREATE TRIGGER on_auth_user_synced
AFTER INSERT OR UPDATE OF
  email,
  phone,
  raw_user_meta_data,
  raw_app_meta_data,
  email_confirmed_at,
  banned_until,
  last_sign_in_at
ON auth.users
FOR EACH ROW EXECUTE FUNCTION ientier.sync_auth_user();

-- Rattrapage des comptes éventuellement créés avant cette migration.
INSERT INTO ientier.app_users (
  user_id,
  email,
  display_name,
  photo_url,
  auth_provider,
  phone,
  email_verified,
  disabled_at,
  last_sign_in_at,
  created_at,
  updated_at
)
SELECT
  u.id::TEXT,
  NULLIF(u.email, ''),
  COALESCE(
    NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
    ''
  ),
  COALESCE(
    NULLIF(btrim(u.raw_user_meta_data ->> 'avatar_url'), ''),
    NULLIF(btrim(u.raw_user_meta_data ->> 'picture'), '')
  ),
  COALESCE(NULLIF(u.raw_app_meta_data ->> 'provider', ''), 'email'),
  NULLIF(u.phone, ''),
  u.email_confirmed_at IS NOT NULL,
  CASE
    WHEN u.banned_until IS NOT NULL AND u.banned_until > CURRENT_TIMESTAMP
      THEN COALESCE(u.updated_at, CURRENT_TIMESTAMP)
    ELSE NULL
  END,
  u.last_sign_in_at,
  COALESCE(u.created_at, CURRENT_TIMESTAMP),
  COALESCE(u.updated_at, CURRENT_TIMESTAMP)
FROM auth.users u
ON CONFLICT (user_id) DO NOTHING;

-- API PostgREST : droits de schéma, de tables et de routines.
GRANT USAGE ON SCHEMA ientier TO anon, authenticated, service_role;

GRANT SELECT ON
  ientier.health_service_catalog,
  ientier.laboratory_exam_catalog
TO anon, authenticated;

ALTER TABLE ientier.health_service_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.laboratory_exam_catalog ENABLE ROW LEVEL SECURITY;

CREATE POLICY health_service_catalog_public_select
ON ientier.health_service_catalog FOR SELECT
TO anon, authenticated
USING (TRUE);

CREATE POLICY laboratory_exam_catalog_public_select
ON ientier.laboratory_exam_catalog FOR SELECT
TO anon, authenticated
USING (TRUE);

GRANT SELECT ON
  ientier.v_public_professionals,
  ientier.v_public_institutions,
  ientier.v_provider_application_queue,
  ientier.v_patient_health_timeline
TO authenticated;

GRANT SELECT, INSERT, UPDATE ON ientier.app_users TO authenticated;
GRANT SELECT ON ientier.administrators TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  ientier.patient_profiles,
  ientier.patient_emergency_contacts,
  ientier.patient_medical_items,
  ientier.institution_capabilities,
  ientier.provider_services,
  ientier.provider_appointment_modes,
  ientier.provider_service_modes,
  ientier.provider_availability,
  ientier.health_measurements,
  ientier.cycle_entries,
  ientier.cycle_entry_symptoms,
  ientier.mental_health_entries,
  ientier.mental_health_entry_feelings,
  ientier.preventive_care_records,
  ientier.preventive_care_reminders,
  ientier.prescriptions,
  ientier.prescription_items,
  ientier.notifications
TO authenticated;

GRANT SELECT, INSERT, UPDATE ON ientier.provider_profiles TO authenticated;
GRANT SELECT ON
  ientier.provider_reviews,
  ientier.appointment_status_history,
  ientier.laboratory_results,
  ientier.laboratory_result_items
TO authenticated;
GRANT SELECT, INSERT, UPDATE ON ientier.appointments TO authenticated;

GRANT ALL ON ALL TABLES IN SCHEMA ientier TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA ientier TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ientier TO service_role;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ientier FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ientier.current_actor_id() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION ientier.current_actor_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.review_provider(
  VARCHAR,
  VARCHAR,
  ientier.verification_status,
  VARCHAR
) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.respond_to_appointment(
  VARCHAR,
  VARCHAR,
  ientier.appointment_status,
  VARCHAR
) TO authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ientier
  GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ientier
  GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ientier
  GRANT EXECUTE ON FUNCTIONS TO service_role;

-- Ordonnances numérisées : bucket privé, 10 Mo, PDF et images seulement.
INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'prescriptions',
  'prescriptions',
  FALSE,
  10485760,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ]
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS ientier_prescriptions_select ON storage.objects;
CREATE POLICY ientier_prescriptions_select
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

DROP POLICY IF EXISTS ientier_prescriptions_insert ON storage.objects;
CREATE POLICY ientier_prescriptions_insert
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

DROP POLICY IF EXISTS ientier_prescriptions_update ON storage.objects;
CREATE POLICY ientier_prescriptions_update
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
)
WITH CHECK (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

DROP POLICY IF EXISTS ientier_prescriptions_delete ON storage.objects;
CREATE POLICY ientier_prescriptions_delete
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

-- Flux réellement observés par les trois applications.
DO $$
DECLARE
  relation_name TEXT;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[
    'app_users',
    'patient_profiles',
    'provider_profiles',
    'appointments',
    'health_measurements',
    'cycle_entries',
    'mental_health_entries',
    'laboratory_results',
    'preventive_care_records',
    'preventive_care_reminders',
    'prescriptions',
    'notifications'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'ientier'
        AND tablename = relation_name
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE ientier.%I',
        relation_name
      );
    END IF;
  END LOOP;
END;
$$;

COMMIT;

-- Le réglage explicite évite les erreurs PGRST106 lorsque le tableau de bord
-- tarde à enregistrer un nouveau schéma exposé.
ALTER ROLE authenticator
  SET pgrst.db_schemas = 'public, graphql_public, ientier';

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

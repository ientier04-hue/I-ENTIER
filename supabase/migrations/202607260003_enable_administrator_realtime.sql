-- Permet au portail d'administration d'observer son propre droit d'accès.
-- La politique RLS administrators_select continue de limiter les lignes
-- visibles au compte courant ou à un administrateur actif.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'ientier'
      AND tablename = 'administrators'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE ientier.administrators;
  END IF;
END;
$$;

COMMIT;

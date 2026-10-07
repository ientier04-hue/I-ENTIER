-- Match the hosted Data API with the schema used by the Flutter clients.
-- Preserve the existing exposed schemas while adding ientier.
ALTER ROLE authenticator SET pgrst.db_schemas = 'public, graphql_public, ientier';

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

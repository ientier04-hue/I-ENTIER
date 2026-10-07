-- Catalogue indépendant des comptes de prestataires : le classeur ne contient
-- ni utilisateur, ni coordonnées de contact permettant de créer un profil.
CREATE TABLE ientier.health_facilities (
  facility_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
  source_row integer NOT NULL CHECK (source_row >= 2),
  legacy_id integer,
  source_code text,
  source_name text NOT NULL CHECK (length(btrim(source_name)) > 0),
  display_name text NOT NULL CHECK (length(btrim(display_name)) > 0),
  department text NOT NULL CHECK (length(btrim(department)) > 0),
  arrondissement text NOT NULL CHECK (length(btrim(arrondissement)) > 0),
  commune text NOT NULL CHECK (length(btrim(commune)) > 0),
  communal_section text,
  category text CHECK (category IN (
    'Centre de santé',
    'Centre communautaire de santé',
    'Hôpital communautaire de référence',
    'Hôpital départemental',
    'Hôpital universitaire',
    'Autres hôpitaux',
    'Point de prestation de services',
    'Point fixe'
  )),
  ownership_status text CHECK (ownership_status IN (
    'Publique', 'Privé à but lucratif', 'Privé sans but lucratif', 'Mixte'
  )),
  operation_status text NOT NULL CHECK (operation_status IN (
    'Fonctionnelle', 'Non fonctionnelle', 'À vérifier'
  )),
  source_operation_status text,
  name_review_required boolean NOT NULL DEFAULT false,
  record_review_required boolean NOT NULL DEFAULT false,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT health_facilities_source_row_unique UNIQUE (source_sha256, source_row)
);

-- Le code fourni n'est pas une clé : deux codes sont attribués chacun à deux
-- établissements différents et cinq lignes n'ont pas de code.
CREATE INDEX health_facilities_source_code_idx
  ON ientier.health_facilities (source_code) WHERE source_code IS NOT NULL;
CREATE INDEX health_facilities_location_idx
  ON ientier.health_facilities (department, arrondissement, commune);
CREATE INDEX health_facilities_review_idx
  ON ientier.health_facilities (record_review_required, name_review_required)
  WHERE record_review_required OR name_review_required;

CREATE TRIGGER health_facilities_updated_at
BEFORE UPDATE ON ientier.health_facilities
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

ALTER TABLE ientier.health_facilities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ientier.health_facilities FROM PUBLIC, anon, authenticated;
GRANT SELECT ON ientier.health_facilities TO authenticated;
GRANT UPDATE (
  display_name, department, arrondissement, commune, communal_section,
  category, ownership_status, operation_status,
  name_review_required, record_review_required, published
) ON ientier.health_facilities TO authenticated;
GRANT ALL ON ientier.health_facilities TO service_role;

CREATE POLICY health_facilities_select
ON ientier.health_facilities FOR SELECT TO authenticated
USING (published OR (SELECT ientier.current_actor_is_admin()));

CREATE POLICY health_facilities_admin_update
ON ientier.health_facilities FOR UPDATE TO authenticated
USING ((SELECT ientier.current_actor_is_admin()))
WITH CHECK ((SELECT ientier.current_actor_is_admin()));

COMMENT ON TABLE ientier.health_facilities IS
  'Répertoire importé du classeur des établissements de santé ; distinct des comptes provider_profiles.';
COMMENT ON COLUMN ientier.health_facilities.source_code IS
  'Code du classeur, conservé tel quel ; peut être absent ou partagé par plusieurs lignes.';
COMMENT ON COLUMN ientier.health_facilities.display_name IS
  'Nom affiché provisoire, initialement égal au nom source, à compléter après vérification des sigles.';
COMMENT ON COLUMN ientier.health_facilities.published IS
  'Publication explicite après validation des données ; faux à l’import.';

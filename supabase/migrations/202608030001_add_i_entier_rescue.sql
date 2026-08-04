-- =============================================================================
-- I-Entier Rescue -- Réseau National de Volontaires
-- Coordination de catastrophes, alertes, équipes, ressources et missions.
-- =============================================================================

BEGIN;

CREATE TABLE ientier.rescue_volunteers (
  volunteer_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   VARCHAR(128) NOT NULL UNIQUE
                            REFERENCES ientier.app_users(user_id)
                            ON DELETE CASCADE,
  full_name                 VARCHAR(140) NOT NULL,
  phone                     VARCHAR(40) NOT NULL,
  profession                VARCHAR(40) NOT NULL,
  specialty                 VARCHAR(140) NOT NULL DEFAULT '',
  organization              VARCHAR(180) NOT NULL DEFAULT '',
  skills                    TEXT[] NOT NULL DEFAULT '{}',
  verification_status       VARCHAR(20) NOT NULL DEFAULT 'pending',
  availability              VARCHAR(20) NOT NULL DEFAULT 'offline',
  intervention_radius_km    SMALLINT NOT NULL DEFAULT 25,
  location_consent          BOOLEAN NOT NULL DEFAULT FALSE,
  latitude                  DOUBLE PRECISION,
  longitude                 DOUBLE PRECISION,
  last_location_at          TIMESTAMPTZ,
  review_notes              VARCHAR(1000) NOT NULL DEFAULT '',
  reviewed_by               VARCHAR(128)
                            REFERENCES ientier.administrators(user_id)
                            ON DELETE SET NULL,
  reviewed_at               TIMESTAMPTZ,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_volunteer_identity CHECK (
    length(btrim(full_name)) BETWEEN 3 AND 140
    AND length(btrim(phone)) BETWEEN 8 AND 40
  ),
  CONSTRAINT ck_rescue_volunteer_profession CHECK (
    profession IN (
      'general_practitioner', 'specialist_doctor', 'nurse', 'midwife',
      'paramedic', 'first_responder', 'pharmacist', 'psychologist',
      'health_student', 'other'
    )
  ),
  CONSTRAINT ck_rescue_volunteer_verification CHECK (
    verification_status IN ('pending', 'verified', 'suspended')
  ),
  CONSTRAINT ck_rescue_volunteer_availability CHECK (
    availability IN ('available', 'busy', 'offline')
  ),
  CONSTRAINT ck_rescue_volunteer_radius CHECK (
    intervention_radius_km BETWEEN 5 AND 250
  ),
  CONSTRAINT ck_rescue_volunteer_location CHECK (
    (NOT location_consent AND latitude IS NULL AND longitude IS NULL)
    OR (
      location_consent
      AND latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
    )
  ),
  CONSTRAINT ck_rescue_volunteer_activation CHECK (
    availability = 'offline' OR verification_status = 'verified'
  )
);

COMMENT ON TABLE ientier.rescue_volunteers IS
  'Volontaires Rescue; les coordonnées GPS ne sont conservées qu’avec consentement explicite.';

CREATE TABLE ientier.rescue_volunteer_documents (
  document_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  volunteer_id       UUID NOT NULL
                     REFERENCES ientier.rescue_volunteers(volunteer_id)
                     ON DELETE CASCADE,
  document_type      VARCHAR(30) NOT NULL,
  storage_path       TEXT NOT NULL UNIQUE,
  file_name          VARCHAR(255) NOT NULL,
  verification_status VARCHAR(20) NOT NULL DEFAULT 'pending',
  verified_by        VARCHAR(128)
                     REFERENCES ientier.administrators(user_id)
                     ON DELETE SET NULL,
  verified_at        TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_document_type CHECK (
    document_type IN ('identity', 'professional_license', 'certificate', 'other')
  ),
  CONSTRAINT ck_rescue_document_status CHECK (
    verification_status IN ('pending', 'verified', 'rejected')
  )
);

CREATE TABLE ientier.rescue_events (
  event_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title                    VARCHAR(180) NOT NULL,
  event_type               VARCHAR(30) NOT NULL,
  severity                 VARCHAR(20) NOT NULL,
  status                   VARCHAR(20) NOT NULL DEFAULT 'active',
  zone_name                VARCHAR(220) NOT NULL,
  latitude                 DOUBLE PRECISION,
  longitude                DOUBLE PRECISION,
  affected_radius_km       NUMERIC(7, 2) NOT NULL DEFAULT 10,
  estimated_victims        INTEGER NOT NULL DEFAULT 0,
  intervention_priorities  TEXT[] NOT NULL DEFAULT '{}',
  description              VARCHAR(3000) NOT NULL DEFAULT '',
  created_by               VARCHAR(128) NOT NULL
                           REFERENCES ientier.administrators(user_id)
                           ON DELETE RESTRICT,
  starts_at                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at                 TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_event_title CHECK (length(btrim(title)) BETWEEN 3 AND 180),
  CONSTRAINT ck_rescue_event_type CHECK (
    event_type IN ('earthquake', 'flood', 'cyclone', 'fire', 'epidemic', 'landslide', 'humanitarian_crisis', 'other')
  ),
  CONSTRAINT ck_rescue_event_severity CHECK (
    severity IN ('critical', 'high', 'medium', 'low')
  ),
  CONSTRAINT ck_rescue_event_status CHECK (
    status IN ('draft', 'active', 'contained', 'closed')
  ),
  CONSTRAINT ck_rescue_event_location CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
  ),
  CONSTRAINT ck_rescue_event_counts CHECK (
    affected_radius_km > 0 AND estimated_victims >= 0
  )
);

CREATE TABLE ientier.rescue_operational_sites (
  site_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id         UUID REFERENCES ientier.rescue_events(event_id)
                   ON DELETE SET NULL,
  name             VARCHAR(180) NOT NULL,
  site_type        VARCHAR(30) NOT NULL,
  status           VARCHAR(20) NOT NULL DEFAULT 'open',
  address          VARCHAR(300) NOT NULL DEFAULT '',
  latitude         DOUBLE PRECISION NOT NULL,
  longitude        DOUBLE PRECISION NOT NULL,
  capacity         INTEGER NOT NULL DEFAULT 0,
  contact_phone    VARCHAR(40) NOT NULL DEFAULT '',
  notes            VARCHAR(1000) NOT NULL DEFAULT '',
  created_by       VARCHAR(128) NOT NULL
                   REFERENCES ientier.administrators(user_id)
                   ON DELETE RESTRICT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_site_type CHECK (
    site_type IN ('health_center', 'partner_hospital', 'temporary_shelter', 'distribution_point')
  ),
  CONSTRAINT ck_rescue_site_status CHECK (status IN ('open', 'limited', 'closed')),
  CONSTRAINT ck_rescue_site_location CHECK (
    latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180
  ),
  CONSTRAINT ck_rescue_site_capacity CHECK (capacity >= 0)
);

CREATE TABLE ientier.rescue_urgent_needs (
  need_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id         UUID NOT NULL REFERENCES ientier.rescue_events(event_id)
                   ON DELETE CASCADE,
  site_id          UUID REFERENCES ientier.rescue_operational_sites(site_id)
                   ON DELETE SET NULL,
  need_type        VARCHAR(30) NOT NULL,
  description      VARCHAR(1000) NOT NULL,
  quantity         NUMERIC(12, 2),
  unit             VARCHAR(40) NOT NULL DEFAULT '',
  priority         VARCHAR(20) NOT NULL,
  status           VARCHAR(20) NOT NULL DEFAULT 'open',
  assigned_team_id UUID,
  created_by       VARCHAR(128) NOT NULL
                   REFERENCES ientier.administrators(user_id)
                   ON DELETE RESTRICT,
  resolved_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_need_type CHECK (
    need_type IN ('blood', 'medication', 'medical_equipment', 'ambulance', 'medical_staff', 'drinking_water', 'food')
  ),
  CONSTRAINT ck_rescue_need_priority CHECK (
    priority IN ('critical', 'high', 'medium', 'low')
  ),
  CONSTRAINT ck_rescue_need_status CHECK (status IN ('open', 'in_progress', 'resolved')),
  CONSTRAINT ck_rescue_need_quantity CHECK (quantity IS NULL OR quantity > 0)
);

CREATE TABLE ientier.rescue_resources (
  resource_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          UUID REFERENCES ientier.rescue_events(event_id)
                    ON DELETE CASCADE,
  site_id           UUID REFERENCES ientier.rescue_operational_sites(site_id)
                    ON DELETE SET NULL,
  resource_type     VARCHAR(30) NOT NULL,
  name              VARCHAR(180) NOT NULL,
  available_quantity NUMERIC(12, 2) NOT NULL DEFAULT 0,
  reserved_quantity NUMERIC(12, 2) NOT NULL DEFAULT 0,
  unit              VARCHAR(40) NOT NULL,
  expires_at        TIMESTAMPTZ,
  status            VARCHAR(20) NOT NULL DEFAULT 'available',
  updated_by        VARCHAR(128) NOT NULL
                    REFERENCES ientier.administrators(user_id)
                    ON DELETE RESTRICT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_resource_type CHECK (
    resource_type IN ('blood', 'medication', 'medical_equipment', 'ambulance', 'medical_staff', 'drinking_water', 'food')
  ),
  CONSTRAINT ck_rescue_resource_quantity CHECK (
    available_quantity >= 0 AND reserved_quantity >= 0
    AND reserved_quantity <= available_quantity
  ),
  CONSTRAINT ck_rescue_resource_status CHECK (
    status IN ('available', 'low', 'depleted', 'expired')
  )
);

CREATE TABLE ientier.rescue_teams (
  team_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id         UUID NOT NULL REFERENCES ientier.rescue_events(event_id)
                   ON DELETE CASCADE,
  name             VARCHAR(120) NOT NULL,
  status           VARCHAR(20) NOT NULL DEFAULT 'forming',
  leader_volunteer_id UUID REFERENCES ientier.rescue_volunteers(volunteer_id)
                   ON DELETE SET NULL,
  created_by       VARCHAR(128) NOT NULL
                   REFERENCES ientier.administrators(user_id)
                   ON DELETE RESTRICT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_team_status CHECK (
    status IN ('forming', 'ready', 'deployed', 'returning', 'completed')
  )
);

ALTER TABLE ientier.rescue_urgent_needs
  ADD CONSTRAINT fk_rescue_need_team
  FOREIGN KEY (assigned_team_id) REFERENCES ientier.rescue_teams(team_id)
  ON DELETE SET NULL;

CREATE TABLE ientier.rescue_team_members (
  team_id       UUID NOT NULL REFERENCES ientier.rescue_teams(team_id)
                ON DELETE CASCADE,
  volunteer_id  UUID NOT NULL REFERENCES ientier.rescue_volunteers(volunteer_id)
                ON DELETE RESTRICT,
  role           VARCHAR(120) NOT NULL DEFAULT '',
  joined_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (team_id, volunteer_id)
);

CREATE TABLE ientier.rescue_alerts (
  alert_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          UUID NOT NULL REFERENCES ientier.rescue_events(event_id)
                    ON DELETE CASCADE,
  team_id           UUID REFERENCES ientier.rescue_teams(team_id)
                    ON DELETE SET NULL,
  title             VARCHAR(180) NOT NULL,
  message           VARCHAR(1000) NOT NULL,
  instructions      VARCHAR(2000) NOT NULL DEFAULT '',
  target_professions TEXT[] NOT NULL DEFAULT '{}',
  target_specialties TEXT[] NOT NULL DEFAULT '{}',
  required_skills    TEXT[] NOT NULL DEFAULT '{}',
  priority          VARCHAR(20) NOT NULL,
  push_enabled      BOOLEAN NOT NULL DEFAULT TRUE,
  sms_enabled       BOOLEAN NOT NULL DEFAULT TRUE,
  email_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  status            VARCHAR(20) NOT NULL DEFAULT 'draft',
  created_by        VARCHAR(128) NOT NULL
                    REFERENCES ientier.administrators(user_id)
                    ON DELETE RESTRICT,
  sent_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_alert_priority CHECK (
    priority IN ('critical', 'high', 'medium', 'low')
  ),
  CONSTRAINT ck_rescue_alert_status CHECK (
    status IN ('draft', 'scheduled', 'sent', 'closed', 'cancelled')
  )
);

CREATE TABLE ientier.rescue_assignments (
  assignment_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id          UUID NOT NULL REFERENCES ientier.rescue_alerts(alert_id)
                    ON DELETE CASCADE,
  volunteer_id      UUID NOT NULL REFERENCES ientier.rescue_volunteers(volunteer_id)
                    ON DELETE RESTRICT,
  volunteer_user_id VARCHAR(128) NOT NULL REFERENCES ientier.app_users(user_id)
                    ON DELETE RESTRICT,
  team_id           UUID REFERENCES ientier.rescue_teams(team_id)
                    ON DELETE SET NULL,
  status            VARCHAR(20) NOT NULL DEFAULT 'sent',
  distance_km       NUMERIC(8, 2),
  match_score       NUMERIC(7, 2) NOT NULL DEFAULT 0,
  response_note     VARCHAR(500) NOT NULL DEFAULT '',
  accepted_at       TIMESTAMPTZ,
  en_route_at       TIMESTAMPTZ,
  on_site_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,
  declined_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  UNIQUE (alert_id, volunteer_id),
  CONSTRAINT ck_rescue_assignment_status CHECK (
    status IN ('sent', 'accepted', 'en_route', 'on_site', 'completed', 'declined')
  ),
  CONSTRAINT ck_rescue_assignment_distance CHECK (distance_km IS NULL OR distance_km >= 0)
);

CREATE TABLE ientier.rescue_team_messages (
  message_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id        UUID NOT NULL REFERENCES ientier.rescue_teams(team_id)
                 ON DELETE CASCADE,
  sender_user_id VARCHAR(128) NOT NULL REFERENCES ientier.app_users(user_id)
                 ON DELETE RESTRICT,
  body           VARCHAR(2000) NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_rescue_message_body CHECK (length(btrim(body)) BETWEEN 1 AND 2000)
);

CREATE TABLE ientier.rescue_notification_outbox (
  notification_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id     UUID NOT NULL REFERENCES ientier.rescue_assignments(assignment_id)
                    ON DELETE CASCADE,
  recipient_user_id VARCHAR(128) NOT NULL REFERENCES ientier.app_users(user_id)
                    ON DELETE CASCADE,
  channel           VARCHAR(20) NOT NULL,
  title             VARCHAR(180) NOT NULL,
  body              VARCHAR(1000) NOT NULL,
  delivery_status   VARCHAR(20) NOT NULL DEFAULT 'queued',
  provider_reference VARCHAR(180),
  attempt_count     SMALLINT NOT NULL DEFAULT 0,
  last_error        VARCHAR(1000) NOT NULL DEFAULT '',
  delivered_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  UNIQUE (assignment_id, channel),
  CONSTRAINT ck_rescue_outbox_channel CHECK (channel IN ('push', 'sms', 'email')),
  CONSTRAINT ck_rescue_outbox_status CHECK (
    delivery_status IN ('queued', 'processing', 'delivered', 'failed', 'cancelled')
  ),
  CONSTRAINT ck_rescue_outbox_attempts CHECK (attempt_count BETWEEN 0 AND 20)
);

CREATE INDEX idx_rescue_volunteer_matching
  ON ientier.rescue_volunteers (verification_status, availability, profession, specialty)
  WHERE verification_status = 'verified' AND availability = 'available';
CREATE INDEX idx_rescue_volunteer_location
  ON ientier.rescue_volunteers (latitude, longitude)
  WHERE location_consent AND availability = 'available';
CREATE INDEX idx_rescue_document_queue
  ON ientier.rescue_volunteer_documents (verification_status, created_at);
CREATE INDEX idx_rescue_event_operations
  ON ientier.rescue_events (status, severity, starts_at DESC);
CREATE INDEX idx_rescue_sites_map
  ON ientier.rescue_operational_sites (status, site_type, event_id);
CREATE INDEX idx_rescue_needs_queue
  ON ientier.rescue_urgent_needs (event_id, status, priority, created_at);
CREATE INDEX idx_rescue_resources_available
  ON ientier.rescue_resources (status, resource_type, event_id, site_id);
CREATE INDEX idx_rescue_assignment_volunteer
  ON ientier.rescue_assignments (volunteer_user_id, status, created_at DESC);
CREATE INDEX idx_rescue_assignment_team
  ON ientier.rescue_assignments (team_id, status, created_at DESC);
CREATE INDEX idx_rescue_team_messages
  ON ientier.rescue_team_messages (team_id, created_at DESC);
CREATE INDEX idx_rescue_notification_delivery
  ON ientier.rescue_notification_outbox (delivery_status, channel, created_at)
  WHERE delivery_status IN ('queued', 'failed');

CREATE OR REPLACE FUNCTION ientier.rescue_protect_volunteer_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
BEGIN
  IF ientier.current_actor_id() IS NOT NULL
     AND NOT ientier.current_actor_is_admin() THEN
    IF OLD.user_id <> ientier.current_actor_id() OR NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'volunteer_access_denied';
    END IF;
    NEW.verification_status := OLD.verification_status;
    NEW.review_notes := OLD.review_notes;
    NEW.reviewed_by := OLD.reviewed_by;
    NEW.reviewed_at := OLD.reviewed_at;
  END IF;
  IF NOT NEW.location_consent THEN
    NEW.latitude := NULL;
    NEW.longitude := NULL;
    NEW.last_location_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_00_rescue_protect_volunteer_review
BEFORE UPDATE ON ientier.rescue_volunteers
FOR EACH ROW EXECUTE FUNCTION ientier.rescue_protect_volunteer_review();

CREATE TRIGGER trg_rescue_volunteers_updated_at
BEFORE UPDATE ON ientier.rescue_volunteers
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_events_updated_at
BEFORE UPDATE ON ientier.rescue_events
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_sites_updated_at
BEFORE UPDATE ON ientier.rescue_operational_sites
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_needs_updated_at
BEFORE UPDATE ON ientier.rescue_urgent_needs
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_resources_updated_at
BEFORE UPDATE ON ientier.rescue_resources
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_teams_updated_at
BEFORE UPDATE ON ientier.rescue_teams
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_alerts_updated_at
BEFORE UPDATE ON ientier.rescue_alerts
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_assignments_updated_at
BEFORE UPDATE ON ientier.rescue_assignments
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();
CREATE TRIGGER trg_rescue_notification_outbox_updated_at
BEFORE UPDATE ON ientier.rescue_notification_outbox
FOR EACH ROW EXECUTE FUNCTION ientier.set_updated_at();

CREATE OR REPLACE FUNCTION ientier.rescue_actor_in_team(p_team_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM ientier.rescue_team_members tm
    JOIN ientier.rescue_volunteers v ON v.volunteer_id = tm.volunteer_id
    WHERE tm.team_id = p_team_id
      AND v.user_id = ientier.current_actor_id()
  );
$$;

CREATE OR REPLACE FUNCTION ientier.rescue_operational_map_points(
  p_profession VARCHAR DEFAULT NULL,
  p_specialty VARCHAR DEFAULT NULL
)
RETURNS TABLE (
  point_id UUID,
  point_type TEXT,
  label TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  detail TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
BEGIN
  IF NOT ientier.current_actor_is_admin()
     AND NOT EXISTS (
       SELECT 1 FROM ientier.rescue_volunteers v
       WHERE v.user_id = ientier.current_actor_id()
         AND v.verification_status = 'verified'
     ) THEN
    RAISE EXCEPTION 'verified_rescue_access_required';
  END IF;

  RETURN QUERY
  SELECT
    e.event_id,
    'disaster'::TEXT,
    e.title::TEXT,
    e.latitude,
    e.longitude,
    (e.severity || ' • ' || e.zone_name)::TEXT
  FROM ientier.rescue_events e
  WHERE e.status IN ('active', 'contained')
    AND e.latitude IS NOT NULL AND e.longitude IS NOT NULL
  UNION ALL
  SELECT
    s.site_id,
    s.site_type::TEXT,
    s.name::TEXT,
    s.latitude,
    s.longitude,
    (s.status || CASE WHEN s.address = '' THEN '' ELSE ' • ' || s.address END)::TEXT
  FROM ientier.rescue_operational_sites s
  WHERE s.status IN ('open', 'limited')
  UNION ALL
  SELECT
    v.volunteer_id,
    'volunteer'::TEXT,
    v.full_name::TEXT,
    v.latitude,
    v.longitude,
    (v.profession || CASE WHEN v.specialty = '' THEN '' ELSE ' • ' || v.specialty END)::TEXT
  FROM ientier.rescue_volunteers v
  WHERE v.verification_status = 'verified'
    AND v.availability = 'available'
    AND v.location_consent
    AND v.latitude IS NOT NULL AND v.longitude IS NOT NULL
    AND (p_profession IS NULL OR v.profession = p_profession)
    AND (p_specialty IS NULL OR v.specialty ILIKE '%' || p_specialty || '%');
END;
$$;

CREATE OR REPLACE FUNCTION ientier.rescue_review_volunteer(
  p_volunteer_id UUID,
  p_admin_id VARCHAR,
  p_new_status VARCHAR,
  p_notes VARCHAR DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
BEGIN
  IF ientier.current_actor_id() IS NULL
     OR ientier.current_actor_id() <> p_admin_id
     OR NOT ientier.current_actor_is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;
  IF p_new_status NOT IN ('verified', 'suspended') THEN
    RAISE EXCEPTION 'invalid_review_status';
  END IF;
  IF p_new_status = 'suspended' AND length(btrim(p_notes)) = 0 THEN
    RAISE EXCEPTION 'suspension_reason_required';
  END IF;

  UPDATE ientier.rescue_volunteers
  SET verification_status = p_new_status,
      availability = CASE WHEN p_new_status = 'verified' THEN availability ELSE 'offline' END,
      location_consent = CASE WHEN p_new_status = 'verified' THEN location_consent ELSE FALSE END,
      latitude = CASE WHEN p_new_status = 'verified' THEN latitude ELSE NULL END,
      longitude = CASE WHEN p_new_status = 'verified' THEN longitude ELSE NULL END,
      last_location_at = CASE WHEN p_new_status = 'verified' THEN last_location_at ELSE NULL END,
      review_notes = btrim(p_notes),
      reviewed_by = p_admin_id,
      reviewed_at = CURRENT_TIMESTAMP
  WHERE volunteer_id = p_volunteer_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'volunteer_not_found'; END IF;

  UPDATE ientier.rescue_volunteer_documents
  SET verification_status = CASE WHEN p_new_status = 'verified' THEN 'verified' ELSE verification_status END,
      verified_by = CASE WHEN p_new_status = 'verified' THEN p_admin_id ELSE verified_by END,
      verified_at = CASE WHEN p_new_status = 'verified' THEN CURRENT_TIMESTAMP ELSE verified_at END
  WHERE volunteer_id = p_volunteer_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.rescue_update_assignment_status(
  p_assignment_id UUID,
  p_new_status VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
DECLARE
  target ientier.rescue_assignments%ROWTYPE;
BEGIN
  SELECT * INTO target FROM ientier.rescue_assignments
  WHERE assignment_id = p_assignment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'assignment_not_found'; END IF;
  IF target.volunteer_user_id <> ientier.current_actor_id()
     AND NOT ientier.current_actor_is_admin() THEN
    RAISE EXCEPTION 'assignment_access_denied';
  END IF;
  IF NOT (
    (target.status = 'sent' AND p_new_status IN ('accepted', 'declined'))
    OR (target.status = 'accepted' AND p_new_status = 'en_route')
    OR (target.status = 'en_route' AND p_new_status = 'on_site')
    OR (target.status = 'on_site' AND p_new_status = 'completed')
  ) THEN
    RAISE EXCEPTION 'invalid_assignment_transition';
  END IF;

  UPDATE ientier.rescue_assignments
  SET status = p_new_status,
      accepted_at = CASE WHEN p_new_status = 'accepted' THEN CURRENT_TIMESTAMP ELSE accepted_at END,
      declined_at = CASE WHEN p_new_status = 'declined' THEN CURRENT_TIMESTAMP ELSE declined_at END,
      en_route_at = CASE WHEN p_new_status = 'en_route' THEN CURRENT_TIMESTAMP ELSE en_route_at END,
      on_site_at = CASE WHEN p_new_status = 'on_site' THEN CURRENT_TIMESTAMP ELSE on_site_at END,
      completed_at = CASE WHEN p_new_status = 'completed' THEN CURRENT_TIMESTAMP ELSE completed_at END
  WHERE assignment_id = p_assignment_id;

  UPDATE ientier.rescue_volunteers
  SET availability = CASE
    WHEN p_new_status IN ('accepted', 'en_route', 'on_site') THEN 'busy'
    WHEN p_new_status IN ('completed', 'declined') THEN 'available'
    ELSE availability
  END
  WHERE volunteer_id = target.volunteer_id;
END;
$$;

CREATE OR REPLACE FUNCTION ientier.rescue_auto_assign_alert(
  p_alert_id UUID,
  p_team_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 20
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ientier, public, pg_temp
AS $$
DECLARE
  inserted_count INTEGER;
BEGIN
  IF NOT ientier.current_actor_is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  INSERT INTO ientier.rescue_assignments (
    alert_id, volunteer_id, volunteer_user_id, team_id, distance_km, match_score
  )
  SELECT
    a.alert_id,
    v.volunteer_id,
    v.user_id,
    p_team_id,
    CASE WHEN e.latitude IS NULL OR v.latitude IS NULL THEN NULL ELSE
      6371 * acos(LEAST(1, GREATEST(-1,
        cos(radians(e.latitude)) * cos(radians(v.latitude)) *
        cos(radians(v.longitude) - radians(e.longitude)) +
        sin(radians(e.latitude)) * sin(radians(v.latitude))
      )))
    END AS distance_km,
    (CASE WHEN v.skills && a.required_skills THEN 40 ELSE 0 END)
    + (CASE WHEN cardinality(a.target_professions) = 0 OR v.profession = ANY(a.target_professions) THEN 35 ELSE 0 END)
    + (CASE WHEN cardinality(a.target_specialties) = 0 OR v.specialty = ANY(a.target_specialties) THEN 15 ELSE 0 END)
    + 10 AS match_score
  FROM ientier.rescue_alerts a
  JOIN ientier.rescue_events e ON e.event_id = a.event_id
  CROSS JOIN ientier.rescue_volunteers v
  WHERE a.alert_id = p_alert_id
    AND v.verification_status = 'verified'
    AND v.availability = 'available'
    AND (cardinality(a.target_professions) = 0 OR v.profession = ANY(a.target_professions))
    AND (cardinality(a.target_specialties) = 0 OR v.specialty = ANY(a.target_specialties))
    AND (
      e.latitude IS NULL OR v.latitude IS NULL OR
      6371 * acos(LEAST(1, GREATEST(-1,
        cos(radians(e.latitude)) * cos(radians(v.latitude)) *
        cos(radians(v.longitude) - radians(e.longitude)) +
        sin(radians(e.latitude)) * sin(radians(v.latitude))
      ))) <= v.intervention_radius_km
    )
  ORDER BY match_score DESC, distance_km ASC NULLS LAST, v.updated_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 100))
  ON CONFLICT (alert_id, volunteer_id) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  INSERT INTO ientier.rescue_notification_outbox (
    assignment_id, recipient_user_id, channel, title, body
  )
  SELECT
    ra.assignment_id,
    ra.volunteer_user_id,
    channel.name,
    alert.title,
    alert.message
  FROM ientier.rescue_assignments ra
  JOIN ientier.rescue_alerts alert ON alert.alert_id = ra.alert_id
  CROSS JOIN LATERAL (
    VALUES
      ('push', alert.push_enabled),
      ('sms', alert.sms_enabled),
      ('email', alert.email_enabled)
  ) AS channel(name, enabled)
  WHERE ra.alert_id = p_alert_id AND channel.enabled
  ON CONFLICT (assignment_id, channel) DO NOTHING;

  UPDATE ientier.rescue_alerts
  SET status = 'sent', sent_at = COALESCE(sent_at, CURRENT_TIMESTAMP), team_id = COALESCE(p_team_id, team_id)
  WHERE alert_id = p_alert_id;
  RETURN inserted_count;
END;
$$;

ALTER TABLE ientier.rescue_volunteers ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_volunteer_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_operational_sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_urgent_needs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_team_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ientier.rescue_notification_outbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY rescue_volunteer_owner_select ON ientier.rescue_volunteers FOR SELECT TO authenticated
USING (user_id = ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY rescue_volunteer_owner_insert ON ientier.rescue_volunteers FOR INSERT TO authenticated
WITH CHECK (user_id = ientier.current_actor_id() AND verification_status = 'pending' AND availability = 'offline');
CREATE POLICY rescue_volunteer_owner_update ON ientier.rescue_volunteers FOR UPDATE TO authenticated
USING (user_id = ientier.current_actor_id())
WITH CHECK (user_id = ientier.current_actor_id());
CREATE POLICY rescue_volunteer_admin_all ON ientier.rescue_volunteers FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_documents_participant_select ON ientier.rescue_volunteer_documents FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_volunteers v
    WHERE v.volunteer_id = rescue_volunteer_documents.volunteer_id
      AND v.user_id = ientier.current_actor_id()
  )
);
CREATE POLICY rescue_documents_owner_insert ON ientier.rescue_volunteer_documents FOR INSERT TO authenticated
WITH CHECK (EXISTS (
  SELECT 1 FROM ientier.rescue_volunteers v
  WHERE v.volunteer_id = rescue_volunteer_documents.volunteer_id
    AND v.user_id = ientier.current_actor_id()
));
CREATE POLICY rescue_documents_admin_all ON ientier.rescue_volunteer_documents FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_operations_verified_select ON ientier.rescue_events FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_volunteers v
    WHERE v.user_id = ientier.current_actor_id() AND v.verification_status = 'verified'
  )
);
CREATE POLICY rescue_events_admin_all ON ientier.rescue_events FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_sites_verified_select ON ientier.rescue_operational_sites FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_volunteers v
    WHERE v.user_id = ientier.current_actor_id() AND v.verification_status = 'verified'
  )
);
CREATE POLICY rescue_sites_admin_all ON ientier.rescue_operational_sites FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_needs_verified_select ON ientier.rescue_urgent_needs FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_volunteers v
    WHERE v.user_id = ientier.current_actor_id() AND v.verification_status = 'verified'
  )
);
CREATE POLICY rescue_needs_admin_all ON ientier.rescue_urgent_needs FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_resources_verified_select ON ientier.rescue_resources FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_volunteers v
    WHERE v.user_id = ientier.current_actor_id() AND v.verification_status = 'verified'
  )
);
CREATE POLICY rescue_resources_admin_all ON ientier.rescue_resources FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_teams_members_select ON ientier.rescue_teams FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_team_members tm
    JOIN ientier.rescue_volunteers v ON v.volunteer_id = tm.volunteer_id
    WHERE tm.team_id = rescue_teams.team_id AND v.user_id = ientier.current_actor_id()
  )
);
CREATE POLICY rescue_teams_admin_all ON ientier.rescue_teams FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());
CREATE POLICY rescue_members_participant_select ON ientier.rescue_team_members FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin()
  OR ientier.rescue_actor_in_team(rescue_team_members.team_id)
);
CREATE POLICY rescue_members_admin_all ON ientier.rescue_team_members FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_alert_assignment_select ON ientier.rescue_alerts FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin() OR EXISTS (
    SELECT 1 FROM ientier.rescue_assignments a
    WHERE a.alert_id = rescue_alerts.alert_id AND a.volunteer_user_id = ientier.current_actor_id()
  )
);
CREATE POLICY rescue_alerts_admin_all ON ientier.rescue_alerts FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_assignment_participant_select ON ientier.rescue_assignments FOR SELECT TO authenticated
USING (volunteer_user_id = ientier.current_actor_id() OR ientier.current_actor_is_admin());
CREATE POLICY rescue_assignments_admin_all ON ientier.rescue_assignments FOR ALL TO authenticated
USING (ientier.current_actor_is_admin()) WITH CHECK (ientier.current_actor_is_admin());

CREATE POLICY rescue_messages_member_select ON ientier.rescue_team_messages FOR SELECT TO authenticated
USING (
  ientier.current_actor_is_admin()
  OR ientier.rescue_actor_in_team(rescue_team_messages.team_id)
);
CREATE POLICY rescue_messages_member_insert ON ientier.rescue_team_messages FOR INSERT TO authenticated
WITH CHECK (
  sender_user_id = ientier.current_actor_id() AND (
    ientier.current_actor_is_admin()
    OR ientier.rescue_actor_in_team(rescue_team_messages.team_id)
  )
);

CREATE POLICY rescue_outbox_admin_select ON ientier.rescue_notification_outbox FOR SELECT TO authenticated
USING (ientier.current_actor_is_admin());

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'rescue-documents', 'rescue-documents', FALSE, 10485760,
  ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY rescue_storage_owner_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'rescue-documents'
  AND (storage.foldername(name))[1] = ientier.current_actor_id()
);
CREATE POLICY rescue_storage_participant_select ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'rescue-documents'
  AND ((storage.foldername(name))[1] = ientier.current_actor_id() OR ientier.current_actor_is_admin())
);
CREATE POLICY rescue_storage_admin_update ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'rescue-documents' AND ientier.current_actor_is_admin())
WITH CHECK (bucket_id = 'rescue-documents' AND ientier.current_actor_is_admin());
CREATE POLICY rescue_storage_admin_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'rescue-documents' AND ientier.current_actor_is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON
  ientier.rescue_volunteers,
  ientier.rescue_volunteer_documents,
  ientier.rescue_events,
  ientier.rescue_operational_sites,
  ientier.rescue_urgent_needs,
  ientier.rescue_resources,
  ientier.rescue_teams,
  ientier.rescue_team_members,
  ientier.rescue_alerts,
  ientier.rescue_assignments,
  ientier.rescue_team_messages,
  ientier.rescue_notification_outbox
TO authenticated;
GRANT ALL ON
  ientier.rescue_volunteers,
  ientier.rescue_volunteer_documents,
  ientier.rescue_events,
  ientier.rescue_operational_sites,
  ientier.rescue_urgent_needs,
  ientier.rescue_resources,
  ientier.rescue_teams,
  ientier.rescue_team_members,
  ientier.rescue_alerts,
  ientier.rescue_assignments,
  ientier.rescue_team_messages,
  ientier.rescue_notification_outbox
TO service_role;
GRANT EXECUTE ON FUNCTION ientier.rescue_review_volunteer(UUID, VARCHAR, VARCHAR, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.rescue_update_assignment_status(UUID, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.rescue_auto_assign_alert(UUID, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.rescue_actor_in_team(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION ientier.rescue_operational_map_points(VARCHAR, VARCHAR) TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.rescue_volunteers;
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.rescue_events;
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.rescue_urgent_needs;
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.rescue_alerts;
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.rescue_assignments;
    ALTER PUBLICATION supabase_realtime ADD TABLE ientier.rescue_team_messages;
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMIT;

-- SALY Visual Factory M1: empty, closed-by-default versioned catalog.
-- No screens, images, approved standards, activations, runtime selectors or
-- generation receipts are created. Owner-approved next lot, no broader brand enablement.
-- All writes remain migration-only; future mutations require a separate governed lane.
-- Apply only PR -> PASE -> ready-to-merge -> LF Migration Merge Train.
BEGIN;

DO $preflight$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='visual') THEN
    RAISE EXCEPTION 'SALY_VISUAL_SCHEMA_ALREADY_EXISTS_RECONCILE_FIRST';
  END IF;
  IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1 THEN
    RAISE EXCEPTION 'SALY_VISUAL_PROJECT_AUTHORITY_NOT_CURRENT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='btree_gist')
    OR NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pgcrypto') THEN
    RAISE EXCEPTION 'SALY_VISUAL_REQUIRED_EXTENSIONS_NOT_INSTALLED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon')
    OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated')
    OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
    RAISE EXCEPTION 'SALY_VISUAL_SUPABASE_ROLE_BASELINE_DRIFT';
  END IF;
END $preflight$;

CREATE SCHEMA visual;
REVOKE ALL ON SCHEMA visual FROM PUBLIC;
REVOKE ALL ON SCHEMA visual FROM anon,authenticated;
GRANT USAGE ON SCHEMA visual TO service_role;

-- SALY-only pilot. Future multi-brand use MUST first establish a cross-project
-- brand authority registry and be approved in a separate migration.
CREATE TABLE visual.standards (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_code text NOT NULL DEFAULT 'SALY' CHECK (brand_code='SALY'),
  standard_code text NOT NULL CHECK (standard_code ~ '^[A-Z][A-Z0-9_]{3,79}$'),
  kind text NOT NULL CHECK (kind IN ('BRAND','APP_SCREEN','APP_MOCKUP')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (brand_code,standard_code),
  UNIQUE (id,brand_code,kind)
);

CREATE TABLE visual.standard_versions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  standard_id bigint NOT NULL,
  brand_code text NOT NULL DEFAULT 'SALY' CHECK (brand_code='SALY'),
  kind text NOT NULL CHECK (kind IN ('BRAND','APP_SCREEN','APP_MOCKUP')),
  version text NOT NULL CHECK (version ~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$'),
  parent_version_id bigint,
  manifest_json jsonb NOT NULL CHECK (jsonb_typeof(manifest_json)='object'),
  -- SHA is emitted by PostgreSQL from its jsonb text representation:
  -- do not claim that independent clients use the same canonicalization.
  manifest_sha256 text GENERATED ALWAYS AS (
    encode(extensions.digest(manifest_json::text,'sha256'),'hex')
  ) STORED,
  state text NOT NULL DEFAULT 'DRAFT'
    CHECK (state IN ('DRAFT','CANDIDATE','APPROVED','REVOKED')),
  approval_ref text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (state<>'APPROVED' OR nullif(btrim(approval_ref),'') IS NOT NULL),
  UNIQUE (standard_id,version),
  UNIQUE (id,standard_id),
  UNIQUE (id,brand_code,kind),
  FOREIGN KEY (standard_id,brand_code,kind)
    REFERENCES visual.standards(id,brand_code,kind) ON DELETE RESTRICT,
  FOREIGN KEY (parent_version_id,standard_id)
    REFERENCES visual.standard_versions(id,standard_id) ON DELETE RESTRICT,
  CHECK (parent_version_id IS NULL OR parent_version_id<>id)
);

CREATE TABLE visual.standard_activations (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_code text NOT NULL DEFAULT 'SALY' CHECK (brand_code='SALY'),
  kind text NOT NULL CHECK (kind IN ('BRAND','APP_SCREEN','APP_MOCKUP')),
  channel_code text NOT NULL CHECK (channel_code ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  audience_code text NOT NULL CHECK (audience_code ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  device_class text NOT NULL CHECK (device_class ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  output_target text NOT NULL CHECK (output_target IN ('APP_SCREEN','APP_MOCKUP','IMAGE','PDF','PPTX','HTML')),
  standard_version_id bigint NOT NULL,
  valid_from timestamptz NOT NULL,
  valid_to timestamptz,
  approval_ref text NOT NULL CHECK (nullif(btrim(approval_ref),'') IS NOT NULL),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (standard_version_id,brand_code,kind)
    REFERENCES visual.standard_versions(id,brand_code,kind) ON DELETE RESTRICT,
  CHECK (valid_to IS NULL OR valid_to>valid_from),
  -- Crucial: exclude by the request context, NOT by standard_version_id;
  -- otherwise two different versions could be ACTIVE concurrently.
  EXCLUDE USING gist (
    brand_code WITH =,
    kind WITH =,
    channel_code WITH =,
    audience_code WITH =,
    device_class WITH =,
    output_target WITH =,
    tstzrange(valid_from,coalesce(valid_to,'infinity'::timestamptz),'[)') WITH &&
  )
);

CREATE TABLE visual.source_assets (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_code text NOT NULL DEFAULT 'SALY' CHECK (brand_code='SALY'),
  asset_code text NOT NULL CHECK (asset_code ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  version_number integer NOT NULL CHECK (version_number>0),
  source_kind text NOT NULL CHECK (source_kind IN
    ('SCREEN','FRAME','BACKGROUND','ICON','OTHER')),
  provider text NOT NULL,
  file_ref text NOT NULL CHECK (nullif(btrim(file_ref),'') IS NOT NULL),
  source_sha256 text CHECK (source_sha256 ~ '^[a-f0-9]{64}$'),
  independent_sha_verified boolean NOT NULL DEFAULT false,
  approval_status text NOT NULL DEFAULT 'CANDIDATE'
    CHECK (approval_status IN ('CANDIDATE','APPROVED','REVOKED')),
  approval_ref text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(metadata)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (brand_code,asset_code,version_number),
  CHECK (approval_status<>'APPROVED' OR
    (source_sha256 IS NOT NULL AND independent_sha_verified
     AND nullif(btrim(approval_ref),'') IS NOT NULL))
);

CREATE TABLE visual.generation_receipts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  brand_code text NOT NULL DEFAULT 'SALY' CHECK (brand_code='SALY'),
  request_ref text NOT NULL CHECK (nullif(btrim(request_ref),'') IS NOT NULL),
  mode text NOT NULL CHECK (mode IN ('OFFICIAL','EXPLORE')),
  state text NOT NULL CHECK (state IN ('BLOCKED','CANDIDATE','APPROVED')),
  version_refs jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(version_refs)='array'),
  dependency_digest text CHECK (dependency_digest ~ '^[a-f0-9]{64}$'),
  input_source_refs jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(input_source_refs)='array'),
  input_digest text CHECK (input_digest ~ '^[a-f0-9]{64}$'),
  engine_ref text,
  output_refs jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(output_refs)='array'),
  output_digest text CHECK (output_digest ~ '^[a-f0-9]{64}$'),
  qa_status text NOT NULL CHECK (qa_status IN ('NOT_RUN','PASS','FAIL','BLOCKED')),
  decision_ref text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (state<>'APPROVED' OR
    (mode='OFFICIAL' AND qa_status='PASS' AND output_digest IS NOT NULL
      AND jsonb_array_length(output_refs)>0 AND nullif(btrim(decision_ref),'') IS NOT NULL))
);

-- Protect history even from future operator paths:
-- versions may only progress their state; immutable manifests always remain.
CREATE FUNCTION visual.guard_standard_version_history_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path='pg_catalog','visual'
AS $function$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_DELETE_FORBIDDEN';
  END IF;
  IF NEW.standard_id IS DISTINCT FROM OLD.standard_id
    OR NEW.brand_code IS DISTINCT FROM OLD.brand_code
    OR NEW.kind IS DISTINCT FROM OLD.kind
    OR NEW.version IS DISTINCT FROM OLD.version
    OR NEW.parent_version_id IS DISTINCT FROM OLD.parent_version_id
    OR NEW.manifest_json IS DISTINCT FROM OLD.manifest_json
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_MANIFEST_IMMUTABLE'; END IF;
  IF NEW.state IS DISTINCT FROM OLD.state
    AND NOT (
      (OLD.state='DRAFT' AND NEW.state IN ('CANDIDATE','REVOKED'))
      OR (OLD.state='CANDIDATE' AND NEW.state IN ('APPROVED','REVOKED'))
      OR (OLD.state='APPROVED' AND NEW.state='REVOKED')
    )
  THEN RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_INVALID_TRANSITION'; END IF;
  IF OLD.state IN ('APPROVED','REVOKED')
     AND NEW.approval_ref IS DISTINCT FROM OLD.approval_ref
  THEN RAISE EXCEPTION 'VISUAL_STANDARD_VERSION_APPROVAL_REF_IMMUTABLE'; END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER trg_visual_standard_versions_guard_v1
BEFORE UPDATE OR DELETE ON visual.standard_versions
FOR EACH ROW EXECUTE FUNCTION visual.guard_standard_version_history_v1();

-- No activation without the exact APPROVED revision in the same brand+kind.
CREATE FUNCTION visual.guard_standard_activation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path='pg_catalog','visual'
AS $function$
DECLARE v_state text;
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'VISUAL_STANDARD_ACTIVATION_HISTORY_DELETE_FORBIDDEN';
  END IF;
  IF TG_OP='UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.brand_code IS DISTINCT FROM OLD.brand_code
       OR NEW.kind IS DISTINCT FROM OLD.kind
       OR NEW.channel_code IS DISTINCT FROM OLD.channel_code
       OR NEW.audience_code IS DISTINCT FROM OLD.audience_code
       OR NEW.device_class IS DISTINCT FROM OLD.device_class
       OR NEW.output_target IS DISTINCT FROM OLD.output_target
       OR NEW.standard_version_id IS DISTINCT FROM OLD.standard_version_id
       OR NEW.valid_from IS DISTINCT FROM OLD.valid_from
       OR NEW.approval_ref IS DISTINCT FROM OLD.approval_ref
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN RAISE EXCEPTION 'VISUAL_STANDARD_ACTIVATION_IMMUTABLE'; END IF;
    -- Only close or shorten an existing activation, never reopen it.
    IF OLD.valid_to IS NOT NULL AND
       (NEW.valid_to IS NULL OR NEW.valid_to>OLD.valid_to) THEN
      RAISE EXCEPTION 'VISUAL_STANDARD_ACTIVATION_EXTENSION_FORBIDDEN';
    END IF;
  END IF;
  SELECT v.state INTO v_state FROM visual.standard_versions v
  WHERE v.id=NEW.standard_version_id AND v.brand_code=NEW.brand_code
    AND v.kind=NEW.kind FOR SHARE;
  IF v_state IS DISTINCT FROM 'APPROVED' THEN
    RAISE EXCEPTION 'VISUAL_STANDARD_ACTIVATION_UNAPPROVED_VERSION';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER trg_visual_standard_activations_guard_v1
BEFORE INSERT OR UPDATE OR DELETE ON visual.standard_activations
FOR EACH ROW EXECUTE FUNCTION visual.guard_standard_activation_v1();

-- Sources and receipts must be versioned by inserting new rows, not rewritten.
CREATE FUNCTION visual.guard_append_only_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path='pg_catalog','visual'
AS $function$
BEGIN
  RAISE EXCEPTION 'VISUAL_APPEND_ONLY_%',TG_TABLE_NAME;
END
$function$;
CREATE TRIGGER trg_visual_standards_append_only_v1
BEFORE UPDATE OR DELETE ON visual.standards
FOR EACH ROW EXECUTE FUNCTION visual.guard_append_only_v1();
CREATE TRIGGER trg_visual_source_assets_append_only_v1
BEFORE UPDATE OR DELETE ON visual.source_assets
FOR EACH ROW EXECUTE FUNCTION visual.guard_append_only_v1();
CREATE TRIGGER trg_visual_generation_receipts_append_only_v1
BEFORE UPDATE OR DELETE ON visual.generation_receipts
FOR EACH ROW EXECUTE FUNCTION visual.guard_append_only_v1();

-- Default-deny even if the schema is accidentally exposed by a PostgREST config.
ALTER TABLE visual.standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE visual.standard_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE visual.standard_activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE visual.source_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE visual.generation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE visual.standards FORCE ROW LEVEL SECURITY;
ALTER TABLE visual.standard_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE visual.standard_activations FORCE ROW LEVEL SECURITY;
ALTER TABLE visual.source_assets FORCE ROW LEVEL SECURITY;
ALTER TABLE visual.generation_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA visual FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA visual FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA visual FROM PUBLIC,anon,authenticated;
GRANT SELECT ON visual.standards,visual.standard_versions,
  visual.standard_activations,visual.source_assets,visual.generation_receipts
  TO service_role;
-- Deliberately NO INSERT/UPDATE/DELETE grants and NO generation selector RPC.

DO $postflight$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM pg_class c JOIN pg_namespace n
  ON n.oid=c.relnamespace
  WHERE n.nspname='visual'
    AND c.relname IN ('standards','standard_versions','standard_activations',
                      'source_assets','generation_receipts')
    AND c.relkind='r'
    AND c.relrowsecurity=true AND c.relforcerowsecurity=true;
  IF v_count<>5 THEN RAISE EXCEPTION 'SALY_VISUAL_CATALOG_TABLES_OR_RLS_NOT_READY'; END IF;
  IF (SELECT count(*) FROM visual.standards)<>0
    OR (SELECT count(*) FROM visual.standard_versions)<>0
    OR (SELECT count(*) FROM visual.standard_activations)<>0
    OR (SELECT count(*) FROM visual.source_assets)<>0
    OR (SELECT count(*) FROM visual.generation_receipts)<>0
  THEN RAISE EXCEPTION 'SALY_VISUAL_CATALOG_MUST_START_EMPTY'; END IF;
  IF has_schema_privilege('anon','visual','USAGE')
    OR has_schema_privilege('authenticated','visual','USAGE')
    OR has_table_privilege('anon','visual.standards','SELECT')
    OR has_table_privilege('authenticated','visual.source_assets','SELECT')
    OR has_table_privilege('service_role','visual.standard_activations','INSERT')
  THEN RAISE EXCEPTION 'SALY_VISUAL_UNEXPECTED_CLIENT_OR_SERVICE_WRITE_GRANT'; END IF;
END
$postflight$;

COMMENT ON SCHEMA visual IS
'SALY-only candidate visual standard catalog: default-deny, all tables empty, no selector/activation/production use until separate governed integration.';
COMMIT;

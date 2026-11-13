-- PG18 TEST FIXTURE: live Supabase OBJECT DEFINITIONS captured read-only 2026-11-13.

-- This recreates the scoped exact column types, current named constraints, indexes,

-- SQL function definitions and operation catalog rows. NOT full Supabase database,

-- no live credentials, no verification of external JWT signature/model invocation.

CREATE SCHEMA IF NOT EXISTS extensions; CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS lf_ops;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DO $roles$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;

IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;

IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END $roles$;

-- PostgREST claims STUB only for in-process SQL tests. Real JWT cryptographic proof requires Supabase Auth/Edge.

CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claims',true),'')::jsonb $$;

CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;

CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.role',true),'') $$;

GRANT USAGE ON SCHEMA auth TO authenticated; GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO authenticated;

GRANT USAGE ON SCHEMA public,lf_ops TO authenticated,service_role;

GRANT USAGE ON SCHEMA extensions TO authenticated,service_role;

CREATE TABLE "lf_ops"."pantallas" (
  id integer NOT NULL,
  codigo text NOT NULL,
  nombre text NOT NULL,
  descripcion text,
  flujo text,
  paso text,
  estado text NOT NULL DEFAULT 'CANDIDATO'::text,
  activa boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  drive_file_id text,
  drive_url text,
  drive_filename text,
  drive_updated_at timestamp with time zone,
  module_code text,
  version text NOT NULL DEFAULT 'v0.1'::text,
  owner_name text,
  objective text,
  allowed_profiles jsonb NOT NULL DEFAULT '[]'::jsonb,
  dependencies jsonb NOT NULL DEFAULT '[]'::jsonb,
  source_decision_id text,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  module_id bigint,
  source_decision_number bigint
);

CREATE TABLE "lf_ops"."reglas" (
  id integer NOT NULL,
  codigo text NOT NULL,
  categoria text NOT NULL,
  titulo text NOT NULL,
  descripcion text NOT NULL,
  razon text,
  valor_config jsonb,
  es_transversal boolean NOT NULL DEFAULT false,
  estado text NOT NULL DEFAULT 'CANDIDATO'::text,
  origen text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  pendiente_decision boolean NOT NULL DEFAULT false,
  pendiente_detalle text,
  created_by text
);

CREATE TABLE "lf_ops"."reglas_pantallas" (
  id integer NOT NULL,
  regla_id integer NOT NULL,
  pantalla_id integer NOT NULL,
  nota text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE "public"."lf_activos" (
  id bigint NOT NULL,
  codigo_activo text NOT NULL,
  nombre_canonico text NOT NULL,
  tipo_activo text NOT NULL,
  subtipo_activo text,
  tipo_original text,
  formato_nativo text,
  linea_codigo text,
  estado_original text,
  estado_documental text NOT NULL,
  estado_operativo text NOT NULL,
  nivel_control text,
  runtime_estado text,
  impacto_automatico text,
  accion_migracion text,
  version text,
  ruta_esperada text,
  url text,
  owner_name text,
  ultima_revision text,
  rol_arquitectura text,
  source_spreadsheet_id text NOT NULL,
  source_spreadsheet_title text NOT NULL,
  source_sheet_name text NOT NULL,
  source_row_number integer NOT NULL,
  migration_batch_id uuid NOT NULL,
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  archived_at timestamp with time zone,
  archived_reason text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text
);

CREATE TABLE "public"."lf_execution_mode_catalog" (
  execution_mode text NOT NULL,
  description text NOT NULL,
  allows_partial_input boolean NOT NULL DEFAULT false,
  canonical_write_allowed boolean NOT NULL DEFAULT false,
  runtime_allowed boolean NOT NULL DEFAULT false,
  promotion_allowed boolean NOT NULL DEFAULT false,
  requires_evidence_complete boolean NOT NULL DEFAULT false,
  reference_source text NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE'::text,
  created_by_execution_id text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE "public"."lf_operation_execution" (
  execution_id text NOT NULL,
  operation_code text NOT NULL,
  target_type text NOT NULL,
  target_code text NOT NULL,
  target_repo text,
  target_path text,
  status text NOT NULL DEFAULT 'IN_PROGRESS'::text,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text,
  idempotency_key text,
  request_sha256 text,
  lease_owner text,
  lease_expires_at timestamp with time zone,
  lease_fence bigint NOT NULL DEFAULT 0,
  checkpoint_seq bigint NOT NULL DEFAULT 0,
  checkpoint_payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE "public"."lf_operation_execution_steps" (
  execution_id text NOT NULL,
  step_order integer NOT NULL,
  step_id text NOT NULL,
  status text NOT NULL,
  evidence_ref text,
  evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  observed_at timestamp with time zone NOT NULL DEFAULT now(),
  notes text,
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by_execution_id text,
  updated_at timestamp with time zone
);

CREATE TABLE "public"."lf_operation_judges" (
  operation_code text NOT NULL,
  judge_code text NOT NULL,
  judge_path text NOT NULL,
  judge_sha text,
  pass_if jsonb NOT NULL DEFAULT '[]'::jsonb,
  fail_if jsonb NOT NULL DEFAULT '[]'::jsonb,
  result_values jsonb NOT NULL DEFAULT '["PASS", "FAIL", "BLOCKED"]'::jsonb,
  status text NOT NULL DEFAULT 'CANDIDATO_READ_ONLY'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text
);

CREATE TABLE "public"."lf_operation_mode_bindings" (
  operation_code text NOT NULL,
  task_mode text NOT NULL,
  execution_mode text NOT NULL,
  allowed boolean NOT NULL DEFAULT false,
  write_allowed boolean NOT NULL DEFAULT false,
  destination_kind text NOT NULL,
  input_completeness text NOT NULL,
  canonical_state text,
  required_existing_state text,
  notes text,
  status text NOT NULL DEFAULT 'ACTIVE'::text,
  created_by_execution_id text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE "public"."lf_operation_registry" (
  operation_code text NOT NULL,
  version text NOT NULL,
  status text NOT NULL,
  source_model text NOT NULL DEFAULT 'GIT_FIRST_YAML'::text,
  source_repo text NOT NULL,
  source_paths jsonb NOT NULL DEFAULT '[]'::jsonb,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  operation_family text,
  operation_domain text,
  operation_type text,
  applies_to_asset_type text,
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text,
  lifecycle_state_code text NOT NULL
);

CREATE TABLE "public"."lf_operation_step_contracts" (
  operation_code text NOT NULL,
  step_id text NOT NULL,
  step_order integer NOT NULL,
  execution_order integer NOT NULL,
  contract_code text NOT NULL,
  purpose text NOT NULL,
  input_required jsonb NOT NULL DEFAULT '[]'::jsonb,
  resolver_ref text NOT NULL DEFAULT 'GPT_RUNTIME_WITH_SUPABASE_CONTEXT'::text,
  output_payload jsonb NOT NULL DEFAULT '[]'::jsonb,
  pass_condition jsonb NOT NULL DEFAULT '{}'::jsonb,
  block_condition jsonb NOT NULL DEFAULT '{}'::jsonb,
  blocking_code text NOT NULL,
  mini_judge_code text NOT NULL,
  required_evidence_keys jsonb NOT NULL DEFAULT '[]'::jsonb,
  next_if_pass text,
  next_if_blocked text,
  status text NOT NULL DEFAULT 'ACTIVE'::text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  execution_sql text,
  fail_condition jsonb,
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text
);

CREATE TABLE "public"."lf_operation_step_judge_bindings" (
  operation_code text NOT NULL,
  step_order integer NOT NULL,
  step_id text NOT NULL,
  judge_code text NOT NULL,
  clean_result_value text NOT NULL,
  blocked_result_value text NOT NULL,
  return_result_value text NOT NULL,
  required_evidence_keys jsonb NOT NULL DEFAULT '[]'::jsonb,
  status text NOT NULL DEFAULT 'ACTIVE_ENFORCEMENT'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text
);

CREATE TABLE "public"."lf_operation_steps" (
  operation_code text NOT NULL,
  step_order integer NOT NULL,
  step_id text NOT NULL,
  required boolean NOT NULL DEFAULT true,
  evidence_required text NOT NULL,
  source_path text NOT NULL,
  source_sha text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  execution_order integer,
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN'::text,
  updated_by_execution_id text
);

CREATE TABLE "public"."lf_profile_write_authority_v1" (
  profile_code text NOT NULL,
  operation_code text NOT NULL,
  status text NOT NULL DEFAULT 'PROPOSED'::text,
  basis text,
  self_update_allowed boolean NOT NULL DEFAULT false
);

CREATE TABLE "public"."lf_rule_promotion_v1" (
  promotion_id text NOT NULL DEFAULT ('PROM-'::text || upper(substr(md5(((random())::text || (clock_timestamp())::text)), 1, 16))),
  rule_code text NOT NULL,
  request_execution_id text NOT NULL,
  requested_by_profile text NOT NULL,
  request_snapshot_sha256 text NOT NULL,
  status text NOT NULL DEFAULT 'PENDING'::text,
  reason text,
  decided_by text,
  decided_at timestamp with time zone,
  applied_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE "public"."lf_skill_catalog_v1" (
  skill_code text NOT NULL,
  description text NOT NULL,
  required_operation text NOT NULL,
  handler_fn text NOT NULL,
  effect text NOT NULL,
  input_required text[] NOT NULL DEFAULT '{}'::text[],
  status text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  opener_fn text,
  child_caller jsonb
);

CREATE TABLE "public"."lf_skill_invocation_v1" (
  skill_run_id text NOT NULL,
  skill_code text NOT NULL,
  parent_execution_id text NOT NULL,
  profile_code text,
  status text NOT NULL,
  blocking_code text,
  input_sha256 text,
  output jsonb,
  evidence_ref text,
  child_execution_id text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE "public"."lf_task_mode_catalog" (
  task_mode text NOT NULL,
  description text NOT NULL,
  allows_new_target boolean NOT NULL DEFAULT false,
  requires_existing_target boolean NOT NULL DEFAULT false,
  mutation_intent boolean NOT NULL DEFAULT false,
  reference_source text NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE'::text,
  created_by_execution_id text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE SEQUENCE IF NOT EXISTS lf_ops.pantallas_id_seq; ALTER TABLE "lf_ops"."pantallas" ALTER COLUMN "id" SET DEFAULT nextval('lf_ops.pantallas_id_seq'::regclass);

ALTER TABLE "lf_ops"."pantallas" ADD CONSTRAINT "pantallas_codigo_key" UNIQUE (codigo);

ALTER TABLE "lf_ops"."pantallas" ADD CONSTRAINT "pantallas_pkey" PRIMARY KEY (id);

CREATE INDEX idx_pantallas_module ON lf_ops.pantallas USING btree (module_code, estado);

ALTER TABLE "lf_ops"."pantallas" ENABLE ROW LEVEL SECURITY;

CREATE SEQUENCE IF NOT EXISTS lf_ops.reglas_id_seq; ALTER TABLE "lf_ops"."reglas" ALTER COLUMN "id" SET DEFAULT nextval('lf_ops.reglas_id_seq'::regclass);

ALTER TABLE "lf_ops"."reglas" ADD CONSTRAINT "reglas_codigo_key" UNIQUE (codigo);

ALTER TABLE "lf_ops"."reglas" ADD CONSTRAINT "reglas_pkey" PRIMARY KEY (id);

CREATE INDEX idx_reglas_categoria ON lf_ops.reglas USING btree (categoria);

CREATE INDEX idx_reglas_estado ON lf_ops.reglas USING btree (estado);

ALTER TABLE "lf_ops"."reglas" ENABLE ROW LEVEL SECURITY;

CREATE SEQUENCE IF NOT EXISTS lf_ops.reglas_pantallas_id_seq; ALTER TABLE "lf_ops"."reglas_pantallas" ALTER COLUMN "id" SET DEFAULT nextval('lf_ops.reglas_pantallas_id_seq'::regclass);

ALTER TABLE "lf_ops"."reglas_pantallas" ADD CONSTRAINT "reglas_pantallas_pkey" PRIMARY KEY (id);

ALTER TABLE "lf_ops"."reglas_pantallas" ADD CONSTRAINT "reglas_pantallas_regla_id_pantalla_id_key" UNIQUE (regla_id, pantalla_id);

CREATE INDEX idx_reglas_pantallas_screen ON lf_ops.reglas_pantallas USING btree (pantalla_id);

CREATE INDEX idx_rp_regla ON lf_ops.reglas_pantallas USING btree (regla_id);

ALTER TABLE "lf_ops"."reglas_pantallas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_activos" ADD CONSTRAINT "lf_activos_codigo_activo_key" UNIQUE (codigo_activo);

ALTER TABLE "public"."lf_activos" ADD CONSTRAINT "lf_activos_operational_url_supabase_only_chk" CHECK (((archived_at IS NOT NULL) OR (url IS NULL) OR (url ~~ 'supabase://%'::text)));

ALTER TABLE "public"."lf_activos" ADD CONSTRAINT "lf_activos_pkey" PRIMARY KEY (id);

CREATE INDEX lf_activos_batch_idx ON public.lf_activos USING btree (migration_batch_id);

CREATE INDEX lf_activos_estado_documental_idx ON public.lf_activos USING btree (estado_documental);

CREATE INDEX lf_activos_estado_operativo_idx ON public.lf_activos USING btree (estado_operativo);

CREATE INDEX lf_activos_linea_idx ON public.lf_activos USING btree (linea_codigo);

CREATE INDEX lf_activos_tipo_idx ON public.lf_activos USING btree (tipo_activo);

CREATE INDEX lf_activos_updated_at_idx ON public.lf_activos USING btree (updated_at DESC);

ALTER TABLE "public"."lf_activos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_execution_mode_catalog" ADD CONSTRAINT "lf_execution_mode_catalog_pkey" PRIMARY KEY (execution_mode);

ALTER TABLE "public"."lf_execution_mode_catalog" ADD CONSTRAINT "lf_execution_mode_catalog_status_check" CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'RETIRED'::text])));

ALTER TABLE "public"."lf_execution_mode_catalog" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_execution" ADD CONSTRAINT "lf_operation_execution_idempotency_pair_ck" CHECK ((((idempotency_key IS NULL) AND (request_sha256 IS NULL)) OR ((idempotency_key IS NOT NULL) AND (btrim(idempotency_key) <> ''::text) AND (length(idempotency_key) <= 200) AND (request_sha256 ~ '^[0-9a-f]{64}$'::text))));

ALTER TABLE "public"."lf_operation_execution" ADD CONSTRAINT "lf_operation_execution_lease_pair_ck" CHECK ((((lease_owner IS NULL) AND (lease_expires_at IS NULL)) OR ((lease_owner IS NOT NULL) AND (btrim(lease_owner) <> ''::text) AND (lease_expires_at IS NOT NULL))));

ALTER TABLE "public"."lf_operation_execution" ADD CONSTRAINT "lf_operation_execution_nonnegative_control_ck" CHECK (((lease_fence >= 0) AND (checkpoint_seq >= 0)));

ALTER TABLE "public"."lf_operation_execution" ADD CONSTRAINT "lf_operation_execution_pkey" PRIMARY KEY (execution_id);

CREATE UNIQUE INDEX lf_operation_execution_idempotency_uq ON public.lf_operation_execution USING btree (operation_code, idempotency_key) WHERE (idempotency_key IS NOT NULL);

ALTER TABLE "public"."lf_operation_execution" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_execution_steps" ADD CONSTRAINT "lf_operation_execution_steps_pkey" PRIMARY KEY (execution_id, step_order);

CREATE UNIQUE INDEX uq_lf_operation_execution_steps_execution_step ON public.lf_operation_execution_steps USING btree (execution_id, step_id);

ALTER TABLE "public"."lf_operation_execution_steps" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_judges" ADD CONSTRAINT "lf_operation_judges_pkey" PRIMARY KEY (operation_code, judge_code);

ALTER TABLE "public"."lf_operation_judges" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_mode_bindings" ADD CONSTRAINT "lf_operation_mode_bindings_check" CHECK (((NOT write_allowed) OR allowed));

ALTER TABLE "public"."lf_operation_mode_bindings" ADD CONSTRAINT "lf_operation_mode_bindings_check1" CHECK ((((destination_kind = 'NO_WRITE'::text) AND (write_allowed = false)) OR (destination_kind <> 'NO_WRITE'::text)));

ALTER TABLE "public"."lf_operation_mode_bindings" ADD CONSTRAINT "lf_operation_mode_bindings_destination_kind_check" CHECK ((destination_kind = ANY (ARRAY['EXPLORATION_STORE'::text, 'CANONICAL_CANDIDATE'::text, 'NO_WRITE'::text])));

ALTER TABLE "public"."lf_operation_mode_bindings" ADD CONSTRAINT "lf_operation_mode_bindings_input_completeness_check" CHECK ((input_completeness = ANY (ARRAY['PARTIAL_ALLOWED'::text, 'COMPLETE_REQUIRED'::text, 'READ_ONLY'::text])));

ALTER TABLE "public"."lf_operation_mode_bindings" ADD CONSTRAINT "lf_operation_mode_bindings_pkey" PRIMARY KEY (operation_code, task_mode, execution_mode);

ALTER TABLE "public"."lf_operation_mode_bindings" ADD CONSTRAINT "lf_operation_mode_bindings_status_check" CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'RETIRED'::text])));

ALTER TABLE "public"."lf_operation_mode_bindings" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_registry" ADD CONSTRAINT "lf_operation_registry_lifecycle_prefix_ck" CHECK ((lifecycle_state_code ~~ 'OP_%'::text));

ALTER TABLE "public"."lf_operation_registry" ADD CONSTRAINT "lf_operation_registry_pkey" PRIMARY KEY (operation_code);

CREATE INDEX idx_lf_operation_registry_classification ON public.lf_operation_registry USING btree (operation_family, operation_domain, operation_type, applies_to_asset_type);

CREATE INDEX idx_lf_operation_registry_lifecycle_state ON public.lf_operation_registry USING btree (lifecycle_state_code);

ALTER TABLE "public"."lf_operation_registry" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_step_contracts" ADD CONSTRAINT "lf_operation_step_contracts_pkey" PRIMARY KEY (operation_code, step_id);

ALTER TABLE "public"."lf_operation_step_contracts" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_step_judge_bindings" ADD CONSTRAINT "lf_operation_step_judge_bindings_pkey" PRIMARY KEY (operation_code, step_order, step_id);

ALTER TABLE "public"."lf_operation_step_judge_bindings" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_operation_steps" ADD CONSTRAINT "lf_operation_steps_operation_code_step_id_key" UNIQUE (operation_code, step_id);

ALTER TABLE "public"."lf_operation_steps" ADD CONSTRAINT "lf_operation_steps_pkey" PRIMARY KEY (operation_code, step_order);

ALTER TABLE "public"."lf_operation_steps" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_profile_write_authority_v1" ADD CONSTRAINT "lf_profile_write_authority_v1_pkey" PRIMARY KEY (profile_code, operation_code);

ALTER TABLE "public"."lf_profile_write_authority_v1" ADD CONSTRAINT "lf_profile_write_authority_v1_status_check" CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'PROPOSED'::text, 'RETIRED'::text])));

ALTER TABLE "public"."lf_profile_write_authority_v1" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_rule_promotion_v1" ADD CONSTRAINT "lf_rule_promotion_v1_pkey" PRIMARY KEY (promotion_id);

ALTER TABLE "public"."lf_rule_promotion_v1" ADD CONSTRAINT "lf_rule_promotion_v1_status_check" CHECK ((status = ANY (ARRAY['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text, 'APPLIED'::text, 'STALE'::text])));

ALTER TABLE "public"."lf_rule_promotion_v1" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_child_caller_check" CHECK (((child_caller IS NULL) OR ((child_caller ? 'method'::text) AND (child_caller ? 'repository'::text) AND (child_caller ? 'workflow_ref'::text))));

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_effect_check" CHECK ((effect = ANY (ARRAY['READ_ONLY'::text, 'PROPOSE_ONLY'::text, 'WRITE_GOVERNED'::text])));

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_handler_fn_check" CHECK ((handler_fn ~ '^lf_skill_h_[a-z0-9_]+$'::text));

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_opener_fn_check" CHECK (((opener_fn IS NULL) OR (opener_fn ~ '^lf_skill_o_[a-z0-9_]+$'::text)));

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_pkey" PRIMARY KEY (skill_code);

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_skill_code_check" CHECK ((skill_code ~ '^[A-Z][A-Z0-9_]{2,63}$'::text));

ALTER TABLE "public"."lf_skill_catalog_v1" ADD CONSTRAINT "lf_skill_catalog_v1_status_check" CHECK ((status = ANY (ARRAY['DRAFT'::text, 'READY'::text, 'DISABLED'::text])));

ALTER TABLE "public"."lf_skill_catalog_v1" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_skill_invocation_v1" ADD CONSTRAINT "lf_skill_invocation_v1_pkey" PRIMARY KEY (skill_run_id);

CREATE UNIQUE INDEX lf_skill_invocation_v1_new_parent_skill_input_uniq ON public.lf_skill_invocation_v1 USING btree (parent_execution_id, skill_code, input_sha256) WHERE ((created_at >= '2026-11-09 08:00:00+00'::timestamp with time zone) AND (input_sha256 IS NOT NULL));

ALTER TABLE "public"."lf_skill_invocation_v1" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lf_task_mode_catalog" ADD CONSTRAINT "lf_task_mode_catalog_check" CHECK ((NOT (allows_new_target AND requires_existing_target)));

ALTER TABLE "public"."lf_task_mode_catalog" ADD CONSTRAINT "lf_task_mode_catalog_pkey" PRIMARY KEY (task_mode);

ALTER TABLE "public"."lf_task_mode_catalog" ADD CONSTRAINT "lf_task_mode_catalog_status_check" CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'RETIRED'::text])));

ALTER TABLE "public"."lf_task_mode_catalog" ENABLE ROW LEVEL SECURITY;

-- live function fn_lf_operation_reserve_execution_v1 md5=311a0377c43c0698ec12826c1a7f6a78


CREATE OR REPLACE FUNCTION public.fn_lf_operation_reserve_execution_v1(p_execution_id text, p_operation_code text, p_target_type text, p_target_code text, p_idempotency_key text, p_request_sha256 text, p_actor_execution_id text, p_target_repo text DEFAULT NULL::text, p_target_path text DEFAULT NULL::text, p_manifest jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_row public.lf_operation_execution%rowtype;
  v_inserted boolean := false;
begin
  if btrim(coalesce(p_execution_id,''))='' then raise exception 'INVALID_EXECUTION_ID'; end if;
  if btrim(coalesce(p_operation_code,''))='' then raise exception 'INVALID_OPERATION_CODE'; end if;
  if btrim(coalesce(p_target_type,''))='' or btrim(coalesce(p_target_code,''))='' then raise exception 'INVALID_TARGET'; end if;
  if btrim(coalesce(p_idempotency_key,''))='' or length(p_idempotency_key)>200 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  if coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_REQUEST_SHA256'; end if;
  if btrim(coalesce(p_actor_execution_id,''))='' then raise exception 'INVALID_ACTOR_EXECUTION_ID'; end if;
  if p_manifest is null or jsonb_typeof(p_manifest)<>'object' then raise exception 'INVALID_MANIFEST'; end if;

  insert into public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,target_repo,target_path,
    idempotency_key,request_sha256,manifest,created_by_execution_id
  ) values (
    p_execution_id,p_operation_code,p_target_type,p_target_code,p_target_repo,p_target_path,
    p_idempotency_key,p_request_sha256,p_manifest,p_actor_execution_id
  )
  on conflict (operation_code,idempotency_key) where idempotency_key is not null do nothing
  returning * into v_row;

  if v_row.execution_id is not null then
    v_inserted := true;
  else
    select * into v_row
    from public.lf_operation_execution
    where operation_code=p_operation_code and idempotency_key=p_idempotency_key;
  end if;

  if v_row.execution_id is null then raise exception 'IDEMPOTENCY_RESERVATION_UNAVAILABLE'; end if;
  if v_row.request_sha256 is distinct from p_request_sha256 then
    raise exception 'IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_REQUEST';
  end if;
  if v_row.target_type is distinct from p_target_type
     or v_row.target_code is distinct from p_target_code
     or v_row.target_repo is distinct from p_target_repo
     or v_row.target_path is distinct from p_target_path then
    raise exception 'IDEMPOTENCY_REPLAY_TARGET_MISMATCH';
  end if;

  return jsonb_build_object(
    'result',case when v_inserted then 'RESERVED_NEW_EXECUTION' else 'REPLAY_EXISTING_EXECUTION' end,
    'execution_id',v_row.execution_id,
    'operation_code',v_row.operation_code,
    'idempotency_key',v_row.idempotency_key,
    'request_sha256',v_row.request_sha256,
    'status',v_row.status,
    'dispatch_permitted',v_inserted
  );
end;
$function$
;

-- live function lf_asset_snapshot_sha_v1 md5=b5f279f4c090faa1b4e7bb2d3ea0f35a


CREATE OR REPLACE FUNCTION public.lf_asset_snapshot_sha_v1(p_asset_type text, p_code text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare v jsonb;
begin
  if p_asset_type='REGLA' then
    select to_jsonb(r)-'created_at'-'updated_at' into v from lf_ops.reglas r where r.codigo=p_code;
  elsif p_asset_type='PANTALLA' then
    select jsonb_agg(to_jsonb(r)-'created_at'-'updated_at' order by r.codigo) into v
    from lf_ops.pantallas p join lf_ops.reglas_pantallas rp on rp.pantalla_id=p.id join lf_ops.reglas r on r.id=rp.regla_id where p.codigo=p_code;
  else return null; end if;
  if v is null then return null; end if;
  return encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex');
end $function$
;

-- live function lf_record_operation_step_core_v1 md5=fe08a25c8e3c023d7181194d2dfdee0d


CREATE OR REPLACE FUNCTION public.lf_record_operation_step_core_v1(p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text, p_expected_operation_code text, p_expected_target_type text, p_contract_status text, p_binding_status text, p_judge_status text, p_trust_validation jsonb, p_close_on_report_output boolean, p_recorder_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_registry public.lf_operation_registry%rowtype;
  v_step public.lf_operation_steps%rowtype;
  v_contract public.lf_operation_step_contracts%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_judge public.lf_operation_judges%rowtype;
  v_existing public.lf_operation_execution_steps%rowtype;
  v_contract_count integer := 0;
  v_binding_count integer := 0;
  v_judge_count integer := 0;
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_required_not_clean integer := 0;
  v_key text;
  v_missing_keys text[] := array[]::text[];
  v_blocking_codes jsonb := '[]'::jsonb;
  v_assertions jsonb := '[]'::jsonb;
  v_hard_fails jsonb := '[]'::jsonb;
  v_pass_if_norm jsonb := '[]'::jsonb;
  v_fail_if_norm jsonb := '[]'::jsonb;
  v_result_values_norm jsonb := '[]'::jsonb;
  v_missing_pass_items text[] := array[]::text[];
  v_triggered_fail_items text[] := array[]::text[];
  v_pass_item text;
  v_fail_item text;
  v_derived_result text;
  v_block_code text;
  v_block_details jsonb := '{}'::jsonb;
  v_payload jsonb;
  v_attempt_history jsonb := '[]'::jsonb;
  v_existing_retryable boolean := false;
  v_snapshot_steps jsonb;
  v_snapshot_applies boolean := false;
  v_snapshot_invalid boolean := false;
  v_route_guard jsonb;
begin
  if p_execution_id is null or btrim(p_execution_id)='' or p_step_id is null or btrim(p_step_id)='' or p_actor_execution_id is null or btrim(p_actor_execution_id)='' then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_OR_ACTOR_MISSING','durable',false);
  end if;
  if p_step_id='init_execution' then return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE','durable',false); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false); end if;
  if p_trust_validation is null
     or jsonb_typeof(p_trust_validation) is distinct from 'object'
     or not (p_trust_validation ? 'valid')
     or jsonb_typeof(p_trust_validation->'valid') is distinct from 'boolean' then
    return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false);
  end if;

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or v_execution.operation_code<>p_expected_operation_code or v_execution.target_type<>p_expected_target_type then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  if v_execution.status<>'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;

  if v_execution.operation_code='EJECUCION_ROUTER_LF' then
    p_trust_validation:=public.lf_router_execution_trust_validation_v1(
      p_execution_id,p_step_id,p_evidence_payload
    );
  end if;

  -- Frozen execution contract is authoritative when present. No silent fallback
  -- when a snapshot is malformed; legacy executions without a snapshot retain
  -- the original current-catalog behavior.
  v_snapshot_steps:=v_execution.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
  if v_snapshot_steps is not null then
    if jsonb_typeof(v_snapshot_steps)<>'array' or jsonb_array_length(v_snapshot_steps)=0 then
      return jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID','durable',false);
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_snapshot_steps) a(value)
      where jsonb_typeof(a.value)<>'string' or nullif(btrim(a.value #>> '{}'),'') is null
    ) or (
      select count(*) from jsonb_array_elements_text(v_snapshot_steps)
    ) <> (
      select count(distinct value) from jsonb_array_elements_text(v_snapshot_steps) s(value)
    ) or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) s(value)
      where not exists (
        select 1 from public.lf_operation_steps os
        where os.operation_code=v_execution.operation_code and os.step_id=s.value
          and os.active and os.required
      )
    ) then
      return jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID','durable',false);
    end if;
    v_snapshot_applies:=true;
  end if;


  select * into v_registry from public.lf_operation_registry where operation_code=v_execution.operation_code;
  if not found or v_registry.applies_to_asset_type<>v_execution.target_type then return jsonb_build_object('outcome','BLOCKED','code','OPERATION_REGISTRY_TARGET_MISMATCH','durable',false); end if;

  select * into v_step from public.lf_operation_steps where operation_code=v_execution.operation_code and step_id=p_step_id and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;

  select count(*) into v_contract_count from public.lf_operation_step_contracts where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_contract_status;
  if v_contract_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_NOT_EXACT','count',v_contract_count,'durable',false); end if;
  select * into v_contract from public.lf_operation_step_contracts where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_contract_status limit 1;

  select count(*) into v_binding_count from public.lf_operation_step_judge_bindings where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_binding_status;
  if v_binding_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_NOT_EXACT','count',v_binding_count,'durable',false); end if;
  select * into v_binding from public.lf_operation_step_judge_bindings where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_binding_status limit 1;

  select count(*) into v_judge_count from public.lf_operation_judges where operation_code=v_execution.operation_code and judge_code=v_binding.judge_code and status=p_judge_status;
  if v_judge_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_NOT_EXACT','count',v_judge_count,'durable',false); end if;
  select * into v_judge from public.lf_operation_judges where operation_code=v_execution.operation_code and judge_code=v_binding.judge_code and status=p_judge_status limit 1;

  select * into v_existing from public.lf_operation_execution_steps where execution_id=p_execution_id and step_order=v_step.step_order;
  if found and v_existing.step_id<>p_step_id then return jsonb_build_object('outcome','BLOCKED','code','STEP_ORDER_ALREADY_BOUND_TO_OTHER_STEP','durable',true); end if;
  if found then
    if v_existing.status=v_binding.clean_result_value
       and v_existing.evidence_ref is not distinct from p_evidence_ref
       and (
         (v_existing.evidence_payload - array[
           'step_result','derived_result','derived_by_judge','mini_judge_code','mini_judge_result',
           'missing_pass_items','triggered_fail_items','attempt_history','recorded_by_rpc','core_recorder',
           'trust_validation','assertions_checked','hard_fails_checked','caller_assertions_ignored',
           'blocking_findings','blocking_codes','return_to_worker_reasons','canonical_route_guard_receipt'
         ]::text[])
         is not distinct from
         (p_evidence_payload - array['assertions_checked','hard_fails_checked','caller_assertions_ignored','blocking_codes','canonical_route_guard_receipt']::text[])
       )
       and coalesce(v_existing.evidence_payload->'blocking_codes','[]'::jsonb)
           is not distinct from coalesce(p_evidence_payload->'blocking_codes','[]'::jsonb)
       and (v_existing.evidence_payload->'trust_validation') is not distinct from p_trust_validation
       and (p_trust_validation->'valid') is not distinct from 'true'::jsonb then
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status,'execution_status',v_execution.status);
    end if;
    if v_existing.status in (v_binding.blocked_result_value,v_binding.return_result_value) then
      v_existing_retryable:=true;
      if jsonb_typeof(v_existing.evidence_payload->'attempt_history')='array' then v_attempt_history:=v_existing.evidence_payload->'attempt_history'; end if;
    else
      return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status,'durable',true);
    end if;
  end if;

  select count(*) into v_prior_missing
  from public.lf_operation_steps s
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and (not v_snapshot_applies or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id)
      where frozen.step_id=s.step_id
    ))
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id);

  select count(*) into v_prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_order=s.step_order and pb.step_id=s.step_id and pb.status=p_binding_status
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and (not v_snapshot_applies or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id)
      where frozen.step_id=s.step_id
    ))
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and (pb.clean_result_value is null or es.status<>pb.clean_result_value);

  if v_prior_missing>0 or v_prior_bad>0 then
    v_block_code:='PRIOR_REQUIRED_STEP_NOT_CLEAN';
    v_block_details:=jsonb_build_object('prior_missing',v_prior_missing,'prior_bad',v_prior_bad);
  end if;

  if v_block_code is null and (p_trust_validation->'valid') is distinct from 'true'::jsonb then
    v_block_code:=coalesce(nullif(p_trust_validation->>'code',''),'TRUST_VALIDATION_FAILED');
    v_block_details:=coalesce(p_trust_validation->'details','{}'::jsonb);
  end if;

  if v_block_code is null then
    for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop
      if not (p_evidence_payload ? v_key) or p_evidence_payload->v_key is null or p_evidence_payload->v_key='null'::jsonb or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
        v_missing_keys:=array_append(v_missing_keys,v_key);
      end if;
    end loop;
    if cardinality(v_missing_keys)>0 then
      v_block_code:='REQUIRED_EVIDENCE_MISSING';
      v_block_details:=jsonb_build_object('missing_keys',to_jsonb(v_missing_keys));
    end if;
  end if;

  if v_block_code is null
     and v_execution.operation_code='EJECUCION_ESTRATEGIA_LF'
     and p_step_id='pre_write_execution_binding_gate' then
    v_route_guard:=public.lf_strategy_canonical_route_guard_v1(
      p_execution_id,v_execution.operation_code,false
    );
    if coalesce((v_route_guard->>'valid')::boolean,false) is not true then
      v_block_code:=coalesce(nullif(v_route_guard->>'blocking_code',''),'CANONICAL_ROUTE_GUARD_FAILED');
      v_block_details:=jsonb_build_object(
        'route_guard',v_route_guard,
        'execution_id',p_execution_id,
        'step_id',p_step_id
      );
    end if;
  end if;

  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then
    if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array' then v_block_code:='BLOCKING_CODES_INVALID';
    else v_blocking_codes:=p_evidence_payload->'blocking_codes'; if jsonb_array_length(v_blocking_codes)>0 then v_block_code:=coalesce(v_contract.blocking_code,'STEP_BLOCKED'); v_block_details:=jsonb_build_object('caller_blocking_codes',v_blocking_codes); end if; end if;
  end if;

  if jsonb_typeof(v_judge.result_values)='array' then v_result_values_norm:=v_judge.result_values;
  elsif jsonb_typeof(v_judge.result_values)='object' then select coalesce(jsonb_agg(value order by key),'[]'::jsonb) into v_result_values_norm from jsonb_each_text(v_judge.result_values) where value is not null and btrim(value)<>'';
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_RESULT_VALUES_SHAPE_INVALID','durable',false); end if;

  if jsonb_typeof(v_judge.pass_if)='array' then v_pass_if_norm:=v_judge.pass_if;
  elsif jsonb_typeof(v_judge.pass_if)='object' and jsonb_typeof(v_judge.pass_if->'pass_if')='array' then v_pass_if_norm:=v_judge.pass_if->'pass_if';
  elsif jsonb_typeof(v_judge.pass_if)='object' then select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_pass_if_norm from jsonb_each(v_judge.pass_if) where value='true'::jsonb;
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_PASS_IF_SHAPE_INVALID','durable',false); end if;

  if jsonb_typeof(v_judge.fail_if)='array' then v_fail_if_norm:=v_judge.fail_if;
  elsif jsonb_typeof(v_judge.fail_if)='object' and jsonb_typeof(v_judge.fail_if->'fail_if')='array' then v_fail_if_norm:=v_judge.fail_if->'fail_if';
  elsif jsonb_typeof(v_judge.fail_if)='object' then select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_fail_if_norm from jsonb_each(v_judge.fail_if) where value='true'::jsonb;
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_FAIL_IF_SHAPE_INVALID','durable',false); end if;

  if (p_trust_validation->'valid') is not distinct from 'true'::jsonb
     and not (p_trust_validation ? 'server_assertions') then
    return jsonb_build_object('outcome','BLOCKED','code','SERVER_ASSERTIONS_REQUIRED_FOR_VALID_TRUST','durable',false);
  end if;
  v_assertions:=coalesce(p_trust_validation->'server_assertions','[]'::jsonb);
  v_hard_fails:=coalesce(p_trust_validation->'server_hard_fails','[]'::jsonb);
  if jsonb_typeof(v_assertions)<>'array' or jsonb_typeof(v_hard_fails)<>'array' then
    if v_block_code is null then v_block_code:='JUDGE_EVIDENCE_ARRAYS_INVALID'; v_block_details:='{}'::jsonb; end if;
  end if;

  if v_block_code is null then
    for v_fail_item in select jsonb_array_elements_text(v_fail_if_norm) loop
      if exists(select 1 from jsonb_array_elements_text(v_hard_fails) hf where hf=v_fail_item) then v_triggered_fail_items:=array_append(v_triggered_fail_items,v_fail_item); end if;
    end loop;
    if cardinality(v_triggered_fail_items)>0 then
      v_block_code:='JUDGE_FAIL_CONDITION_TRIGGERED';
      v_block_details:=jsonb_build_object('triggered_fail_items',to_jsonb(v_triggered_fail_items));
    else
      for v_pass_item in select jsonb_array_elements_text(v_pass_if_norm) loop
        if not exists(select 1 from jsonb_array_elements_text(v_assertions) pa where pa=v_pass_item) then v_missing_pass_items:=array_append(v_missing_pass_items,v_pass_item); end if;
      end loop;
      if cardinality(v_missing_pass_items)>0 then v_derived_result:=v_binding.return_result_value; else v_derived_result:=v_binding.clean_result_value; end if;
    end if;
  end if;

  if v_block_code is not null then v_derived_result:=v_binding.blocked_result_value; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_result_values_norm) rv where rv=v_derived_result) then return jsonb_build_object('outcome','BLOCKED','code','DERIVED_RESULT_NOT_ALLOWED_BY_JUDGE','derived_result',v_derived_result,'durable',false); end if;

  v_payload:=(p_evidence_payload - array['assertions_checked','hard_fails_checked','caller_assertions_ignored']::text[])
    || jsonb_build_object(
      'assertions_checked',v_assertions,
      'hard_fails_checked',v_hard_fails,
      'caller_assertions_ignored',true
    );
  if v_route_guard is not null then
    v_payload:=v_payload||jsonb_build_object('canonical_route_guard_receipt',v_route_guard);
  end if;
  for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;

  if v_derived_result=v_binding.blocked_result_value then
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb);
  elsif v_derived_result=v_binding.return_result_value then
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','RETURN','code','JUDGE_PASS_CONDITIONS_INCOMPLETE','evidence_ref',p_evidence_ref,'details',jsonb_build_object('missing_pass_items',to_jsonb(v_missing_pass_items))));
    v_payload:=v_payload||jsonb_build_object('blocking_findings','[]'::jsonb,'blocking_codes','[]'::jsonb,'return_to_worker_reasons',to_jsonb(v_missing_pass_items));
  else
    v_payload:=v_payload||jsonb_build_object('blocking_findings','[]'::jsonb,'blocking_codes','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb);
  end if;

  v_payload:=v_payload||jsonb_build_object('step_result',v_derived_result,'derived_result',v_derived_result,'derived_by_judge',v_binding.judge_code,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,'missing_pass_items',to_jsonb(v_missing_pass_items),'triggered_fail_items',to_jsonb(v_triggered_fail_items),'attempt_history',v_attempt_history,'recorded_by_rpc',p_recorder_name,'core_recorder','lf_record_operation_step_core_v1','trust_validation',p_trust_validation);

  if v_existing_retryable then
    update public.lf_operation_execution_steps set status=v_derived_result,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Retry persisted transactionally by operation-neutral recorder core.' where execution_id=p_execution_id and step_order=v_step.step_order and step_id=p_step_id;
  else
    insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id)
    values(p_execution_id,v_step.step_order,p_step_id,v_derived_result,p_evidence_ref,v_payload,'Recorded transactionally by operation-neutral recorder core.',p_actor_execution_id);
  end if;

  if v_derived_result=v_binding.clean_result_value and p_close_on_report_output and p_step_id='report_output' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_order=s.step_order and b.step_id=s.step_id and b.status=p_binding_status
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and (not v_snapshot_applies or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id)
      where frozen.step_id=s.step_id
    )) and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'OPERATION_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution set status='COMPLETED',completed_at=coalesce(completed_at,now()),manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;

  return jsonb_build_object('outcome',case when v_derived_result=v_binding.clean_result_value then 'STEP_RECORDED' when v_derived_result=v_binding.return_result_value then 'RETURN_TO_ROUTER' else 'BLOCKED' end,'replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_derived_result,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history),'code',v_block_code);
end;
$function$
;

-- live function lf_regla_candidate_write_v1 md5=c311087befe49afb2affa668231c9dd1


CREATE OR REPLACE FUNCTION public.lf_regla_candidate_write_v1(p_execution_id text, p_action_code text, p_codigo text, p_categoria text, p_titulo text, p_descripcion text, p_razon text DEFAULT NULL::text, p_valor_config jsonb DEFAULT NULL::jsonb, p_es_transversal boolean DEFAULT false, p_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'lf_ops'
AS $function$
declare v_exec public.lf_operation_execution%rowtype; v_expected text; v_before lf_ops.reglas%rowtype; v_after lf_ops.reglas%rowtype;
begin
 if upper(coalesce(p_action_code,'')) not in ('REGLA_CREATE','REGLA_UPDATE') then raise exception 'LF_REGLA_ACTION_INVALID:%',p_action_code; end if;
 if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_codigo,''))='' or btrim(coalesce(p_categoria,''))='' or btrim(coalesce(p_titulo,''))='' or btrim(coalesce(p_descripcion,''))='' then raise exception 'LF_REGLA_REQUIRED_INPUT_MISSING'; end if;
 v_expected:=case upper(p_action_code) when 'REGLA_CREATE' then 'CREACION_REGLA_LF' else 'ACTUALIZACION_REGLA_LF' end;
 perform 1 from public.lf_operation_mode_bindings b where b.operation_code=v_expected and b.task_mode=case when upper(p_action_code)='REGLA_CREATE' then 'CREATE_NEW' else 'REMEDIATE_EXISTING' end and b.execution_mode='GOVERNED' and b.status='ACTIVE' and b.allowed and b.write_allowed and b.destination_kind='CANONICAL_CANDIDATE' and b.input_completeness='COMPLETE_REQUIRED';
 if not found then raise exception 'LF_REGLA_GOVERNED_MODE_BINDING_MISSING:%',v_expected; end if;
 select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
 if not found then raise exception 'LF_REGLA_EXECUTION_NOT_FOUND:%',p_execution_id; end if;
 if v_exec.operation_code<>v_expected or v_exec.status<>'IN_PROGRESS' or v_exec.target_type<>'REGLA' or v_exec.target_code<>p_codigo then raise exception 'LF_REGLA_EXECUTION_BINDING_MISMATCH'; end if;
 select * into v_before from lf_ops.reglas where codigo=p_codigo;
 if upper(p_action_code)='REGLA_CREATE' then
  if found then raise exception 'LF_REGLA_CREATE_DUPLICATE:%',p_codigo; end if;
  insert into lf_ops.reglas(codigo,categoria,titulo,descripcion,razon,valor_config,es_transversal,estado,origen,pendiente_decision,pendiente_detalle,created_by)
  values(p_codigo,p_categoria,p_titulo,p_descripcion,p_razon,p_valor_config,coalesce(p_es_transversal,false),'CANDIDATO',p_origen,true,'GOVERNED_CANDIDATE_REQUIRES_REVIEW',p_execution_id) returning * into v_after;
 else
  if not found then raise exception 'LF_REGLA_UPDATE_NOT_FOUND:%',p_codigo; end if;
  if v_before.estado<>'CANDIDATO' then raise exception 'LF_REGLA_UPDATE_REQUIRES_CANDIDATO:%:%',p_codigo,v_before.estado; end if;
  update lf_ops.reglas set categoria=p_categoria,titulo=p_titulo,descripcion=p_descripcion,razon=p_razon,valor_config=p_valor_config,es_transversal=coalesce(p_es_transversal,false),estado='CANDIDATO',origen=coalesce(p_origen,origen),pendiente_decision=true,pendiente_detalle='GOVERNED_CANDIDATE_REQUIRES_REVIEW',updated_at=now() where codigo=p_codigo returning * into v_after;
 end if;
 return jsonb_build_object('result',case when upper(p_action_code)='REGLA_CREATE' then 'RULE_CANDIDATE_CREATED' else 'RULE_CANDIDATE_UPDATED' end,'operation_code',v_expected,'execution_id',p_execution_id,'before',case when upper(p_action_code)='REGLA_UPDATE' then to_jsonb(v_before) else null end,'after',to_jsonb(v_after));
end;$function$
;

-- live function lf_resolve_operation_mode_v1 md5=b4a513268d6c63f84a8ca4dff7f9e3e4


CREATE OR REPLACE FUNCTION public.lf_resolve_operation_mode_v1(p_operation_code text, p_task_mode text, p_execution_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_b public.lf_operation_mode_bindings%rowtype; v_t public.lf_task_mode_catalog%rowtype; v_m public.lf_execution_mode_catalog%rowtype;
begin
 if btrim(coalesce(p_operation_code,''))='' or btrim(coalesce(p_task_mode,''))='' or btrim(coalesce(p_execution_mode,''))='' then return jsonb_build_object('status','BLOCKED','blocking_code','MODE_IDENTITY_MISSING'); end if;
 select * into v_t from public.lf_task_mode_catalog where task_mode=upper(p_task_mode) and status='ACTIVE';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','TASK_MODE_NOT_ACTIVE','task_mode',upper(p_task_mode)); end if;
 select * into v_m from public.lf_execution_mode_catalog where execution_mode=upper(p_execution_mode) and status='ACTIVE';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','EXECUTION_MODE_NOT_ACTIVE','execution_mode',upper(p_execution_mode)); end if;
 select * into v_b from public.lf_operation_mode_bindings where operation_code=p_operation_code and task_mode=v_t.task_mode and execution_mode=v_m.execution_mode and status='ACTIVE';
 if not found or not v_b.allowed then return jsonb_build_object('status','BLOCKED','blocking_code','OPERATION_MODE_NOT_ALLOWED','operation_code',p_operation_code,'task_mode',v_t.task_mode,'execution_mode',v_m.execution_mode); end if;
 return jsonb_build_object('status','READY','operation_code',v_b.operation_code,'task_mode',v_b.task_mode,'execution_mode',v_b.execution_mode,'write_allowed',v_b.write_allowed,'destination_kind',v_b.destination_kind,'input_completeness',v_b.input_completeness,'canonical_state',v_b.canonical_state,'required_existing_state',v_b.required_existing_state,'allows_partial_input',v_m.allows_partial_input,'canonical_write_allowed',v_m.canonical_write_allowed,'runtime_allowed',v_m.runtime_allowed,'promotion_allowed',v_m.promotion_allowed,'reference_source',v_m.reference_source);
end $function$
;

-- live function lf_rule_promotion_apply_v1 md5=d7fe763c999db6f6259b6b1e2bd69644


CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;
 if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';
 update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;
 return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
end $function$
;

-- live function lf_rule_promotion_decide_v1 md5=16e45f40dad5cecc215a2f978be47728


CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1(p_promotion_id text, p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 if p_decided_by is null or p_decided_by !~ '^HUMAN:.+' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;
 if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING','estado',p.status); end if;
 if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update public.lf_rule_promotion_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=coalesce(reason,'')||' | '||coalesce(p_note,'') where promotion_id=p_promotion_id;
 return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'promotion_id',p_promotion_id);
end $function$
;

-- live function lf_rule_promotion_guard_v1 md5=ee782e4bd0128c80ee13881899c0d74e


CREATE OR REPLACE FUNCTION public.lf_rule_promotion_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
begin
 if NEW.estado='VIGENTE' and OLD.estado is distinct from 'VIGENTE' then
  if not exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=OLD.codigo and p.status='APPROVED' and p.request_snapshot_sha256=public.lf_asset_snapshot_sha_v1('REGLA',OLD.codigo)) then
   raise exception 'LF_RULE_PROMOTION_REQUIRED:%',OLD.codigo; end if;
 end if;
 return NEW;
end $function$
;

-- live function lf_rule_promotion_request_v1 md5=2fcac9f18b1581985af93639e475cd1a


CREATE OR REPLACE FUNCTION public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; r record; v_sha text; v_id text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;
 select * into r from lf_ops.reglas where codigo=p_rule_code;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); end if;
 if r.estado<>'CANDIDATO' then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_CANDIDATE','estado',r.estado); end if;
 if exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=p_rule_code and p.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_ALREADY_OPEN'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;
 v_sha := public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 insert into public.lf_rule_promotion_v1(rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,reason) values(p_rule_code,p_execution_id,par.target_code,v_sha,p_reason) returning promotion_id into v_id;
 return jsonb_build_object('status','PENDING_HUMAN_APPROVAL','promotion_id',v_id,'snapshot_sha256',v_sha,'next_action','Una persona debe aprobar con lf_rule_promotion_decide_v1');
end $function$
;

-- live function lf_skill_child_caller_manifest_v1 md5=7d2953a9d783bfd4045822ff8f7a5487


CREATE OR REPLACE FUNCTION public.lf_skill_child_caller_manifest_v1(p_skill text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 select coalesce((select jsonb_build_object('governed_caller_method',c.child_caller->>'method','caller_repository',c.child_caller->>'repository','caller_workflow_ref',c.child_caller->>'workflow_ref')
                  from public.lf_skill_catalog_v1 c where c.skill_code=p_skill and c.child_caller is not null), '{}'::jsonb);
$function$
;

-- live function lf_skill_h_rule_create_propose_v1 md5=e2cf37423e91f7d2921e9470605ca474


CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_create_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo') then raise exception 'RULE_ALREADY_EXISTS:%', p_input->>'regla_codigo'; end if;
 return jsonb_build_object('regla_codigo',p_input->>'regla_codigo','existe',false,'operacion_requerida','CREACION_REGLA_LF','escribe',false);
end $function$
;

-- live function lf_skill_h_rule_update_propose_v1 md5=c9696418d7404df55b3af28082abaa4f


CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_update_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 select jsonb_build_object('regla_codigo',p_input->>'regla_codigo','existe',exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo'),
  'operacion_requerida','ACTUALIZACION_REGLA_LF','escribe',false,'analysis_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',p_input->>'regla_codigo'));
$function$
;

-- live function lf_skill_invoke_v1 md5=ac7e351e1834cbfb91aabf26e1a04a8d


CREATE OR REPLACE FUNCTION public.lf_skill_invoke_v1(p_skill text, p_execution_id text, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare c record; par record; v_run text := 'RUN-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,20)); v_in text; v_missing text[]; k text; v_out jsonb; v_code text; v_prof text; v_ev text; v_child text; v_status text; v_prior public.lf_skill_invocation_v1%ROWTYPE; v_prior_count integer; v_rule_receipt jsonb;
begin
  v_in := encode(extensions.digest(convert_to(coalesce(p_input,'{}'::jsonb)::text,'UTF8'),'sha256'),'hex');
  select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
  v_prof := par.target_code;
  if not found then v_code:='PARENT_EXECUTION_NOT_ACTIVE';
  else
    select * into c from public.lf_skill_catalog_v1 s where s.skill_code=p_skill;
    if not found then v_code:='SKILL_NOT_FOUND';
    elsif c.status<>'READY' then v_code:='SKILL_NOT_READY';
    elsif not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=v_prof and a.operation_code=c.required_operation and a.status='ACTIVE') then v_code:='SKILL_NOT_AUTHORIZED_FOR_PROFILE';
    else
      v_missing := array[]::text[];
      foreach k in array c.input_required loop if nullif(p_input->>k,'') is null then v_missing:=v_missing||k; end if; end loop;
      if array_length(v_missing,1) is not null then v_code:='SKILL_INPUT_INVALID';
      elsif not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=c.handler_fn) then v_code:='SKILL_HANDLER_MISSING';
      else
        -- One parent+skill+input may open only one invocation/child.
        -- Advisory transaction lock serializes two concurrent calls before the effect.
        perform pg_catalog.pg_advisory_xact_lock(
          pg_catalog.hashtextextended(p_execution_id||':'||p_skill||':'||v_in,0)
        );
        select count(*) into v_prior_count
          from public.lf_skill_invocation_v1 i
         where i.parent_execution_id=p_execution_id and i.skill_code=p_skill
           and i.input_sha256=v_in;
        if v_prior_count>1 then
          return jsonb_build_object('status','BLOCKED',
            'blocking_code','SKILL_REPLAY_AMBIGUOUS_HISTORY','replay',false,
            'next_action','RECONCILE_HISTORICAL_DUPLICATES_WITHOUT_DELETE');
        elsif v_prior_count=1 then
          select * into v_prior from public.lf_skill_invocation_v1 i
           where i.parent_execution_id=p_execution_id and i.skill_code=p_skill
             and i.input_sha256=v_in;
          if v_prior.profile_code is distinct from v_prof then
            return jsonb_build_object('status','BLOCKED',
              'blocking_code','SKILL_REPLAY_PROFILE_MISMATCH','replay',false);
          end if;
          if v_prior.child_execution_id is not null and
             not exists(
               select 1 from public.lf_operation_execution e
                where e.execution_id=v_prior.child_execution_id
                  and e.operation_code=c.required_operation
                  and e.created_by_execution_id=p_execution_id
             ) then
            return jsonb_build_object('status','BLOCKED',
              'blocking_code','SKILL_REPLAY_CHILD_BINDING_MISMATCH','replay',false);
          end if;
          IF p_skill='RULE_UPDATE_APPLY' AND v_prior.child_execution_id IS NOT NULL THEN
            v_rule_receipt:=public.lf_skill_rule_child_readback_v1(
              p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id);
          ELSE
            v_rule_receipt:=NULL;
          END IF;
          return jsonb_build_object(
            'status',v_prior.status,
            'skill_run_id',v_prior.skill_run_id,
            'output',coalesce(v_prior.output,'{}'::jsonb),
            'evidence_ref',v_prior.evidence_ref,
            'child_execution_id',v_prior.child_execution_id,
            'blocking_code',v_prior.blocking_code,
            'replay',true,
            'effect_verified',coalesce(v_rule_receipt->>'status','')='APPLIED_VERIFIED',
            'child_receipt',v_rule_receipt,
            'next_action',case
              when v_rule_receipt->>'status'='APPLIED_VERIFIED' then 'CONTINUE_PROFILE'
              when v_prior.child_execution_id is not null then 'VERIFY_CHILD_OPERATION_BEFORE_PROFILE_CLOSE'
              when v_prior.status='COMPLETED' then 'CONTINUE_PROFILE'
              else 'FIX_REQUEST_AND_RETRY' end
          );
        end if;
        begin
          execute format('select public.%I($1)',c.handler_fn) into v_out using p_input;
        exception when others then
          v_code:='SKILL_HANDLER_ERROR';
        end;
      end if;
    end if;
  end if;
  if v_code is null and exists(select 1 from public.lf_skill_catalog_v1 s2 where s2.skill_code=p_skill and s2.effect='WRITE_GOVERNED') then
    v_child := 'EXEC-SKILL-'||substr(v_run,5,16);
    v_ev := 'SKILLRUN:'||v_run||':'||encode(extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex');
    insert into public.lf_skill_invocation_v1(skill_run_id,skill_code,parent_execution_id,profile_code,status,input_sha256,output,evidence_ref,child_execution_id) values(v_run,p_skill,p_execution_id,v_prof,'COMPLETED',v_in,v_out,v_ev,v_child);
    begin
      if c.opener_fn is null then
      insert into public.lf_operation_execution(execution_id,operation_code,target_type,target_code,manifest,request_sha256,idempotency_key,created_by_execution_id)
      values(v_child,c.required_operation,coalesce(p_input->>'target_type','REGLA'),coalesce(p_input->>'target_code',p_input->>'regla_codigo'),
        jsonb_build_object('profile_handoff',jsonb_build_object('source_execution_id',p_execution_id,'skill_run_id',v_run,'analysis_snapshot_sha256',p_input->>'analysis_snapshot_sha256','via','SKILL_INVOKER')) || public.lf_skill_child_caller_manifest_v1(p_skill),
        par.request_sha256,'skill-child-v1:'||v_run,p_execution_id);
      else
        execute format('select public.%I($1,$2,$3,$4,$5)',c.opener_fn) using v_child,p_input,p_execution_id,v_run,par.request_sha256;
      end if;
    exception when others then
      v_code := coalesce(nullif(split_part(sqlerrm,':',1),''),'SKILL_CHILD_EXECUTION_BLOCKED');
      update public.lf_skill_invocation_v1 set status='BLOCKED', blocking_code=v_code, child_execution_id=null where skill_run_id=v_run;
      return jsonb_build_object('status','BLOCKED','skill_run_id',v_run,'output','{}'::jsonb,'evidence_ref',null,'blocking_code',v_code,'detail',left(sqlerrm,220),'next_action','FIX_REQUEST_AND_RETRY');
    end;
    IF p_skill='RULE_UPDATE_APPLY' THEN
      v_rule_receipt:=public.lf_skill_rule_child_readback_v1(p_execution_id,v_run,v_child);
    ELSE
      v_rule_receipt:=NULL;
    END IF;
    return jsonb_build_object('status','COMPLETED','skill_run_id',v_run,
      'output',v_out,'evidence_ref',v_ev,'child_execution_id',v_child,
      'effect_verified',coalesce(v_rule_receipt->>'status','')='APPLIED_VERIFIED',
      'child_receipt',v_rule_receipt,
      'next_action',case when v_rule_receipt->>'status'='APPLIED_VERIFIED'
        then 'CONTINUE_PROFILE' else 'VERIFY_CHILD_OPERATION_BEFORE_PROFILE_CLOSE' end);
  end if;
  if v_code is not null then
    v_status := case when v_code='SKILL_HANDLER_ERROR' then 'FAILED' else 'BLOCKED' end;
    insert into public.lf_skill_invocation_v1(skill_run_id,skill_code,parent_execution_id,profile_code,status,blocking_code,input_sha256) values(v_run,p_skill,p_execution_id,v_prof,v_status,v_code,v_in);
    return jsonb_build_object('status',v_status,'skill_run_id',v_run,'output','{}'::jsonb,'evidence_ref',null,'blocking_code',v_code,'missing_inputs',to_jsonb(v_missing),'next_action','FIX_REQUEST_AND_RETRY');
  end if;
  v_ev := 'SKILLRUN:'||v_run||':'||encode(extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_skill_invocation_v1(skill_run_id,skill_code,parent_execution_id,profile_code,status,input_sha256,output,evidence_ref) values(v_run,p_skill,p_execution_id,v_prof,'COMPLETED',v_in,v_out,v_ev);
  return jsonb_build_object('status','COMPLETED','skill_run_id',v_run,'output',v_out,'evidence_ref',v_ev,'next_action','CONTINUE_PROFILE');
end $function$
;

-- live function lf_skill_o_rule_update_v1 md5=dc97a0e7c65b65ae1951e2da86c6238b


CREATE OR REPLACE FUNCTION public.lf_skill_o_rule_update_v1(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'lf_ops', 'extensions'
AS $function$
DECLARE
 v_par public.lf_operation_execution%ROWTYPE;
 v_inv public.lf_skill_invocation_v1%ROWTYPE;
 v_before lf_ops.reglas%ROWTYPE;
 v_after jsonb;
 v_profile_output jsonb;
 v_patch jsonb;
 v_changes jsonb;
 v_source_refs jsonb;
 v_semantic jsonb;
 v_decision text;
 v_rule text;
 v_screen text;
 v_snapshot text;
 v_out_sha text;
 v_step_payload jsonb;
 v_trust jsonb;
 v_rec jsonb;
 v_written jsonb;
 v_mode jsonb;
 v_reservation jsonb;
 v_field text;
 v_current text;
 v_next text;
 v_old_title text;
 v_old_desc text;
 v_old_reason text;
 v_new_title text;
 v_new_desc text;
 v_new_reason text;
 v_changed integer := 0;
 v_n integer;
 v_after_sha text;
 v_evidence text;
 v_steps text[] := ARRAY[
  'ekb_preflight','classify','existing_check','destination_validate',
  'candidate_write','readback','trace_close'
 ];
 v_status text;
BEGIN
 IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
    OR coalesce(p_input->>'regla_codigo','') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR coalesce(p_input->>'analysis_snapshot_sha256','') !~ '^[0-9a-f]{64}$'
    OR coalesce(p_input->>'decision_id','')=''
    OR jsonb_typeof(p_input->'candidate_patch') IS DISTINCT FROM 'object'
    OR p_input->'candidate_patch'->>'rule_code' IS DISTINCT FROM p_input->>'regla_codigo'
    OR p_input->'candidate_patch'->>'change_kind' IS DISTINCT FROM 'DOCUMENTARY_ONLY'
    OR jsonb_typeof(p_input->'candidate_patch'->'changes') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INPUT_OR_PATCH_CONTRACT';
 END IF;
 v_rule := p_input->>'regla_codigo';
 v_patch := p_input->'candidate_patch';
 v_changes := v_patch->'changes';
 IF (SELECT count(*) FROM jsonb_object_keys(v_patch))<>3
    OR (SELECT count(*) FROM jsonb_object_keys(v_changes)) NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_KEYS';
 END IF;
 FOR v_field IN SELECT jsonb_object_keys(v_changes) LOOP
    IF v_field NOT IN ('titulo','descripcion','razon')
       OR jsonb_typeof(v_changes->v_field)<>'string'
       OR length(btrim(v_changes->>v_field))<8
       OR length(v_changes->>v_field)>8000 THEN
       RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROTECTED_OR_INVALID_FIELD:%',v_field;
    END IF;
 END LOOP;

 SELECT * INTO v_par FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
   AND status='IN_PROGRESS' FOR UPDATE;
 IF NOT FOUND OR v_par.target_type<>'PERFIL'
    OR v_par.manifest->>'read_only' IS DISTINCT FROM 'true'
    OR v_par.manifest->>'no_write' IS DISTINCT FROM 'true'
    OR v_par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
    OR v_par.manifest->'router_profile_handoff'->'router_authorization_receipt'->>'profile_execution_allowed' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_PARENT_NOT_AUTHORIZED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code=v_par.target_code
      AND operation_code='ACTUALIZACION_REGLA_LF' AND status='ACTIVE') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROFILE_OPERATION_AUTHORITY'; END IF;
 SELECT * INTO v_inv FROM public.lf_skill_invocation_v1
 WHERE skill_run_id=p_run AND skill_code='RULE_UPDATE_APPLY'
   AND child_execution_id=p_child AND parent_execution_id=p_parent
   AND profile_code=v_par.target_code AND status='COMPLETED'
   AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex')
 FOR UPDATE;
 IF NOT FOUND OR p_request_sha IS DISTINCT FROM v_par.request_sha256 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INVOCATION_OR_REQUEST_BINDING'; END IF;
 -- Profile output is the ONLY authority for exact patch bytes. The caller may
 -- echo that patch but cannot choose new values or target independently.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=p_parent AND step_id='output_validate'
      AND status='STEP_PASS_WITH_EVIDENCE'
      AND evidence_payload->>'output_contract_result'='PASS') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROFILE_OUTPUT_NOT_VALIDATED'; END IF;
 SELECT evidence_payload->'semantic_judge_result' INTO v_semantic
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='semantic_judge'
   AND status='STEP_PASS_WITH_EVIDENCE'
   AND evidence_payload->'blocking_codes'='[]'::jsonb;
 IF v_semantic IS NULL OR v_semantic->>'verdict'
      NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SEMANTIC_JUDGE_NOT_CLEAN'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_profile_output
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF v_profile_output IS NULL OR v_profile_output->>'worker' IS DISTINCT FROM 'product_director_lf'
    OR v_profile_output->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
    OR v_profile_output->>'self_verdict' IS DISTINCT FROM 'PASS'
    OR v_profile_output->'deliverable_created'->>'authority_status' IS NULL
    OR v_profile_output->'deliverable_created'->>'authority_status'
          NOT IN ('SUPPORTED','CONFLICT_RESOLVED') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PRODUCT_DECISION_NOT_FOUND'; END IF;
 v_out_sha := encode(extensions.digest(convert_to(v_profile_output::text,'UTF8'),'sha256'),'hex');
 IF v_profile_output->'deliverable_created'->'governed_rule_patch'
       IS DISTINCT FROM v_patch
    OR v_profile_output->'deliverable_created'->'product_decision'->>'decision_id'
       IS DISTINCT FROM p_input->>'decision_id' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_NOT_IN_JUDGED_OUTPUT'; END IF;
 v_source_refs := v_profile_output->'deliverable_created'->'product_decision'->'source_refs';
 IF jsonb_typeof(v_source_refs)<>'array'
    OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_source_refs) ref
      WHERE ref->>'authority' IN ('AUTHORITATIVE','CONSTRAINT')
        AND ref->>'current'='true'
        AND nullif(btrim(ref->>'source_ref'),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_AUTHORITATIVE_SOURCE_ABSENT'; END IF;
 -- A screen task cannot mutate rules unrelated to the screen actually
 -- selected by the SAME parent. No caller-provided pantalla_id is trusted.
 v_screen := v_par.manifest->'screen_selection_result'->>'selected_screen_code';
 IF nullif(btrim(v_screen),'') IS NULL OR NOT EXISTS (
   SELECT 1 FROM lf_ops.pantallas s
   JOIN lf_ops.reglas_pantallas rel ON rel.pantalla_id=s.id
   JOIN lf_ops.reglas r ON r.id=rel.regla_id
   WHERE s.codigo=v_screen AND r.codigo=v_rule
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_RULE_NOT_IN_SELECTED_SCREEN'; END IF;
 SELECT count(*) INTO v_n FROM lf_ops.reglas WHERE codigo=v_rule;
 IF v_n<>1 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_EXACT_RULE_CARDINALITY:%',v_n; END IF;
 SELECT * INTO v_before FROM lf_ops.reglas WHERE codigo=v_rule FOR UPDATE;
 IF v_before.estado<>'CANDIDATO' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_REQUIRES_CANDIDATO:%',v_before.estado;
 END IF;
 v_snapshot := public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF v_snapshot IS DISTINCT FROM p_input->>'analysis_snapshot_sha256' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SOURCE_SNAPSHOT_STALE';
 END IF;
 v_old_title:=v_before.titulo;
 v_old_desc:=v_before.descripcion;
 v_old_reason:=v_before.razon;
 v_new_title:=COALESCE(v_changes->>'titulo',v_old_title);
 v_new_desc:=COALESCE(v_changes->>'descripcion',v_old_desc);
 v_new_reason:=COALESCE(v_changes->>'razon',v_old_reason);
 IF v_new_title IS DISTINCT FROM v_old_title THEN v_changed:=v_changed+1; END IF;
 IF v_new_desc IS DISTINCT FROM v_old_desc THEN v_changed:=v_changed+1; END IF;
 IF v_new_reason IS DISTINCT FROM v_old_reason THEN v_changed:=v_changed+1; END IF;
 IF v_changed=0 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_NO_MATERIAL_CHANGE'; END IF;
 v_mode:=public.lf_resolve_operation_mode_v1('ACTUALIZACION_REGLA_LF','REMEDIATE_EXISTING','GOVERNED');
 IF v_mode->>'status' IS DISTINCT FROM 'READY' OR v_mode->>'destination_kind' IS DISTINCT FROM 'CANONICAL_CANDIDATE'
    OR v_mode->>'write_allowed' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_GOVERNED_MODE_NOT_READY'; END IF;
 v_reservation:=public.fn_lf_operation_reserve_execution_v1(
   p_child,'ACTUALIZACION_REGLA_LF','REGLA',v_rule,
   'skill-child-v1:'||p_run,p_request_sha,p_parent,NULL,NULL,
   jsonb_build_object(
     'profile_handoff',jsonb_build_object(
       'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
     'analysis_snapshot_sha256',v_snapshot,'profile_decision_sha256',v_out_sha,
     'production_allowed',false,'promotion_authorized',false,
     'candidate_patch_scope','DOCUMENTARY_ONLY')
 );
 IF v_reservation->>'result'<>'RESERVED_NEW_EXECUTION'
    OR v_reservation->>'execution_id'<>p_child THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_RESERVATION_NOT_NEW'; END IF;
 v_evidence:='SKILLRUN:'||p_run;
 v_trust:=jsonb_build_object('valid',true,'code','LF_RULE_CHILD_SERVER_VALIDATED_V1',
   'server_assertions',jsonb_build_array('required_evidence_present'),
   'server_hard_fails','[]'::jsonb);
 -- Each record uses the existing canonical judge/core. No raw PASS inserts.
 v_step_payload:=jsonb_build_object(
    'ekb_refs',jsonb_build_array('INPUT_GOVERNANCE_LF_V1_4'),
    'execution_binding',p_child,'parent_execution_id',p_parent,
    'profile_decision_sha256',v_out_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'ekb_preflight',v_evidence||'/10',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'category',v_before.categoria,
    'candidate_classification','REGLA_UPDATE','analysis_snapshot_sha256',v_snapshot);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'classify',v_evidence||'/20',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'existing_count',1,'expected_existence','ONE_CANDIDATO');
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'existing_check',v_evidence||'/30',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'destination_schema','lf_ops','destination_table','reglas','unique_code_guard',true);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'destination_validate',v_evidence||'/40',v_step_payload,v_trust);

 v_written:=public.lf_regla_candidate_write_v1(
    p_child,'REGLA_UPDATE',v_rule,v_before.categoria,v_new_title,
    v_new_desc,v_new_reason,v_before.valor_config,
    v_before.es_transversal,v_before.origen
 );
 IF v_written->>'result' IS DISTINCT FROM 'RULE_CANDIDATE_UPDATED'
    OR v_written->'before'->>'estado' IS DISTINCT FROM 'CANDIDATO'
    OR v_written->'after'->>'estado' IS DISTINCT FROM 'CANDIDATO' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_WRITER_RESULT_MISMATCH'; END IF;
 v_step_payload:=jsonb_build_object(
    'execution_id',p_child,'rule_code',v_rule,
    'write_result',v_written->>'result','estado','CANDIDATO',
    'writer','lf_regla_candidate_write_v1');
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'candidate_write',v_evidence||'/50',v_step_payload,v_trust);
 SELECT to_jsonb(r) INTO v_after FROM lf_ops.reglas r WHERE r.codigo=v_rule;
 IF v_after IS NULL OR v_after->>'estado'<>'CANDIDATO'
    OR v_after->>'titulo' IS DISTINCT FROM v_new_title
    OR v_after->>'descripcion' IS DISTINCT FROM v_new_desc
    OR v_after->>'razon' IS DISTINCT FROM v_new_reason
    OR coalesce(v_after->'valor_config','null'::jsonb) IS DISTINCT FROM coalesce(to_jsonb(v_before.valor_config),'null'::jsonb)
    OR v_after->>'categoria' IS DISTINCT FROM v_before.categoria
    OR v_after->>'es_transversal' IS DISTINCT FROM v_before.es_transversal::text
    OR v_after->>'pendiente_decision' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_CANONICAL_READBACK_MISMATCH'; END IF;
 v_after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF v_after_sha IS NULL OR v_after_sha=v_snapshot THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_CANONICAL_HASH_NOT_CHANGED'; END IF;
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'readback_row',v_after,'estado','CANDIDATO',
    'source_snapshot_sha256',v_snapshot,'result_snapshot_sha256',v_after_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'readback',v_evidence||'/60',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'execution_id',p_child,'operation_code','ACTUALIZACION_REGLA_LF',
    'trace_ref',v_evidence,'no_promotion',true,'result_snapshot_sha256',v_after_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'trace_close',v_evidence||'/70',v_step_payload,v_trust);
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=p_child AND step_id=ANY(v_steps)
      AND status='PASS_CLEAN')<>7 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_7_STEPS_NOT_CLEAN'; END IF;
 UPDATE public.lf_operation_execution SET
    status='COMPLETED',completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'operation_closed',true,'candidate_write_verified',true,
      'result_snapshot_sha256',v_after_sha,'rule_state','CANDIDATO',
      'promotion_authorized',false,'profile_continuation_required',true),
    updated_by_execution_id=p_child,updated_at=now()
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_TERMINAL_WRITE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','child_execution_id',p_child,
   'parent_execution_id',p_parent,'rule_code',v_rule,
   'result_snapshot_sha256',v_after_sha,'promotion_authorized',false);
END
$function$
;

-- live function lf_skill_rule_child_readback_v1 md5=85b22ffafeeb740d1c3ba403ac21190e


CREATE OR REPLACE FUNCTION public.lf_skill_rule_child_readback_v1(p_parent text, p_run text, p_child text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'lf_ops'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;
 v_code text; v_sha text; v_count integer; v_clean integer; v_names integer;
BEGIN
 IF coalesce(p_parent,'')='' OR coalesce(p_run,'')='' OR coalesce(p_child,'')='' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_READBACK_INPUT_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_invocation_v1 i
   WHERE i.skill_run_id=p_run AND i.skill_code='RULE_UPDATE_APPLY'
     AND i.parent_execution_id=p_parent AND i.child_execution_id=p_child
     AND i.status='COMPLETED') THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_INVOCATION_MISMATCH'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_child
   AND operation_code='ACTUALIZACION_REGLA_LF'
   AND target_type='REGLA'
   AND created_by_execution_id=p_parent;
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_OPERATION_BINDING_INVALID'); END IF;
 IF e.manifest#>>'{profile_handoff,source_execution_id}' IS DISTINCT FROM p_parent
    OR e.manifest#>>'{profile_handoff,skill_run_id}' IS DISTINCT FROM p_run THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_HANDOFF_MISMATCH'); END IF;
 IF e.status<>'COMPLETED' THEN
   RETURN jsonb_build_object('status','CHILD_IN_PROGRESS','child_execution_id',p_child,
     'effect_verified',false,'profile_execution_complete',false); END IF;
 IF e.manifest->>'candidate_write_verified' IS DISTINCT FROM 'true'
    OR e.manifest->>'rule_state' IS DISTINCT FROM 'CANDIDATO'
    OR e.manifest->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR coalesce(e.manifest->>'result_snapshot_sha256','') !~ '^[0-9a-f]{64}$' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_COMPLETION_UNATTESTED'); END IF;
 SELECT count(*),count(*) FILTER (WHERE status='PASS_CLEAN'),
        count(DISTINCT step_id) FILTER(WHERE step_id IN (
          'ekb_preflight','classify','existing_check','destination_validate',
          'candidate_write','readback','trace_close'))
 INTO v_count,v_clean,v_names
 FROM public.lf_operation_execution_steps WHERE execution_id=p_child;
 IF v_count<>7 OR v_clean<>7 OR v_names<>7 THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_REQUIRED_STEPS_NOT_CLEAN',
     'observed_steps',v_count,'clean_steps',v_clean); END IF;
 v_code:=e.target_code;
 IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_code AND estado='CANDIDATO'
   AND pendiente_decision=true) THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_STATE_DRIFT'); END IF;
 v_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_code);
 IF v_sha IS DISTINCT FROM e.manifest->>'result_snapshot_sha256' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT'); END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','effect_verified',true,
   'parent_execution_id',p_parent,'child_execution_id',p_child,
   'skill_run_id',p_run,'operation_code','ACTUALIZACION_REGLA_LF',
   'rule_code',v_code,'rule_state','CANDIDATO','result_snapshot_sha256',v_sha,
   'canonical_readback',true,'required_steps_clean',7,
   'promotion_authorized',false,'profile_execution_complete',false,
   'next_action','CONTINUE_SAME_PARENT_PROFILE');
END
$function$
;

-- live function lf_skill_rule_step_record_v1 md5=7a7c2a3ae4c62d1ea7570bca84fd66de


CREATE OR REPLACE FUNCTION public.lf_skill_rule_step_record_v1(p_child text, p_step text, p_ref text, p_evidence jsonb, p_trust jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v jsonb;
BEGIN
 v:=public.lf_record_operation_step_core_v1(
  p_child,p_step,p_ref,p_evidence,p_child,
  'ACTUALIZACION_REGLA_LF','REGLA',
  'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
  p_trust,false,'lf_skill_rule_step_record_v1');
 IF v->>'outcome'<>'STEP_RECORDED' OR v->>'status'<>'PASS_CLEAN' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_STEP_RECORD_FAILED:%:%',p_step,coalesce(v->>'code',v->>'status','UNKNOWN');
 END IF;
END
$function$
;

CREATE TRIGGER trg_lf_rule_promotion_guard_v1 BEFORE UPDATE OF estado ON lf_ops.reglas FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();

INSERT INTO public.lf_operation_registry SELECT (jsonb_populate_record(NULL::public.lf_operation_registry,'{"notes":"Lightweight governed rule candidate operation; no automatic promotion; VIGENTE direct update blocked.","status":"SANDBOX_ACTIVE","version":"v0.1","created_at":"2026-09-13T15:07:51.431232+00:00","updated_at":"2026-09-14T06:11:16.86926+00:00","source_repo":"cristhianlujan/claude-persona-lf-patch","source_model":"GOVERNED_DB_OPERATION","source_paths":["public.lf_router_resolve_v1","public.lf_router_action_registry","lf_ops.reglas","public.lf_regla_candidate_write_v1"],"operation_code":"ACTUALIZACION_REGLA_LF","operation_type":"UPDATE_CANDIDATE","operation_domain":"RULE_GOVERNANCE","operation_family":"RULE_OPERATIONS","lifecycle_state_code":"OP_CANDIDATE","applies_to_asset_type":"REGLA","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_registry SELECT (jsonb_populate_record(NULL::public.lf_operation_registry,'{"notes":"Uso read-only de un perfil existente. Resolver primero exactamente un activo PERFIL; no crea, no modifica GitHub, no habilita runtime y no cambia estado del activo. | 2026-09-20 context wiring: mandatory server-derived context_admission before execute_profile; compact JIT-only receipt, current resolver readback, and exact receipt digest binding enforced. | 2026-09-21 research baseline wiring: canonical profile asset decides applicability; durable baseline_freeze step precedes execute_profile; exact snapshot/digest is rebound at server trust validation; legacy profiles default NOT_REQUIRED.","status":"PRODUCCION_CONTROLADA_READ_ONLY","version":"v0.1","created_at":"2026-08-27T06:11:02.712359+00:00","updated_at":"2026-09-21T05:50:56.836627+00:00","source_repo":"Supabase/LF_OPERATION_GOVERNANCE","source_model":"SUPABASE_STRUCTURED_OPERATION","source_paths":["public.v_lf_fuente_operativa","public.lf_operation_registry","public.lf_operation_contracts","public.lf_operation_step_contracts"],"operation_code":"EJECUCION_PERFIL_LF","operation_type":"PROFILE_EXECUTION","operation_domain":"PROFILE_EXECUTION","operation_family":"PROFILE_OPERATIONS","lifecycle_state_code":"OP_OPERATIONAL","applies_to_asset_type":"PERFIL","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_registry SELECT (jsonb_populate_record(NULL::public.lf_operation_registry,'{"notes":"Ruta canónica sandbox para reparación mínima y reversible de DB/MIGRATION/FUNCTION/TRIGGER. No producción; exige EKB/schema/source-first, target exacto, rollback y readback/regresión. DB_WRITE_TRANSPORT v1 is the transversal selector for write-channel choice; authority remains in Router/contracts. A1 uses server-bound Router authority receipt and effect-time revalidation; caller-declared router JSON is not authority.","status":"SANDBOX_ACTIVE","version":"v0.1","created_at":"2026-09-03T16:52:30.385083+00:00","updated_at":"2026-09-17T22:43:47.487254+00:00","source_repo":"Supabase/LF_OPERATION_GOVERNANCE","source_model":"SUPABASE_STRUCTURED_OPERATION","source_paths":["public.lf_capability_binding","public.lf_capability_current","public.lf_capability_registry","public.lf_operation_contracts","public.lf_operation_effect_guard","public.lf_operation_judges","public.lf_operation_registry","public.lf_operation_step_contracts","public.lf_operation_step_judge_bindings","public.lf_operation_steps","public.lf_router_action_registry","public.lf_router_downstream_authority_validate_v1"],"operation_code":"ACTUALIZACION_DB_LF","operation_type":"UPDATE_PROTOCOL","operation_domain":"DATABASE_MAINTENANCE","operation_family":"DATABASE_OPERATIONS","lifecycle_state_code":"OP_CANDIDATE","applies_to_asset_type":null,"created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_registry SELECT (jsonb_populate_record(NULL::public.lf_operation_registry,'{"notes":"Lightweight governed rule candidate operation; no automatic promotion; VIGENTE direct update blocked.","status":"SANDBOX_ACTIVE","version":"v0.1","created_at":"2026-09-13T15:07:51.431232+00:00","updated_at":"2026-09-14T06:11:16.86926+00:00","source_repo":"cristhianlujan/claude-persona-lf-patch","source_model":"GOVERNED_DB_OPERATION","source_paths":["public.lf_router_resolve_v1","public.lf_router_action_registry","lf_ops.reglas","public.lf_regla_candidate_write_v1"],"operation_code":"CREACION_REGLA_LF","operation_type":"CREATE_CANDIDATE","operation_domain":"RULE_GOVERNANCE","operation_family":"RULE_OPERATIONS","lifecycle_state_code":"OP_CANDIDATE","applies_to_asset_type":"REGLA","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"init_execution","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":0,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/init_execution","operation_code":"EJECUCION_PERFIL_LF","execution_order":0,"evidence_required":"execution_id_created","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"router","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":10,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/router","operation_code":"EJECUCION_PERFIL_LF","execution_order":10,"evidence_required":"router_read; action=PROFILE_EXECUTION","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"profile_resolve","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":20,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/profile_resolve","operation_code":"EJECUCION_PERFIL_LF","execution_order":20,"evidence_required":"exact_profile_resolved; codigo_activo; profile_slug","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"profile_source_read","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":30,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/profile_source_read","operation_code":"EJECUCION_PERFIL_LF","execution_order":30,"evidence_required":"profile_source_ref; source_revision","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"input_validate","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":40,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/input_validate","operation_code":"EJECUCION_PERFIL_LF","execution_order":40,"evidence_required":"input_scope; activation_trigger_match","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"output_validate","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":60,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/output_validate","operation_code":"EJECUCION_PERFIL_LF","execution_order":60,"evidence_required":"output_contract_result; deterministic_validation","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"semantic_judge","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":70,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/semantic_judge","operation_code":"EJECUCION_PERFIL_LF","execution_order":70,"evidence_required":"semantic_judge_result; unsupported_claims","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"report_output","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":80,"updated_at":"2026-08-27T06:12:01.171299+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/report_output","operation_code":"EJECUCION_PERFIL_LF","execution_order":80,"evidence_required":"result; profile_code; execution_id; no_write_performed","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"preflight","required":true,"created_at":"2026-09-03T16:52:30.385083+00:00","source_sha":null,"step_order":10,"updated_at":"2026-09-17T22:43:47.487254+00:00","source_path":"public.lf_operation_step_contracts/ACTUALIZACION_DB_LF/preflight","operation_code":"ACTUALIZACION_DB_LF","execution_order":10,"evidence_required":"router_binding; ekb_refs; schema_source_readback; exact_target; rollback_plan; db_write_transport_binding; router_downstream_authority","created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"patch","required":true,"created_at":"2026-09-03T16:52:30.385083+00:00","source_sha":null,"step_order":20,"updated_at":"2026-09-17T22:43:47.487254+00:00","source_path":"public.lf_operation_step_contracts/ACTUALIZACION_DB_LF/patch","operation_code":"ACTUALIZACION_DB_LF","execution_order":20,"evidence_required":"minimal_diff; write_receipt; target_binding; db_write_transport_decision; db_write_transport_receipt; router_downstream_authority","created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"verify","required":true,"created_at":"2026-09-03T16:52:30.385083+00:00","source_sha":null,"step_order":30,"updated_at":"2026-09-17T22:43:47.487254+00:00","source_path":"public.lf_operation_step_contracts/ACTUALIZACION_DB_LF/verify","operation_code":"ACTUALIZACION_DB_LF","execution_order":30,"evidence_required":"readback; regression_or_parity; ekb_closeout; db_write_transport_readback; router_downstream_authority","created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"ekb_preflight","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":10,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/ekb_preflight","operation_code":"CREACION_REGLA_LF","execution_order":10,"evidence_required":"ekb_refs,execution_binding","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"ekb_preflight","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":10,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/ekb_preflight","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":10,"evidence_required":"ekb_refs,execution_binding","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"classify","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":20,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/classify","operation_code":"CREACION_REGLA_LF","execution_order":20,"evidence_required":"rule_code,category,candidate_classification","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"classify","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":20,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/classify","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":20,"evidence_required":"rule_code,category,candidate_classification","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"existing_check","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":30,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/existing_check","operation_code":"CREACION_REGLA_LF","execution_order":30,"evidence_required":"rule_code,existing_count,expected_existence","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"existing_check","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":30,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/existing_check","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":30,"evidence_required":"rule_code,existing_count,expected_existence","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"destination_validate","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":40,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/destination_validate","operation_code":"CREACION_REGLA_LF","execution_order":40,"evidence_required":"destination_schema,destination_table,unique_code_guard","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"destination_validate","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":40,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/destination_validate","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":40,"evidence_required":"destination_schema,destination_table,unique_code_guard","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"candidate_write","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":50,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/candidate_write","operation_code":"CREACION_REGLA_LF","execution_order":50,"evidence_required":"execution_id,rule_code,write_result,estado","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"candidate_write","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":50,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/candidate_write","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":50,"evidence_required":"execution_id,rule_code,write_result,estado","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"readback","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":60,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/readback","operation_code":"CREACION_REGLA_LF","execution_order":60,"evidence_required":"rule_code,readback_row,estado","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"readback","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":60,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/readback","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":60,"evidence_required":"rule_code,readback_row,estado","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"trace_close","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":70,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/CREACION_REGLA_LF/trace_close","operation_code":"CREACION_REGLA_LF","execution_order":70,"evidence_required":"execution_id,operation_code,trace_ref,no_promotion","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"context_admission","required":true,"created_at":"2026-09-20T10:26:39.527635+00:00","source_sha":null,"step_order":45,"updated_at":"2026-09-20T10:26:39.527635+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/context_admission","operation_code":"EJECUCION_PERFIL_LF","execution_order":45,"evidence_required":"context_receipt_ref; context_receipt_digest; context_budget_status; context_event_id; context_budget_event_id; delivery; lazy_refs; profile_source_mode; jit_resolver_ref; server_validated","created_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003","updated_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003"}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"execute_profile","required":true,"created_at":"2026-08-27T06:12:01.171299+00:00","source_sha":null,"step_order":50,"updated_at":"2026-09-21T05:50:56.836627+00:00","source_path":"public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/execute_profile","operation_code":"EJECUCION_PERFIL_LF","execution_order":50,"evidence_required":"profile_output; source_refs; context_receipt_ref; context_receipt_digest; context_transport; research_baseline_ref; research_baseline_digest","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"trace_close","required":true,"created_at":"2026-09-13T15:07:51.431232+00:00","source_sha":null,"step_order":70,"updated_at":"2026-09-13T15:07:51.431232+00:00","source_path":"supabase://public/lf_operation_step_contracts/ACTUALIZACION_REGLA_LF/trace_close","operation_code":"ACTUALIZACION_REGLA_LF","execution_order":70,"evidence_required":"execution_id,operation_code,trace_ref,no_promotion","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_steps SELECT (jsonb_populate_record(NULL::public.lf_operation_steps,'{"active":true,"step_id":"research_baseline_freeze","required":true,"created_at":"2026-09-21T05:50:56.836627+00:00","source_sha":"4d2de745272a3d5b746deab20de182dc560798d031388aa7d7086de411537f35","step_order":47,"updated_at":"2026-09-21T05:50:56.836627+00:00","source_path":"sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json","operation_code":"EJECUCION_PERFIL_LF","execution_order":47,"evidence_required":"research_baseline_binding; baseline_receipt_ref; server_validated","created_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Resolver exactamente un PERFIL.","step_id":"profile_resolve","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":20,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"profile_source_read","resolver_ref":"CANONICAL_PROFILE_ASSET_RESOLUTION","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_PROFILE_RESOLVE_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["exact_profile_resolved","codigo_activo","profile_slug"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["exact_profile_resolved","codigo_activo","profile_slug"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":20,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["exact_profile_resolved","codigo_activo","profile_slug"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Leer entrypoint/contratos sin write.","step_id":"profile_source_read","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":30,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"input_validate","resolver_ref":"EXACT_PROFILE_SOURCE_READBACK","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_PROFILE_SOURCE_READ_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["profile_source_ref","source_revision"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["profile_source_ref","source_revision"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":30,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["profile_source_ref","source_revision"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"ekb_preflight governed rule step.","step_id":"ekb_preflight","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":10,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"classify","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_EKB_PREFLIGHT","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["ekb_refs","execution_binding"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":10,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["ekb_refs","execution_binding"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"ekb_preflight governed rule step.","step_id":"ekb_preflight","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":10,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"classify","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_EKB_PREFLIGHT","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["ekb_refs","execution_binding"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":10,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["ekb_refs","execution_binding"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"classify governed rule step.","step_id":"classify","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":20,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"existing_check","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_CLASSIFY","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["rule_code","category","candidate_classification"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":20,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["rule_code","category","candidate_classification"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"classify governed rule step.","step_id":"classify","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":20,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"existing_check","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_CLASSIFY","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["rule_code","category","candidate_classification"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":20,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["rule_code","category","candidate_classification"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"existing_check governed rule step.","step_id":"existing_check","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":30,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"destination_validate","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_EXISTING_CHECK","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["rule_code","existing_count","expected_existence"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":30,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["rule_code","existing_count","expected_existence"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"existing_check governed rule step.","step_id":"existing_check","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":30,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"destination_validate","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_EXISTING_CHECK","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["rule_code","existing_count","expected_existence"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":30,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["rule_code","existing_count","expected_existence"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"destination_validate governed rule step.","step_id":"destination_validate","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":40,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"candidate_write","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_DESTINATION_VALIDATE","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["destination_schema","destination_table","unique_code_guard"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":40,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["destination_schema","destination_table","unique_code_guard"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Deterministic-first handshake. NOT_REQUIRED closes server-side with null envelope. PRE_RESEARCH_ALWAYS returns BASELINE_REQUIRED without recording, then the same profile model generates the compact envelope and retries this exact step.","status":"ACTIVE_ENFORCEMENT","purpose":"Freeze a compact server-bound pre-research solution baseline when the canonical profile asset requires it; otherwise close as server-side N/A.","step_id":"research_baseline_freeze","created_at":"2026-09-21T05:50:56.836627+00:00","step_order":47,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"execute_profile","resolver_ref":"public.lf_profile_execution_research_baseline_v1","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_RESEARCH_BASELINE_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":"public.lf_profile_execution_research_baseline_v1(text,jsonb,text)","fail_condition":{"server_validation_failed":true},"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["research_baseline_binding","baseline_receipt_ref","server_validated"],"pass_condition":{"server_validated":true,"applicability_source":"PROFILE_ASSET_METADATA","clean_step_immutable":true},"block_condition":{"binding_mismatch":true,"missing_or_mutated_baseline":true,"external_pre_freeze_evidence":true},"execution_order":47,"mini_judge_code":"MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["research_baseline_binding","baseline_receipt_ref","server_validated"],"created_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Resolver ACT-0001 y clasificar uso de perfil.","step_id":"router","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":10,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"profile_resolve","resolver_ref":"public.lf_router_resolve_v1","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_ROUTER_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["router_read","action"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["router_read","action"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":10,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["router_read","action"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Validar soporte semántico.","step_id":"semantic_judge","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":70,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"report_output","resolver_ref":"BOUND_SEMANTIC_JUDGE","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_SEMANTIC_JUDGE_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["semantic_judge_result","unsupported_claims"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["semantic_judge_result","unsupported_claims"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":70,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["semantic_judge_result","unsupported_claims"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Ejecutar el perfil read-only.","step_id":"execute_profile","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":50,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"output_validate","resolver_ref":"public.lf_record_profile_execution_step_v1 + SELECTED_PROFILE_MODEL_RUNTIME","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_EXECUTE_PROFILE_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["context_receipt_digest","context_receipt_ref","context_transport","profile_output","research_baseline_digest","research_baseline_ref","source_refs"],"pass_condition":{"context_delivery":"COMPACT_JIT_ONLY","must_not_be_generic":true,"required_evidence_keys":["profile_output","source_refs"],"full_prefetch_forbidden":true,"must_match_step_purpose":true,"research_baseline_exact_binding":true,"context_admission_predecessor_clean":true,"research_baseline_predecessor_clean":true,"research_baseline_output_immutable_when_required":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":50,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["context_receipt_digest","context_receipt_ref","context_transport","profile_output","research_baseline_digest","research_baseline_ref","source_refs"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"destination_validate governed rule step.","step_id":"destination_validate","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":40,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"candidate_write","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_DESTINATION_VALIDATE","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["destination_schema","destination_table","unique_code_guard"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":40,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["destination_schema","destination_table","unique_code_guard"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"candidate_write governed rule step.","step_id":"candidate_write","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":50,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"readback","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_CANDIDATE_WRITE","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["execution_id","rule_code","write_result","estado"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":50,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["execution_id","rule_code","write_result","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"candidate_write governed rule step.","step_id":"candidate_write","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":50,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"readback","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_CANDIDATE_WRITE","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["execution_id","rule_code","write_result","estado"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":50,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["execution_id","rule_code","write_result","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"readback governed rule step.","step_id":"readback","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":60,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"trace_close","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_READBACK","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["rule_code","readback_row","estado"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":60,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["rule_code","readback_row","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"readback governed rule step.","step_id":"readback","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":60,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":"trace_close","resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_READBACK","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["rule_code","readback_row","estado"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":60,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["rule_code","readback_row","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"trace_close governed rule step.","step_id":"trace_close","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":70,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":null,"resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_CREACION_REGLA_LF_TRACE_CLOSE","contract_code":"CONTRACT-CREACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"CREACION_REGLA_LF","output_payload":["execution_id","operation_code","trace_ref","no_promotion"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":70,"mini_judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["execution_id","operation_code","trace_ref","no_promotion"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Small fail-closed rule governance step.","status":"ACTIVE_ENFORCEMENT","purpose":"trace_close governed rule step.","step_id":"trace_close","created_at":"2026-09-13T15:07:51.431232+00:00","step_order":70,"updated_at":"2026-09-13T15:07:51.431232+00:00","next_if_pass":null,"resolver_ref":"RULE_OPERATION_DETERMINISTIC","blocking_code":"BLOCK_ACTUALIZACION_REGLA_LF_TRACE_CLOSE","contract_code":"CONTRACT-ACTUALIZACION_REGLA_LF-v0.1","execution_sql":null,"fail_condition":{},"input_required":{},"operation_code":"ACTUALIZACION_REGLA_LF","output_payload":["execution_id","operation_code","trace_ref","no_promotion"],"pass_condition":{"required_evidence_present":true},"block_condition":{"missing_required_evidence":true},"execution_order":70,"mini_judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","next_if_blocked":"trace_close","required_evidence_keys":["execution_id","operation_code","trace_ref","no_promotion"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Sandbox only; no production.","status":"ACTIVE_ENFORCEMENT","purpose":"Validar Router, EKB, schema/source, target exacto y rollback antes de cualquier write.","step_id":"preflight","created_at":"2026-09-03T16:52:30.385083+00:00","step_order":10,"updated_at":"2026-09-17T22:43:47.487254+00:00","next_if_pass":"patch","resolver_ref":"SUPABASE_MCP","blocking_code":"BLOCK_DB_PREWRITE_PREFLIGHT","contract_code":"CONTRACT-ACTUALIZACION-DB-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":["db_write_transport_capability_binding","ekb_refs","exact_target","rollback_plan","router_authority_receipt","router_authority_validation","router_binding","schema_source"],"operation_code":"ACTUALIZACION_DB_LF","output_payload":["preflight_pass"],"pass_condition":{"preflight_pass":true},"block_condition":{"preflight_pass":false},"execution_order":10,"mini_judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","next_if_blocked":"close","required_evidence_keys":["db_write_transport_capability_binding","ekb_refs","exact_target","rollback_plan","router_authority_receipt","router_authority_validation","router_binding","schema_source_readback"],"created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"No parity bypass, no direct hash patch. DB_WRITE_TRANSPORT selects exact-version source-first for MIGRATION and governed SUPABASE_MCP for direct DB/FUNCTION/TRIGGER writes.","status":"ACTIVE_ENFORCEMENT","purpose":"Aplicar únicamente el delta mínimo reversible al target exacto.","step_id":"patch","created_at":"2026-09-03T16:52:30.385083+00:00","step_order":20,"updated_at":"2026-09-17T22:43:47.487254+00:00","next_if_pass":"verify","resolver_ref":"DB_WRITE_TRANSPORT","blocking_code":"BLOCK_DB_PATCH_SCOPE","contract_code":"CONTRACT-ACTUALIZACION-DB-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":["db_write_transport_decision","exact_target","minimal_diff","operation_effect_guard_reservation","rollback_plan","router_authority_pre_effect"],"operation_code":"ACTUALIZACION_DB_LF","output_payload":["db_write_transport_receipt","write_receipt"],"pass_condition":{"minimal_patch":true},"block_condition":{"unscoped_or_irreversible":true},"execution_order":20,"mini_judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","next_if_blocked":"close","required_evidence_keys":["db_write_transport_decision","db_write_transport_receipt","minimal_diff","operation_effect_guard_reservation","router_authority_pre_effect","target_binding","write_receipt"],"created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"PASS solo con readback y sin regresión.","status":"ACTIVE_ENFORCEMENT","purpose":"Verificar readback exacto, regresión/paridad y cierre EKB.","step_id":"verify","created_at":"2026-09-03T16:52:30.385083+00:00","step_order":30,"updated_at":"2026-09-17T22:43:47.487254+00:00","next_if_pass":null,"resolver_ref":"SUPABASE_MCP","blocking_code":"BLOCK_DB_VERIFY_FAILED","contract_code":"CONTRACT-ACTUALIZACION-DB-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":["db_write_transport_readback","ekb_closeout","operation_effect_guard_readback","readback","regression_or_parity","router_authority_readback"],"operation_code":"ACTUALIZACION_DB_LF","output_payload":["verified"],"pass_condition":{"verified":true},"block_condition":{"verified":false},"execution_order":30,"mini_judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","next_if_blocked":null,"required_evidence_keys":["db_write_transport_readback","ekb_closeout","operation_effect_guard_readback","readback","regression_or_parity","router_authority_readback"],"created_by_execution_id":"EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Crear execution_id antes de ejecutar el perfil.","step_id":"init_execution","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":0,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"router","resolver_ref":"public.lf_profile_execution_begin_v1","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_INIT_EXECUTION_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["execution_id_created"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["execution_id_created"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":0,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["execution_id_created"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Validar output contract.","step_id":"output_validate","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":60,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":"semantic_judge","resolver_ref":"BOUND_PROFILE_OUTPUT_VALIDATOR","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_OUTPUT_VALIDATE_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["output_contract_result","deterministic_validation"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["output_contract_result","deterministic_validation"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":60,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["output_contract_result","deterministic_validation"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. No Drive dereference.","status":"ACTIVE_ENFORCEMENT","purpose":"Entregar resultado trazable.","step_id":"report_output","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":80,"updated_at":"2026-09-21T05:50:56.836627+00:00","next_if_pass":null,"resolver_ref":"DETERMINISTIC_REPORT_OUTPUT","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_REPORT_OUTPUT_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["result","profile_code","execution_id","no_write_performed"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["result","profile_code","execution_id","no_write_performed"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":80,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["result","profile_code","execution_id","no_write_performed"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Mandatory server-derived bounded context gate. Full policies, EKB entries and READMEs remain out of model transport by default.","status":"ACTIVE_ENFORCEMENT","purpose":"Compilar y verificar el contexto mínimo necesario antes de despachar el modelo.","step_id":"context_admission","created_at":"2026-09-20T10:26:39.527635+00:00","step_order":45,"updated_at":"2026-10-24T18:35:22.788945+00:00","next_if_pass":"research_baseline_freeze","resolver_ref":"public.lf_profile_execution_context_admission_v1 + public.lf_profile_execution_channel_context_v1","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_CONTEXT_ADMISSION_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":"public.lf_profile_execution_context_admission_v1(text)","fail_condition":{"server_validation_failed":true},"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"],"pass_condition":{"delivery":"COMPACT_JIT_ONLY","server_validated":true,"context_budget_status":["GREEN","YELLOW"]},"block_condition":{"context_budget_red":true,"full_prefetch_forbidden":true,"missing_context_receipt":true,"context_readback_mismatch":true},"execution_order":45,"mini_judge_code":"MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1","next_if_blocked":"RETURN_TO_ROUTER","required_evidence_keys":["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"],"created_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_step_contracts,'{"notes":"Supabase-only operational contract. Materializes producer-independent scope authority packet before profile execution; no Drive dereference. | CONTEXT_PACK/INPUT_GOVERNANCE pending or blocked is handled by the profile execution worker; the same Router decision is not re-entered.","status":"ACTIVE_ENFORCEMENT","purpose":"Validar scope y trigger.","step_id":"input_validate","created_at":"2026-08-27T06:12:01.171299+00:00","step_order":40,"updated_at":"2026-10-24T18:41:10.116855+00:00","next_if_pass":"context_admission","resolver_ref":"public.lf_profile_execution_input_validate_v1 + programacion.fn_lf_profile_input_governance_resolve_v1","blocking_code":"BLOCKED_EJECUCION_PERFIL_LF_INPUT_VALIDATE_NOT_CLEAN","contract_code":"CONTRACT-EJECUCION-PERFIL-LF-v0.1","execution_sql":null,"fail_condition":null,"input_required":[],"operation_code":"EJECUCION_PERFIL_LF","output_payload":["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"],"pass_condition":{"must_not_be_generic":true,"required_evidence_keys":["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"],"must_match_step_purpose":true},"block_condition":{"generic_payload":true,"wrong_action_or_target":true,"missing_required_evidence":true},"execution_order":40,"mini_judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","next_if_blocked":"RETURN_TO_WORKER","required_evidence_keys":["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"init_execution","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":0,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["execution_id_created"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"router","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":10,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["router_read","action"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"profile_resolve","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":20,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["exact_profile_resolved","codigo_activo","profile_slug"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"profile_source_read","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":30,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["profile_source_ref","source_revision"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"output_validate","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":60,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["output_contract_result","deterministic_validation"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"semantic_judge","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":70,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["semantic_judge_result","unsupported_claims"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"report_output","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":80,"updated_at":"2026-08-27T06:14:36.922403+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["result","profile_code","execution_id","no_write_performed"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"ekb_preflight","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":10,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["ekb_refs","execution_binding"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"ekb_preflight","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":10,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["ekb_refs","execution_binding"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"classify","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":20,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["rule_code","category","candidate_classification"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"classify","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":20,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["rule_code","category","candidate_classification"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"existing_check","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":30,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["rule_code","existing_count","expected_existence"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"existing_check","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":30,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["rule_code","existing_count","expected_existence"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"destination_validate","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":40,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["destination_schema","destination_table","unique_code_guard"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"destination_validate","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":40,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["destination_schema","destination_table","unique_code_guard"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"candidate_write","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":50,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["execution_id","rule_code","write_result","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"candidate_write","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":50,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["execution_id","rule_code","write_result","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"readback","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":60,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["rule_code","readback_row","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"readback","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":60,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["rule_code","readback_row","estado"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"trace_close","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","step_order":70,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"CREACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["execution_id","operation_code","trace_ref","no_promotion"],"created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"trace_close","created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","step_order":70,"updated_at":"2026-09-13T15:07:51.431232+00:00","operation_code":"ACTUALIZACION_REGLA_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["execution_id","operation_code","trace_ref","no_promotion"],"created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"patch","created_at":"2026-09-17T22:43:47.487254+00:00","judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","step_order":20,"updated_at":"2026-09-17T22:43:47.487254+00:00","operation_code":"ACTUALIZACION_DB_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["db_write_transport_decision","db_write_transport_receipt","minimal_diff","operation_effect_guard_reservation","router_authority_pre_effect","target_binding","write_receipt"],"created_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"preflight","created_at":"2026-09-17T22:43:47.487254+00:00","judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","step_order":10,"updated_at":"2026-09-17T22:43:47.487254+00:00","operation_code":"ACTUALIZACION_DB_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["db_write_transport_capability_binding","ekb_refs","exact_target","rollback_plan","router_authority_receipt","router_authority_validation","router_binding","schema_source_readback"],"created_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"verify","created_at":"2026-09-17T22:43:47.487254+00:00","judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","step_order":30,"updated_at":"2026-09-17T22:43:47.487254+00:00","operation_code":"ACTUALIZACION_DB_LF","clean_result_value":"PASS_CLEAN","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_BY_ENFORCEMENT","required_evidence_keys":["db_write_transport_readback","ekb_closeout","operation_effect_guard_readback","readback","regression_or_parity","router_authority_readback"],"created_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"context_admission","created_at":"2026-09-20T10:26:39.527635+00:00","judge_code":"MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1","step_order":45,"updated_at":"2026-09-20T10:26:39.527635+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"],"created_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003","updated_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"execute_profile","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":50,"updated_at":"2026-09-21T05:50:56.836627+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["context_receipt_digest","context_receipt_ref","context_transport","profile_output","research_baseline_digest","research_baseline_ref","source_refs"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"input_validate","created_at":"2026-08-27T06:12:01.171299+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","step_order":40,"updated_at":"2026-10-24T18:41:10.116855+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_WORKER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"],"created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_step_judge_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_step_judge_bindings,'{"status":"ACTIVE_ENFORCEMENT","step_id":"research_baseline_freeze","created_at":"2026-09-21T05:50:56.836627+00:00","judge_code":"MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1","step_order":47,"updated_at":"2026-09-21T05:50:56.836627+00:00","operation_code":"EJECUCION_PERFIL_LF","clean_result_value":"STEP_PASS_WITH_EVIDENCE","return_result_value":"RETURN_TO_ROUTER","blocked_result_value":"BLOCKED_STEP_NOT_CLEAN","required_evidence_keys":["research_baseline_binding","baseline_receipt_ref","server_validated"],"created_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_judges SELECT (jsonb_populate_record(NULL::public.lf_operation_judges,'{"status":"ACTIVE_ENFORCEMENT","fail_if":[],"pass_if":[],"judge_sha":"ROUTER_DOWNSTREAM_AUTHORITY_A1_V1","created_at":"2026-09-17T22:43:47.487254+00:00","judge_code":"JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","judge_path":"supabase://public/lf_operation_judges/ACTUALIZACION_DB_LF/JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1","updated_at":"2026-09-17T22:43:47.487254+00:00","result_values":["PASS_CLEAN","RETURN_TO_WORKER","BLOCKED_BY_ENFORCEMENT"],"operation_code":"ACTUALIZACION_DB_LF","created_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001","updated_by_execution_id":"EXEC-S30-ROUTER-DOWNSTREAM-AUTHORITY-A1-20260917-001"}'::jsonb)).*;

INSERT INTO public.lf_operation_judges SELECT (jsonb_populate_record(NULL::public.lf_operation_judges,'{"status":"ACTIVE_ENFORCEMENT","fail_if":{"missing_required_evidence":true},"pass_if":{"required_evidence_present":true},"judge_sha":null,"created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1","judge_path":"supabase://public/lf_operation_judges/ACTUALIZACION_REGLA_LF","updated_at":"2026-09-13T15:07:51.431232+00:00","result_values":["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"],"operation_code":"ACTUALIZACION_REGLA_LF","created_by_execution_id":"EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_judges SELECT (jsonb_populate_record(NULL::public.lf_operation_judges,'{"status":"ACTIVE_ENFORCEMENT","fail_if":{"missing_required_evidence":true},"pass_if":{"required_evidence_present":true},"judge_sha":null,"created_at":"2026-09-13T15:07:51.431232+00:00","judge_code":"MINI_JUDGE_CREACION_REGLA_LF_V1","judge_path":"supabase://public/lf_operation_judges/CREACION_REGLA_LF","updated_at":"2026-09-13T15:07:51.431232+00:00","result_values":["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"],"operation_code":"CREACION_REGLA_LF","created_by_execution_id":"EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001","updated_by_execution_id":null}'::jsonb)).*;

INSERT INTO public.lf_operation_judges SELECT (jsonb_populate_record(NULL::public.lf_operation_judges,'{"status":"ACTIVE_ENFORCEMENT","fail_if":[],"pass_if":[],"judge_sha":null,"created_at":"2026-08-27T06:11:02.712359+00:00","judge_code":"JUDGE-EJECUCION-PERFIL-LF-v0.1","judge_path":"public.lf_operation_judges/EJECUCION_PERFIL_LF/JUDGE-EJECUCION-PERFIL-LF-v0.1","updated_at":"2026-08-27T06:14:36.922403+00:00","result_values":["STEP_PASS_WITH_EVIDENCE","BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"],"operation_code":"EJECUCION_PERFIL_LF","created_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827","updated_by_execution_id":"USER_AUTH_PROFILE_ROUTING_20260827"}'::jsonb)).*;

INSERT INTO public.lf_operation_judges SELECT (jsonb_populate_record(NULL::public.lf_operation_judges,'{"status":"ACTIVE_ENFORCEMENT","fail_if":["server_validation_failed"],"pass_if":["server_validated"],"judge_sha":null,"created_at":"2026-09-20T10:26:39.527635+00:00","judge_code":"MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1","judge_path":"supabase://public/lf_operation_judges/EJECUCION_PERFIL_LF/MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1","updated_at":"2026-09-20T10:26:39.527635+00:00","result_values":["STEP_PASS_WITH_EVIDENCE","BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"],"operation_code":"EJECUCION_PERFIL_LF","created_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003","updated_by_execution_id":"EXEC-RUNTIME-CONTEXT-ADMISSION-WIRING-20260920-003"}'::jsonb)).*;

INSERT INTO public.lf_operation_judges SELECT (jsonb_populate_record(NULL::public.lf_operation_judges,'{"status":"ACTIVE_ENFORCEMENT","fail_if":["server_validation_failed"],"pass_if":["server_validated"],"judge_sha":"4d2de745272a3d5b746deab20de182dc560798d031388aa7d7086de411537f35","created_at":"2026-09-21T05:50:56.836627+00:00","judge_code":"MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1","judge_path":"sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json","updated_at":"2026-09-21T05:50:56.836627+00:00","result_values":["STEP_PASS_WITH_EVIDENCE","BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"],"operation_code":"EJECUCION_PERFIL_LF","created_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010","updated_by_execution_id":"EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010"}'::jsonb)).*;

INSERT INTO public.lf_operation_mode_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_mode_bindings,'{"notes":"Incomplete rule discovery; canonical lf_ops.reglas remains untouched.","status":"ACTIVE","allowed":true,"task_mode":"CREATE_NEW","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","write_allowed":true,"execution_mode":"EXPLORATION","operation_code":"CREACION_REGLA_LF","canonical_state":null,"destination_kind":"EXPLORATION_STORE","input_completeness":"PARTIAL_ALLOWED","created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","required_existing_state":null}'::jsonb)).*;

INSERT INTO public.lf_operation_mode_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_mode_bindings,'{"notes":"Strict canonical rule candidate creation.","status":"ACTIVE","allowed":true,"task_mode":"CREATE_NEW","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","write_allowed":true,"execution_mode":"GOVERNED","operation_code":"CREACION_REGLA_LF","canonical_state":"CANDIDATO","destination_kind":"CANONICAL_CANDIDATE","input_completeness":"COMPLETE_REQUIRED","created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","required_existing_state":null}'::jsonb)).*;

INSERT INTO public.lf_operation_mode_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_mode_bindings,'{"notes":"Read/evaluate existing exploratory context without mutation.","status":"ACTIVE","allowed":true,"task_mode":"EVALUATE_EXISTING","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","write_allowed":false,"execution_mode":"EXPLORATION","operation_code":"ACTUALIZACION_REGLA_LF","canonical_state":null,"destination_kind":"NO_WRITE","input_completeness":"READ_ONLY","created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","required_existing_state":null}'::jsonb)).*;

INSERT INTO public.lf_operation_mode_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_mode_bindings,'{"notes":"Accumulate partial rule information before governed normalization.","status":"ACTIVE","allowed":true,"task_mode":"REMEDIATE_EXISTING","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","write_allowed":true,"execution_mode":"EXPLORATION","operation_code":"ACTUALIZACION_REGLA_LF","canonical_state":null,"destination_kind":"EXPLORATION_STORE","input_completeness":"PARTIAL_ALLOWED","created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","required_existing_state":null}'::jsonb)).*;

INSERT INTO public.lf_operation_mode_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_mode_bindings,'{"notes":"Strict update of an existing canonical rule candidate; VIGENTE remains blocked.","status":"ACTIVE","allowed":true,"task_mode":"REMEDIATE_EXISTING","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","write_allowed":true,"execution_mode":"GOVERNED","operation_code":"ACTUALIZACION_REGLA_LF","canonical_state":"CANDIDATO","destination_kind":"CANONICAL_CANDIDATE","input_completeness":"COMPLETE_REQUIRED","created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","required_existing_state":"CANDIDATO"}'::jsonb)).*;

INSERT INTO public.lf_operation_mode_bindings SELECT (jsonb_populate_record(NULL::public.lf_operation_mode_bindings,'{"notes":"Read-only exploratory execution of an existing governed profile. No profile mutation, canonical write, runtime activation or promotion.","status":"ACTIVE","allowed":true,"task_mode":"EVALUATE_EXISTING","created_at":"2026-09-14T00:16:01.62114+00:00","updated_at":"2026-09-14T00:16:01.62114+00:00","write_allowed":false,"execution_mode":"EXPLORATION","operation_code":"EJECUCION_PERFIL_LF","canonical_state":null,"destination_kind":"NO_WRITE","input_completeness":"READ_ONLY","created_by_execution_id":"EXEC-S37-PROFILE-EXPLORATION-BINDING-20260913-001","required_existing_state":null}'::jsonb)).*;

INSERT INTO public.lf_task_mode_catalog SELECT (jsonb_populate_record(NULL::public.lf_task_mode_catalog,'{"status":"ACTIVE","task_mode":"CREATE_NEW","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","description":"Create a new target. Vocabulary observed in UI Architect.","mutation_intent":true,"reference_source":"UI_ARCHITECT","allows_new_target":true,"created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","requires_existing_target":false}'::jsonb)).*;

INSERT INTO public.lf_task_mode_catalog SELECT (jsonb_populate_record(NULL::public.lf_task_mode_catalog,'{"status":"ACTIVE","task_mode":"EVALUATE_EXISTING","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","description":"Evaluate an existing target without mutating it. Vocabulary observed in UI Architect.","mutation_intent":false,"reference_source":"UI_ARCHITECT","allows_new_target":false,"created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","requires_existing_target":true}'::jsonb)).*;

INSERT INTO public.lf_task_mode_catalog SELECT (jsonb_populate_record(NULL::public.lf_task_mode_catalog,'{"status":"ACTIVE","task_mode":"REMEDIATE_EXISTING","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","description":"Modify or remediate an existing target. Vocabulary observed in UI Architect.","mutation_intent":true,"reference_source":"UI_ARCHITECT","allows_new_target":false,"created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","requires_existing_target":true}'::jsonb)).*;

INSERT INTO public.lf_execution_mode_catalog SELECT (jsonb_populate_record(NULL::public.lf_execution_mode_catalog,'{"status":"ACTIVE","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","description":"Non-production execution mode observed in UI Architect.","execution_mode":"SANDBOX","runtime_allowed":false,"reference_source":"UI_ARCHITECT","promotion_allowed":false,"allows_partial_input":false,"canonical_write_allowed":false,"created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","requires_evidence_complete":false}'::jsonb)).*;

INSERT INTO public.lf_execution_mode_catalog SELECT (jsonb_populate_record(NULL::public.lf_execution_mode_catalog,'{"status":"ACTIVE","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","description":"LF normalized exploratory mode: partial information may accumulate, but cannot write canonical rules, activate runtime, or promote.","execution_mode":"EXPLORATION","runtime_allowed":false,"reference_source":"LF_NORMALIZATION_FROM_UI_MODE_PATTERN","promotion_allowed":false,"allows_partial_input":true,"canonical_write_allowed":false,"created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","requires_evidence_complete":false}'::jsonb)).*;

INSERT INTO public.lf_execution_mode_catalog SELECT (jsonb_populate_record(NULL::public.lf_execution_mode_catalog,'{"status":"ACTIVE","created_at":"2026-09-13T17:53:44.294855+00:00","updated_at":"2026-09-13T17:53:44.294855+00:00","description":"LF normalized governed mode: complete evidence is required before canonical candidate write; no runtime or promotion implied.","execution_mode":"GOVERNED","runtime_allowed":false,"reference_source":"LF_NORMALIZATION_FROM_UI_MODE_PATTERN","promotion_allowed":false,"allows_partial_input":false,"canonical_write_allowed":true,"created_by_execution_id":"EXEC-ACTUALIZACION-DB-MODE-NORMALIZATION-20260913-001","requires_evidence_complete":true}'::jsonb)).*;

INSERT INTO public.lf_profile_write_authority_v1 SELECT (jsonb_populate_record(NULL::public.lf_profile_write_authority_v1,'{"basis":"aprobado por usuario 2026-11-03: Producto define reglas, promocion y cards","status":"ACTIVE","profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","operation_code":"ACTUALIZACION_REGLA_LF","self_update_allowed":false}'::jsonb)).*;

INSERT INTO public.lf_profile_write_authority_v1 SELECT (jsonb_populate_record(NULL::public.lf_profile_write_authority_v1,'{"basis":"aprobado por usuario 2026-11-03: Producto define reglas, promocion y cards","status":"ACTIVE","profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","operation_code":"CREACION_REGLA_LF","self_update_allowed":false}'::jsonb)).*;

INSERT INTO public.lf_profile_write_authority_v1 SELECT (jsonb_populate_record(NULL::public.lf_profile_write_authority_v1,'{"basis":"aprobado por usuario 2026-11-03: Producto define reglas, promocion y cards","status":"ACTIVE","profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","operation_code":"PROMOCION_REGLA_LF","self_update_allowed":false}'::jsonb)).*;

INSERT INTO public.lf_skill_catalog_v1 SELECT (jsonb_populate_record(NULL::public.lf_skill_catalog_v1,'{"effect":"WRITE_GOVERNED","status":"READY","opener_fn":"lf_skill_o_rule_update_v1","created_at":"2026-11-04T04:36:59.520672+00:00","handler_fn":"lf_skill_h_rule_update_propose_v1","skill_code":"RULE_UPDATE_APPLY","description":"Ejecuta ACTUALIZACION_REGLA_LF solo para parche documental exacto validado por el mismo Product Director RUN; 7 pasos registrados y readback CANDIDATO, nunca promocion","child_caller":null,"input_required":["regla_codigo","analysis_snapshot_sha256","decision_id","candidate_patch"],"required_operation":"ACTUALIZACION_REGLA_LF"}'::jsonb)).*;

INSERT INTO public.lf_skill_catalog_v1 SELECT (jsonb_populate_record(NULL::public.lf_skill_catalog_v1,'{"effect":"WRITE_GOVERNED","status":"READY","opener_fn":null,"created_at":"2026-11-04T04:51:18.295213+00:00","handler_fn":"lf_skill_h_rule_create_propose_v1","skill_code":"RULE_CREATE_APPLY","description":"Abre la operacion gobernada CREACION_REGLA_LF desde el perfil (la escritura la hacen sus 7 pasos)","child_caller":null,"input_required":["regla_codigo"],"required_operation":"CREACION_REGLA_LF"}'::jsonb)).*;

-- Column-for-column live public.lf_operation_contracts definition.
-- External FK to lf_operation_registry not enforced in the isolated object slice.
CREATE TABLE public.lf_operation_contracts(
  operation_code text NOT NULL,
  contract_code text NOT NULL,
  contract_path text NOT NULL,
  contract_sha text,
  required_before_write jsonb NOT NULL DEFAULT '[]'::jsonb,
  allowed jsonb NOT NULL DEFAULT '{}'::jsonb,
  blocked jsonb NOT NULL DEFAULT '[]'::jsonb,
  required_after_write jsonb NOT NULL DEFAULT '[]'::jsonb,
  status text NOT NULL DEFAULT 'CANDIDATO_READ_ONLY',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN',
  updated_by_execution_id text,
  PRIMARY KEY (operation_code,contract_code)
);

-- Exact live contract row captured read-only for isolated PG18 contract migration.
INSERT INTO public.lf_operation_contracts SELECT (jsonb_populate_record(NULL::public.lf_operation_contracts,'{"status": "ACTIVE_ENFORCEMENT", "allowed": {"asset_code": "EDGE_FN_INPUT_GOVERNANCE_AGENT_V1", "asset_type": "CAPABILITY", "entrypoint": "programacion.fn_input_governance_execute(integer,text)", "worker_spec": "programacion.fn_input_governance_worker_spec(integer,text)", "sandbox_only": true, "subject_type": "LF_OPS_PANTALLA", "runtime_orchestrator": "SUPABASE_EDGE_FUNCTION:input-governance-agent-v1", "production_authorized": false, "direct_request_consumer": "MANUAL", "canonical_execution_contract": "INPUT_GOVERNANCE_EXECUTION_CONTRACT", "generic_capability_execution": false}, "blocked": ["screen_not_found", "screen_inactive", "screen_ambiguous", "consumer_not_allowed", "production_promotion", "generic_capability_execution", "subject_asset_role_inversion"], "created_at": "2026-09-28T20:20:23.214746+00:00", "updated_at": "2026-09-28T20:20:23.214746+00:00", "contract_sha": "783103f2196c1e49d1460bee239d41b74235be97f3b114ab27366f7c436afbb9", "contract_code": "CONTRACT-EJECUCION-INPUT-GOVERNANCE-LF-v0.1", "contract_path": "programacion.contratos/INPUT_GOVERNANCE_EXECUTION_CONTRACT", "operation_code": "EJECUCION_INPUT_GOVERNANCE_LF", "required_after_write": ["governance_status", "output_sha256", "screen_code", "consumer"], "required_before_write": ["exact_screen_resolved", "consumer_authorized", "worker_spec_resolved"], "created_by_execution_id": "EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001", "updated_by_execution_id": "EXEC-BOOTSTRAP-EJECUCION-INPUT-GOVERNANCE-LF-20260928-001"}'::jsonb)).*;


-- Exact live function body lf_profile_execution_terminal_authority_receipt_v1, MD5 1d5f3bca8a7601c9f5f46340c83c22d7.
-- Test calls require missing upstream dependencies; no fake Step80 PASS.
CREATE OR REPLACE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  j record;
  v_steps jsonb;
  v_step_count int;
  v_router jsonb;
  v_router_kind text;
  v_scope jsonb;
  v_source jsonb;
  v_context jsonb;
  v_execute jsonb;
  v_output jsonb;
  v_semantic jsonb;
  v_report jsonb;
  v_literal text;
  v_body jsonb;
  v_sha text;
  v_queue_request_id text;
  v_executor_mode text;
  v_executor_provider text;
  v_transport_kind text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTION_INVALID'
    );
  END IF;

  IF e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTION_NOT_COMPLETED',
      'canonical_status',e.status
    );
  END IF;

  SELECT required_steps,required_steps_pass,fail_count,blocked_count,judge_result
    INTO j
  FROM public.v_lf_operation_execution_judge
  WHERE execution_id=p_execution_id;

  IF j IS NULL
     OR j.judge_result IS DISTINCT FROM 'PASS'
     OR j.required_steps IS DISTINCT FROM 11
     OR j.required_steps_pass IS DISTINCT FROM j.required_steps
     OR coalesce(j.fail_count,0)<>0
     OR coalesce(j.blocked_count,0)<>0
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_JUDGE_NOT_CLEAN',
      'judge_result',coalesce(j.judge_result,'MISSING'),
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count
    );
  END IF;

  SELECT count(*),
         jsonb_object_agg(
           s.step_id,
           jsonb_build_object(
             'status',s.status,
             'evidence_ref',s.evidence_ref,
             'evidence_payload',s.evidence_payload
           )
           ORDER BY os.step_order
         )
    INTO v_step_count,v_steps
  FROM public.lf_operation_execution_steps s
  JOIN public.lf_operation_steps os
    ON os.operation_code='EJECUCION_PERFIL_LF'
   AND os.step_id=s.step_id
   AND os.active
  WHERE s.execution_id=p_execution_id
    AND s.status='STEP_PASS_WITH_EVIDENCE';

  IF v_step_count<>11 OR jsonb_typeof(v_steps)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_STEP_SET_INCOMPLETE',
      'clean_steps',v_step_count
    );
  END IF;

  v_router:=coalesce(
    v_steps#>'{router,evidence_payload,router_authorization_receipt}',
    v_steps#>'{router,evidence_payload,router_result}'
  );

  IF v_steps#>'{router,evidence_payload,router_authorization_receipt}' IS NOT NULL THEN
    v_router_kind:='CARRIED_AUTHORIZATION_RECEIPT';
  ELSE
    v_router_kind:='LEGACY_ROUTER_RESULT';
  END IF;

  v_scope:=v_steps#>'{input_validate,evidence_payload,scope_authority_packet}';
  v_source:=v_steps#>'{profile_source_read,evidence_payload}';
  v_context:=v_steps#>'{context_admission,evidence_payload}';
  v_execute:=v_steps#>'{execute_profile,evidence_payload}';
  v_output:=v_steps#>'{output_validate,evidence_payload}';
  v_semantic:=v_steps#>'{semantic_judge,evidence_payload}';
  v_report:=v_steps#>'{report_output,evidence_payload}';
  v_literal:=v_scope#>>'{authorized_requirements,0,statement}';

  IF jsonb_typeof(v_router)<>'object'
     OR (
       v_router_kind='CARRIED_AUTHORIZATION_RECEIPT'
       AND (
         v_router->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1'
         OR v_router->>'router' IS DISTINCT FROM 'ACT-0001'
         OR v_router->>'profile_code' IS DISTINCT FROM e.target_code
         OR v_router->>'action_code' IS DISTINCT FROM 'PROFILE_EXECUTION'
         OR v_router->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
         OR v_router->'profile_execution_allowed' IS DISTINCT FROM 'true'::jsonb
         OR v_router->'router_reentry_before_execution' IS DISTINCT FROM 'false'::jsonb
       )
     )
     OR v_router_kind='LEGACY_ROUTER_RESULT'
     OR jsonb_typeof(v_scope)<>'object'
     OR v_scope->>'packet_version' IS DISTINCT FROM 'LF_SCOPE_AUTHORITY_PACKET_V1'
     OR coalesce(v_scope->>'sha256','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_source)<>'object'
     OR coalesce(v_source->>'profile_source_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_context)<>'object'
     OR coalesce(v_context->>'context_receipt_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_execute)<>'object'
     OR jsonb_typeof(v_execute->'profile_output')<>'object'
     OR jsonb_typeof(v_output)<>'object'
     OR jsonb_typeof(v_semantic)<>'object'
     OR v_semantic#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
     OR jsonb_typeof(v_report)<>'object'
     OR coalesce(v_semantic#>>'{semantic_judge_result,verdict}','') NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
     OR v_report->>'result' IS DISTINCT FROM v_semantic#>>'{semantic_judge_result,verdict}'
     OR nullif(v_literal,'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_AUTHORITY_CHAIN_INCOMPLETE',
      'router_authority_kind',v_router_kind
    );
  END IF;

  v_queue_request_id:=nullif(btrim(coalesce(e.manifest->>'queue_request_id','')),'');
  v_executor_mode:=upper(nullif(btrim(coalesce(e.manifest->>'executor_mode','')),''));
  v_executor_provider:=nullif(btrim(coalesce(e.manifest->>'executor_provider','')),'');

  IF v_executor_mode IS NULL AND v_queue_request_id IS NOT NULL THEN
    v_executor_mode:='REMOTE_API';
  END IF;

  IF v_executor_mode IS NULL
     OR v_executor_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTOR_MODE_INVALID',
      'executor_mode',v_executor_mode
    );
  END IF;

  IF v_executor_mode='REMOTE_API' THEN
    IF v_queue_request_id IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','QUEUE_REQUEST_ID_REQUIRED_FOR_REMOTE_API'
      );
    END IF;
    v_transport_kind:='REMOTE_API_QUEUE';

  ELSIF v_executor_mode='GPT_NATIVE' THEN
    IF v_queue_request_id IS NOT NULL
       OR v_executor_provider IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
       OR nullif(btrim(coalesce(e.manifest->>'runtime_target','')),'') IS NOT NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','GPT_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE'
      );
    END IF;
    v_transport_kind:='NATIVE_CURRENT_CONTEXT';

  ELSIF v_executor_mode='CLAUDE_NATIVE' THEN
    IF v_queue_request_id IS NOT NULL
       OR v_executor_provider IS DISTINCT FROM 'ANTHROPIC_CLAUDE_NATIVE'
       OR nullif(btrim(coalesce(e.manifest->>'runtime_target','')),'') IS NOT NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','CLAUDE_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE'
      );
    END IF;
    v_transport_kind:='NATIVE_CURRENT_CONTEXT';
  END IF;

  IF e.manifest->>'input_sha256' IS NULL
     OR v_scope->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'profile_code' IS DISTINCT FROM e.target_code
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_IDENTITY_MISMATCH'
    );
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_PROFILE_RUNTIME_TERMINAL_AUTHORITY_RECEIPT_V1',
    'queue_request_id',v_queue_request_id,
    'canonical_execution_id',e.execution_id,
    'operation_code',e.operation_code,
    'profile_code',e.target_code,
    'executor_mode',v_executor_mode,
    'execution_transport',v_transport_kind,
    'executor_provider',v_executor_provider,
    'input_literal',v_literal,
    'input_literal_sha256',e.manifest->>'input_sha256',
    'router_authority_kind',v_router_kind,
    'router_authority_receipt',v_router,
    'scope_authority_packet',v_scope,
    'scope_authority_packet_sha256',
      v_steps#>>'{input_validate,evidence_payload,scope_authority_packet_sha256}',
    'profile_source_receipt',v_source,
    'context_receipt',jsonb_build_object(
      'ref',v_context->>'context_receipt_ref',
      'digest',v_context->>'context_receipt_digest',
      'server_validated',v_context->'server_validated'
    ),
    'raw_output_receipt',jsonb_build_object(
      'profile_output_sha256','sha256:'||encode(
        extensions.digest(
          convert_to((v_execute->'profile_output')::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      'execute_evidence_ref',v_steps#>>'{execute_profile,evidence_ref}'
    ),
    'validator_receipt',jsonb_build_object(
      'output_contract_result',v_output->>'output_contract_result',
      'deterministic_validation',v_output->'deterministic_validation',
      'evidence_ref',v_steps#>>'{output_validate,evidence_ref}'
    ),
    'semantic_judge_receipt',v_semantic,
    'report_output_receipt',v_report,
    'canonical_judge_readback',jsonb_build_object(
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count,
      'judge_result',j.judge_result
    ),
    'source_refs',jsonb_build_array(
      v_steps#>>'{router,evidence_ref}',
      v_steps#>>'{input_validate,evidence_ref}',
      v_steps#>>'{profile_source_read,evidence_ref}',
      v_steps#>>'{context_admission,evidence_ref}',
      v_steps#>>'{execute_profile,evidence_ref}',
      v_steps#>>'{output_validate,evidence_ref}',
      v_steps#>>'{semantic_judge,evidence_ref}',
      v_steps#>>'{report_output,evidence_ref}'
    ),
    'authority_rule','ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
  );

  v_sha:='sha256:'||encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','READY',
    'terminal_authority_receipt',
      v_body||jsonb_build_object('sha256',v_sha),
    'terminal_authority_receipt_sha256',v_sha
  );
END
$function$
;


-- Exact live function body lf_profile_native_bridge_record_report_v1, MD5 cafaaff15eb0751a9af0cfb67db3c30b.
-- Test calls require missing upstream dependencies; no fake Step80 PASS.
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(p_execution_id text, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_semantic public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_actor text;
  v_candidate text;
  v_scope text;
  v_semantic_receipt text;
  v_step jsonb;
  v_clean integer;
  v_terminal jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_INVALID');
  END IF;

  SELECT * INTO v_semantic
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_semantic.step_id IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_NOT_CLEAN');
  END IF;

  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';
  v_scope:=v_semantic.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}';
  v_semantic_receipt:=coalesce(v_semantic.evidence_payload->>'semantic_review_receipt_ref',v_semantic.evidence_payload->>'independent_semantic_receipt_ref');

  IF coalesce(v_candidate,'') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_scope,'') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_BINDING_INVALID');
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='report_output';

  IF v_existing IS NULL THEN
    IF e.status<>'IN_PROGRESS' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_ALREADY_CLOSED_WITHOUT_REPORT');
    END IF;
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'report_output',
      p_evidence_ref,
      jsonb_build_object(
        'result',v_semantic.evidence_payload#>>'{semantic_judge_result,verdict}',
        'execution_id',p_execution_id,
        'profile_code',e.target_code,
        'no_write_performed',true,
        'candidate_sha256',v_candidate,
        'scope_packet_sha256',v_scope,
        'semantic_review_receipt_ref',v_semantic_receipt,
        'independent_semantic_receipt_ref',case
          when v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW' then null
          else v_semantic_receipt end,
        'next_gate','RETURN_TO_ROUTER'
      ),
      v_actor
    );
    IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF v_clean<>11 OR e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN',
      'clean_step_count',v_clean,
      'execution_status',e.status
    );
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id);
  IF v_terminal->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_TERMINAL_RECEIPT_NOT_READY',
      'terminal_result',v_terminal
    );
  END IF;

  RETURN jsonb_build_object(
    'status','PROFILE_EXECUTION_COMPLETED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','report_output',
    'execution_status',e.status,
    'terminal_authority_receipt_sha256',v_terminal->>'terminal_authority_receipt_sha256',
    'next_gate','RETURN_TO_ROUTER'
  );
END
$function$
;

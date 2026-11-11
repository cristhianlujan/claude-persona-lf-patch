-- Synthetic isolated PG18 database only. Fixture setup, NOT manual production INSERT.
CREATE SCHEMA IF NOT EXISTS lf_ops;
CREATE SCHEMA IF NOT EXISTS programacion;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $roles$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text NOT NULL,target_code text NOT NULL,
 target_type text DEFAULT 'PERFIL',status text NOT NULL,manifest jsonb NOT NULL);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text,
 PRIMARY KEY(profile_code,operation_code));
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY,codigo text UNIQUE NOT NULL,categoria text NOT NULL DEFAULT 'SECURITY',
 titulo text NOT NULL DEFAULT 'Test rule',descripcion text NOT NULL DEFAULT 'Test baseline',
 estado text NOT NULL CHECK (estado IN ('CANDIDATO','VIGENTE')),
 valor_config jsonb NOT NULL DEFAULT '{}'::jsonb,
 origen text,created_by text,owner_name text
);
CREATE TABLE lf_ops.politicas_seguridad(
 security_policy_id integer PRIMARY KEY,
 policy_code text UNIQUE NOT NULL,status text NOT NULL,
 policy_config jsonb NOT NULL,parameter_provenance jsonb DEFAULT '{}'::jsonb);
CREATE TABLE public.lf_decisiones_gov(
 decision_number bigint PRIMARY KEY,id_decision text NOT NULL,
 estado_normalizado text NOT NULL,raw_payload jsonb NOT NULL);
INSERT INTO public.lf_decisiones_gov VALUES(
 101,'DEC-GOV-TEST','VIGENTE',
 '{"authority_class":"AUTOMATED_ALLOWED","source":"synthetic_test_approved","rule_code":"RULE-TEST-001"}'::jsonb);
CREATE TABLE public.lf_rule_promotion_v1(
 promotion_id text PRIMARY KEY DEFAULT 'PROM-TEST',
 rule_code text NOT NULL,
 request_execution_id text NOT NULL,
 requested_by_profile text NOT NULL,
 request_snapshot_sha256 text NOT NULL,
 status text NOT NULL DEFAULT 'PENDING'
 CHECK (status IN ('PENDING','APPROVED','REJECTED','APPLIED','STALE')),
 reason text,
 decided_by text,decided_at timestamptz,applied_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(p_asset_type text,p_code text)
RETURNS text LANGUAGE sql STABLE AS $sha$
 SELECT encode(extensions.digest(convert_to(
  (to_jsonb(r))::text,'UTF8'),'sha256'),'hex')
 FROM lf_ops.reglas r WHERE p_asset_type='REGLA' AND r.codigo=p_code
$sha$;
-- Isolated minimal CURRENTNESS_AUTHORITY dependencies. The checked function
-- fn_input_run_source_currentness_v1 is copied EXACTLY from live Supabase.
CREATE TABLE public.lf_capability_registry(
 capability_code text PRIMARY KEY,status text NOT NULL);
CREATE TABLE public.lf_capability_current(
 capability_code text PRIMARY KEY);
CREATE TABLE programacion.contratos(
 id integer PRIMARY KEY,version_id integer,contrato_codigo text,
 especificacion jsonb NOT NULL,fail_closed boolean NOT NULL,estado text NOT NULL);
CREATE TABLE programacion.input_readiness_runs(
 id bigint PRIMARY KEY,version_id integer,pantalla_id integer,
 status text,contract_version integer,contract_revision text,
 contract_snapshot_sha256 text,source_manifest jsonb,source_snapshot_sha256 text,
 invalidated_at timestamptz,scope jsonb,supersedes_run_id bigint);
CREATE FUNCTION programacion.fn_v09_sha256_jsonb(p_json jsonb)
RETURNS text LANGUAGE sql STABLE AS $finger$
 SELECT encode(extensions.digest(convert_to(p_json::text,'UTF8'),'sha256'),'hex')
$finger$;
CREATE FUNCTION programacion.fn_input_source_manifest_identity_v1(p_json jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $identity$ SELECT p_json $identity$;
CREATE FUNCTION programacion.fn_input_build_source_manifest(p_run_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $build$
 SELECT jsonb_build_array(jsonb_build_object(
    'kind','RULE','codigo',r.codigo,'estado',r.estado,
    'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r.codigo)))
 FROM lf_ops.reglas r WHERE r.codigo='RULE-TEST-001'
$build$;
-- Seed exactly one promotion target, and one supporting dependency.
INSERT INTO lf_ops.reglas(id,codigo,estado,owner_name,origen,created_by,valor_config)
VALUES
 (1,'RULE-TEST-001','CANDIDATO','LF_GOVERNANCE','DEC-GOV-TEST','ChatGPT',
  '{"source_decision_number":101,"security_policy_code":"SEC-AUTH","deny_by_default":true,"depends_on_rules":["RULE-DEPENDENCY-001"]}'::jsonb),
 (2,'RULE-DEPENDENCY-001','VIGENTE','LF_GOVERNANCE','DEC-GOV-TEST','ChatGPT',
  '{"source_decision_number":99}'::jsonb);
INSERT INTO lf_ops.politicas_seguridad(
 security_policy_id,policy_code,status,policy_config)
VALUES(1,'SEC-AUTH','VIGENTE',
 '{"deny_by_default":true,"server_side_enforcement":true,"cross_tenant_access":"DENY"}'::jsonb);
INSERT INTO public.lf_profile_write_authority_v1 VALUES
('PERFIL-PRODUCT-DIRECTOR-LF','PROMOCION_REGLA_LF','ACTIVE');
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_code,status,manifest)
VALUES('EXEC-PARENT-TEST-001','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF',
'IN_PROGRESS','{"read_only":true,"no_write":true,"no_promotion":true,
 "router_profile_handoff":{"scope":{"target_type":"REGLA",
 "resolution_status":"RESOLVED","target_hint":"RULE-TEST-001"},
 "router_authorization_receipt":{"profile_execution_allowed":true}}}'::jsonb);
INSERT INTO public.lf_operation_execution_steps VALUES(
 'EXEC-PARENT-TEST-001','input_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('input_governance',jsonb_build_object(
 'status','READY','scope_type','REGLA','scope_mode','ONE_CANONICAL_RULE',
 'rule_code','RULE-TEST-001','source_scope_validated',true,
 'rule_source_sha256',public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001'))));
-- This is explicitly a SYNTHETIC judge fixture, not a real independently
-- executed GPT-native judge. Source code must never claim otherwise.
INSERT INTO public.lf_operation_execution_steps VALUES(
 'EXEC-PARENT-TEST-001','semantic_judge','STEP_PASS_WITH_EVIDENCE',
 '{"semantic_judge_result":{"status":"PASS",
 "verdict":"PASS_REVIEWED_CURRENT_CONTEXT","unsupported_claims":[]},
 "test_only_synthetic":true}'::jsonb);
INSERT INTO public.lf_capability_registry VALUES('CURRENTNESS_AUTHORITY','ACTIVE');
INSERT INTO public.lf_capability_current VALUES('CURRENTNESS_AUTHORITY');
INSERT INTO programacion.contratos VALUES(
 1,1,'INPUT_READINESS_CONTRACT',
 '{"schema_version":1,"contract_revision":"TEST-1.0"}'::jsonb,true,'defined');
INSERT INTO programacion.input_readiness_runs(
 id,version_id,pantalla_id,status,contract_version,contract_revision,
 contract_snapshot_sha256,source_manifest,source_snapshot_sha256,scope)
SELECT 1101,1,101,'COMPLETED',1,'TEST-1.0',
 programacion.fn_v09_sha256_jsonb(jsonb_build_object(
 'id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
 'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)),
 programacion.fn_input_build_source_manifest(1101),
 programacion.fn_v09_sha256_jsonb(programacion.fn_input_build_source_manifest(1101)),
 '{}'::jsonb FROM programacion.contratos c WHERE c.id=1;

-- ACT-0001 four material probes, in an EPHEMERAL PG17 database only.
-- TEST CONTRACT:
-- T02: catalog creation / existing-target rejection (not a real skill factory).
-- T12: new type & action discoverable but CANDIDATE route not active.
-- T14: actual lf_router_downstream_authority_validate_v1 detects stale revisions/bindings.
-- PE1: actual live validator accepts negative intent with coherent authority receipt;
--      this demonstrates a confirmed security gap, NOT a repaired prewrite gate.
-- Read-only canonical function bodies are included verbatim. All other functions
-- are explicit sandbox stubs. Entire suite is transactionally rolled back.
\set ON_ERROR_STOP on
SET statement_timeout TO '30s';
BEGIN;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;

CREATE TABLE public.lf_activos(
 codigo_activo text PRIMARY KEY,
 tipo_activo text,
 estado_operativo text,
 archived_at timestamptz,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE public.lf_router_action_registry(
 asset_type text NOT NULL, action_code text NOT NULL,
 operation_code text NOT NULL, status text NOT NULL,
 requires_existing_target boolean NOT NULL DEFAULT true,
 requires_missing_target boolean NOT NULL DEFAULT false,
 write_allowed boolean NOT NULL DEFAULT false,
 PRIMARY KEY(asset_type,action_code)
);
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,
 operation_code text, target_type text, target_code text,
 target_repo text, target_path text, manifest jsonb,
 request_sha256 text
);
CREATE TABLE public.lf_operation_step_judge_bindings(
 operation_code text, step_order integer, step_id text,
 status text, judge_code text, required_evidence_keys jsonb,
 created_at timestamptz, updated_at timestamptz
);
CREATE TABLE public.act0001_sandbox_revision(
 operation_code text PRIMARY KEY, revision text NOT NULL
);
CREATE OR REPLACE FUNCTION public.lf_operation_revision_sha256_v1(p_operation_code text)
RETURNS text LANGUAGE sql STABLE AS $stub$
 SELECT revision FROM public.act0001_sandbox_revision
 WHERE operation_code = p_operation_code
$stub$;
-- Explicitly STUBBED: this is not production semantic resolution.
CREATE OR REPLACE FUNCTION public.lf_router_resolve_v1(
 p_request_text text, p_target_hint text DEFAULT NULL,
 p_action_hint text DEFAULT NULL, p_type_hint text DEFAULT NULL,
 p_consumer text DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE AS $stub$
 SELECT jsonb_build_object(
 'status','READY_TO_EXECUTE','downstream_execution_allowed',true,
 'router','ACT-0001','asset_type',p_type_hint,
 'action_code',p_action_hint,'operation_code','ACTUALIZACION_ADAPTER_LF',
 'contract_refs','[]'::jsonb,'policy_refs','[]'::jsonb,
 'required_policy_count',0,'resolved_policy_count',0,
 'operation_status','PRODUCCION_CONTROLADA',
 'operation_lifecycle_state','ACTIVE')
$stub$;

-- These TWO functions are current canonical source, not stubs.
\ir act0001_live_authority_source_snapshot_v1.sql

INSERT INTO public.lf_activos(codigo_activo,tipo_activo,estado_operativo,metadata)
VALUES('ROUTER_DOWNSTREAM_AUTHORITY','CAPABILITY','ACTIVO',
 jsonb_build_object('transversal_inventory',
 jsonb_build_object('consumers_known',
 jsonb_build_array('ACTUALIZACION_ADAPTER_LF'))));
INSERT INTO public.lf_router_action_registry(
asset_type,action_code,operation_code,status,write_allowed
) VALUES ('ADAPTER','ADAPTER_UPDATE','ACTUALIZACION_ADAPTER_LF','ACTIVE',true);
INSERT INTO public.act0001_sandbox_revision
VALUES ('ACTUALIZACION_ADAPTER_LF','revision-original');

-- T02 / T12: catalog semantics on actual table names and corresponding columns.
-- NOT tests of the full creation factory or production Router.
DO $test$
BEGIN
 INSERT INTO public.lf_router_action_registry
  (asset_type,action_code,operation_code,status,
   requires_existing_target,requires_missing_target,write_allowed)
 VALUES('SKILL','SKILL_CREATE','CREACION_SKILL_LF','ACTIVE',false,true,true);
 IF NOT EXISTS(
  SELECT 1 FROM public.lf_router_action_registry r
  WHERE r.asset_type='SKILL' AND r.action_code='SKILL_CREATE'
    AND r.status='ACTIVE' AND r.requires_missing_target
    AND r.write_allowed
    AND NOT EXISTS(SELECT 1 FROM public.lf_activos a
        WHERE a.codigo_activo='SKILL-SANDBOX-NEW')) THEN
   RAISE EXCEPTION 'FAIL_T02_CREATE_TARGET_ABSENT_NOT_ADMITTED';
 END IF;
 INSERT INTO public.lf_activos(codigo_activo,tipo_activo,estado_operativo)
 VALUES('SKILL-SANDBOX-NEW','SKILL','CANDIDATO');
 IF NOT EXISTS(SELECT 1 FROM public.lf_activos WHERE codigo_activo='SKILL-SANDBOX-NEW')
    OR EXISTS(
      SELECT 1 FROM public.lf_router_action_registry r
      WHERE r.asset_type='SKILL' AND r.action_code='SKILL_CREATE'
      AND r.requires_missing_target
      AND NOT EXISTS(SELECT 1 FROM public.lf_activos a WHERE a.codigo_activo='SKILL-SANDBOX-NEW')
    ) THEN
   RAISE EXCEPTION 'FAIL_T02_CREATE_NOT_PERSISTED_OR_DUPLICATE_NOT_STOPPED';
 END IF;
 RAISE NOTICE 'PASS_T02_CATALOG_CREATE_AND_DUPLICATE_BLOCK_SANDBOX_ONLY';
 INSERT INTO public.lf_activos(codigo_activo,tipo_activo,estado_operativo)
 VALUES('WIDGET-SANDBOX-NEW','WIDGET_EXPERIMENTAL','CANDIDATO');
 INSERT INTO public.lf_router_action_registry
  (asset_type,action_code,operation_code,status,
   requires_existing_target,requires_missing_target,write_allowed)
 VALUES('WIDGET_EXPERIMENTAL','WIDGET_CREATE','EXPERIMENTAL_CREATE','CANDIDATE',false,true,false);
 IF NOT EXISTS(SELECT 1 FROM public.lf_activos
      WHERE codigo_activo='WIDGET-SANDBOX-NEW' AND tipo_activo='WIDGET_EXPERIMENTAL')
    OR NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
      WHERE asset_type='WIDGET_EXPERIMENTAL' AND action_code='WIDGET_CREATE'
      AND status='CANDIDATE' AND NOT write_allowed)
    OR EXISTS(SELECT 1 FROM public.lf_router_action_registry
      WHERE asset_type='WIDGET_EXPERIMENTAL' AND status='ACTIVE') THEN
   RAISE EXCEPTION 'FAIL_T12_NEW_CAPABILITY_REGISTRATION_OR_AUTO_ACTIVATION';
 END IF;
 RAISE NOTICE 'PASS_T12_CATALOG_NEW_TYPE_DISCOVERABLE_NOT_ACTIVE_SANDBOX_ONLY';
END
$test$;

-- An internally consistent V1 receipt is constructed from the actual fields
-- and fingerprint formula. The ORIGINAL user request is expressly negative.
DO $test$
DECLARE
 v_core jsonb; v_binding_sha text; v_fingerprint text; v_receipt jsonb;
 v_reply jsonb; v_negative text;
BEGIN
 v_negative := 'analiza si conviene crear una regla nueva, no la crees todavia';
 v_binding_sha := encode(extensions.digest(convert_to(
    coalesce((SELECT jsonb_agg(
      to_jsonb(b)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
      ORDER BY b.step_order,b.step_id)
     FROM public.lf_operation_step_judge_bindings b
     WHERE b.operation_code='ACTUALIZACION_ADAPTER_LF'
       AND b.status IN ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')),'[]'::jsonb)::text,
    'UTF8'),'sha256'),'hex');
 v_core := jsonb_build_object(
    'schema_version','LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1',
    'execution_id','EXEC-PE1-SANDBOX-NEGATIVE',
    'operation_code','ACTUALIZACION_ADAPTER_LF',
    'target_type','ADAPTER','target_code','ADAPTER-SANDBOX-1',
    'target_repo',NULL,'target_path',NULL,
    'action_code','ADAPTER_UPDATE',
    'router','ACT-0001','producer_ref','public.lf_router_resolve_v1',
    'authority_ref','ROUTER_DOWNSTREAM_AUTHORITY',
    'operation_revision_sha256','revision-original',
    'step_binding_sha256',v_binding_sha,
    'contract_refs','[]'::jsonb,'policy_refs','[]'::jsonb,
    'required_policy_count',0,'resolved_policy_count',0,
    'operation_status','PRODUCCION_CONTROLADA',
    'operation_lifecycle_state','ACTIVE',
    'issued_at','2026-10-16T12:00:00.000000Z');
 v_fingerprint := encode(extensions.digest(
   convert_to(v_core::text,'UTF8'),'sha256'),'hex');
 v_receipt := v_core || jsonb_build_object('fingerprint_sha256',v_fingerprint);
 INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,manifest,request_sha256
 ) VALUES (
 'EXEC-PE1-SANDBOX-NEGATIVE','ACTUALIZACION_ADAPTER_LF','ADAPTER',
 'ADAPTER-SANDBOX-1',jsonb_build_object('router_authority_receipt',v_receipt),
 encode(extensions.digest(convert_to(v_negative,'UTF8'),'sha256'),'hex')
 );
 v_reply := public.lf_router_downstream_authority_validate_v1('EXEC-PE1-SANDBOX-NEGATIVE');
 IF v_reply->>'code' IS DISTINCT FROM 'ROUTER_DOWNSTREAM_AUTHORITY_VALID'
   OR (v_reply->>'valid')::boolean IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'FAIL_PE1_BASELINE_FIXTURE:%',v_reply;
 END IF;
 -- This PASS means the *vulnerable baseline* approved a NEGATED intent.
 RAISE NOTICE 'PASS_PE1_BASELINE_GAP_REPRODUCED_NOT_PROTECTED';
 -- T14: an actual canonical validator rejects a stale operation revision.
 UPDATE public.act0001_sandbox_revision SET revision='revision-updated'
 WHERE operation_code='ACTUALIZACION_ADAPTER_LF';
 v_reply := public.lf_router_downstream_authority_validate_v1('EXEC-PE1-SANDBOX-NEGATIVE');
 IF v_reply->>'code' IS DISTINCT FROM 'ROUTER_AUTHORITY_REVISION_STALE'
    OR (v_reply->>'valid')::boolean IS DISTINCT FROM FALSE THEN
  RAISE EXCEPTION 'FAIL_T14_STALE_REVISION_NOT_REJECTED:%',v_reply;
 END IF;
 RAISE NOTICE 'PASS_T14_REAL_VALIDATOR_REJECTS_STALE_REVISION_WITH_STUBBED_PRODUCERS';
 UPDATE public.act0001_sandbox_revision SET revision='revision-original'
 WHERE operation_code='ACTUALIZACION_ADAPTER_LF';
 v_reply := public.lf_router_downstream_authority_validate_v1('EXEC-PE1-SANDBOX-NEGATIVE');
 IF v_reply->>'code' IS DISTINCT FROM 'ROUTER_DOWNSTREAM_AUTHORITY_VALID' THEN
  RAISE EXCEPTION 'FAIL_T14_RESTORED_REVISION_NOT_VALID:%',v_reply;
 END IF;
 RAISE NOTICE 'PASS_T14_REVISION_RESTORED';
 INSERT INTO public.lf_operation_step_judge_bindings(
   operation_code,step_order,step_id,status,judge_code
 ) VALUES('ACTUALIZACION_ADAPTER_LF',60,'pre_write_execution_binding_gate',
 'ACTIVE_ENFORCEMENT','JUDGE-SANDBOX');
 v_reply := public.lf_router_downstream_authority_validate_v1('EXEC-PE1-SANDBOX-NEGATIVE');
 IF v_reply->>'code' IS DISTINCT FROM 'ROUTER_AUTHORITY_STEP_BINDING_STALE'
    OR (v_reply->>'valid')::boolean IS DISTINCT FROM FALSE THEN
  RAISE EXCEPTION 'FAIL_T14_STEP_BINDING_CHANGE_NOT_REJECTED:%',v_reply;
 END IF;
 RAISE NOTICE 'PASS_T14_REAL_VALIDATOR_REJECTS_CHANGED_STEP_BINDING';
END
$test$;

ROLLBACK;
DO $post$
BEGIN
 IF to_regclass('public.lf_operation_execution') IS NOT NULL OR
    to_regclass('public.lf_router_action_registry') IS NOT NULL OR
    to_regclass('public.act0001_sandbox_revision') IS NOT NULL OR
    to_regclass('public.lf_activos') IS NOT NULL THEN
  RAISE EXCEPTION 'FAIL_ACT0001_MATERIAL_ROLLBACK_RESIDUE';
 END IF;
 RAISE NOTICE 'PASS_ACT0001_MATERIAL_PROBES_ROLLBACK_ZERO_RESIDUE';
END
$post$;

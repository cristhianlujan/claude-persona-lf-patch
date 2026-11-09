-- ISOLATED PG17 ONLY. Synthetic authority for positive and negative control tests.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role')
THEN CREATE ROLE service_role NOLOGIN; END IF; END $$;

CREATE TABLE public.lf_skill_catalog_v1(
 skill_code text,required_operation text,handler_fn text,opener_fn text,
 effect text,status text,child_caller jsonb);
CREATE TABLE public.lf_router_governed_callers(
 caller_code text,operation_code text,status text);
CREATE TABLE public.lf_activos(
 codigo_activo text,tipo_activo text,archived_at timestamptz,metadata jsonb);
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY, operation_code text,target_type text,
 target_code text,status text DEFAULT 'IN_PROGRESS',manifest jsonb,
 request_sha256 text,target_repo text,target_path text,
 idempotency_key text,created_by_execution_id text);
CREATE TABLE public.lf_skill_invocation_v1(
 skill_run_id text,skill_code text,parent_execution_id text,
 child_execution_id text,profile_code text,status text,input_sha256 text);
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text);
CREATE TABLE public.lf_operation_contracts(
 operation_code text,status text,contract_code text,contract_sha text);
CREATE TABLE public.lf_operation_steps(
 operation_code text,step_id text,step_order integer,active boolean);
CREATE TABLE public.lf_operation_step_judge_bindings(
 operation_code text,step_id text,step_order integer,status text,
 clean_result_value text,judge_code text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_order integer,step_id text,status text,evidence_ref text,
 evidence_payload jsonb,notes text,created_by_execution_id text);

CREATE FUNCTION public.lf_skill_child_caller_manifest_v1(p_skill text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object(
   'governed_caller_method','GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1',
   'caller_repository','cristhianlujan/claude-persona-lf-patch',
   'caller_workflow_ref','cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main');
$$;
CREATE FUNCTION public.lf_router_governed_caller_route_v1(p_caller jsonb,p_target text,p_path text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT CASE WHEN EXISTS(SELECT 1 FROM public.lf_router_governed_callers
     WHERE caller_code='CALLER-GHA-NATIVE-SKILL-UPDATE-V1' AND status='ACTIVE')
 THEN jsonb_build_object('status','ROUTER_REDERIVED',
   'router_result',jsonb_build_object('status','READY_TO_EXECUTE',
     'operation_code','ACTUALIZACION_SKILL_LF','action_code','SKILL_UPDATE'),
   'semantic_receipt_sha256',repeat('c',64),
   'downstream_execution_allowed',false,
   'caller_code','CALLER-GHA-NATIVE-SKILL-UPDATE-V1')
 ELSE jsonb_build_object('status','BLOCKED',
   'blocking_code','BLOCK_GOVERNED_CALLER_NOT_REGISTERED') END;
$$;
CREATE FUNCTION public.fn_lf_operation_reserve_execution_v1(
 p_execution_id text,p_operation_code text,p_target_type text,p_target_code text,
 p_idempotency_key text,p_request_sha256 text,p_actor_execution_id text,
 p_target_repo text DEFAULT NULL,p_target_path text DEFAULT NULL,p_manifest jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,
   target_code,status,manifest,request_sha256,target_repo,target_path,
   idempotency_key,created_by_execution_id)
 VALUES(p_execution_id,p_operation_code,p_target_type,p_target_code,
  'IN_PROGRESS',p_manifest,p_request_sha256,p_target_repo,p_target_path,
   p_idempotency_key,p_actor_execution_id);
 RETURN jsonb_build_object('result','RESERVED_NEW_EXECUTION',
   'execution_id',p_execution_id);
END $$;

INSERT INTO public.lf_skill_catalog_v1 VALUES(
 'SKILL_UPDATE_APPLY','ACTUALIZACION_SKILL_LF',
 'lf_skill_h_skill_update_propose_v1','lf_skill_o_skill_update_v1','WRITE_GOVERNED','DRAFT',
 jsonb_build_object('method','GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1'));
INSERT INTO public.lf_router_governed_callers VALUES(
 'CALLER-GHA-NATIVE-SKILL-UPDATE-V1','ACTUALIZACION_SKILL_LF','DISABLED');
INSERT INTO public.lf_profile_write_authority_v1 VALUES(
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','ACTUALIZACION_SKILL_LF','ACTIVE');
INSERT INTO public.lf_activos VALUES('ACT-0045','SKILL',NULL,
 jsonb_build_object('historical_source','Drive legacy; no GitHub binding'));
INSERT INTO public.lf_operation_contracts VALUES(
 'ACTUALIZACION_SKILL_LF','ACTIVE_ENFORCEMENT',
 'CONTRACT-ACTUALIZACION-SKILL-LF-v0.1',NULL);
INSERT INTO public.lf_operation_steps VALUES(
 'ACTUALIZACION_SKILL_LF','init_execution',0,true);
INSERT INTO public.lf_operation_step_judge_bindings VALUES(
 'ACTUALIZACION_SKILL_LF','init_execution',0,'ACTIVE_ENFORCEMENT',
 'STEP_PASS_WITH_EVIDENCE','JUDGE-ACTUALIZACION-SKILL-LF-v0.1');
INSERT INTO public.lf_operation_execution VALUES(
 'EXEC-PROFILE-GATE2-FIXTURE','EJECUCION_PERFIL_LF','PERFIL',
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS',
 jsonb_build_object('read_only',true,'no_write',true,
 'router_profile_handoff',jsonb_build_object('router_authorization_receipt',
   jsonb_build_object('profile_execution_allowed',true))),
 repeat('a',64),NULL,NULL,NULL,'FIXTURE');

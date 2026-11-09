-- isolated PostgreSQL 17 only; synthetic parent, skill invocation, and core recorder.
-- This tests the new OIDC-bound adapter, not the production core's own tests.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;

CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text NOT NULL,target_type text NOT NULL,
 target_code text NOT NULL,status text NOT NULL DEFAULT 'IN_PROGRESS',
 manifest jsonb NOT NULL DEFAULT '{}'::jsonb,request_sha256 text,
 created_by_execution_id text,target_repo text,target_path text);
CREATE TABLE public.lf_skill_catalog_v1(
 skill_code text,required_operation text,effect text,status text);
CREATE TABLE public.lf_router_governed_callers(
 caller_code text,operation_code text,status text,caller_method text,
 repository text,workflow_ref text);
CREATE TABLE public.lf_skill_invocation_v1(
 skill_run_id text,skill_code text,parent_execution_id text,
 child_execution_id text,profile_code text,status text);
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text);
CREATE TABLE public.lf_operation_steps(
 operation_code text,step_id text,step_order integer,active boolean);
CREATE TABLE public.lf_operation_step_judge_bindings(
 operation_code text,step_id text,step_order integer,status text,
 clean_result_value text);
CREATE TABLE public.lf_operation_step_contracts(
 operation_code text,step_id text,step_order integer,status text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,step_order integer,status text,
 evidence_ref text,evidence_payload jsonb);

-- Synthetic core verifies sequencing, rather than granting blanket PASS to
-- out-of-order attempts; production uses canonical core+jude and more checks.
CREATE FUNCTION public.lf_record_operation_step_core_v1(
 p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,
 p_actor_execution_id text,p_expected_operation_code text,p_expected_target_type text,
 p_contract_status text,p_binding_status text,p_judge_status text,p_trust_validation jsonb,
 p_close_on_report_output boolean,p_recorder_name text
) RETURNS jsonb LANGUAGE plpgsql AS $core$
DECLARE v_step public.lf_operation_steps%ROWTYPE;v_previous integer;
BEGIN
 IF p_trust_validation->>'valid'<>'true'
   OR p_trust_validation->>'source'<>'OIDC_EDGE_EXACT_GITHUB_MAIN_AND_BLOB'
   OR p_trust_validation->'server_assertions' <> '[]'::jsonb
   OR p_trust_validation->'server_hard_fails' <> '[]'::jsonb
 THEN RETURN jsonb_build_object('outcome','BLOCKED','code','SYNTHETIC_CORE_TRUST_DENIED'); END IF;
 SELECT * INTO v_step FROM public.lf_operation_steps
  WHERE operation_code=p_expected_operation_code AND step_id=p_step_id;
 SELECT COUNT(*) INTO v_previous FROM public.lf_operation_steps s
  WHERE s.operation_code=p_expected_operation_code AND s.step_order<v_step.step_order
    AND NOT EXISTS(
      SELECT 1 FROM public.lf_operation_execution_steps e
      WHERE e.execution_id=p_execution_id AND e.step_id=s.step_id
        AND e.status='STEP_PASS_WITH_EVIDENCE');
 IF v_previous>0 THEN
  RETURN jsonb_build_object('outcome','BLOCKED','code','SYNTHETIC_CORE_PREDECESSOR_MISSING'); END IF;
 IF EXISTS(SELECT 1 FROM public.lf_operation_execution_steps e
   WHERE e.execution_id=p_execution_id AND e.step_id=p_step_id) THEN
  RETURN jsonb_build_object('outcome','BLOCKED','code','SYNTHETIC_CORE_DUPLICATE'); END IF;
 INSERT INTO public.lf_operation_execution_steps VALUES(
 p_execution_id,p_step_id,v_step.step_order,'STEP_PASS_WITH_EVIDENCE',
 p_evidence_ref,p_evidence_payload);
 RETURN jsonb_build_object('outcome','STEP_RECORDED','status','STEP_PASS_WITH_EVIDENCE',
  'step_id',p_step_id,'next_gate','NEXT_STEP');
END
$core$;

INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,manifest,request_sha256)
VALUES(
 'EXEC-PROFILE-GATE2-8DC96C01CF8C81DEEAB067DA','EJECUCION_PERFIL_LF','PERFIL',
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS',
 jsonb_build_object('read_only',true,'no_write',true,'no_promotion',true,
 'router_profile_handoff',jsonb_build_object('router_authorization_receipt',
    jsonb_build_object('profile_execution_allowed',true))),
 repeat('f',64));
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,manifest,request_sha256,
 created_by_execution_id,target_repo,target_path)
VALUES(
 'EXEC-SKILL-49797550002EE84C','ACTUALIZACION_SKILL_LF','SKILL',
 'ACT-0045','IN_PROGRESS',
 jsonb_build_object(
  'profile_handoff',jsonb_build_object(
    'source_execution_id','EXEC-PROFILE-GATE2-8DC96C01CF8C81DEEAB067DA',
    'skill_run_id','RUN-49797550002EE84C709A'),
  'router_governed_caller_code','CALLER-GHA-NATIVE-SKILL-UPDATE-V1',
  'router_semantic_receipt_sha256',repeat('c',64),
  'initial_main_revision',repeat('a',40),
  'initial_target_blob_sha',repeat('b',40),
  'owner_provenance',jsonb_build_object(
    'readme_blob_sha',repeat('d',40),
    'canonical_root_path','skills/profile_creator')),
 repeat('f',64),
 'EXEC-PROFILE-GATE2-8DC96C01CF8C81DEEAB067DA',
 'cristhianlujan/claude-persona-lf-patch',
 'skills/profile_creator/validators/compare_s26_profile_evolution_v1.py');
INSERT INTO public.lf_skill_catalog_v1 VALUES(
 'SKILL_UPDATE_APPLY','ACTUALIZACION_SKILL_LF','WRITE_GOVERNED','READY');
INSERT INTO public.lf_router_governed_callers VALUES(
 'CALLER-GHA-NATIVE-SKILL-UPDATE-V1','ACTUALIZACION_SKILL_LF','ACTIVE',
 'GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1',
 'cristhianlujan/claude-persona-lf-patch',
 'cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/main');
INSERT INTO public.lf_skill_invocation_v1 VALUES(
 'RUN-49797550002EE84C709A','SKILL_UPDATE_APPLY',
 'EXEC-PROFILE-GATE2-8DC96C01CF8C81DEEAB067DA',
 'EXEC-SKILL-49797550002EE84C',
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','COMPLETED');
INSERT INTO public.lf_profile_write_authority_v1 VALUES(
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','ACTUALIZACION_SKILL_LF','ACTIVE');

INSERT INTO public.lf_operation_steps VALUES
 ('ACTUALIZACION_SKILL_LF','init_execution',0,true),
 ('ACTUALIZACION_SKILL_LF','router',10,true),
 ('ACTUALIZACION_SKILL_LF','skill_resolve',20,true),
 ('ACTUALIZACION_SKILL_LF','baseline_read',30,true),
 ('ACTUALIZACION_SKILL_LF','change_scope',40,true),
 ('ACTUALIZACION_SKILL_LF','regression_plan',50,true),
 ('ACTUALIZACION_SKILL_LF','pre_write_execution_binding_gate',60,true);
INSERT INTO public.lf_operation_step_judge_bindings
 SELECT operation_code,step_id,step_order,'ACTIVE_ENFORCEMENT','STEP_PASS_WITH_EVIDENCE'
 FROM public.lf_operation_steps;
INSERT INTO public.lf_operation_step_contracts
 SELECT operation_code,step_id,step_order,'ACTIVE_ENFORCEMENT'
 FROM public.lf_operation_steps;
INSERT INTO public.lf_operation_execution_steps VALUES(
 'EXEC-SKILL-49797550002EE84C','init_execution',0,
 'STEP_PASS_WITH_EVIDENCE','supabase://real-child-init','{}'::jsonb);

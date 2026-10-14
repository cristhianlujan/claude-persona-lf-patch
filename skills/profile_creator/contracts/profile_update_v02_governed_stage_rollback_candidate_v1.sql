-- PE10 v0.2 GOVERNED STAGING REHEARSAL ONLY. NOT A DEPLOYABLE MIGRATION.
-- This script ALWAYS ROLLBACKS. It does not change operation v0.1, activate
-- a step, bind an active judge, or supersede the current PASS policy.
-- Execute only against isolated PostgreSQL, then promote a separately reviewed
-- migration via Train. Never substitute an unrelated execution as owner.
-- The session MUST bind an authorized ACTUALIZACION_PERFIL_LF IN_PROGRESS
-- execution using: SELECT set_config('lf.pe10_governed_actor_execution_id',
-- '<real actor execution id>', false);
-- IMPORTANT CURRENT BLOCKER: the live OIDC profile_update_init_v1 caller
-- forwards only profile asset identity and research baseline. Its downstream
-- initialize_profile_update_v1 builds the manifest without governance_scope,
-- governance_target or governance_pr. Thus it CANNOT currently produce an
-- eligible PE10 v0.2 governance author; do not trigger a bogus profile update.
-- The runtime-update begin route is also hard-bound to EJECUCION_PERFIL_LF.
-- The human governance owner for PE10 v0.2 is SUPER_ADMIN. In software
-- governance the corresponding role is SUPER_ADMIN_GOVERNANCE, authority
-- ref contract://LF_GOVERNANCE_SUPER_ADMIN_V1 (currently CANDIDATE_READ_ONLY).
-- This owner designation is not a human decision request nor proof of
-- authenticated execution. The trusted migration lane must still admit writes.
-- created_by_execution_id is technical provenance, not the human author.
-- Do not use the product B2B_ADMIN_LF role for software governance.
-- No historical in-progress execution is automatically eligible.
-- A separately admitted, scope-bound governance bootstrap must issue an
-- ACTUALIZACION_PERFIL_LF operation execution with these immutable fields:
-- governance_scope=PE10_V02_GOVERNED_REGISTRATION,
-- governance_target=ACTUALIZACION_PERFIL_LF, governance_pr=2619,
-- governance_owner_role=SUPER_ADMIN.
-- Reuse the canonical operation reservation/bootstrap under Train authority;
-- do NOT synthesize the actor through session GUC or a manual INSERT.
-- The GUC below merely selects an already-authorized row for rehearsal.
-- Until a trusted bootstrap receipt exists, this file is NOT executable
-- against real LF authority and must remain candidate/rollback-only.
BEGIN;
DO $pe10_stage$
DECLARE
  v_op constant text := 'ACTUALIZACION_PERFIL_LF';
  v_actor text := nullif(current_setting('lf.pe10_governed_actor_execution_id',true),'');
  v_policy jsonb;
  v_update jsonb;
  v_nochange jsonb;
  v_prefix jsonb;
  v_digest text;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id=v_actor AND operation_code=v_op AND status='IN_PROGRESS'
      AND manifest->>'governance_scope'='PE10_V02_GOVERNED_REGISTRATION'
      AND manifest->>'governance_target'=v_op
      AND manifest->>'governance_pr'='2619'
      AND manifest->>'governance_owner_role'='SUPER_ADMIN'
  ) THEN RAISE EXCEPTION 'PE10_V02_GOVERNED_ACTOR_REQUIRED'; END IF;
  IF (SELECT version FROM public.lf_operation_registry WHERE operation_code=v_op)
       IS DISTINCT FROM 'v0.1'
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code=v_op AND active)=15 IS NOT TRUE
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1' AND status='ACTIVE')<>1
  THEN RAISE EXCEPTION 'PE10_V02_STAGE_AUTHORITY_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_operation_steps WHERE operation_code=v_op
                AND (step_id IN ('method_selection','evolution_decision') OR step_order IN (35,37)))
    OR EXISTS (SELECT 1 FROM public.lf_policy_versions
               WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate')
  THEN RAISE EXCEPTION 'PE10_V02_STAGE_ALREADY_PRESENT'; END IF;
  IF to_regprocedure('public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)') IS NULL
      OR to_regprocedure('public.lf_profile_update_effective_route_v1(text)') IS NULL
      OR to_regprocedure('public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PE10_V02_STAGE_READONLY_HELPERS_NOT_INSTALLED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_judges
      WHERE operation_code=v_op AND status='ACTIVE_ENFORCEMENT') THEN
    RAISE EXCEPTION 'PE10_V02_STAGE_BASELINE_JUDGE_MISSING';
  END IF;

  INSERT INTO public.lf_operation_steps
    (operation_code,step_order,execution_order,step_id,required,active,evidence_required,source_path,created_by_execution_id)
  VALUES
    (v_op,35,35,'method_selection',true,false,
     'profile_slug; source_head_sha; profile_assessment_receipt_id; profile_assessment_sha256; selector_version; selected_methods; method_execution_permitted',
     'public.lf_operation_step_contracts/ACTUALIZACION_PERFIL_LF/method_selection',v_actor),
    (v_op,37,37,'evolution_decision',true,false,
     'profile_slug; source_head_sha; profile_assessment_receipt_id; profile_assessment_sha256; decision; evolution_mode; decision_evidence_ref; github_write_permitted',
     'public.lf_operation_step_contracts/ACTUALIZACION_PERFIL_LF/evolution_decision',v_actor);

  -- Exact UTF-8 source SHA-256 (verified from GitHub candidate source blob
  -- 6565ce15ea00297dc54c80014bbcc3723d7dc646):
  -- 7eb8ad1a5549c63a8f5c6de43b18cc966c9f62085313aaa57248a39eb3dfdeac
  -- Train must independently reread and verify the exact candidate source.
  -- One shared guard source, two distinct step-specific judge contracts.
  INSERT INTO public.lf_operation_judges
    (operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id)
  VALUES
    (v_op,'JUDGE-PE10-V02-METHOD-SELECTION',
     'skills/profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql',
     '7eb8ad1a5549c63a8f5c6de43b18cc966c9f62085313aaa57248a39eb3dfdeac',
     '["verified_assessment","qualified_method_receipts_or_reasoned_empty","current_selector","method_execution_permitted_false"]'::jsonb,
     '["missing_receipt","stale_selector","unqualified_method","caller_method_execution"]'::jsonb,
     '{"pass":"STEP_PASS_WITH_EVIDENCE","blocked":"BLOCKED_STEP_NOT_CLEAN","return":"RETURN_TO_ROUTER"}'::jsonb,
     'CANDIDATO_READ_ONLY',v_actor),
    (v_op,'JUDGE-PE10-V02-EVOLUTION-DECISION',
     'skills/profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql',
     '7eb8ad1a5549c63a8f5c6de43b18cc966c9f62085313aaa57248a39eb3dfdeac',
     '["verified_assessment","clean_method_selection","typed_decision_mode","frozen_route_consistency"]'::jsonb,
     '["unverified_source","unrecorded_method_selection","route_mismatch","unsupported_decision"]'::jsonb,
     '{"pass":"STEP_PASS_WITH_EVIDENCE","blocked":"BLOCKED_STEP_NOT_CLEAN","return":"RETURN_TO_ROUTER"}'::jsonb,
     'CANDIDATO_READ_ONLY',v_actor);

  INSERT INTO public.lf_operation_step_contracts
    (operation_code,step_id,step_order,execution_order,contract_code,purpose,
     input_required,resolver_ref,output_payload,pass_condition,block_condition,
     blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
     status,created_by_execution_id)
  VALUES
    (v_op,'method_selection',35,35,'CONTRACT-PE10-V02-METHOD-SELECTION',
     'Qualify additional methods from verified assessment; do not execute selected methods.',
     '["profile_assessment_receipt_id","selector_version","selected_methods"]'::jsonb,
     'public.lf_profile_update_evolution_step_guard_v1',
     '["selection_decision","method_qualification_receipts"]'::jsonb,
     '{"guard_result":"NULL_AND_REAL_JUDGE_PASS"}'::jsonb,
     '{"guard_result":"NON_NULL"}'::jsonb,
     'EVOLUTION_METHOD_SELECTION_NOT_ADMITTED','JUDGE-PE10-V02-METHOD-SELECTION',
     '["profile_slug","source_head_sha","profile_assessment_receipt_id","profile_assessment_sha256","selector_version","selected_methods","method_execution_permitted"]'::jsonb,
     'evolution_decision','method_selection','CANDIDATE',v_actor),
    (v_op,'evolution_decision',37,37,'CONTRACT-PE10-V02-EVOLUTION-DECISION',
     'Bind a verified UPDATE or NO_CHANGE decision to the immutable route; evidence-pending remains blocked.',
     '["profile_assessment_receipt_id","decision","evolution_mode"]'::jsonb,
     'public.lf_profile_update_evolution_step_guard_v1',
     '["decision","evolution_mode","route"]'::jsonb,
     '{"guard_result":"NULL_AND_REAL_JUDGE_PASS"}'::jsonb,
     '{"guard_result":"NON_NULL"}'::jsonb,
     'EVOLUTION_DECISION_NOT_ADMITTED','JUDGE-PE10-V02-EVOLUTION-DECISION',
     '["profile_slug","source_head_sha","profile_assessment_receipt_id","profile_assessment_sha256","decision","evolution_mode","decision_evidence_ref","github_write_permitted"]'::jsonb,
     NULL,'method_selection','CANDIDATE',v_actor);

  INSERT INTO public.lf_operation_step_judge_bindings
    (operation_code,step_order,step_id,judge_code,clean_result_value,
     blocked_result_value,return_result_value,required_evidence_keys,status,created_by_execution_id)
  SELECT c.operation_code,c.step_order,c.step_id,c.mini_judge_code,
         'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
         c.required_evidence_keys,'CANDIDATE',v_actor
  FROM public.lf_operation_step_contracts c
  WHERE c.operation_code=v_op AND c.step_id IN ('method_selection','evolution_decision');

  SELECT jsonb_agg(to_jsonb(s.step_id) ORDER BY s.execution_order)
    INTO v_update FROM public.lf_operation_steps s
   WHERE s.operation_code=v_op AND (s.active OR s.step_id IN ('method_selection','evolution_decision'));
  v_nochange := '["init_execution","router","profile_resolve","baseline_read","method_selection","evolution_decision","deterministic_validation","semantic_judge","close","report_output"]'::jsonb;
  SELECT jsonb_agg(x.value ORDER BY x.ordinality) INTO v_prefix
    FROM jsonb_array_elements(v_update) WITH ORDINALITY x(value,ordinality)
   WHERE x.ordinality<=6;
  IF jsonb_array_length(v_update)<>17 OR jsonb_array_length(v_nochange)<>10
     OR v_prefix IS DISTINCT FROM '["init_execution","router","profile_resolve","baseline_read","method_selection","evolution_decision"]'::jsonb
  THEN RAISE EXCEPTION 'PE10_V02_STAGE_ORDER_INVARIANT_FAILED'; END IF;
  SELECT policy_payload INTO v_policy FROM public.lf_policy_versions
   WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1' AND status='ACTIVE';
  v_policy:=v_policy||jsonb_build_object(
    'required_steps',v_update,
    'required_steps_before_decision',v_prefix,
    'required_steps_by_outcome',jsonb_build_object('UPDATE',v_update,'NO_CHANGE',v_nochange),
    'proposed_operation_version','v0.2','activation_authorized',false,
    'governance_owner_role','SUPER_ADMIN',
    'governance_authority_domain','LF_GOVERNANCE',
    'governance_reviewer_role','SUPER_ADMIN_GOVERNANCE',
    'governance_authority_ref','contract://LF_GOVERNANCE_SUPER_ADMIN_V1',
    'governance_authority_binding','OWNER_ROLE_ONLY_NOT_HUMAN_DECISION');
  v_digest:=encode(extensions.digest(convert_to(v_policy::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_policy_versions
    (policy_code,policy_version,policy_payload,policy_sha,status,source_ref,created_by_execution_id)
  VALUES ('POL-PROFILE-UPDATE-PASS','v1.4-evolved-routing-candidate',v_policy,v_digest,
    'CANDIDATE','skills/profile_creator/contracts/profile_update_evolved_routing_candidate_v1.json',v_actor);

  IF (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code=v_op AND active)<>15
     OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code=v_op AND NOT active
         AND step_id IN ('method_selection','evolution_decision'))<>2
     OR (SELECT count(*) FROM public.lf_operation_judges WHERE operation_code=v_op
         AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION')
         AND status='CANDIDATO_READ_ONLY'
         AND judge_sha='7eb8ad1a5549c63a8f5c6de43b18cc966c9f62085313aaa57248a39eb3dfdeac')<>2
     OR (SELECT count(*) FROM public.lf_operation_step_contracts WHERE operation_code=v_op
         AND step_id IN ('method_selection','evolution_decision') AND status='CANDIDATE')<>2
     OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code=v_op
         AND step_id IN ('method_selection','evolution_decision') AND status='CANDIDATE')<>2
  THEN RAISE EXCEPTION 'PE10_V02_STAGE_READBACK_FAILED'; END IF;
END
$pe10_stage$;
SELECT 'PE10_V02_STAGING_REHEARSAL_ASSERTIONS_PASS' AS check_result;
ROLLBACK;
-- No durable changes. Promotion is a separate governed Train migration.

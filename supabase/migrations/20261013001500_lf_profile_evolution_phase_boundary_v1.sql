-- LF Profile Evolution: split the accepted first code evolution from expert certification.
-- Scope: PE10E/PE10 unit metadata + CANDIDATE policy + one EKB row.
-- No checkpoint transition, no expert admission, no runtime activation, no version cutover.
BEGIN;
DO $phase$
DECLARE
 v_pe10e_id bigint;
 v_pe10_id bigint;
 v_meta jsonb;
 v_pe10_meta jsonb;
 v_spec jsonb;
 v_receipts jsonb;
 v_first jsonb;
 v_phase jsonb;
 v_new jsonb;
 v_boot jsonb;
BEGIN
 IF (SELECT count(*) FROM public.lf_policy_versions
     WHERE policy_code='POL-PROFILE-UPDATE-PASS'
       AND policy_version='v1.1' AND status='ACTIVE')<>1 THEN
   RAISE EXCEPTION 'LF_PE_PHASE_ACTIVE_GOVERNANCE_DRIFT';
 END IF;
 IF EXISTS(SELECT 1 FROM public.lf_policy_versions
     WHERE policy_code='POL-PROFILE-UPDATE-PASS'
       AND policy_version='v1.3-phase-separation-candidate') THEN
   RAISE EXCEPTION 'LF_PE_PHASE_CANDIDATE_ALREADY_EXISTS';
 END IF;
 SELECT u.id,u.unit_metadata INTO STRICT v_pe10e_id,v_meta
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
   AND u.unit_code='PE10E'
 FOR UPDATE;
 SELECT u.id,u.unit_metadata INTO STRICT v_pe10_id,v_pe10_meta
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
   AND u.unit_code='PE10'
 FOR UPDATE;
 IF v_meta ? 'phase_separation_v1'
    OR v_pe10_meta ? 'phase_separation_v1'
    OR v_meta#>>'{action_specs_v1,PE10E_C4,status}' IS DISTINCT FROM 'READY'
    OR v_meta#>>'{action_specs_v1,PE10E_C4,action_kind}' IS DISTINCT FROM 'READBACK_ONCE'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
           WHERE id=v_pe10e_id) AND checkpoint_code='PE10E_C4')
        IS DISTINCT FROM 'PENDING'
 THEN
   RAISE EXCEPTION 'LF_PE_PHASE_EXPERT_CHECKPOINT_PRESTATE_DRIFT';
 END IF;
 -- Immutable Git PR merge identities were independently read from GitHub at source authoring.
 -- They qualify only code delivery. They do NOT attest a native executor or reviewer.
 v_receipts := jsonb_build_array(
   jsonb_build_object('profile','quality_pack','pr',2322,'merge_sha','0c7b41cc19c88e4115bebd1888f731fb316dce2e'),
   jsonb_build_object('profile','ui_architect','pr',2324,'merge_sha','71ddf4866def4ca66ad4645c6f1edb62ad09a936'),
   jsonb_build_object('profile','product_director_lf','pr',2325,'merge_sha','e02343badc9c06c2065db4351c9d3bfc16771699'),
   jsonb_build_object('profile','customer_financial_ux_decisioning','pr',2326,'merge_sha','8b436bc8c50b4e93959d9bf3279ee0108924a476'),
   jsonb_build_object('profile','gamification_system_architect','pr',2327,'merge_sha','0ff98faec756b9dd1fa2c8fae656482b1473f595'),
   jsonb_build_object('profile','evidence_lineage_reviewer_lf','pr',2328,'merge_sha','ff0e48bc870b48c7ea645c79544ed5b083a75720'),
   jsonb_build_object('profile','frontend_prototype_architect_lf','pr',2329,'merge_sha','82b9c583d46c81eb9c6d45561e8ede2ca7fa61d1'),
   jsonb_build_object('profile','systemic_root_cause_repair_lf','pr',2330,'merge_sha','94d56170577eaaa3d4a82ea74b01f570afa702de'),
   jsonb_build_object('profile','programming_analysis_lf','pr',2331,'merge_sha','2b4dec92cfc925208014fb0bc9e708799078f5b5')
 );
 v_first := jsonb_build_object(
   'code_delivery_status','CODE_MERGED_USER_ACCEPTED',
   'profile_count',jsonb_array_length(v_receipts),
   'git_pr_receipts',v_receipts,
   'scope','VERSIONED_CODE_ONLY',
   'native_profile_execution_attested',false,
   'expert_performance_admitted',false,
   'runtime_activated',false,
   'cutover_allowed',false
 );
 v_phase := jsonb_build_object(
   'schema','PROFILE_EVOLUTION_PHASE_SEPARATION_V1',
   'source_contract','skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json',
   'first_evolution',v_first,
   'expert_certification',jsonb_build_object(
     'checkpoint','PE10E_C4',
     'status','PENDING_GENUINE_GPT_NATIVE_AND_INDEPENDENT_REVIEW',
     'four_arm_required',true,
     'blind_independent_reviewer_required',true,
     'no_provenance_forgery',true,
     'cutover_requires_expert_pass',true
   ),
   'checkpoint_statuses_unchanged',true,
   'active_policy_unchanged',true
 );
 v_spec := v_meta#>'{action_specs_v1,PE10E_C4}';
 -- Correct the false READBACK classification, but do not manufacture a RUN_TEST.
 -- The connector must remain closed until an authentic native producer and
 -- independent reviewer have a scoped executable contract and real receipts.
 v_spec := v_spec || jsonb_build_object(
   'status','BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING',
   'action_kind','DECLARED_TEST_EXECUTION',
   'recipe_mode','EXECUTE_EXPERT_BENCHMARK_WHEN_ATTESTED',
   'precision','EXPLICIT_EXECUTION_REQUIRED_NO_READBACK_SUBSTITUTE',
   'requires_material_execution',true,
   'verification_queries','[]'::jsonb,
   'expert_execution_gate',jsonb_build_object(
     'scope','EXPERT_TASK_PERFORMANCE_E2E',
     'status','BLOCKED_UNTIL_AUTHENTIC_EXECUTOR_AND_REVIEWER',
     'source_contract','skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json',
     'required','FOUR_ARM_GPT_NATIVE_REAL_OPEN_TASKS_AND_INDEPENDENT_BLIND_JUDGE',
     'first_evolution_pr_receipts_are_not_expert_evidence',true,
     'synthetic_pass_forbidden',true,
     'no_provider_attestation_forgery',true
   ),
   'assertion_contract',jsonb_build_object(
     'mode','EXPLICIT_PASS_WHEN_SUBSET',
     'pass_when',jsonb_build_object(
       'schema','PROFILE_EXPERT_BEHAVIOR_SCORE_V1',
       'status','BENCHMARK_PASS',
       'benchmark_scope','EXPERT_TASK_PERFORMANCE_E2E',
       'independent_assurance','PASS',
       'critical_regressions',0,
       'cutover_eligible',false
     )
   )
 );
 v_new := jsonb_set(v_meta,'{action_specs_v1,PE10E_C4}',v_spec,true);
 v_new := jsonb_set(v_new,'{phase_separation_v1}',v_phase,true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_new WHERE id=v_pe10e_id;
 v_pe10_meta := jsonb_set(v_pe10_meta,'{phase_separation_v1}',
   jsonb_build_object(
     'schema','PROFILE_EVOLUTION_PHASE_SEPARATION_V1',
     'first_evolution_code_status','CODE_MERGED_USER_ACCEPTED',
     'expert_checkpoint','PE10E_C4',
     'expert_gate_required_for_cutover',true,
     'first_evolution_does_not_admit_cutover',true,
     'no_v02_activation_from_code_merge',true),true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_pe10_meta WHERE id=v_pe10_id;
 -- Fail-closed postcheck: no actual benchmark execution has occurred.
 v_boot := programacion.fn_engineering_unit_bootstrap_v3(
   'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10E');
 IF v_boot#>>'{action_spec,status}' IS DISTINCT FROM 'BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'
    OR v_boot#>>'{action_spec,action_kind}' IS DISTINCT FROM 'DECLARED_TEST_EXECUTION'
    OR coalesce((v_boot->>'execution_allowed')::boolean,false)
    OR v_boot->>'terminal_action'='CONTINUE_CURRENT_CHECKPOINT'
    OR v_boot#>>'{phase_separation_v1,expert_certification,status}'='ADMITTED'
 THEN
   RAISE EXCEPTION 'LF_PE_PHASE_POSTCHECK_FAIL_CLOSED_VIOLATED';
 END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
       WHERE id=v_pe10e_id) AND checkpoint_code='PE10E_C4') <> 'PENDING'
 THEN RAISE EXCEPTION 'LF_PE_PHASE_EXPERT_CHECKPOINT_FALSIFIED'; END IF;
END $phase$;

WITH p AS (
 SELECT policy_code,
   policy_payload || jsonb_build_object(
     'profile_evolution_phase_separation_v1',
       jsonb_build_object(
         'source_contract','skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json',
         'first_evolution','CODE_MERGED_ONLY',
         'code_delivery_not_expert_admission',true,
         'expert_benchmark_gate','PE10E_C4',
         'expert_proof_required',true,
         'independent_reviewer_required',true,
         'candidate_only',true,
         'operational_cutover_allowed',false,
         'active_policy_untouched',true)
   ) payload
 FROM public.lf_policy_versions
 WHERE policy_code='POL-PROFILE-UPDATE-PASS'
   AND policy_version='v1.1' AND status='ACTIVE'
)
INSERT INTO public.lf_policy_versions
  (policy_code,policy_version,policy_payload,policy_sha,status,effective_at,source_ref,created_by_execution_id)
SELECT policy_code,'v1.3-phase-separation-candidate',payload,
       encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
       'CANDIDATE',clock_timestamp(),
       'supabase/migrations/20261013001500_lf_profile_evolution_phase_boundary_v1.sql',
       'EXEC-PE-PHASE-BOUNDARY-20261012-001'
FROM p;

INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT
 'LF-PE-PHASE-CONFLATION-20261012-001','PROFILE_EVOLUTION',
 'Code release confused with expert admission and incompatible readback',
 'Phase-1 PR publication is distinct from GPT_NATIVE expert score and v0.2 cutover',
 'Expert checkpoint required actual producer + independent judge but was typed READBACK_ONCE with zero SQL queries; repeating code artifacts did not move 70/76.',
 'READ_QUERY_MISSING masked MISSING_NATIVE_EXECUTOR_AND_REVIEWER',
 'Separate phase-1 code receipt and expert checkpoint; keep expert gate fail-closed, fix local action spec and governance together, never infer provider attestation from chat.',
 'Positive: nine merged Git PRs recorded as CODE_ONLY. Negative: PE10E_C4 remains pending, bootstrap cannot CONTINUE, active policy stays v1.1.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10E_C4','ACTIVO',
 'supabase/migrations/20261013001500_lf_profile_evolution_phase_boundary_v1.sql'
WHERE NOT EXISTS (
 SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='LF-PE-PHASE-CONFLATION-20261012-001'
);

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.lf_policy_versions
       WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE')<>1
    OR (SELECT count(*) FROM public.lf_policy_versions
       WHERE policy_code='POL-PROFILE-UPDATE-PASS'
         AND policy_version='v1.3-phase-separation-candidate'
         AND status='CANDIDATE'
         AND policy_payload#>>'{profile_evolution_phase_separation_v1,operational_cutover_allowed}'='false'
         AND policy_sha=encode(extensions.digest(convert_to(policy_payload::text,'UTF8'),'sha256'),'hex'))<>1
 THEN RAISE EXCEPTION 'LF_PE_PHASE_GOVERNANCE_POSTCHECK_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
       AND unit_code IN ('PE10','PE10E')
       AND unit_metadata ? 'phase_separation_v1')<>2
 THEN RAISE EXCEPTION 'LF_PE_PHASE_UNIT_DUAL_SCOPE_POSTCHECK_FAILED'; END IF;
END $post$;
COMMIT;

-- LF_PROFILE_UPDATER_IO_INPUT_BINDINGS_V1
-- Candidate source only. NO permission change, Router modification, or new enforcement.
-- Sole deployment authority: LF Migration Merge Train after independent review.
-- Reference: skills/profile_creator/contracts/profile_updater_io_bindings_v1.json
-- This only fills the currently unused input_required metadata (17 steps).
-- The live RPC still validates judge.required_evidence_keys, not input_required.
-- Do not claim a PASS or a new E2E based on this migration.
DO $lf$
DECLARE
    v_operation CONSTANT text := 'ACTUALIZACION_PERFIL_LF';
    v_before_count integer;
    v_after_count integer;
BEGIN
    SELECT count(*) INTO v_before_count
      FROM public.lf_operation_step_contracts
     WHERE operation_code = v_operation AND status = 'ACTIVE_ENFORCEMENT';
    IF v_before_count <> 17 THEN
        RAISE EXCEPTION 'BLOCK_UPDATER_IO_LIVE_STEP_COUNT:%', v_before_count;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.lf_operation_step_contracts
        WHERE operation_code=v_operation AND status='ACTIVE_ENFORCEMENT'
          AND (jsonb_typeof(input_required) <> 'array'
               OR (step_id IN ('method_selection','evolution_decision')
                   AND input_required <> CASE step_id
                     WHEN 'method_selection' THEN '["profile_assessment_receipt_id","selector_version","selected_methods"]'::jsonb
                     ELSE '["profile_assessment_receipt_id","decision","evolution_mode"]'::jsonb
                   END)
               OR (step_id NOT IN ('method_selection','evolution_decision')
                   AND input_required <> '[]'::jsonb))
    ) THEN
        RAISE EXCEPTION 'BLOCK_UPDATER_IO_INPUT_CURRENTNESS_DRIFT';
    END IF;

    WITH proposed(step_id, required_input) AS (
        VALUES
    ('init_execution', '["target_code","target_path","research_baseline_mode"]'::jsonb),
    ('router', '["execution_id","init_execution_ref","router_read"]'::jsonb),
    ('profile_resolve', '["target_code","router_receipt_ref","profile_slug"]'::jsonb),
    ('baseline_read', '["profile_repo_path","baseline_revision"]'::jsonb),
    ('method_selection', '["profile_assessment_receipt_id","selector_version","selected_methods"]'::jsonb),
    ('evolution_decision', '["profile_assessment_receipt_id","decision","evolution_mode"]'::jsonb),
    ('change_scope', '["decision","baseline_revision"]'::jsonb),
    ('regression_plan', '["minimal_patch_scope","positive_cases"]'::jsonb),
    ('pre_write_execution_binding_gate', '["execution_id","target_path","regression_plan_ref","write_plan"]'::jsonb),
    ('github_write', '["bound_revision","written_files"]'::jsonb),
    ('github_readback', '["commit_sha","written_files"]'::jsonb),
    ('deterministic_validation', '["bound_revision","candidate_commit_sha","readback_exact_head","evolution_proof_run_id"]'::jsonb),
    ('semantic_judge', '["deterministic_receipt_ref","semantic_judge_result"]'::jsonb),
    ('regression_after', '["deterministic_receipt_ref","semantic_receipt_ref","before_after_matrix"]'::jsonb),
    ('post_merge_reconcile', '["regression_receipt_ref","merge_sha"]'::jsonb),
    ('close', '["reconciliation_receipt_ref","open_blockers"]'::jsonb),
    ('report_output', '["closure_receipt_ref","exact_head"]'::jsonb)
    ), updated AS (
        UPDATE public.lf_operation_step_contracts c
           SET input_required = p.required_input,
               updated_at = clock_timestamp()
          FROM proposed p
         WHERE c.operation_code = v_operation
           AND c.step_id = p.step_id
           AND c.status = 'ACTIVE_ENFORCEMENT'
         RETURNING c.step_id
    )
    SELECT count(*) INTO v_after_count FROM updated;
    IF v_after_count <> 17 THEN
        RAISE EXCEPTION 'BLOCK_UPDATER_IO_CHANGED_STEPS:%', v_after_count;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.lf_operation_step_contracts c
        WHERE c.operation_code = v_operation AND c.status='ACTIVE_ENFORCEMENT'
          AND (c.input_required IS NULL OR jsonb_typeof(c.input_required) <> 'array'
               OR jsonb_array_length(c.input_required)=0)
    ) THEN
        RAISE EXCEPTION 'BLOCK_UPDATER_IO_REQUIREMENT_MISSING';
    END IF;
END
$lf$;

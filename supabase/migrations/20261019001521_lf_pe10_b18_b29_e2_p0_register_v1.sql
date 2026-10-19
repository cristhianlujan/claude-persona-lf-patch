-- PE10 B18/B29 E2: append a same-case research/evaluation unit under the existing PE10 programme.
-- PLAN REGISTRATION ONLY. Do not alter M01-M32, their receipts, their RAW artifacts, product runtime or P0.
-- Database writes: authorized ACTUALIZACION_DB_LF migration, via Merge Train only.
DO $pe10_e2$
DECLARE
  v_exec text;
  v_stream_id bigint;
  v_parent_id bigint;
  v_original_id bigint;
  v_plan_event_id bigint;
  v_work_id bigint;
  v_n integer;
  v_case_at timestamptz;
BEGIN
  SELECT execution_id INTO v_exec
  FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND target_type='MIGRATION'
    AND target_code LIKE '%lf_pe10_b18_b29_e2_p0_register_v1'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC LIMIT 1;
  IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_E2_BLOCK_TRAIN_EXECUTOR_MISSING'; END IF;

  SELECT id INTO STRICT v_stream_id FROM programacion.engineering_workstreams
  WHERE stream_code='PROFILE_UPDATER_EVOLUTION_V1' AND status='ACTIVE';
  SELECT id INTO STRICT v_parent_id FROM programacion.engineering_work_items
  WHERE work_code='PEVO-PE10' AND workstream_id=v_stream_id;
  SELECT id INTO STRICT v_original_id FROM programacion.engineering_work_items
  WHERE work_code='PEVO-PE10-METHODS32-P0' AND workstream_id=v_stream_id AND status='DONE';
  SELECT plan_event_id INTO STRICT v_plan_event_id FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10' AND work_item_id=v_parent_id;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_original_id AND status='DONE'
      AND evidence_ref IS NOT NULL AND assertion_receipt->>'passed'='true'
      AND assertion_receipt_sha256 IS NOT NULL) <> 32
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_original_id) <> 32
  THEN RAISE EXCEPTION 'PE10_E2_ORIGINAL_32_RECEIPTS_NOT_INTACT'; END IF;

  SELECT created_at INTO STRICT v_case_at FROM public.lf_eventos
  WHERE id=20161 AND evento_tipo='READBACK_VERIFICADO';
  IF v_case_at >= timestamptz '2026-10-15T00:00:00Z'
    OR (SELECT count(*) FROM programacion.pe10_method_variants
        WHERE case_ref='PE10-IG-M107-M109-P0'
          AND method_code IN ('PE10_M18','PE10_M29')) <> 2
  THEN RAISE EXCEPTION 'PE10_E2_P0_ORIGINAL_METHOD_SCOPE_NOT_VERIFIED'; END IF;

  IF EXISTS(SELECT 1 FROM programacion.engineering_work_items WHERE work_code='PEVO-PE10-B18-B29-E2-P0')
    OR EXISTS(SELECT 1 FROM programacion.engineering_plan_units
      WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10_B18_B29_E2')
  THEN RAISE EXCEPTION 'PE10_E2_ALREADY_REGISTERED_DO_NOT_DUPLICATE'; END IF;

  INSERT INTO programacion.engineering_work_items
    (work_code,workstream_id,parent_work_item_id,title,objective,expected_result,
     work_type,priority,status,assignee_type,assignee_ref,target_repo,
     target_domain,target_component,source_ref,acceptance_criteria,created_by_execution_id)
  VALUES
    ('PEVO-PE10-B18-B29-E2-P0',v_stream_id,v_parent_id,
     'PE10 B18/B29 evolution on unchanged frozen P0',
     'Diagnose omitted relations, improve generic discovery and synthesis, re-run B18/B29 on exactly the SAME P0, then externally evaluate H1-H4 without answer leakage',
     'Four separately evidenced checkpoints C1-C4; original 32 checkpoints unchanged; no domain repairs or production activation',
     'QA','P1','BACKLOG','AGENT','PE10_E2_COORDINATOR_UNBOUND',
     'cristhianlujan/claude-persona-lf-patch','LF_PE10','PE10-IG-M107-M109-P0',
     'supabase://public.lf_eventos/20161',
     '["Preserve identical PE10-IG-M107-M109-P0, historical cutoff 2026-10-15T00:00:00Z, and source event public.lf_eventos/20161","Leave all 32 original method checkpoints and their immutable RAW/evidence/receipts unchanged","C1 evaluator-only causal audit; do not leak known H1-H4 answers to C3 producers","C2 generalized methodology changes must be falsifiable and never hardcode expected functions or values","C3 rerun B18 and B29 with the exact same P0 and source cutoff; freeze outputs before evaluating; label CURRENT replay separately","C4 independent post-freeze evaluator compares exact same-case method performance, false positives, costs and unresolved","No activation or product/runtime changes; only governed checkpoint completion with actual evidence through Train"]'::jsonb,v_exec)
  RETURNING id INTO v_work_id;

  INSERT INTO programacion.engineering_work_checkpoints
    (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
  VALUES
    (v_work_id,'PE10_E2_C1','C1 - Root-cause audit of missed discoveries',1,1,true,'PENDING',v_exec),
    (v_work_id,'PE10_E2_C2','C2 - Generic method correction and regression controls',2,1,true,'PENDING',v_exec),
    (v_work_id,'PE10_E2_C3','C3 - Same P0 producer rerun with frozen inputs',3,1,true,'PENDING',v_exec),
    (v_work_id,'PE10_E2_C4','C4 - External scoring and method comparison',4,1,true,'PENDING',v_exec);

  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>4 THEN RAISE EXCEPTION 'PE10_E2_CHECKPOINT_COUNT_%',v_n; END IF;

  INSERT INTO programacion.engineering_plan_units
    (plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,exit_criterion,
     plan_event_id,source_event_id,work_item_id,created_by_execution_id,unit_metadata)
  VALUES
    ('PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10_B18_B29_E2',
     'METHOD_EVIDENCE','E10_B18_B29_E2',10,10,
     'Same-P0 PE10 B18/B29 method evolution and external comparison',
     'Four actual governed evidence receipts; exact P0; no oracle leakage; unchanged frozen original reports',
     v_plan_event_id,20161,v_work_id,v_exec,
     '{"schema":"PE10_B18_B29_SAME_P0_EVOLUTION_UNIT_V1","case_ref":"PE10-IG-M107-M109-P0","source_cutoff_utc":"2026-10-15T00:00:00Z","source_event_id":20161,"plan_lineage":"PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10","original_method_work_code":"PEVO-PE10-METHODS32-P0","original_methods":["PE10_M18","PE10_M29"],"original_outputs_immutable":true,"original_checkpoints_immutable":true,"runtime_activation":false,"source_pack_v2":{"schema":"PE10_IDENTICAL_P0_INPUTS_V1","p0":{"case_ref":"PE10-IG-M107-M109-P0","cutoff_utc":"2026-10-15T00:00:00Z","event_id":20161,"ekb_asof_only":true},"producer_inputs":{"base":"exact original frozen P0 only","allow":"assigned generic method revision and authorized historical sources","exclude":["oracle H1-H4","original M01-M32 answers","C1 evaluator-only causal findings","other producer arm outputs","post-cutoff facts misrepresented as P0"]},"current_replay":"REPLAY_CURRENT_NOT_ASOF; results cannot certify historical state","checkpoint_inputs":{"PE10_E2_C1":{"case_ref":"PE10-IG-M107-M109-P0","source_event_id":20161,"cutoff_utc":"2026-10-15T00:00:00Z","purpose":"Audit frozen M18/M29 and originals, distinguish discovery/representation/coverage/synthesis failure; evaluator-only diagnostic, no producer leakage"},"PE10_E2_C2":{"case_ref":"PE10-IG-M107-M109-P0","source_event_id":20161,"cutoff_utc":"2026-10-15T00:00:00Z","purpose":"Update generalized bidirectional dependency discovery, exact object identity and evidence-preserving synthesis; never encode expected names/answers"},"PE10_E2_C3":{"case_ref":"PE10-IG-M107-M109-P0","source_event_id":20161,"cutoff_utc":"2026-10-15T00:00:00Z","purpose":"Rerun revised B18 and B29 on the identical frozen case, isolated from oracle, original reports and other arm; freeze RAW before grading"},"PE10_E2_C4":{"case_ref":"PE10-IG-M107-M109-P0","source_event_id":20161,"cutoff_utc":"2026-10-15T00:00:00Z","purpose":"After C3 freeze, qualified external evaluator scores four reserved discoveries and false positives against preserved original B18/B29 with comparable cost accounting"}}},"action_specs_v1":{"PE10_E2_C1":{"status":"BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION","target":{"checkpoint":"PE10_E2_C1","case_ref":"PE10-IG-M107-M109-P0"},"requires_material_execution":true,"action_kind":"RESEARCH_OR_EVALUATE","recipe_mode":"EVIDENCE_FIRST","contract_family":"PE10_EVOLUTION_EVIDENCE","expected":"Audit frozen M18/M29 and originals, distinguish discovery/representation/coverage/synthesis failure; evaluator-only diagnostic, no producer leakage","forbidden":["P0_CASE_REPLACEMENT","FROZEN_BASELINE_MUTATION","KNOWN_ANSWER_LEAK_TO_PRODUCER","PREMATURE_DONE","UNAUTHORIZED_PRODUCTION_WRITE"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_E2_C1","case_ref":"PE10-IG-M107-M109-P0","original_work_unchanged":true,"source_cutoff_unchanged":true,"material_evidence_verified":true}}},"PE10_E2_C2":{"status":"BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION","target":{"checkpoint":"PE10_E2_C2","case_ref":"PE10-IG-M107-M109-P0"},"requires_material_execution":true,"action_kind":"RESEARCH_OR_EVALUATE","recipe_mode":"EVIDENCE_FIRST","contract_family":"PE10_EVOLUTION_EVIDENCE","expected":"Update generalized bidirectional dependency discovery, exact object identity and evidence-preserving synthesis; never encode expected names/answers","forbidden":["P0_CASE_REPLACEMENT","FROZEN_BASELINE_MUTATION","KNOWN_ANSWER_LEAK_TO_PRODUCER","PREMATURE_DONE","UNAUTHORIZED_PRODUCTION_WRITE"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_E2_C2","case_ref":"PE10-IG-M107-M109-P0","original_work_unchanged":true,"source_cutoff_unchanged":true,"material_evidence_verified":true}}},"PE10_E2_C3":{"status":"BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION","target":{"checkpoint":"PE10_E2_C3","case_ref":"PE10-IG-M107-M109-P0"},"requires_material_execution":true,"action_kind":"RESEARCH_OR_EVALUATE","recipe_mode":"EVIDENCE_FIRST","contract_family":"PE10_EVOLUTION_EVIDENCE","expected":"Rerun revised B18 and B29 on the identical frozen case, isolated from oracle, original reports and other arm; freeze RAW before grading","forbidden":["P0_CASE_REPLACEMENT","FROZEN_BASELINE_MUTATION","KNOWN_ANSWER_LEAK_TO_PRODUCER","PREMATURE_DONE","UNAUTHORIZED_PRODUCTION_WRITE"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_E2_C3","case_ref":"PE10-IG-M107-M109-P0","original_work_unchanged":true,"source_cutoff_unchanged":true,"material_evidence_verified":true}}},"PE10_E2_C4":{"status":"BLOCK_PENDING_MATERIAL_RESEARCH_AND_VALIDATION","target":{"checkpoint":"PE10_E2_C4","case_ref":"PE10-IG-M107-M109-P0"},"requires_material_execution":true,"action_kind":"RESEARCH_OR_EVALUATE","recipe_mode":"EVIDENCE_FIRST","contract_family":"PE10_EVOLUTION_EVIDENCE","expected":"After C3 freeze, qualified external evaluator scores four reserved discoveries and false positives against preserved original B18/B29 with comparable cost accounting","forbidden":["P0_CASE_REPLACEMENT","FROZEN_BASELINE_MUTATION","KNOWN_ANSWER_LEAK_TO_PRODUCER","PREMATURE_DONE","UNAUTHORIZED_PRODUCTION_WRITE"],"assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_E2_C4","case_ref":"PE10-IG-M107-M109-P0","original_work_unchanged":true,"source_cutoff_unchanged":true,"material_evidence_verified":true}}}},"done_procedures_v1":{"PE10_E2_C1":{"status":"NOT_EXECUTED","requirements":["Exact original RAW and query evidence linked","Causal alternatives and negative falsifiers distinguish stages","P0 vs later CURRENT sources separated","Findings and evaluator-only details withheld from C3 producers"],"closure_route":"GOVERNED_MIGRATION_OR_OPERATION_THEN_TRAIN_AND_POST_READBACK"},"PE10_E2_C2":{"status":"NOT_EXECUTED","requirements":["Method changes documented with source diff and review","Forward/reverse dependency probes and qualifier checks demonstrated","Positive, negative, missing, NULL, substring/comment cases exercised","No target-specific names, values or hidden rubric embedded in producer method"],"closure_route":"GOVERNED_MIGRATION_OR_OPERATION_THEN_TRAIN_AND_POST_READBACK"},"PE10_E2_C3":{"status":"NOT_EXECUTED","requirements":["Both producer input packets identical to original P0 evidence scope","Method-specific changes only; original case and date invariant","Separate input/output provenance and leakage checks; no fictitious independent agents","B18/B29 RAW immutable before any evaluator access or scoring","CURRENT readbacks identified as replay, not P0 historical fact"],"closure_route":"GOVERNED_MIGRATION_OR_OPERATION_THEN_TRAIN_AND_POST_READBACK"},"PE10_E2_C4":{"status":"NOT_EXECUTED","requirements":["Evaluator-only rubric H1-H4 withheld from producers until source freeze","Exact object relationships, evidence scope and negative tests verified","Original vs evolved arms compared on same P0; SQL, elapsed and tokens only if measured","No declaration of independent blind discovery when exposure cannot be excluded","Final method-selection decision separately evidenced; no product/runtime activation"],"closure_route":"GOVERNED_MIGRATION_OR_OPERATION_THEN_TRAIN_AND_POST_READBACK"}},"checkpoint_ordering":["PE10_E2_C1","PE10_E2_C2","PE10_E2_C3","PE10_E2_C4"],"isolation_contract":{"same_case":true,"same_historical_cutoff":true,"p0_source_event_id":20161,"producers_see_oracle":false,"producer_arms_read_each_other":false,"external_evaluator_only_after_freeze":true,"shared_chat_not_genuinely_independent":true},"evaluation_contract":{"criteria":"H1-H4 reserved to evaluator; not disclosed to producers","status":"NOT_PERFORMED","blindness":"NOT_ATTESTED_UNTIL_REAL_INPUT_PROVENANCE","success":"independent evidence-backed correctness, no self-scoring","no_known_answer_hardcoding":true},"negative_regressions":["MISSING_CONSUMER_OUTSIDE_NAMING_PATTERN","AMBIGUOUS_OBJECT_IDENTITY","SUBSTRING_FALSE_DEPENDENCY","COMMENT_ONLY_FALSE_REFERENCE","CANDIDATE_INFERRED_AS_EXECUTED_CALL","LEAKAGE_FROM_EVALUATOR","ORIGINAL_RESULT_MODIFIED"],"scope":"PLAN_REGISTRATION_ONLY_NO_RUNTIME_OR_METHOD_CODE_PATCH"}'::jsonb);

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_id AND status='PENDING'
        AND completed_at IS NULL AND assertion_receipt IS NULL AND evidence_ref IS NULL) <> 4
    OR (SELECT count(*) FROM programacion.engineering_plan_units
        WHERE work_item_id=v_work_id AND plan_event_id=v_plan_event_id
          AND source_event_id=20161
          AND unit_metadata->>'case_ref'='PE10-IG-M107-M109-P0'
          AND unit_metadata->>'source_cutoff_utc'='2026-10-15T00:00:00Z') <> 1
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_original_id AND status='DONE'
          AND evidence_ref IS NOT NULL AND assertion_receipt->>'passed'='true') <> 32
  THEN RAISE EXCEPTION 'PE10_E2_REGISTRATION_READBACK_FAILED'; END IF;
END
$pe10_e2$;

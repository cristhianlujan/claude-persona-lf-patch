-- RW1-02_C3: bind independent review to the repaired neutral V2 competition package.
-- No checkpoint transition and no assertion receipt are produced here.
BEGIN;
DO $rw102_c3_v2_bind$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-02';
  v_cp constant text := 'RW1-02_C3';
  v_work_item constant bigint := 1128;
  v_prior_md5 constant text := '225290a27eaeb0e5eab77f190ce3b670';
  v_main constant text := 'fa6e679fc3df5ff2f9d67338aec4901a78c023c1';
  v_corpus_blob constant text := 'cf22d9889eb008dc7afcf64dd1b3712b9536ec98';
  v_result_blob constant text := '09d42bd6ebbcb8b140d4abd92802c5be72078fb9';
  v_validator_blob constant text := '3c0a6eb4419574accf2138725ef8cd95d4ef210e';
  v_workflow_blob constant text := 'cb3adc5e050ee5f10b325e6607814319c746dd55';
  v_handoff_blob constant text := 'aa4654dc81dd156198b7a48afaa88efae8df7913';
  v_revise_blob constant text := '90e7db8d03310b9b1b06e61aa07339d5d6021775';

  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_source jsonb;
  v_declared jsonb;
  v_evidence jsonb;
  v_mutation jsonb;
  v_contract jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_work_item
    AND disposition='ASSIGNED'
    AND md5(unit_metadata::text)=v_prior_md5
  FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE id=1612 AND work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND evidence_ref IS NULL
        AND assertion_receipt IS NULL AND assertion_receipt_sha256 IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C3_V2_BIND_LIFECYCLE_DRIFT'; END IF;

  v_spec:=v_old#>'{action_specs_v1,RW1-02_C3}';
  v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,RW1-02_C3}';
  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'precision' IS DISTINCT FROM 'EXACT_RW102_C3_INDEPENDENT_ARCHITECTURE_REVIEW_V1'
     OR v_source->>'source_snapshot_commit' IS DISTINCT FROM '5d7f30580d4c6bb557e51943693c4b95e192900e'
  THEN RAISE EXCEPTION 'RW102_C3_V2_BIND_SOURCE_DRIFT'; END IF;

  SELECT jsonb_agg(
    CASE
      WHEN x->>'path' LIKE '%RW1_02_C3_BLIND_JUDGE_HANDOFF_V1.md'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V2.md'::text))
      WHEN x->>'path' LIKE '%RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json'::text))
      WHEN x->>'path' LIKE '%validate_rw102_architecture_competition_v1.py'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v2.py'::text))
      WHEN x->>'path' LIKE '%RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V2.json'::text))
      WHEN x->>'path' LIKE '%RW1_02_C3_INDEPENDENT_VERDICT_V1.json'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json'::text))
      ELSE x END
  ) INTO v_declared
  FROM jsonb_array_elements(v_spec#>'{target,declared_artifacts}') x;

  SELECT jsonb_agg(
    CASE
      WHEN x->>'path' LIKE '%RW1_02_C3_BLIND_JUDGE_HANDOFF_V1.md'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V2.md'::text))
      WHEN x->>'path' LIKE '%RW1_02_C2_ARCHITECTURE_COMPETITION_V1.json'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json'::text))
      WHEN x->>'path' LIKE '%validate_rw102_architecture_competition_v1.py'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v2.py'::text))
      WHEN x->>'path' LIKE '%RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V1.json'
        THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V2.json'::text))
      ELSE x END
  ) INTO v_evidence
  FROM jsonb_array_elements(v_spec#>'{target,evidence_artifacts}') x;

  SELECT jsonb_agg(
    CASE WHEN x->>'path' LIKE '%RW1_02_C3_INDEPENDENT_VERDICT_V1.json'
      THEN jsonb_set(x,'{path}',to_jsonb('cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json'::text))
      ELSE x END
  ) INTO v_mutation
  FROM jsonb_array_elements(v_spec#>'{target,mutation_artifacts}') x;

  v_spec:=jsonb_set(v_spec,'{precision}','"EXACT_RW102_C3_INDEPENDENT_ARCHITECTURE_REVIEW_V2"'::jsonb,true);
  v_spec:=jsonb_set(v_spec,'{target,declared_artifacts}',v_declared,true);
  v_spec:=jsonb_set(v_spec,'{target,evidence_artifacts}',v_evidence,true);
  v_spec:=jsonb_set(v_spec,'{target,mutation_artifacts}',v_mutation,true);
  v_spec:=jsonb_set(v_spec,'{evidence_ref}',
    to_jsonb('github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C3_INDEPENDENT_VERDICT_V2.json'::text),true);
  v_spec:=jsonb_set(v_spec,'{expected}',
    to_jsonb('A materially separate judge independently recomputes the neutral structured V2 architecture competition before opening the producer result, executes at least 24 adversarial mutations, and returns PASS only with zero material blockers and a supported final selection. No Router runtime, production, latency/cost, or GOLDEN claim.'::text),true);

  v_source:=jsonb_set(v_source,'{source_snapshot_commit}',to_jsonb(v_main),true);
  v_source:=jsonb_set(v_source,'{source_git_blobs,c2_corpus}',to_jsonb(v_corpus_blob),true);
  v_source:=jsonb_set(v_source,'{source_git_blobs,c2_result}',to_jsonb(v_result_blob),true);
  v_source:=jsonb_set(v_source,'{source_git_blobs,c2_validator}',to_jsonb(v_validator_blob),true);
  v_source:=jsonb_set(v_source,'{source_git_blobs,workflow}',to_jsonb(v_workflow_blob),true);
  v_source:=jsonb_set(v_source,'{source_git_blobs,handoff}',to_jsonb(v_handoff_blob),true);
  v_source:=jsonb_set(v_source,'{source_git_blobs,c3_prior_revise}',to_jsonb(v_revise_blob),true);
  v_source:=jsonb_set(v_source,'{verification_boundary}',
    '"RW102_C3_V2_INDEPENDENT_ARCHITECTURE_ASSURANCE_ONLY_NOT_ROUTER_RUNTIME_OR_PRODUCTION"'::jsonb,true);
  v_source:=jsonb_set(v_source,'{expected_result}',
    to_jsonb('Independent V2 architecture review with producer result hidden until RAW1, at least 24 adversarial mutations, zero semantically invalid false accepts, zero valid sensitivity false rejects caused by winner hardcoding, and a defensible final selection or fail-closed REVISE.'::text),true);
  v_source:=jsonb_set(v_source,'{inputs,artifacts}',
    jsonb_build_array(
      'docs/programming-agent/router_wave/RW1_02_C3_BLIND_JUDGE_HANDOFF_V2.md',
      'docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md',
      'docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md',
      'docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_V2.json',
      'sandbox/lf_contract_gate_test/router_wave/validate_rw102_architecture_competition_v2.py',
      '.github/workflows/lf-router-level2-advisory-tests.yml',
      'docs/programming-agent/router_wave/RW1_02_C2_ARCHITECTURE_COMPETITION_RESULT_V2.json',
      'docs/programming-agent/router_wave/RW1_02_C3_ADVERSARIAL_REVISE_V1.json'
    ),true);

  v_new:=jsonb_set(v_old,'{action_specs_v1,RW1-02_C3}',v_spec,true);
  v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,RW1-02_C3}',v_source,true);

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND work_item_id=v_work_item
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW102_C3_V2_BIND_UPDATE_COUNT:%',v_count; END IF;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    v_plan,v_unit,v_cp,
    programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp)
  );
  IF v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
  THEN RAISE EXCEPTION 'RW102_C3_V2_BIND_CONTRACT_NOT_READY:%',v_contract::text; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE id=1612 AND status='PENDING'
        AND evidence_ref IS NULL AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C3_V2_BIND_CHANGED_CHECKPOINT'; END IF;
END
$rw102_c3_v2_bind$;
COMMIT;

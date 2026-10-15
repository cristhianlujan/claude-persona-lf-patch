-- INPUT GOVERNANCE M10.7 CP3 - bound transactional trigger profile.
-- Only final EKB row is persistent. Transient Curator run, family UPDATE,
-- proposal UPDATE, and negative tamper attempt are subtransaction-rolled back.
-- Never test against terminal receipt; never disable triggers, RLS, security or timeouts.
DO $profile$
DECLARE
  v_code constant text:='IG-M107-TRIGGER-ROLLBACK-PROFILE-008';
  v_before_count integer;
  v_curator jsonb;
  v_run_id bigint;
  v_plan_family jsonb;
  v_plan_proposal jsonb;
  v_probe_error text;
  v_validator_id text;
  v_validator_component bigint;
  v_run programacion.input_readiness_runs%rowtype;
  v_family programacion.input_family_assessments%rowtype;
  v_prop programacion.input_gap_proposals%rowtype;
  v_parent_has_contract boolean;
  v_assertions jsonb;
  v_evidence jsonb;
  v_physical jsonb;
  v_bad_physical jsonb;
  v_assert_sha text;
  v_eval jsonb;
  v_assertion jsonb;
  v_readbacks jsonb:='[]'::jsonb;
  v_obs jsonb;
  v_ref jsonb;
  v_started timestamptz;
  v_curator_ms bigint;
  v_family_ms numeric;
  v_proposal_ms numeric;
  v_family_triggers jsonb;
  v_proposal_triggers jsonb;
  v_family_trigger_count int;
  v_proposal_trigger_count int;
  v_trial int;
  v_evidence_payload jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
    RAISE EXCEPTION 'IG_M107_PROFILE_ALREADY_EXISTS';
  END IF;
  IF (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
     OR (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
     OR (programacion.fn_input_run_source_currentness_v1(933)->>'source_current')<>'false'
  THEN RAISE EXCEPTION 'IG_M107_PROFILE_SCREEN43_PRECONDITION_DRIFT'; END IF;
  SELECT count(*) INTO v_before_count FROM programacion.input_readiness_runs WHERE pantalla_id=43;
  v_started:=clock_timestamp();

  BEGIN
    -- Curator runtime uses the already governed production SQL route but
    -- is wholly local to this rollback subtransaction.
    v_curator:=programacion.fn_input_governance_direct_step_v1(43,'MANUAL');
    IF v_curator->>'status'<>'VALIDATOR_RUNTIME_REQUIRED'
       OR v_curator->>'step'<>'CURATOR_MATERIALIZED'
       OR v_curator->>'next_action'<>'REINVOKE_SAME_SCREEN'
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_UNEXPECTED_CURATOR:%',left(v_curator::text,450); END IF;
    v_run_id:=(v_curator->>'run_id')::bigint;
    v_curator_ms:=round(extract(epoch from (clock_timestamp()-v_started))*1000)::bigint;
    SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_run_id;
    IF v_run.status<>'CURATING'
       OR v_run.pantalla_id<>43
       OR v_run.version_id<>19
       OR v_run.source_snapshot_sha256 IS NULL
       OR (programacion.fn_input_run_source_currentness_v1(v_run_id)->>'source_current')<>'true'
       OR (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=v_run_id)<>47
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_CURATOR_READBACK_INVALID'; END IF;

    v_validator_id:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
    SELECT id INTO STRICT v_validator_component FROM programacion.componentes
     WHERE version_id=v_run.version_id AND componente_codigo='INPUT_VALIDATOR';
    UPDATE programacion.input_readiness_runs
       SET status='VALIDATING',
           validator_identity=v_validator_id,
           validator_component_id=v_validator_component
     WHERE id=v_run_id;
    SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_run_id;
    IF v_run.status<>'VALIDATING' THEN RAISE EXCEPTION 'IG_M107_PROFILE_VALIDATING_STAGE_MISSING'; END IF;

    SELECT * INTO STRICT v_family FROM programacion.input_family_assessments
      WHERE run_id=v_run_id AND family_code='SCREEN_IDENTITY' AND validator_outcome='PENDING';
    SELECT EXISTS (
      SELECT 1 FROM programacion.input_family_assessments pa
      CROSS JOIN LATERAL jsonb_array_elements(
       programacion.fn_input_validator_evidence_rehydrate_v1(pa.validator_evidence)->'assertions') j(x)
      WHERE pa.run_id=v_run.supersedes_run_id AND pa.family_code=v_family.family_code
      AND j.x#>>'{source_ref,kind}'='CONTRACT'
    ) INTO v_parent_has_contract;
    IF v_run.supersedes_run_id IS NOT NULL AND NOT v_parent_has_contract THEN
      v_assertions:=programacion.fn_input_v58_build_assertions(v_run_id,v_run.supersedes_run_id,v_family.family_code);
    ELSE
      v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(v_run_id,v_family.family_code);
    END IF;
    IF jsonb_array_length(v_assertions)<>1 THEN
      RAISE EXCEPTION 'IG_M107_PROFILE_EXPECT_SINGLE_ASSERTION';
    END IF;
    FOR v_assertion IN SELECT value FROM jsonb_array_elements(v_assertions) LOOP
      v_eval:=programacion.fn_input_evaluate_assertion(v_run_id,v_family.family_code,v_assertion);
      IF coalesce((v_eval->>'passed')::boolean,false) IS NOT TRUE
         OR v_assertion->>'result'<>'PASS'
         OR v_assertion->>'source_observed_sha256' IS DISTINCT FROM v_eval->>'source_observed_sha256'
      THEN RAISE EXCEPTION 'IG_M107_PROFILE_POSITIVE_ASSERTION_FAILED'; END IF;
    END LOOP;
    v_assert_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);
    INSERT INTO programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
    VALUES (v_assert_sha,v_assertions) ON CONFLICT(assertion_set_sha256) DO NOTHING;
    IF (SELECT assertions FROM programacion.input_validator_assertion_sets_v1
        WHERE assertion_set_sha256=v_assert_sha) IS DISTINCT FROM v_assertions
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_ASSERTION_SET_DRIFT'; END IF;

    v_evidence:=jsonb_build_object(
     'component_id',v_validator_component,'execution_id',gen_random_uuid()::text,
     'validated_curator_execution_id',v_family.curator_evidence->>'execution_id',
     'execution_mode','INDEPENDENT_VALIDATOR',
     'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
     'direct_source_readback',true,'contract_revision',v_run.contract_revision,
     'source_snapshot_sha256',v_run.source_snapshot_sha256,
     'curator_sha256',v_family.curator_sha256,
     'semantic_depth_sha256',v_family.semantic_depth_sha256,
     'bootstrap_classifier_sha256',NULL,
     'semantic_conclusion_independence','UNPROVEN',
     'validation_phase','SOURCE_INTEGRITY',
     'semantic_comparison_requested',false,'semantic_independence_credited',false,
     'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
     'assertions',v_assertions);
    v_physical:=(v_evidence-'assertions')||
      jsonb_build_object('assertion_set_sha256',v_assert_sha);
    IF programacion.fn_input_validator_evidence_rehydrate_v1(v_physical)
       IS DISTINCT FROM v_evidence THEN
      RAISE EXCEPTION 'IG_M107_PROFILE_PHYSICAL_EVIDENCE_DRIFT'; END IF;

    -- Explicit negative: same family, false source SHA must fail closed.
    v_bad_physical:=jsonb_set(v_physical,'{source_snapshot_sha256}',
       to_jsonb(repeat('0',64)),true);
    v_probe_error:=NULL;
    BEGIN
      UPDATE programacion.input_family_assessments
         SET validator_outcome='PASS',validator_findings='[]'::jsonb,
             validator_evidence=v_bad_physical,
             validator_identity=v_validator_id,validator_assessed_at=clock_timestamp()
       WHERE id=v_family.id;
    EXCEPTION WHEN OTHERS THEN
      v_probe_error:=SQLSTATE||':'||left(SQLERRM,220);
    END;
    IF v_probe_error IS NULL
      OR (SELECT validator_outcome FROM programacion.input_family_assessments
           WHERE id=v_family.id)<>'PENDING'
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_TAMPER_NOT_REJECTED'; END IF;

    -- Real family UPDATE with all six active guards, returned timing per trigger.
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
       UPDATE programacion.input_family_assessments
       SET validator_outcome=$1,validator_findings=$2,
           validator_evidence=$3,validator_identity=$4,
           validator_assessed_at=clock_timestamp()
       WHERE id=$5'
       INTO v_plan_family
       USING 'PASS'::text,'[]'::jsonb,v_physical,v_validator_id,v_family.id;
    v_family_ms:=(v_plan_family->0->>'Execution Time')::numeric;
    v_family_triggers:=coalesce(v_plan_family->0->'Triggers','[]'::jsonb);
    v_family_trigger_count:=jsonb_array_length(v_family_triggers);
    IF (SELECT validator_outcome FROM programacion.input_family_assessments
          WHERE id=v_family.id)<>'PASS'
        OR v_family_trigger_count<>6 THEN
       RAISE EXCEPTION 'IG_M107_PROFILE_FAMILY_TRIGGERS_INCOMPLETE:%',v_family_triggers;
    END IF;

    -- Proposal control; source readback must match same source SHA.
    SELECT * INTO STRICT v_prop FROM programacion.input_gap_proposals
      WHERE run_id=v_run_id AND validator_outcome='PENDING'
      ORDER BY id LIMIT 1;
    v_readbacks:='[]'::jsonb;
    FOR v_ref IN SELECT value FROM jsonb_array_elements(v_prop.source_refs) LOOP
      v_obs:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
      v_readbacks:=v_readbacks||jsonb_build_array(jsonb_build_object(
        'source_ref',v_ref,'source_observed_sha256',
        programacion.fn_v09_sha256_jsonb(v_obs)));
    END LOOP;
    v_evidence:=jsonb_build_object(
      'direct_source_readback',true,
      'source_snapshot_sha256',v_run.source_snapshot_sha256,
      'source_readbacks',v_readbacks,
      'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
      'proposal_is_canonical_source',false,
      'automatic_canonicalization','DENY');
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      UPDATE programacion.input_gap_proposals
      SET validator_identity=$1,validator_outcome=$2,
          status=CASE WHEN proposal_kind=''HUMAN_DECISION_REQUIRED''
                 THEN ''HUMAN_DECISION_REQUIRED'' ELSE ''VALIDATED'' END,
          validator_evidence=$3,validated_at=clock_timestamp()
      WHERE id=$4'
      INTO v_plan_proposal USING v_validator_id,'PASS'::text,v_evidence,v_prop.id;
    v_proposal_ms:=(v_plan_proposal->0->>'Execution Time')::numeric;
    v_proposal_triggers:=coalesce(v_plan_proposal->0->'Triggers','[]'::jsonb);
    v_proposal_trigger_count:=jsonb_array_length(v_proposal_triggers);
    IF (SELECT validator_outcome FROM programacion.input_gap_proposals
         WHERE id=v_prop.id)<>'PASS' OR v_proposal_trigger_count<>2 THEN
      RAISE EXCEPTION 'IG_M107_PROFILE_PROPOSAL_TRIGGERS_INCOMPLETE:%',
         v_proposal_triggers;
    END IF;

    -- Intentional rollback including ALL runtime/canonical/receipt/proposal effects.
    RAISE EXCEPTION 'IG_M107_PROFILE_EXPECTED_ROLLBACK' USING ERRCODE='PZ127';
  EXCEPTION WHEN SQLSTATE 'PZ127' THEN NULL;
  END;

  IF v_plan_family IS NULL OR v_plan_proposal IS NULL
      OR v_family_ms IS NULL OR v_proposal_ms IS NULL
      OR v_run_id IS NULL OR v_probe_error IS NULL
  THEN RAISE EXCEPTION 'IG_M107_PROFILE_NO_MATERIAL_POSITIVE_AND_NEGATIVE'; END IF;
  IF EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_run_id)
      OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_run_id)
      OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_run_id)
      OR (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_before_count
      OR (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
  THEN RAISE EXCEPTION 'IG_M107_PROFILE_ROLLBACK_RESIDUE'; END IF;

  v_evidence_payload:=jsonb_build_object(
    'schema_version','IG_M107_TX_TRIGGER_PROFILE_V1',
    'target_screen_id',43,'baseline_run_id',933,
    'synthetic_run_id_rolled_back',v_run_id,
    'curator_elapsed_ms',v_curator_ms,
    'positive_family','SCREEN_IDENTITY',
    'family_statement_execution_ms',v_family_ms,
    'family_triggers',v_family_triggers,
    'family_buffer_summary',v_plan_family->0->'Plan',
    'proposal_statement_execution_ms',v_proposal_ms,
    'proposal_triggers',v_proposal_triggers,
    'proposal_buffer_summary',v_plan_proposal->0->'Plan',
    'negative_error_code',v_probe_error,
    'negative_accepted',false,
    'all_runtime_changes_rolled_back',true,
    'source_asof_new_run',true,
    'scope','DIAGNOSTIC_ONE_SCREEN_ONE_FAMILY_ONE_PROPOSAL',
    'performance_admission',false);
  FOR v_trial IN 1..2 LOOP
    BEGIN
      INSERT INTO public.lf_error_knowledge(
        id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
        validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
        estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
        detectability,source_context,source_ref)
      VALUES (
        gen_random_uuid(),v_code,'GOVERNANCE',
        'Trigger profiling en UPDATE real de una familia y propuesta, con rollback total',
        'EXPLAIN ANALYZE BUFFERS FORMAT JSON sobre una familia y una propuesta del mismo run synthetic TEMPORAL de pantalla 43. Curator autorizado y source readback vigente dentro de transaccion; familia PASS con assertions y hashes gobernados, caso negativo con SHA falsa rechazado. Todos los cambios de runtime se revierten por PZ127 antes de persistir esta evidencia. Los triggers se miden separadamente en el plan; no representa 47 familias ni p90.',
        'Costo de SQL se concentra en recomputar manifesta/canonical graph y verificaciones por fila. Se mide costo de cada trigger de UPDATE con buffers y consultas internas autorizadas, para priorizar optimizacion segura y genericidad. Guardrails positivos y negativos activos, sin triggers deshabilitados.',
        'ROW_TRIGGER_RECALCULATION_ATOMIC_TX_PROFILE',
        'Usar duraciones de triggers reales para distinguir currentness, assertion re-evaluation y source manifest por familia/propuesta. Las propuestas de cache o batching exigen snapshot actual, readback independiente, negativo tamper y regresion; no extrapolar una familia a 47, ni p90 con muestra n=1. No ampliar timeout ni quitar triggers.',
        'Muestra 1 familia, 1 propuesta, 1 negativa; los planes EXPLAIN en evidencia conservan tiempos por trigger. Run temporal y receipts limpiados con rollback; CP3 sigue PENDING hasta su prueba integral.',
        'HIGH',1,clock_timestamp(),clock_timestamp(),
        'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
        'ACTIVO',v_evidence_payload::text,clock_timestamp(),clock_timestamp(),
        'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
        'M10.7 diagnostic rollback-only, one screen, one family/proposal and tamper',
        'supabase://programacion.input_readiness_runs/933'
      );
      IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
      THEN RAISE EXCEPTION 'IG_M107_PROFILE_EKB_READBACK_FAILED'; END IF;
      IF v_trial=1 THEN RAISE EXCEPTION 'IG_M107_PROFILE_EKB_ROLLBACK'
        USING ERRCODE='PZ128'; END IF;
    EXCEPTION WHEN SQLSTATE 'PZ128' THEN
      IF v_trial<>1 THEN RAISE; END IF;
    END;
    IF v_trial=1 AND EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
    THEN RAISE EXCEPTION 'IG_M107_PROFILE_EKB_ROLLBACK_RESIDUE'; END IF;
  END LOOP;
END $profile$;

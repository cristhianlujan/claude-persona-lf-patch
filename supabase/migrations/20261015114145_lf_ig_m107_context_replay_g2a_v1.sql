-- IG M10.7 G2A: material readback/tamper test with no edit to canonical sources.
-- This is a partial gate, not a two-session concurrency test or CP3 completion.
-- Single screen / temporary run; runtime changes are subtransaction rolled back.
DO $g2$
DECLARE
  v_code constant text:='IG-M107-CONTEXT-G2A-REPLAY-READBACK-011';
  v_original_sha constant text:='c0d4e5e8515e79343358fa1d490d0ca6';
  v_count integer;
  v_curator jsonb;
  v_run bigint;
  v_version bigint;
  v_component bigint;
  v_validator text;
  v_a jsonb;
  v_b jsonb;
  v_live jsonb;
  v_auth jsonb;
  v_decision jsonb;
  v_bad_source jsonb;
  v_bad_contract jsonb;
  v_bad_identity jsonb;
  v_bad_ref jsonb;
  v_positive boolean:=false;
  v_negative boolean:=false;
  v_sha text;
  v_payload jsonb;
  v_elapsed_ms bigint;
  v_start timestamptz;
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
  THEN RAISE EXCEPTION 'IG_M107_G2A_DUPLICATE_EKB'; END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_governance_run_context_packet_v1(bigint)'::regprocedure))
    IS DISTINCT FROM v_original_sha
  THEN RAISE EXCEPTION 'IG_M107_G2A_PROVIDER_SOURCE_DRIFT'; END IF;
  IF (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
  THEN RAISE EXCEPTION 'IG_M107_G2A_SCREEN_SAMPLE_CHANGED'; END IF;
  SELECT count(*) INTO v_count FROM programacion.input_readiness_runs WHERE pantalla_id=43;
  v_start:=clock_timestamp();
  BEGIN
    v_curator:=programacion.fn_input_governance_direct_step_v1(43,'MANUAL');
    IF v_curator->>'status'<>'VALIDATOR_RUNTIME_REQUIRED'
      OR v_curator->>'step'<>'CURATOR_MATERIALIZED'
    THEN RAISE EXCEPTION 'IG_M107_G2A_NO_CURATOR_SAMPLE'; END IF;
    v_run:=(v_curator->>'run_id')::bigint;
    SELECT version_id INTO STRICT v_version FROM programacion.input_readiness_runs
      WHERE id=v_run AND status='CURATING';
    v_validator:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
    SELECT id INTO STRICT v_component FROM programacion.componentes
      WHERE version_id=v_version AND componente_codigo='INPUT_VALIDATOR';
    UPDATE programacion.input_readiness_runs
      SET status='VALIDATING',validator_identity=v_validator,
          validator_component_id=v_component WHERE id=v_run;
    v_a:=programacion.fn_input_governance_run_context_packet_v1(v_run);
    -- Second independent invocation, same as a resumed validator chunk
    -- while no source has changed. No cache survives between calls.
    v_b:=programacion.fn_input_governance_run_context_packet_v1(v_run);
    IF v_a IS DISTINCT FROM v_b
      OR programacion.fn_v09_sha256_jsonb(v_a)
         IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_b)
      OR jsonb_array_length(v_a->'family_codes')<>47
    THEN RAISE EXCEPTION 'IG_M107_G2A_REPEATED_READBACK_NOT_EQUAL'; END IF;
    v_live:=programacion.fn_input_build_source_manifest(v_run);
    v_sha:=programacion.fn_v09_sha256_jsonb(
       programacion.fn_input_source_manifest_identity_v1(v_live));
    IF v_sha IS DISTINCT FROM v_b->>'source_manifest_identity_sha256'
    THEN RAISE EXCEPTION 'IG_M107_G2A_SOURCE_MANIFEST_NOT_EQUAL'; END IF;
    v_positive:=true;

    -- Synthetic stale/tampered packet variants. There is no consumer yet;
    -- equality is only a candidate admission proof, not full G2.
    v_bad_source:=jsonb_set(v_a,'{source_manifest_identity_sha256}',
      to_jsonb(repeat('0',64)),true);
    v_bad_contract:=jsonb_set(v_a,'{contract_snapshot_sha256}',
      to_jsonb(repeat('0',64)),true);
    v_bad_identity:=jsonb_set(v_a,'{run_id}',to_jsonb(v_run+1),true);
    v_bad_ref:=jsonb_set(v_a,'{distinct_family_source_refs}',
      '[]'::jsonb,true);
    IF v_bad_source IS NOT DISTINCT FROM v_b OR v_bad_contract IS NOT DISTINCT FROM v_b
       OR v_bad_identity IS NOT DISTINCT FROM v_b OR v_bad_ref IS NOT DISTINCT FROM v_b
    THEN RAISE EXCEPTION 'IG_M107_G2A_TAMPER_NOT_DETECTABLE'; END IF;

    -- Exercise the ACTUAL governed fail-closed decision helper against
    -- altered authority evidence, without changing any canonical table.
    v_auth:=programacion.fn_input_run_source_currentness_v1(v_run);
    IF v_auth#>>'{dimensions,source_manifest,current}'<>'true'
    THEN RAISE EXCEPTION 'IG_M107_G2A_BASELINE_AUTHORITY_NOT_CURRENT'; END IF;
    v_decision:=programacion.fn_input_governance_continuation_currentness_decide_v1(
      'VALIDATING',jsonb_set(v_auth,'{dimensions,source_manifest,current}','false'::jsonb,true));
    IF (v_decision->>'continuation_current')::boolean IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'IG_M107_G2A_STALE_MANIFEST_FALSE_PASS'; END IF;
    v_decision:=programacion.fn_input_governance_continuation_currentness_decide_v1(
      'VALIDATING',jsonb_set(v_auth,'{dimensions,readiness_contract,current}','false'::jsonb,true));
    IF (v_decision->>'continuation_current')::boolean IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'IG_M107_G2A_BAD_CONTRACT_FALSE_PASS'; END IF;
    v_decision:=programacion.fn_input_governance_continuation_currentness_decide_v1(
      'VALIDATING',jsonb_set(v_auth,'{dimensions,execution_policy,current}','false'::jsonb,true));
    IF (v_decision->>'continuation_current')::boolean IS DISTINCT FROM false
    THEN RAISE EXCEPTION 'IG_M107_G2A_BAD_POLICY_FALSE_PASS'; END IF;
    v_negative:=true;
    RAISE EXCEPTION 'IG_M107_G2A_EXPECTED_ROLLBACK' USING ERRCODE='PZ151';
  EXCEPTION WHEN SQLSTATE 'PZ151' THEN
    IF NOT (v_positive AND v_negative)
    THEN RAISE EXCEPTION 'IG_M107_G2A_ASSERTIONS_NOT_COMPLETE'; END IF;
  END;
  IF v_run IS NULL OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_run)
     OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_run)
     OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_run)
     OR (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_count
     OR (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
  THEN RAISE EXCEPTION 'IG_M107_G2A_RUNTIME_ROLLBACK_RESIDUE'; END IF;
  v_elapsed_ms:=round(extract(epoch from(clock_timestamp()-v_start))*1000);
  v_payload:=jsonb_build_object(
    'schema','IG_M107_G2A_REPLAY_READBACK_V1',
    'candidate_provider_md5',v_original_sha,
    'screen_id',43,'sample_run_rolled_back',v_run,
    'family_count',47,'repeat_call_json_equal',true,
    'repeat_call_sha_equal',true,
    'manifest_sha_live_equal',true,
    'synthetic_packet_tamper_variants_detectable',4,
    'actual_decider_negative_authority_dimensions',3,
    'all_runtime_changes_rolled_back',true,
    'source_tables_mutated',false,'two_session_concurrency_executed',false,
    'real_source_drift_executed',false,
    'downstream_validator_integrated',false,
    'cp3_pass',false,'measurement_scope','ONE_SCREEN_NON_PERFORMANCE',
    'elapsed_ms',v_elapsed_ms);
  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES(
    gen_random_uuid(),v_code,'GOVERNANCE',
    'G2A readback repetido y autoridad negativa sin modificar fuentes de negocio',
    'Prueba real: ejecucion temporal VALIDATING, dos llamadas independientes al G1, mismo JSON/sha y manifiesto de fuente; 4 variaciones sintéticas de paquete; 3 decisiones negativas sobre autoridad con el helper canónico. Todo el run vuelve por rollback. No se modifica regla de prevención ni otra fuente.',
    'Múltiples llamadas del Validator necesitan pin exacto y rechazo de autoridad alterada; no se debe acreditar una prueba sintética como concurrencia real.',
    'READBACK_EQUALITY_AND_AUTHORITY_FAIL_CLOSED',
    'G2B pendiente con dos sesiones, fuente fixture aislada, cambio real, y prueba negativa de contrato/identidad antes de consumidores. No activar G3 ni relajar 21 triggers, 246 reglas o controles de currentness.',
    'G2A acotado: positivo dos llamadas mismo origen; negativos fuente, contrato, política en decider; tamper JSON detectable; cero residuos. No prueba cambios entre transacciones ni tiempo del Validator.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    v_payload::text,clock_timestamp(),clock_timestamp(),
    'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'G2A readback two invocations plus synthetic negative, no canonical mutation',
    'programacion.fn_input_governance_run_context_packet_v1(bigint)'
  );
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
  THEN RAISE EXCEPTION 'IG_M107_G2A_EKB_READBACK_NOT_ONE'; END IF;
END $g2$;
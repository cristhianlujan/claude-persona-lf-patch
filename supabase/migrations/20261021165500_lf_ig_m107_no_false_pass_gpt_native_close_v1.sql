-- IG M10.7 NO_FALSE_PASS governed closure from exact GPT Native material execution.
-- Evidence: immutable native capture blob a62528e6c8a5db73b0f5e2a94aa1e1c94c37810a.
-- No production activation.

BEGIN;

DO $close$
DECLARE
  v_cp record;
  v_spec jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_capture_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/input_governance/M10_7_NO_FALSE_PASS_GPT_NATIVE_CAPTURE_V1.json#blob:a62528e6c8a5db73b0f5e2a94aa1e1c94c37810a';
  v_packet_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch@ffd3e4be01129e7700d035abdc9fde746952ef57/docs/programming-agent/input_governance/M10_7_NO_FALSE_PASS_GPT_NATIVE_EXECUTION_PACKET_V1.json#blob:4b7e1c84d7851b65fe8c4bef734538b2a795fc2c';
  v_result jsonb := jsonb_build_object(
    'evidence_ref', v_packet_ref,
    'observed', jsonb_build_object(
      'adversarial_case_executed', true,
      'budget_breach_count', 0,
      'frozen_run_ids', jsonb_build_array(930,931,944),
      'frozen_window_sha256', '5dfa11c2ab8b47e205c1e5a03b5f28a42c2cae969643443690c539cbb1e52466',
      'frozen_window_verified', true,
      'historical_receipt_sha256', '17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972',
      'known_false_pass_signals', 0,
      'sample_policy', 'RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1',
      'semantic_authority_bound', true,
      'test_exit_code', 0,
      'test_passed', true,
      'timeout_signal_count', 0,
      'unmeasured_duration_count', 0,
      'unresolved_d4', 0
    ),
    'schema_version', 'M10_7_NO_FALSE_PASS_RESULT_V2',
    'status', 'PASS',
    'suite_code', 'INPUT_GOVERNANCE_REGRESSION',
    'test_code', 'ENG_M10_7_NO_FALSE_PASS'
  );
BEGIN
  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478
    AND checkpoint_code='NO_FALSE_PASS'
  FOR UPDATE;

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_PRESTATE_DRIFT:%',row_to_json(v_cp);
  END IF;

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.7','NO_FALSE_PASS'
  );

  IF v_spec#>>'{test_execution_contract,execution_route,provider}' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_spec#>>'{test_execution_contract,execution_route,adapter_id}' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_spec#>>'{test_execution_contract,execution_route,conversation_scope}' IS DISTINCT FROM 'EXISTING_CONVERSATION_ONLY'
     OR v_spec#>>'{assertion_contract,pass_when,test_passed}' IS DISTINCT FROM 'true'
     OR v_spec#>>'{assertion_contract,pass_when,test_exit_code}' IS DISTINCT FROM '0'
     OR v_spec#>>'{assertion_contract,pass_when,budget_breach_count}' IS DISTINCT FROM '0'
     OR v_spec#>>'{assertion_contract,pass_when,timeout_signal_count}' IS DISTINCT FROM '0'
     OR v_spec#>>'{assertion_contract,pass_when,known_false_pass_signals}' IS DISTINCT FROM '0'
     OR v_spec#>>'{assertion_contract,pass_when,unresolved_d4}' IS DISTINCT FROM '0'
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_CONTRACT_DRIFT:%',v_spec;
  END IF;

  v_assertion := programacion.fn_engineering_checkpoint_assertion_record_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'NO_FALSE_PASS',
    v_result,
    'GPT_NATIVE:M10.7:NO_FALSE_PASS'
  );

  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR nullif(v_assertion->>'assertion_receipt_sha256','') IS NULL
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_packet_ref
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_ASSERTION_RECORD_FAIL:%',v_assertion;
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'NO_FALSE_PASS',
    'DONE',
    v_capture_ref,
    'GPT_NATIVE:M10.7:NO_FALSE_PASS',
    'Exact GPT Native material execution PASS. source main=ffd3e4be01129e7700d035abdc9fde746952ef57; test blob=635cf2bcae96712c6150c4accadcafe68296c257; test sha256=475e1a5981e0d356da17644c0d3c8c4a722c7044754305988e4ad8ff02a0b58a; input sha256=fb290a3aaea348a3ea64b098453f579e475256becad6cf205dd6a29e5f233aac; stdout sha256=689a532d5cb47a8bdad173f010164fcca658f722bf94a36e25c0f6949cdff18c; frozen window=5dfa11c2ab8b47e205c1e5a03b5f28a42c2cae969643443690c539cbb1e52466; runs=930,931,944; 47/47 each; durations=115551/120015/124635ms; 8 adversarial negatives rejected; 0 false PASS, 0 timeout, 0 D4, 0 unmeasured. Python process exit=0. Non-test artifact_tool startup warning on stderr recorded in capture and did not alter test exit/result.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_TRANSITION_FAIL:%',v_transition;
  END IF;
END
$close$;

UPDATE public.lf_error_knowledge
SET estado='RESUELTO',
    evidencia=coalesce(evidencia,'') ||
      ' | Resolved by PR native-route correction and material GPT Native NO_FALSE_PASS PASS; capture blob a62528e6c8a5db73b0f5e2a94aa1e1c94c37810a.',
    ultima_vez=now(),
    updated_at=now()
WHERE codigo='IG-M107-NATIVE-EXECUTOR-ROUTE-CORRECTION-044';

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M107-NO-FALSE-PASS-GPT-NATIVE-PASS-045',
  'VALIDATION',
  'M10.7 NO_FALSE_PASS cerrado con ejecución material GPT Native',
  'El verificador exacto ENG_M10_7_NO_FALSE_PASS fue ejecutado en GPT Native current context sobre fuente main congelada y paquete de entrada inmutable. La muestra 930/931/944 mantuvo currentness, 47/47 PASS por run, tiempos bajo 150s y cero señales de timeout/false-pass/D4.',
  'N/A: evidencia de cierre del checkpoint; no es una nueva causa raíz.',
  'GPT_NATIVE_EXACT_SOURCE_FROZEN_INPUT_MATERIAL_PASS',
  'Para cierres Native, congelar fuente e input, ejecutar el test exacto, persistir captura inmutable y registrar assertion receipt antes de la transición DONE. No sustituir con REMOTE_API/host ni autoatestación externa ficticia.',
  'PASS si assertion receipt valida el subconjunto canónico, capture blob es inmutable, NO_FALSE_PASS queda DONE y el bootstrap avanza exactamente a NEG_INSUFFICIENT con progreso ledger 65%.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'GPT Native capture blob a62528e6c8a5db73b0f5e2a94aa1e1c94c37810a; packet blob 4b7e1c84d7851b65fe8c4bef734538b2a795fc2c; source main ffd3e4be01129e7700d035abdc9fde746952ef57; test blob 635cf2bcae96712c6150c4accadcafe68296c257; stdout sha256 689a532d5cb47a8bdad173f010164fcca658f722bf94a36e25c0f6949cdff18c.',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.7 NO_FALSE_PASS material GPT Native closure',
  'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/input_governance/M10_7_NO_FALSE_PASS_GPT_NATIVE_CAPTURE_V1.json#blob:a62528e6c8a5db73b0f5e2a94aa1e1c94c37810a'
)
ON CONFLICT (codigo) DO UPDATE SET
  descripcion=excluded.descripcion,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

DO $postcheck$
DECLARE
  v_cp record;
  v_progress numeric;
  v_next text;
BEGIN
  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NO_FALSE_PASS';

  IF v_cp.status IS DISTINCT FROM 'DONE'
     OR v_cp.evidence_ref IS NULL
     OR v_cp.assertion_receipt_sha256 IS NULL
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_POSTCHECK_FAIL:%',row_to_json(v_cp);
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  IF v_progress IS DISTINCT FROM 65.00 THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_PROGRESS_FAIL:%',v_progress;
  END IF;

  SELECT c.checkpoint_code INTO v_next
  FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=478
    AND c.status NOT IN ('DONE','NOT_APPLICABLE')
  ORDER BY c.sequence_no
  LIMIT 1;

  IF v_next IS DISTINCT FROM 'NEG_INSUFFICIENT' THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_NEXT_FAIL:%',v_next;
  END IF;
END
$postcheck$;

COMMIT;

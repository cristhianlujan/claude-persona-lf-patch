-- IG M10.7 NEG_INSUFFICIENT governed closure from exact GPT Native material execution.
-- Capture blob: b851895a62cda7e569d4586f1d740b59483ee837.
-- No production activation.

BEGIN;

DO $close$
DECLARE
  v_cp record;
  v_spec jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_capture_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/input_governance/M10_7_NEG_INSUFFICIENT_GPT_NATIVE_CAPTURE_V1.json#blob:b851895a62cda7e569d4586f1d740b59483ee837';
  v_packet_ref constant text :=
    'github://cristhianlujan/claude-persona-lf-patch@57d9422713ef8ef6ecc6e543c6a555d0c565d7fd/docs/programming-agent/input_governance/M10_7_NEG_INSUFFICIENT_GPT_NATIVE_EXECUTION_PACKET_V1.json#blob:e902803d68f0b513945f00317997dc7a5f167661';
  v_result jsonb := jsonb_build_object(
    'evidence_ref', v_packet_ref,
    'observed', jsonb_build_object(
      'adversarial_case_executed', true,
      'historical_receipt_sha256', '17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972',
      'insufficient_window_rejected', true,
      'negative_cases_executed', 8,
      'negative_cases_rejected', jsonb_build_array(
        'screen_coverage',
        'family_coverage',
        'screen_observation_depth',
        'family_observation_depth',
        'known_false_pass',
        'unresolved_d4',
        'timeout_over_150s',
        'missing_required_coverage_field'
      ),
      'positive_control_admitted', true,
      'semantic_authority_bound', true,
      'test_exit_code', 0,
      'test_passed', true,
      'thresholds', jsonb_build_object(
        'max_false_pass', 0,
        'max_timeout_over_150s', 0,
        'max_unresolved_d4', 0,
        'min_families', 47,
        'min_observations', 2,
        'min_screens', 13
      )
    ),
    'schema_version', 'M10_7_NEG_INSUFFICIENT_RESULT_V1',
    'status', 'PASS',
    'suite_code', 'INPUT_GOVERNANCE_REGRESSION',
    'test_code', 'ENG_M10_7_NEG_INSUFFICIENT'
  );
BEGIN
  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478
    AND checkpoint_code='NEG_INSUFFICIENT'
  FOR UPDATE;

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_PRESTATE_DRIFT:%',row_to_json(v_cp);
  END IF;

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.7','NEG_INSUFFICIENT'
  );

  IF v_spec#>>'{test_execution_contract,execution_route,provider}' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_spec#>>'{test_execution_contract,execution_route,adapter_id}' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_spec#>>'{test_execution_contract,execution_route,conversation_scope}' IS DISTINCT FROM 'EXISTING_CONVERSATION_ONLY'
     OR v_spec#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'false'
     OR v_spec#>>'{test_execution_contract,test_code}' IS DISTINCT FROM 'ENG_M10_7_NEG_INSUFFICIENT'
     OR v_spec#>>'{assertion_contract,pass_when,test_passed}' IS DISTINCT FROM 'true'
     OR v_spec#>>'{assertion_contract,pass_when,test_exit_code}' IS DISTINCT FROM '0'
     OR v_spec#>>'{assertion_contract,pass_when,semantic_authority_bound}' IS DISTINCT FROM 'true'
     OR v_spec#>>'{assertion_contract,pass_when,adversarial_case_executed}' IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_CONTRACT_DRIFT:%',v_spec;
  END IF;

  v_assertion := programacion.fn_engineering_checkpoint_assertion_record_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'NEG_INSUFFICIENT',
    v_result,
    'GPT_NATIVE:M10.7:NEG_INSUFFICIENT'
  );

  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR nullif(v_assertion->>'assertion_receipt_sha256','') IS NULL
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_packet_ref
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_ASSERTION_RECORD_FAIL:%',v_assertion;
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'NEG_INSUFFICIENT',
    'DONE',
    v_capture_ref,
    'GPT_NATIVE:M10.7:NEG_INSUFFICIENT',
    'Exact GPT Native material execution PASS. frozen source=838a9055053be01a690525b89895ef573200d064; test blob=9b0bffa9c3b1569c5e4cdc92cdc36b23ac21c9d0; test sha256=b7665117ae2967a147891aa685b81e8200182a7174eae3957b51005e86d4b4b7; packet blob=e902803d68f0b513945f00317997dc7a5f167661; input sha256=79b25c56447b3bd82f4c646d18ee522c7ecbbe80e3d17636cac22b870ed4babb; stdout sha256=419878a8ae885398905f4bb17968621eed26b3cf53f09d217eda022834ab54a4; process exit=0; positive control admitted; 8/8 insufficient/adversarial windows rejected. Non-test artifact_tool startup warning on stderr recorded in capture and did not alter test exit/result.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_TRANSITION_FAIL:%',v_transition;
  END IF;
END
$close$;

UPDATE public.lf_error_knowledge
SET estado='RESUELTO',
    evidencia=coalesce(evidencia,'') ||
      ' | Resolved by exact GPT Native NEG_INSUFFICIENT PASS; capture blob b851895a62cda7e569d4586f1d740b59483ee837.',
    ultima_vez=now(),
    updated_at=now()
WHERE codigo='IG-M107-NEG-INSUFFICIENT-ACL-NATIVE-BIND-046';

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M107-NEG-INSUFFICIENT-GPT-NATIVE-PASS-047',
  'VALIDATION',
  'M10.7 NEG_INSUFFICIENT cerrado con ejecución material GPT Native',
  'El verificador exacto ENG_M10_7_NEG_INSUFFICIENT ejecutó un control positivo y ocho casos insuficientes/adversariales. Todos los negativos fueron rechazados: cobertura 12/13, 46/47 familias, profundidad <2 por pantalla y familia, false PASS, D4, timeout >150s y campo requerido ausente.',
  'N/A: evidencia de cierre del checkpoint negativo.',
  'GPT_NATIVE_INSUFFICIENT_WINDOW_FAIL_CLOSED_PASS',
  'Para probar suficiencia de soak, reutilizar el recibo histórico verificado como autoridad de umbrales y demostrar explícitamente que cada degradación material no puede producir cierre. No elevar permisos ni sustituir con currentness inferida.',
  'PASS si el control positivo es admitido, los 8 negativos son rechazados, assertion receipt es válido, NEG_INSUFFICIENT queda DONE y el progreso ledger de M10.7 pasa exactamente a 80%.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'GPT Native capture blob b851895a62cda7e569d4586f1d740b59483ee837; packet blob e902803d68f0b513945f00317997dc7a5f167661; source 838a9055053be01a690525b89895ef573200d064; test blob 9b0bffa9c3b1569c5e4cdc92cdc36b23ac21c9d0; stdout sha256 419878a8ae885398905f4bb17968621eed26b3cf53f09d217eda022834ab54a4.',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.7 NEG_INSUFFICIENT material GPT Native closure',
  'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/input_governance/M10_7_NEG_INSUFFICIENT_GPT_NATIVE_CAPTURE_V1.json#blob:b851895a62cda7e569d4586f1d740b59483ee837'
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
  WHERE work_item_id=478 AND checkpoint_code='NEG_INSUFFICIENT';

  IF v_cp.status IS DISTINCT FROM 'DONE'
     OR v_cp.evidence_ref IS NULL
     OR v_cp.assertion_receipt_sha256 IS NULL
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_POSTCHECK_FAIL:%',row_to_json(v_cp);
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  IF v_progress IS DISTINCT FROM 80.00 THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_PROGRESS_FAIL:%',v_progress;
  END IF;

  SELECT c.checkpoint_code INTO v_next
  FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=478
    AND c.status NOT IN ('DONE','NOT_APPLICABLE')
  ORDER BY c.sequence_no
  LIMIT 1;

  IF v_next IS DISTINCT FROM 'SOAK_RECEIPT' THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_NEXT_FAIL:%',v_next;
  END IF;
END
$postcheck$;

COMMIT;

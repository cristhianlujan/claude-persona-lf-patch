-- IG M10.7 NEG_INSUFFICIENT: bind exact authored test to GPT Native
-- and replace an ACL-denied currentness query with the verified M9.11 soak receipt.
-- No checkpoint closure. No production activation. No remote API or host execution.

BEGIN;

DO $preflight$
DECLARE
  v_spec jsonb;
  v_cp record;
  v_progress numeric;
BEGIN
  SELECT unit_metadata#>'{action_specs_v1,NEG_INSUFFICIENT}'
    INTO v_spec
  FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.7'
    AND disposition='ASSIGNED';

  IF v_spec IS NULL THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_SPEC_MISSING';
  END IF;

  IF v_spec#>>'{test_execution_contract,test_code}' IS DISTINCT FROM 'ENG_M10_7_NEG_INSUFFICIENT'
     OR v_spec#>>'{test_execution_contract,test_path}' IS DISTINCT FROM
        'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/neg_insufficient.py'
     OR v_spec#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'true'
     OR v_spec#>'{test_execution_contract,execution_route}' IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_PREIMAGE_DRIFT:%',v_spec;
  END IF;

  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NEG_INSUFFICIENT';

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_CP_PRESTATE_DRIFT:%',row_to_json(v_cp);
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  IF v_progress IS DISTINCT FROM 65.00 THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_PROGRESS_PRESTATE_DRIFT:%',v_progress;
  END IF;
END
$preflight$;

UPDATE programacion.engineering_plan_units
SET unit_metadata =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            unit_metadata,
            '{action_specs_v1,NEG_INSUFFICIENT,test_execution_contract,authoring_required}',
            'false'::jsonb,
            true
          ),
          '{action_specs_v1,NEG_INSUFFICIENT,test_execution_contract,execution_route}',
          jsonb_build_object(
            'provider','GPT_NATIVE',
            'adapter_id','chatgpt-native-current-context-v1',
            'conversation_scope','EXISTING_CONVERSATION_ONLY'
          ),
          true
        ),
        '{action_specs_v1,NEG_INSUFFICIENT,test_execution_contract,declared_objects}',
        jsonb_build_array('programacion.provenance_receipts'),
        true
      ),
      '{action_specs_v1,NEG_INSUFFICIENT,test_execution_contract,declared_queries}',
      jsonb_build_array(
        'select id,receipt_kind,subject_type,subject_ref,issuer_identity,verification_ref,payload,receipt_sha256,created_at from programacion.provenance_receipts where id=38'
      ),
      true
    ),
    '{action_specs_v1,NEG_INSUFFICIENT,verification_queries}',
    jsonb_build_array(
      'select id,receipt_kind,subject_type,subject_ref,issuer_identity,verification_ref,payload,receipt_sha256,created_at from programacion.provenance_receipts where id=38'
    ),
    true
  )
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND unit_code='M10.7'
  AND disposition='ASSIGNED';

UPDATE programacion.engineering_plan_units
SET unit_metadata = jsonb_set(
  unit_metadata,
  '{action_specs_v1,NEG_INSUFFICIENT,target,declared_objects}',
  jsonb_build_array('programacion.provenance_receipts'),
  true
)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND unit_code='M10.7'
  AND disposition='ASSIGNED';

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M107-NEG-INSUFFICIENT-ACL-NATIVE-BIND-046',
  'GOVERNANCE',
  'M10.7 NEG_INSUFFICIENT: source query no ejecutable y runner Native no enlazado',
  'El checkpoint NEG_INSUFFICIENT declaraba fn_input_readiness_run_is_current en una query que el rol read-only no puede ejecutar (SQLSTATE 42501) y no tenía execution_route, aunque el objetivo negativo sólo necesita los umbrales certificados por M9.11.',
  'El source pack histórico reutilizó una query de currentness que no corresponde a la semántica del negativo y quedó sin alinear con GPT_NATIVE después de autorar el test.',
  'ACL_DENIED_IRRELEVANT_CURRENTNESS_QUERY_PLUS_UNBOUND_NATIVE_EXECUTOR',
  'No elevar EXECUTE ni inferir currentness con status/invalidated_at. Para este negativo usar el recibo VERIFIED SOAK_OBSERVATION_HISTORY_V2 como autoridad de 13/47/>=2/false-pass/D4 y GPT_NATIVE current context como executor.',
  'PASS cuando el packet compila RUN_TEST GPT_NATIVE, remote_api_fallback y host_execution quedan FORBIDDEN, la única lectura es provenance_receipts/38, checkpoint permanece PENDING y progreso sigue 65%.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'Read-only connector reproduced SQLSTATE 42501 on fn_input_readiness_run_is_current. Test artifact merged by PR #3029 at main 5baad36d3eab69e164e4e73b1bcd7cf52b909b54.',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.7 NEG_INSUFFICIENT exact native binding',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7'
)
ON CONFLICT (codigo) DO UPDATE SET
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

DO $postcheck$
DECLARE
  v_spec jsonb;
  v_packet jsonb;
  v_cp record;
  v_progress numeric;
BEGIN
  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.7','NEG_INSUFFICIENT'
  );

  IF v_spec#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'false'
     OR v_spec#>>'{test_execution_contract,execution_route,provider}' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_spec#>>'{test_execution_contract,execution_route,adapter_id}' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_spec#>>'{test_execution_contract,execution_route,conversation_scope}' IS DISTINCT FROM 'EXISTING_CONVERSATION_ONLY'
     OR v_spec#>>'{test_execution_contract,declared_objects,0}' IS DISTINCT FROM 'programacion.provenance_receipts'
     OR v_spec#>>'{test_execution_contract,declared_queries,0}' NOT LIKE '%provenance_receipts where id=38%'
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_SPEC_READBACK_FAIL:%',v_spec;
  END IF;

  v_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'NEG_INSUFFICIENT',
    v_spec,
    '{}'::jsonb
  );

  IF v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_allowed' IS DISTINCT FROM 'true'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
     OR v_packet#>>'{connector_plan,0,provider}' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_packet#>>'{connector_plan,0,runner_contract,adapter_id}' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR v_packet#>>'{connector_plan,0,runner_contract,remote_api_fallback}' IS DISTINCT FROM 'FORBIDDEN'
     OR v_packet#>>'{connector_plan,0,runner_contract,host_execution}' IS DISTINCT FROM 'FORBIDDEN'
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_PACKET_FAIL:%',v_packet;
  END IF;

  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NEG_INSUFFICIENT';

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
     OR v_progress IS DISTINCT FROM 65.00
  THEN
    RAISE EXCEPTION 'M107_NEG_INSUFFICIENT_FALSE_CLOSURE:%/%',row_to_json(v_cp),v_progress;
  END IF;
END
$postcheck$;

COMMIT;

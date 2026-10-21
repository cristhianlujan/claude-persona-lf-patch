-- M10.7 / NO_FALSE_PASS: bind the already-authored exact checkpoint test
-- to the previously authorized SentinelX execution host.
-- No checkpoint closure, no production activation, no runtime mutation.
BEGIN;

DO $preflight$
DECLARE
  v_spec jsonb;
  v_cp record;
BEGIN
  SELECT unit_metadata#>'{action_specs_v1,NO_FALSE_PASS}'
    INTO v_spec
  FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.7'
    AND disposition='ASSIGNED';

  IF v_spec IS NULL THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_ACTION_SPEC_MISSING';
  END IF;

  IF v_spec#>>'{test_execution_contract,test_code}' IS DISTINCT FROM 'ENG_M10_7_NO_FALSE_PASS'
     OR v_spec#>>'{test_execution_contract,test_path}' IS DISTINCT FROM
        'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py'
     OR v_spec#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'true'
     OR v_spec#>'{test_execution_contract,execution_route}' IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_PREIMAGE_DRIFT:%', v_spec;
  END IF;

  SELECT status,evidence_ref,assertion_receipt
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NO_FALSE_PASS';

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt IS NOT NULL
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_CHECKPOINT_PRESTATE_DRIFT:%', row_to_json(v_cp);
  END IF;
END
$preflight$;

UPDATE programacion.engineering_plan_units
SET unit_metadata =
  jsonb_set(
    jsonb_set(
      unit_metadata,
      '{action_specs_v1,NO_FALSE_PASS,test_execution_contract,authoring_required}',
      'false'::jsonb,
      true
    ),
    '{action_specs_v1,NO_FALSE_PASS,test_execution_contract,execution_route}',
    jsonb_build_object(
      'provider','SENTINELX',
      'host_id','host_3d5ff6fb467d4e9e'
    ),
    true
  )
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND unit_code='M10.7'
  AND disposition='ASSIGNED';

DO $postcheck$
DECLARE
  v_spec jsonb;
  v_packet jsonb;
  v_ops text[];
  v_progress numeric;
  v_cp_status text;
BEGIN
  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.7','NO_FALSE_PASS'
  );

  IF v_spec#>>'{test_execution_contract,authoring_required}' IS DISTINCT FROM 'false'
     OR v_spec#>>'{test_execution_contract,execution_route,provider}' IS DISTINCT FROM 'SENTINELX'
     OR v_spec#>>'{test_execution_contract,execution_route,host_id}' IS DISTINCT FROM 'host_3d5ff6fb467d4e9e'
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_BINDING_READBACK_FAIL:%', v_spec;
  END IF;

  v_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.7',
    'NO_FALSE_PASS',
    v_spec,
    '{}'::jsonb
  );

  SELECT array_agg(x.value->>'operation' ORDER BY x.ordinality)
    INTO v_ops
  FROM jsonb_array_elements(coalesce(v_packet->'connector_plan','[]'::jsonb))
       WITH ORDINALITY x(value,ordinality);

  IF v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_allowed' IS DISTINCT FROM 'true'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
     OR v_packet->>'capability_mode' IS DISTINCT FROM 'RUN_EXISTING_DECLARED_CHECKPOINT_TEST'
     OR v_ops IS DISTINCT FROM ARRAY['RUN_TEST','CHECKPOINT_ASSERTION_RECORD','CHECKPOINT_TRANSITION']::text[]
     OR v_packet#>>'{connector_plan,0,provider}' IS DISTINCT FROM 'SENTINELX'
     OR v_packet#>>'{connector_plan,0,runner_contract,host_id}' IS DISTINCT FROM 'host_3d5ff6fb467d4e9e'
     OR v_packet#>>'{connector_plan,0,source_contract,ref_mode}' IS DISTINCT FROM 'EXACT_MERGED_SHA'
     OR v_packet#>>'{connector_plan,0,runner_contract,actual_execution_required}' IS DISTINCT FROM 'true'
     OR v_packet#>>'{connector_plan,0,runner_contract,synthetic_pass}' IS DISTINCT FROM 'FORBIDDEN'
  THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_EXECUTION_PACKET_FAIL:%', v_packet;
  END IF;

  SELECT status INTO v_cp_status
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=478 AND checkpoint_code='NO_FALSE_PASS';

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=478;

  IF v_cp_status IS DISTINCT FROM 'PENDING' OR v_progress IS DISTINCT FROM 45.00 THEN
    RAISE EXCEPTION 'M107_NO_FALSE_PASS_FALSE_CLOSURE:%/%',v_cp_status,v_progress;
  END IF;
END
$postcheck$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M107-NO-FALSE-PASS-RUNNER-BINDING-043',
  'GOVERNANCE',
  'M10.7 NO_FALSE_PASS: artefacto autorado pero executor no enlazado',
  'Tras integrar el verificador material NO_FALSE_PASS por Train, el action spec seguía authoring_required=true y sin execution_route, por lo que el packet repetía WRITE_GIT y bloqueaba RUN_TEST aunque el artefacto ya existía en main.',
  'El contrato de checkpoint no había sido actualizado después de la autoría gobernada del artefacto y el resolver fail-closed exige un provider explícito.',
  'AUTHORED_TEST_WITH_STALE_AUTHORING_FLAG_AND_UNBOUND_EXECUTOR',
  'Después de mergear el artefacto exacto, cambiar sólo ese checkpoint a authoring_required=false y enlazar un runner previamente autorizado. No crear workflow nuevo, no reutilizar un workflow que no ejecute el test y no aceptar self-test/local como evidencia material.',
  'PASS cuando el packet compila RUN_EXISTING_DECLARED_CHECKPOINT_TEST con SENTINELX host_3d5ff6fb467d4e9e, exact merged SHA, ejecución real obligatoria, assertion receipt posterior y checkpoint aún PENDING hasta dicha ejecución.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'PR #3017 / main 4b1b20864177267f370d7f5b9efafe6424872bc1 materializó no_false_pass.py; esta migración sólo corrige el binding de ejecución y prueba que M10.7 permanece 45%.',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.7 NO_FALSE_PASS exact authored-test runner binding',
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

COMMIT;

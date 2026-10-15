-- PE10_C3 V3: materialize the missing JSON ancestor for checkpoint execution input.
-- Contract, governance, and policy otherwise unchanged. No cutover or fake assurance.
BEGIN;
DO $fix$
DECLARE
  v_meta jsonb;
  v_pack jsonb;
  v_query jsonb;
  v_w bigint;
BEGIN
  SELECT unit_metadata,work_item_id INTO STRICT v_meta,v_w
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10' FOR UPDATE;

  IF v_meta ? 'source_pack_v2'
     OR v_meta#>>'{action_specs_v1,PE10_C3,status}' IS DISTINCT FROM 'READY'
     OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,receipt_status}'
        IS DISTINCT FROM 'NOT_PROVEN_AT_PUBLICATION'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_w AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
  THEN RAISE EXCEPTION 'PE10_C3_SOURCE_PACK_V3_PRESTATE_DRIFT'; END IF;

  v_query:=v_meta#>'{action_specs_v1,PE10_C3,verification_queries}';
  IF jsonb_typeof(v_query) IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_query)<>1
  THEN RAISE EXCEPTION 'PE10_C3_DECLARED_READBACK_QUERY_MISSING'; END IF;

  v_pack:=jsonb_build_object(
    'checkpoint_code','PE10_C3',
    'execution_kind','READBACK_ONCE',
    'validator_code','PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1',
    'expected_result','INDEPENDENT_ASSURANCE_PASS_WITH_BOUND_SUBJECT_AND_EXACT_RECEIPT',
    'inputs',jsonb_build_object(
      'queries',v_query,
      'db_objects',jsonb_build_array(
        'public.lf_capability_registry','public.lf_capability_current',
        'public.lf_assurance_subject_bindings','public.lf_assurance_evaluations',
        'programacion.engineering_work_checkpoints'),
      'artifacts',jsonb_build_array(
        'skills/profile_creator/evals/results/pe10e_pilot_001_qualitative_acceptance_v1.json'),
      'events','[]'::jsonb,'assets','[]'::jsonb));

  -- jsonb_set cannot create multiple absent path ancestors.
  v_meta:=jsonb_set(v_meta,'{source_pack_v2}',
    jsonb_build_object('checkpoint_inputs',jsonb_build_object('PE10_C3',v_pack)),true);

  IF jsonb_typeof(v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}')<>'object'
     OR jsonb_array_length(v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3,inputs,queries}')<>1
  THEN RAISE EXCEPTION 'PE10_C3_SOURCE_PACK_V3_LOCAL_ASSERT_FAIL'; END IF;

  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
END $fix$;

INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE10-C3-JSONB-PARENT-MISSING-20261012-001','PROFILE_EVOLUTION',
 'jsonb_set nested path did not create source_pack_v2 parent',
 'PE10_C3 source pack remained null after previous transaction succeeded.',
 'jsonb_set(...,{source_pack_v2,checkpoint_inputs,PE10_C3},...,true) does not create the missing intermediate ancestors.',
 'JSONB nested path update looks valid but silently fails when parent does not exist.',
 'Create the source_pack_v2 ancestor as a whole object before assigning checkpoint_inputs; verify direct JSON path and external bootstrap readback.',
 'Positive: direct source_pack_v2 input has one query; bootstrap execution_input_origin=SOURCE_PACK_V2_CHECKPOINT; negative: PE10_C3 stays IN_PROGRESS pending real independent assurance receipt.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C3','ACTIVO',
 'supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-PE10-C3-JSONB-PARENT-MISSING-20261012-001');
COMMIT;

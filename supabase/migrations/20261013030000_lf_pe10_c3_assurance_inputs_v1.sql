-- PE10_C3: restore missing source inputs for independent cutover assurance.
-- Does NOT certify assurance, complete the checkpoint, authorize cutover or alter active policy.
-- Uses existing INDEPENDENT_ASSURANCE / ASSURANCE_EVALUATOR capabilities, SUPER_ADMIN authority.
BEGIN;
DO $pe$
DECLARE
  v_meta jsonb;
  v_work bigint;
  v_spec jsonb;
  v_probe text;
  v_pack jsonb;
  v_boot jsonb;
BEGIN
  SELECT unit_metadata,work_item_id INTO STRICT v_meta,v_work
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10' FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code='PE10_C3' AND status='IN_PROGRESS')<>1
    OR v_meta#>>'{action_specs_v1,PE10_C3,action_kind}' IS DISTINCT FROM 'READBACK_ONCE'
    OR v_meta#>'{source_pack_v2,checkpoint_inputs,PE10_C3}' IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_C3_CONTRACT_PRESTATE_DRIFT'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
      WHERE capability_code='INDEPENDENT_ASSURANCE'
      AND status='ACTIVE' AND owner_scope='SUPER_ADMIN'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
      WHERE capability_code='ASSURANCE_EVALUATOR'
      AND status='ACTIVE' AND owner_scope='SUPER_ADMIN'
  ) THEN RAISE EXCEPTION 'PE10_C3_TRANSVERSAL_CAPABILITY_NOT_ACTIVE'; END IF;

  v_probe:=$sql$select
    (select count(*) from public.lf_capability_registry r join public.lf_capability_current c
       on c.capability_code=r.capability_code
     where r.capability_code='INDEPENDENT_ASSURANCE'
       and r.status='ACTIVE' and r.owner_scope='SUPER_ADMIN')=1 as independent_capability_current,
    (select count(*) from public.lf_capability_registry r join public.lf_capability_current c
       on c.capability_code=r.capability_code
     where r.capability_code='ASSURANCE_EVALUATOR'
       and r.status='ACTIVE' and r.owner_scope='SUPER_ADMIN')=1 as evaluator_current,
    (select count(*) from public.lf_assurance_subject_bindings b
     where b.subject_type='OPERATION' and b.subject_code='ACTUALIZACION_PERFIL_LF'
       and b.status='ACTIVE' and b.required) as active_profile_assurance_bindings,
    (select count(*) from public.lf_assurance_evaluations e
     where e.subject_type='OPERATION' and e.subject_code='ACTUALIZACION_PERFIL_LF'
       and e.result='PASS') as profile_assurance_pass_evaluations,
    (select count(*) from programacion.engineering_work_checkpoints c
       join programacion.engineering_plan_units u on u.work_item_id=c.work_item_id
     where u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
       and u.unit_code='PE10E' and c.checkpoint_code='PE10E_C4'
       and c.status='DONE'
       and c.assertion_receipt#>>'{status}'='ACCEPTED_QUALITATIVE_FIRST_EVOLUTION')=1
      as first_evolution_accepted
$sql$;

  v_pack:=jsonb_build_object(
    'checkpoint_code','PE10_C3',
    'execution_kind','READBACK_ONCE',
    'verification_role','SOURCE_AUDIT_ONLY_NOT_INDEPENDENT_CERTIFICATION',
    'inputs',jsonb_build_object(
      'queries',jsonb_build_array(v_probe),
      'db_objects',jsonb_build_array(
        'public.lf_capability_registry','public.lf_capability_current',
        'public.lf_assurance_subject_bindings','public.lf_assurance_evaluations',
        'programacion.engineering_work_checkpoints'),
      'artifacts',jsonb_build_array(
        'skills/profile_creator/evals/results/pe10e_pilot_001_qualitative_acceptance_v1.json'),
      'assets','[]'::jsonb,'events','[]'::jsonb),
    'validator_code','PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1',
    'expected_result','INDEPENDENT_ASSURANCE_PASS_WITH_BOUND_SUBJECT_AND_EXACT_RECEIPT');

  v_spec:=v_meta#>'{action_specs_v1,PE10_C3}' ||
    jsonb_build_object(
      'status','READY',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'verification_queries',jsonb_build_array(v_probe),
      'requires_material_execution',false,
      'phase_classification','INDEPENDENT_CUTOVER_ASSURANCE_ONLY',
      'missing_receipt_action','OBTAIN_EXISTING_INDEPENDENT_ASSURANCE_RECEIPT_NOT_SELF_ASSERT_PASS',
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'assurance','PASS',
          'independent',true,
          'subject_type','OPERATION',
          'subject_code','ACTUALIZACION_PERFIL_LF',
          'critical_regressions',0,
          'provenance_attested',true)),
      'validator_contract',jsonb_build_object(
        'required',true,
        'validator_code','PROFILE_EVOLUTION_BENCHMARK_ADMISSION_V1',
        'pass_when','A real current subject-bound independent cutover assurance receipt is PASS, exact source and policy are matched; merely having ACTIVE capability or a positive pilot is insufficient',
        'failure_code','INDEPENDENT_CUTOVER_ASSURANCE_NOT_YET_ATTESTED',
        'resolver_policy','CONSUME_EXISTING_INDEPENDENT_ASSURANCE_WITH_SUBJECT_ADAPTER'),
      'forbidden',jsonb_build_array(
        'SELF_JUDGE','CLAIM_PILOT_AS_CUTOVER_ASSURANCE',
        'AUTO_ACTIVATE_V02','SKIP_SUBJECT_BINDING'));

  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C3}',v_spec,true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v2,checkpoint_inputs,PE10_C3}',v_pack,true);
  v_meta:=jsonb_set(v_meta,'{phase_separation_v1,independent_cutover_assurance}',
    jsonb_build_object(
      'provider_capability','INDEPENDENT_ASSURANCE',
      'evaluator_capability','ASSURANCE_EVALUATOR',
      'owner','SUPER_ADMIN','subject_type','OPERATION',
      'subject_code','ACTUALIZACION_PERFIL_LF',
      'receipt_status','NOT_PROVEN_AT_PUBLICATION',
      'not_equivalent_to_first_evolution_acceptance',true,
      'operational_cutover_allowed',false),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';

  UPDATE programacion.engineering_work_items
     SET acceptance_criteria=(SELECT jsonb_agg(
        case when x.value LIKE 'PE10_C3:%' then
          to_jsonb('PE10_C3: exact current subject-bound independent assurance receipt PASS with provenance, not an inference from active capability or phase-one pilot'::text)
          else to_jsonb(x.value) end order by x.ordinality)
          FROM jsonb_array_elements_text(acceptance_criteria)
           with ordinality x(value,ordinality))
  WHERE id=v_work;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10');
  IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'PE10_C3'
     OR v_boot#>>'{execution_packet,status}' IS DISTINCT FROM 'READY'
     OR v_boot->>'terminal_action'='STOP_MISSING_EXECUTION_INPUT'
     OR v_boot->'execution_input' IS NULL THEN
    RAISE EXCEPTION 'PE10_C3_SOURCE_PACK_NOT_OPERATIONAL: %',v_boot->>'terminal_action';
  END IF;
END $pe$;

INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE10-C3-INDEPENDENT-INPUT-MISSING-20261012-001','PROFILE_EVOLUTION',
 'PE10_C3 lacked explicit independent assurance input',
 'The checkpoint was stuck at STOP_MISSING_EXECUTION_INPUT; transversal capabilities exist but have no Profile Updater subject binding or evaluation in the observed tables.',
 'Action spec declared READBACK_ONCE but no exact source pack/verification query; independent assurance was not invoked or evidenced.',
 'Nonmaterial checkpoint masquerades as ready without declared input.',
 'Define a subject-scoped evidence readback using the existing INDEPENDENT_ASSURANCE capability and keep missing independent receipt as an explicit fail-closed cutover gate.',
 'Positive: bootstrap execution_input is non-null and packet READY; negative: first-release pilot and ACTIVE capability alone do not close PE10_C3; v0.2 remains inactive.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C3','ACTIVO',
 'supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='LF-PE10-C3-INDEPENDENT-INPUT-MISSING-20261012-001');
COMMIT;

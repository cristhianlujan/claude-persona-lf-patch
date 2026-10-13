-- PE10E_C4: user-accepted first-evolution comparative pilot; qualitative scope only.
-- Via LF Migration Merge Train. No production/cutover or expert certification.
BEGIN;
DO $pe10e$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_w bigint;
  v_pe10 bigint;
  v_unit jsonb;
  v_gov jsonb;
  v_spec jsonb;
  v_ev jsonb;
  v_query text;
  v_pre jsonb;
  v_tr jsonb;
  v_post jsonb;
BEGIN
  SELECT work_item_id,unit_metadata INTO STRICT v_w,v_unit
    FROM programacion.engineering_plan_units
    WHERE plan_code=v_plan AND unit_code='PE10E' FOR UPDATE;
  SELECT work_item_id,unit_metadata INTO STRICT v_pe10,v_gov
    FROM programacion.engineering_plan_units
    WHERE plan_code=v_plan AND unit_code='PE10' FOR UPDATE;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w AND checkpoint_code='PE10E_C4'
        AND sequence_no=5 AND status='PENDING')<>1
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w AND checkpoint_code='PE10E_C3B' AND status='DONE')<>1
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_pe10 AND checkpoint_code='PE10_C3' AND status='IN_PROGRESS')<>1
    OR v_unit#>>'{action_specs_v1,PE10E_C4,status}' IS DISTINCT FROM 'BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'
    OR v_unit#>>'{first_evolution_acceptance_v2,status}' IS DISTINCT FROM 'ACCEPTED_CODE_ONLY'
    OR jsonb_array_length(coalesce(v_unit#>'{first_evolution_acceptance_v2,git_receipts}','[]'::jsonb))<>9
    OR v_unit ? 'pilot_001_acceptance_v1'
  THEN RAISE EXCEPTION 'PE10E_C4_PRESTATE_DRIFT'; END IF;

  v_ev:=jsonb_build_object(
    'schema','PROFILE_EVOLUTION_FIRST_RELEASE_COMPARATIVE_ACCEPTANCE_V1',
    'status','ACCEPTED_QUALITATIVE_FIRST_EVOLUTION',
    'test_id','PE10E_PILOT_001',
    'evidence_path','skills/profile_creator/evals/results/pe10e_pilot_001_qualitative_acceptance_v1.json',
    'raw_upload_sha256','c6cb9837ca287c121359ffc20f435cadafcddcd3418be8c4af557265d38f1515',
    'merged_profile_count',9,
    'original_commit','ff0e48bc870b48c7ea645c79544ed5b083a75720',
    'evolved_commit','2b4dec92cfc925208014fb0bc9e708799078f5b5',
    'original_response','Y','evolved_response','X',
    'original_requirements_observed',2,'evolved_requirements_observed',5,
    'user_review','ACCEPTED',
    'no_fabricated_cause',true,
    'model_isolation_verified',false,
    'provider_execution_receipts_present',false,
    'independent_semantic_judge_executed',false,
    'normal_runtime_projection_executed',false,
    'statistical_expertise_certified',false,
    'four_arm_120_case_benchmark_executed',false,
    'operational_cutover_allowed',false);

  v_query:='select (unit_metadata#>>''{pilot_001_acceptance_v1,status}''=''ACCEPTED_QUALITATIVE_FIRST_EVOLUTION'') as acceptance, '
    ||'(jsonb_array_length(unit_metadata#>''{first_evolution_acceptance_v2,git_receipts}'')=9) as nine_merges '
    ||'from programacion.engineering_plan_units where plan_code=''PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'' and unit_code=''PE10E''';

  v_spec:=jsonb_build_object(
    'status','READY','action_kind','READBACK_ONCE',
    'recipe_mode','READBACK_EXACT','requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'verification_queries',jsonb_build_array(v_query),
    'phase_classification','FIRST_EVOLUTION_QUALITATIVE_ACCEPTANCE',
    'validator_contract',jsonb_build_object('required',true,
      'validator_code','PROFILE_EVOLUTION_FIRST_RELEASE_COMPARATIVE_ACCEPTANCE_V1',
      'pass_when','Nine merged profiles and accepted PE10E_PILOT_001; qualitative only'),
    'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
      'pass_when',jsonb_build_object(
        'schema','PROFILE_EVOLUTION_FIRST_RELEASE_COMPARATIVE_ACCEPTANCE_V1',
        'status','ACCEPTED_QUALITATIVE_FIRST_EVOLUTION',
        'test_id','PE10E_PILOT_001','merged_profile_count',9,
        'statistical_expertise_certified',false,'operational_cutover_allowed',false)),
    'forbidden',jsonb_build_array('CLAIM_EXPERT_BENCHMARK_PASS',
       'CLAIM_INDEPENDENT_JUDGE','AUTO_ACTIVATE_V02'));

  v_unit:=jsonb_set(v_unit,'{pilot_001_acceptance_v1}',v_ev,true);
  v_unit:=jsonb_set(v_unit,'{action_specs_v1,PE10E_C4}',v_spec,true);
  v_unit:=jsonb_set(v_unit,'{source_pack_v2,checkpoint_inputs,PE10E_C4}',
    jsonb_build_object('validator_code','PROFILE_EVOLUTION_FIRST_RELEASE_COMPARATIVE_ACCEPTANCE_V1',
      'expected_result','ACCEPTED_QUALITATIVE_FIRST_EVOLUTION',
      'inputs',jsonb_build_object(
        'queries',jsonb_build_array(v_query),
        'artifacts',jsonb_build_array('skills/profile_creator/evals/results/pe10e_pilot_001_qualitative_acceptance_v1.json'),
        'db_objects',jsonb_build_array('programacion.engineering_plan_units'),
        'assets','[]'::jsonb,'events','[]'::jsonb)),true);
  v_unit:=jsonb_set(v_unit,'{phase_separation_v1,expert_certification,status}',
    to_jsonb('NOT_CERTIFIED_SEPARATE_ADVANCED'::text),true);
  v_unit:=jsonb_set(v_unit,'{phase_separation_v1,expert_certification,checkpoint}',
    to_jsonb('NOT_PART_OF_FIRST_EVOLUTION_CHECKPOINT'::text),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_unit
  WHERE plan_code=v_plan AND unit_code='PE10E';

  UPDATE programacion.engineering_work_items w SET
    title='First evolution: qualitative comparison accepted',
    acceptance_criteria=(SELECT jsonb_agg(
      CASE WHEN x.value LIKE 'PE10E_C4:%' THEN to_jsonb(
        'PE10E_C4: nine merged profiles accepted; Claude PE10E_PILOT_001 X=evolved Y=original, 5 versus 2 verifiable requirements; qualitative only, not expert certification'::text)
      ELSE to_jsonb(x.value) END ORDER BY x.ordinality)
      FROM jsonb_array_elements_text(w.acceptance_criteria)
        WITH ORDINALITY AS x(value,ordinality))
  WHERE w.id=v_w;

  -- Preserve independent assurance and advanced expert gate for actual cutover.
  v_gov:=jsonb_set(v_gov,'{phase_separation_v1,expert_checkpoint}',
    to_jsonb('ADVANCED_CERTIFICATION_SEPARATE_UNPROVEN'::text),true);
  v_gov:=jsonb_set(v_gov,'{phase_separation_v1,expert_gate_required_for_cutover}',
    'true'::jsonb,true);
  v_gov:=jsonb_set(v_gov,'{first_evolution_acceptance_v2,pe10_c3_scope}',
    to_jsonb('INDEPENDENT_CUTOVER_ASSURANCE_UNCHANGED'::text),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_gov
    WHERE plan_code=v_plan AND unit_code='PE10';

  v_pre:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,'PE10E');
  IF v_pre#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'PE10E_C4'
    OR v_pre#>>'{execution_packet,status}' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'PE10E_C4_PREFLIGHT_FAIL %',v_pre#>'{execution_packet,block_reasons}'; END IF;

  v_tr:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,'PE10E','PE10E_C4','DONE',
    'github://cristhianlujan/claude-persona-lf-patch/skills/profile_creator/evals/results/pe10e_pilot_001_qualitative_acceptance_v1.json',
    'PROFILE_EVOLUTION_ORCHESTRATOR',
    'Nine merged profiles and Claude original/evolved comparison user accepted; qualitative scope only.');
  IF v_tr#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'PE10E_C4_CANONICAL_TRANSITION_FAILED'; END IF;

  UPDATE programacion.engineering_work_checkpoints
    SET title='First evolution: user-accepted comparative pilot',
      assertion_contract_sha256=encode(extensions.digest(convert_to(
        (v_spec->'assertion_contract')::text,'UTF8'),'sha256'),'hex'),
      assertion_receipt=v_ev,
      assertion_receipt_sha256=encode(extensions.digest(
        convert_to(v_ev::text,'UTF8'),'sha256'),'hex'),
      assertion_recorded_at=clock_timestamp(),
      assertion_recorded_by='PROFILE_EVOLUTION_ORCHESTRATOR'
    WHERE work_item_id=v_w AND checkpoint_code='PE10E_C4' AND status='DONE';
  IF NOT FOUND THEN RAISE EXCEPTION 'PE10E_C4_RECEIPT_MISSING'; END IF;

  v_post:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,'PE10E');
  IF v_post#>>'{state,status}' IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_pe10 AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
  THEN RAISE EXCEPTION 'PE10E_C4_POST_READBACK_FAILED'; END IF;
END $pe10e$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE-PILOT-ACCEPTANCE-SCOPE-20261012-001','PROFILE_EVOLUTION',
 'First evolution was blocked by an unrelated advanced certification requirement',
 'Nine merged profiles and Claude comparison user-accepted for the first release.',
 'PE10E_C4 conflated first-release acceptance with four-arm advanced expertise certification.',
 'Wrong maturity phase imposed on a first-release checkpoint.',
 'Separate qualitative first release from expert certification, preserve cutover governance.',
 'PE10E_C4 DONE for first release; PE10_C3 IN_PROGRESS; no expert claim.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10E_C4','ACTIVO',
 'skills/profile_creator/evals/results/pe10e_pilot_001_qualitative_acceptance_v1.json'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='LF-PE-PILOT-ACCEPTANCE-SCOPE-20261012-001');
COMMIT;

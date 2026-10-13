-- LF Profile Evolution: persist accepted first-release proof without masquerading as expert certification.
-- No changes to existing checkpoint statuses/meaning: PE10E_C4 stays the four-arm expert gate.
-- One new independently scoped checkpoint PE10E_C3B is inserted before it, then closed via the canonical transition function.
-- PE10_C3 is independent operational assurance, not a prerequisite of the accepted code milestone.
-- Strictly LF Train migration; no runtime deployment, v0.2 cutover, permissions or active policy changes.
BEGIN;
DO $phase1$
DECLARE
  v_u_pe10e bigint;
  v_u_pe10 bigint;
  v_w_pe10e bigint;
  v_m jsonb;
  v_pe10 jsonb;
  v_receipts jsonb;
  v_acceptance jsonb;
  v_query text;
  v_spec jsonb;
  v_source jsonb;
  v_transition jsonb;
  v_post jsonb;
  v_snapshot jsonb;
  v_active_count integer;
BEGIN
  SELECT id,work_item_id,unit_metadata
    INTO STRICT v_u_pe10e,v_w_pe10e,v_m
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10E'
  FOR UPDATE;

  SELECT id,unit_metadata INTO STRICT v_u_pe10,v_pe10
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10'
  FOR UPDATE;

  IF v_m ? 'first_evolution_acceptance_v2'
      OR v_pe10 ? 'first_evolution_acceptance_v2'
      OR v_m#>>'{phase_separation_v1,first_evolution,status}' IS DISTINCT FROM 'CODE_MERGED_USER_ACCEPTED'
      OR v_m#>>'{phase_separation_v1,expert_certification,status}' IS DISTINCT FROM 'PENDING_GENUINE_GPT_NATIVE_AND_INDEPENDENT_REVIEW'
      OR v_m#>>'{action_specs_v1,PE10E_C4,status}' IS DISTINCT FROM 'BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'
      OR v_m#>>'{action_specs_v1,PE10E_C4,validator_contract,validator_code}' IS DISTINCT FROM 'PROFILE_EXPERT_BEHAVIOR_BENCHMARK_V1'
      OR v_pe10#>>'{phase_separation_v1,expert_gate_required_for_cutover}' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_PRESTATE_GOVERNANCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w_pe10e AND checkpoint_code='PE10E_C4'
        AND sequence_no=4 AND status='PENDING')<>1
      OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w_pe10e AND checkpoint_code='PE10E_C3B')<>0
      OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w_pe10e AND status='DONE')<>3
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_PRESTATE_CHECKPOINT_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
       WHERE id=v_u_pe10) AND checkpoint_code='PE10_C3' AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_PE10_ASSURANCE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_policy_versions
      WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1'
        AND status='ACTIVE')<>1
      OR (SELECT count(*) FROM public.lf_policy_versions
      WHERE policy_code='POL-PROFILE-UPDATE-PASS'
        AND policy_version='v1.3-phase-separation-candidate' AND status='CANDIDATE')<>1
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_POLICY_DRIFT'; END IF;

  -- These nine PR merge identities were verified through GitHub API against current main.
  -- Their evidence class is VERSIONED_CODE_ONLY, not a four-arm LLM execution receipt.
  v_receipts:=jsonb_build_array(
    jsonb_build_object('profile','quality_pack','pr',2322,'merge_sha','0c7b41cc19c88e4115bebd1888f731fb316dce2e'),
    jsonb_build_object('profile','ui_architect','pr',2324,'merge_sha','71ddf4866def4ca66ad4645c6f1edb62ad09a936'),
    jsonb_build_object('profile','product_director_lf','pr',2325,'merge_sha','e02343badc9c06c2065db4351c9d3bfc16771699'),
    jsonb_build_object('profile','customer_financial_ux_decisioning','pr',2326,'merge_sha','8b436bc8c50b4e93959d9bf3279ee0108924a476'),
    jsonb_build_object('profile','gamification_system_architect','pr',2327,'merge_sha','0ff98faec756b9dd1fa2c8fae656482b1473f595'),
    jsonb_build_object('profile','evidence_lineage_reviewer_lf','pr',2328,'merge_sha','ff0e48bc870b48c7ea645c79544ed5b083a75720'),
    jsonb_build_object('profile','frontend_prototype_architect_lf','pr',2329,'merge_sha','82b9c583d46c81eb9c6d45561e8ede2ca7fa61d1'),
    jsonb_build_object('profile','systemic_root_cause_repair_lf','pr',2330,'merge_sha','94d56170577eaaa3d4a82ea74b01f570afa702de'),
    jsonb_build_object('profile','programming_analysis_lf','pr',2331,'merge_sha','2b4dec92cfc925208014fb0bc9e708799078f5b5')
  );
  IF jsonb_array_length(v_receipts)<>9
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_receipts) e
       WHERE (e->>'merge_sha') !~ '^[0-9a-f]{40}$'
          OR (e->>'pr') !~ '^[0-9]{4}$'
     )
     OR (SELECT count(distinct x->>'profile') FROM jsonb_array_elements(v_receipts) x)<>9
     OR (SELECT count(distinct x->>'pr') FROM jsonb_array_elements(v_receipts) x)<>9
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_INCOMPLETE_GIT_PROOF'; END IF;

  v_acceptance:=jsonb_build_object(
    'schema','PROFILE_EVOLUTION_FIRST_RELEASE_ACCEPTANCE_V1',
    'scope','VERSIONED_PROFILE_CODE_QUALITATIVE_REVIEW',
    'status','ACCEPTED_CODE_ONLY',
    'profile_count',9,
    'evidence_class','GIT_MERGED_CONTRACTS_PLUS_USER_REVIEWED_ILLUSTRATIVE_COMPARISONS',
    'git_receipts',v_receipts,
    'source_contract','skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json',
    'review_status','USER_ACCEPTED_QUALITATIVE',
    'independent_blind_benchmark',false,
    'four_arm_gpt_native_executed',false,
    'expertise_certified',false,
    'operational_cutover_allowed',false,
    'expert_checkpoint','PE10E_C4',
    'cutover_assurance_checkpoint','PE10_C3'
  );

  v_query:='select (unit_metadata #>> ''{first_evolution_acceptance_v2,status}'' = ''ACCEPTED_CODE_ONLY'') as code_accepted, '
    ||'(jsonb_array_length(unit_metadata #> ''{first_evolution_acceptance_v2,git_receipts}'') = 9) as nine_merges, '
    ||'(unit_metadata #>> ''{phase_separation_v1,expert_certification,status}'' = ''PENDING_GENUINE_GPT_NATIVE_AND_INDEPENDENT_REVIEW'') as expert_still_pending '
    ||'from programacion.engineering_plan_units '
    ||'where plan_code = ''PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'' and unit_code = ''PE10E''';

  v_spec:=jsonb_build_object(
    'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
    'requires_material_execution',false,
    'contract_family','FIRST_EVOLUTION_CODE_ACCEPTANCE',
    'verification_queries',jsonb_build_array(v_query),
    'target',jsonb_build_object('declared_objects',
        jsonb_build_array('programacion.engineering_plan_units','programacion.engineering_work_checkpoints')),
    'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
      'pass_when',jsonb_build_object('status','ACCEPTED_CODE_ONLY','profile_count',9,
        'expertise_certified',false,'operational_cutover_allowed',false)),
    'validator_contract',jsonb_build_object('required',true,
      'validator_code','PROFILE_EVOLUTION_FIRST_RELEASE_ACCEPTANCE_V1',
      'validation_input',jsonb_build_object('source','NINE_GITHUB_MERGE_RECEIPTS_AND_QUALITATIVE_USER_ACCEPTANCE')),
    'forbidden',jsonb_build_array('EXPERT_BENCHMARK_PASS_INFERENCE','RUNTIME_ACTIVATION',
      'INDEPENDENT_REVIEW_CLAIM','ASSUME_QUANTITATIVE_UPLIFT')
  );
  v_source:=jsonb_build_object(
    'inputs',jsonb_build_object('assets','[]'::jsonb,'events','[]'::jsonb,
      'queries',jsonb_build_array(v_query),'artifacts',jsonb_build_array(
       'skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json'),
      'db_objects',jsonb_build_array('programacion.engineering_plan_units')),
    'validator_code','PROFILE_EVOLUTION_FIRST_RELEASE_ACCEPTANCE_V1',
    'expected_result','Nine profile contracts merged and user qualitative acceptance; expert gate remains PENDING',
    'validation_input',jsonb_build_object('scope','CODE_ONLY','profile_count',9));

  v_m:=jsonb_set(v_m,'{first_evolution_acceptance_v2}',v_acceptance,true);
  v_m:=jsonb_set(v_m,'{action_specs_v1,PE10E_C3B}',v_spec,true);
  v_m:=jsonb_set(v_m,'{source_pack_v2,checkpoint_inputs,PE10E_C3B}',v_source,true);
  v_m:=jsonb_set(v_m,'{action_specs_v1,PE10E_C4,phase_classification}',
      to_jsonb('ADVANCED_EXPERT_CERTIFICATION_NOT_PHASE1_CODE_ACCEPTANCE'::text),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_m WHERE id=v_u_pe10e;

  v_pe10:=jsonb_set(v_pe10,'{first_evolution_acceptance_v2}',
    jsonb_build_object('status','CODE_ONLY_ACCEPTED_SEPARATE_FROM_PE10_C3',
      'source_checkpoint','PE10E_C3B','expert_checkpoint','PE10E_C4',
      'pe10_c3_scope','CUTOVER_INDEPENDENT_ASSURANCE_ONLY',
      'cutover_gate_preserved',true,'runtime_activated',false),true);
  v_pe10:=jsonb_set(v_pe10,'{action_specs_v1,PE10_C3,phase_classification}',
    to_jsonb('INDEPENDENT_ASSURANCE_FOR_CUTOVER_NOT_FIRST_EVOLUTION_ACCEPTANCE'::text),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_pe10 WHERE id=v_u_pe10;

  UPDATE programacion.engineering_work_checkpoints
    SET sequence_no=5,updated_at=clock_timestamp()
    WHERE work_item_id=v_w_pe10e AND checkpoint_code='PE10E_C4'
      AND sequence_no=4 AND status='PENDING';
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_PE_PHASE1_EXPERT_REORDER_FAILED'; END IF;

  INSERT INTO programacion.engineering_work_checkpoints(
    work_item_id,checkpoint_code,title,sequence_no,weight,required,status,
    created_by_execution_id)
  VALUES(v_w_pe10e,'PE10E_C3B',
    'First evolution: nine merged profiles qualitatively accepted (code only)',
    4,1,true,'PENDING','EXEC-PE-PHASE1-ACCEPTANCE-20261012-001');

  -- This is a separate positive code-only validation; never record expert PASS.
  v_snapshot:=programacion.fn_engineering_unit_bootstrap_v3(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10E');
  IF v_snapshot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'PE10E_C3B'
     OR v_snapshot#>>'{action_spec,action_kind}' IS DISTINCT FROM 'READBACK_ONCE'
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_CURRENT_CHECKPOINT_MISMATCH'; END IF;

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10E','PE10E_C3B','DONE',
    'github://cristhianlujan/claude-persona-lf-patch/skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json',
    'EXEC-PE-PHASE1-ACCEPTANCE-20261012-001',
    'User-accepted qualitative comparison of nine profile evolutions with exact nine Git merges; CODE_ONLY. No authentic A/B/C/D, no expert benchmark, no independent cutover assurance, no runtime activation.');
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_CANONICAL_TRANSITION_FAILED'; END IF;

  -- Attach typed evidence to the new checkpoint only, never reclassify expert evidence.
  UPDATE programacion.engineering_work_checkpoints
    SET assertion_receipt=jsonb_build_object(
      'schema','PROFILE_EVOLUTION_FIRST_RELEASE_ACCEPTANCE_V1',
      'result','CODE_ONLY_ACCEPTED',
      'code_delivery_receipts',v_receipts,
      'qualitative_user_acceptance',true,
      'expert_certified',false,'independent_assurance','NOT_EXECUTED',
      'runtime_activated',false,
      'source_contract','skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json'),
      assertion_recorded_at=clock_timestamp(),
      assertion_recorded_by='EXEC-PE-PHASE1-ACCEPTANCE-20261012-001'
  WHERE work_item_id=v_w_pe10e AND checkpoint_code='PE10E_C3B' AND status='DONE';

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w_pe10e AND checkpoint_code='PE10E_C3B'
        AND status='DONE')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_w_pe10e AND checkpoint_code='PE10E_C4'
        AND status='PENDING' AND sequence_no=5)<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
        WHERE id=v_u_pe10) AND checkpoint_code='PE10_C3'
        AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_CHECKPOINT_POSTSTATE_INVALID'; END IF;

  v_post:=programacion.fn_engineering_unit_bootstrap_v3(
    'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10E');
  IF v_post#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'PE10E_C4'
      OR v_post#>>'{action_spec,status}' IS DISTINCT FROM 'BLOCK_GPT_NATIVE_EXECUTOR_AND_REVIEWER_MISSING'
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_EXPERT_GATE_REMOVED'; END IF;
  IF (SELECT count(*) FROM public.lf_policy_versions
      WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE')<>1
  THEN RAISE EXCEPTION 'LF_PE_PHASE1_POLICY_CHANGED'; END IF;
END $phase1$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT 'LF-PE-FIRST-RELEASE-ACCEPTANCE-20261012-001','PROFILE_EVOLUTION',
  'First-evolution code acceptance was conflated with expert benchmark',
  'Accept nine merged user-reviewed first evolutions in a separately typed checkpoint, keeping original expert checkpoint untouched.',
  'PE10E_C4 requested an expert-level 120-case A/B/C/D benchmark even when the user was accepting only initial code candidate qualitative comparison.',
  'Phase-one acceptance and later blind expertise certification shared a release gate.',
  'Add code-only checkpoint PE10E_C3B, record 9 PR receipts and user acceptance. Retain PE10E_C4 and PE10_C3 as advanced expert/independent cutover gates.',
  'Positive: PE10E_C3B DONE with code-only receipt; negative: PE10E_C4 PENDING and PE10_C3 IN_PROGRESS, runtime not activated.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10E_C3B','ACTIVO',
  'skills/profile_creator/contracts/profile_evolution_phase_separation_v1.json'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='LF-PE-FIRST-RELEASE-ACCEPTANCE-20261012-001');
COMMIT;

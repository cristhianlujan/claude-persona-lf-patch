-- M10.2 / PAULO-097. CONTRACT PREFLIGHT ONLY.
-- Does not promote INPUT_GOVERNANCE, create a candidate, alter a runtime,
-- approve a release, update capability pointers, or transition checkpoints.
-- Technical qualification and operational cutover are independent gates.
DO $m102$
DECLARE
  v_id bigint;
  v_work bigint;
  v_meta jsonb;
  v_specs jsonb;
  v_source jsonb;
  v_current public.lf_capability_current%rowtype;
  v_registered integer;
  v_m92_done integer;
  v_m100_done integer;
  v_old text;
  q_current text := 'SELECT c.capability_code,c.version,c.manifest_sha256,c.previous_version,r.release_state FROM public.lf_capability_current c JOIN public.lf_capability_version_registry r ON r.capability_code=c.capability_code AND r.version=c.version WHERE c.capability_code=''INPUT_GOVERNANCE''';
  q_versions text := 'SELECT capability_code,version,release_state,manifest_sha256 FROM public.lf_capability_version_registry WHERE capability_code=''INPUT_GOVERNANCE'' ORDER BY version';
  q_m92 text := 'SELECT c.checkpoint_code,c.status,c.evidence_ref FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id WHERE u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' AND u.unit_code=''M9.2'' AND c.checkpoint_code IN (''SWITCH_REVERT_SANDBOX'',''BINDING_READBACK'')';
  q_m100 text := 'SELECT c.checkpoint_code,c.status,c.evidence_ref FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id WHERE u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' AND u.unit_code=''M10.0'' AND c.checkpoint_code IN (''HUMAN_DECISION_RECORD'',''AUTHORITY_READBACK'')';
  q_runtime text := 'SELECT capability_code,version,manifest_sha256 FROM public.lf_capability_current WHERE capability_code=''INPUT_GOVERNANCE''';
BEGIN
  SELECT u.id,u.work_item_id,u.unit_metadata,u.exit_criterion
    INTO v_id,v_work,v_meta,v_old
  FROM programacion.engineering_plan_units u
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M10.2' FOR UPDATE;
  IF NOT FOUND OR v_work IS DISTINCT FROM 199 OR v_id IS DISTINCT FROM 11
     OR v_old NOT LIKE 'Un único cambio de puntero%'
     OR v_meta ? 'm10_2_contract_governance_v1'
  THEN RAISE EXCEPTION 'M102_PREFLIGHT_UNIT_PRESTATE_DRIFT'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_work_items w
    WHERE w.id=v_work AND w.work_code='PAULO-097'
      AND w.status='BACKLOG' AND w.expected_result='switch reversible'
  ) OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work AND status='PENDING')<>6
  THEN RAISE EXCEPTION 'M102_PREFLIGHT_WORK_OR_CHECKPOINT_DRIFT'; END IF;

  SELECT * INTO v_current FROM public.lf_capability_current
  WHERE capability_code='INPUT_GOVERNANCE';
  SELECT count(*) INTO v_registered FROM public.lf_capability_version_registry
  WHERE capability_code='INPUT_GOVERNANCE';
  IF v_current.version IS DISTINCT FROM '1.0.0'
     OR v_current.manifest_sha256 IS DISTINCT FROM
       'd1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44'
     OR v_registered<>1
     OR NOT EXISTS (SELECT 1 FROM public.lf_capability_version_registry
         WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0'
           AND release_state='RELEASED'
           AND manifest_sha256=v_current.manifest_sha256)
  THEN RAISE EXCEPTION 'M102_PREFLIGHT_CURRENT_OR_CANDIDATE_DRIFT'; END IF;

  SELECT count(*) INTO v_m92_done
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND u.unit_code='M9.2' AND c.status='DONE';
  SELECT count(*) INTO v_m100_done
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND u.unit_code='M10.0' AND c.status='DONE';
  IF v_m92_done<>6 OR v_m100_done<>7
  THEN RAISE EXCEPTION 'M102_PREFLIGHT_REUSE_EVIDENCE_MISSING'; END IF;

  -- Correct the authority boundary, not the production/current pointer.
  v_meta := jsonb_set(v_meta,'{m10_2_contract_governance_v1}',
    jsonb_build_object(
      'schema','IG_M102_ENGINEERING_VS_OPERATIONAL_V1',
      'phase','CONSTRUCTION_SANDBOX',
      'authority_capability','INPUT_GOVERNANCE',
      'custodian_scope','LF_GOVERNANCE',
      'product_owner','NONE_TRANSVERSAL',
      'baseline_version','1.0.0',
      'baseline_manifest_sha256',v_current.manifest_sha256,
      'registered_version_count',v_registered,
      'candidate_status','ABSENT_NOT_FABRICATED',
      'switch_mechanism','public.fn_lf_capability_promote_v1',
      'existing_reversible_precedent','M9.2:SWITCH_REVERT_SANDBOX',
      'engineering_gate','REQUIRES_SOURCE_BOUND_REUSABLE_TEST_AND_ASSERTION',
      'operational_gate','BLOCKED_PENDING_REGISTERED_CANDIDATE_AND_GOVERNED_AUTHORITY',
      'operational_authority_ref','M10.0:AUTHORITY_READBACK',
      'runtime_activation','FORBIDDEN_IN_CONSTRUCTION_SANDBOX',
      'activation_performed',false,
      'no_pointer_mutation',true,
      'no_data_migration',true,
      'no_checkpoint_transitions',true),true);

  v_specs := coalesce(v_meta->'action_specs_v1','{}'::jsonb);

  -- CP1: exact evidence of CURRENT and candidate absence, not an "authorized bundle".
  v_specs := jsonb_set(v_specs,'{BINDING_ASIS}',
    (coalesce(v_specs->'BINDING_ASIS','{}'::jsonb) ||
      jsonb_build_object(
        'schema_version','ENGINEERING_ACTION_SPEC_V3',
        'checkpoint_code','BINDING_ASIS',
        'contract_source','EXPLICIT_ACTION_SPEC',
        'action_kind','READBACK_ONCE',
        'status','READY',
        'recipe_mode','OBSERVE_AND_PERSIST',
        'target',jsonb_build_object('declared_objects',jsonb_build_array(
          'public.lf_capability_current','public.lf_capability_version_registry',
          'programacion.engineering_work_checkpoints')),
        'expected','Observe CURRENT 1.0.0, no CANDIDATE, M10.0 sandbox DONE but operational authority blocked',
        'checkpoint_title','Readback CURRENT/registry de IG y gate operativo M10.0 separado',
        'verification_queries',jsonb_build_array(q_current,q_versions,q_m100),
        'requires_material_execution',false)),true);

  -- CP2: re-use the governed existing promotion mechanism, not a fictitious
  -- CAPABILITY_CUTOVER registry entry or an active POST_PASE workstream.
  v_specs := jsonb_set(v_specs,'{REUSE_CAPABILITY_CUTOVER}',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','REUSE_CAPABILITY_CUTOVER',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'action_kind','READBACK_ONCE',
      'status','READY',
      'recipe_mode','OBSERVE_AND_PERSIST',
      'expected','Confirm reusable M9.2 mechanism and actual pg_proc public.fn_lf_capability_promote_v1; no new engine or SADM activation',
      'target',jsonb_build_object('declared_objects',jsonb_build_array(
           'public.lf_capability_current','public.lf_capability_version_registry',
           'programacion.engineering_work_checkpoints')),
      'verification_queries',jsonb_build_array(q_m92,q_current),
      'requires_material_execution',false),true);

  -- CP3 sandbox qualification: proof of a bounded reversible switch from M9.2.
  -- The original live-cutover authoring contract is retained separately but is
  -- NOT executable in engineering while a governed candidate/approval is absent.
  v_meta := jsonb_set(v_meta,'{m10_2_original_live_cutover_v1}',
     coalesce(v_specs->'SWITCH_ONLY_MIGRATION','{}'::jsonb),true);
  v_specs := jsonb_set(v_specs,'{SWITCH_ONLY_MIGRATION}',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','SWITCH_ONLY_MIGRATION',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'action_kind','READBACK_ONCE',
      'status','READY',
      'recipe_mode','OBSERVE_AND_PERSIST',
      'expected','Existing M9.2 source-bound switch-only reversible sandbox canary (not an operational release migration)',
      'target',jsonb_build_object('declared_objects',jsonb_build_array(
        'public.lf_capability_current','public.lf_capability_version_registry',
        'programacion.engineering_work_checkpoints')),
      'verification_queries',jsonb_build_array(q_m92,q_current,q_versions),
      'requires_material_execution',false),true);

  -- CP4 is a verification obligation: no deployment/mutating input_readiness_runs.
  -- It stays fail closed until actual Edge-vs-main readback is attached.
  v_specs := jsonb_set(v_specs,'{RUNTIME_PREFLIGHT}',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','RUNTIME_PREFLIGHT',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'action_kind','READBACK_ONCE',
      'status','READY',
      'recipe_mode','OBSERVE_AND_PERSIST',
      'expected','R17 actual deployed Edge source versions and Git main parity, contract current; no deployment',
      'target',jsonb_build_object('declared_objects',jsonb_build_array('public.lf_capability_current')),
      'verification_queries',jsonb_build_array(q_runtime),
      'runtime_evidence_required',jsonb_build_array(
           'input-governance-agent-v1','input-governance-curator-v1',
           'input-governance-validator-v1'),
      'runtime_source_parity_preflight',jsonb_build_object(
         'observed_date','2026-10-13',
         'verification','DEPLOYED_INDEX_TS_EXACTLY_EQUALS_GITHUB_MAIN',
         'required_currentness','REVERIFY_BEFORE_CHECKPOINT_DONE',
         'items',jsonb_build_array(
           jsonb_build_object('slug','input-governance-agent-v1','version',17,
             'git_blob_sha','326a5c492c84cceccb45ea8d6a0f39a1d5305637',
             'deployed_ezbr_sha256','95977bfd7be64aef68a4c18c2e7fe15914aa510bcc1c1ee668863068cc5e656c'),
           jsonb_build_object('slug','input-governance-curator-v1','version',14,
             'git_blob_sha','bd43f469d5d508f64dbee21eea7be611e7d2e780',
             'deployed_ezbr_sha256','31fff4bc573c6832f7c3ce53c783c31b735ead263e3262af5d43b3a7b64b3d5c'),
           jsonb_build_object('slug','input-governance-validator-v1','version',18,
             'git_blob_sha','31a77e43c02f714479e5ed2f1fdb615fbe38eead',
             'deployed_ezbr_sha256','57bfa7fcf19002378a5f1ffcdd3f3777223a4c8ca3417df8220b55c996e59a77'))),
      'requires_material_execution',false),true);

  -- CP5: enforce real source-bound reversibility; historical M9.2 is a
  -- candidate evidence INPUT, not an automatic PASS for M10.2.
  v_specs := jsonb_set(v_specs,'{NEG_REVERSE}',
    (coalesce(v_specs->'NEG_REVERSE','{}'::jsonb) ||
      jsonb_build_object(
        'expected','Actual canary positive, negative and rollback readback with baseline 1.0.0; zero delta, source-bound assertion',
        'baseline_version','1.0.0',
        'preexisting_case_ref','M9.2:SWITCH_REVERT_SANDBOX',
        'target',jsonb_build_object(
          'declared_objects',jsonb_build_array(
            'public.lf_capability_current','public.lf_capability_version_registry'),
          'declared_artifacts',jsonb_build_array(
            jsonb_build_object(
              'path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m10_2/neg_reverse.py',
              'role','MUTATION_TARGET',
              'purpose','CHECKPOINT_TEST_ARTIFACT',
              'target_kind','EXACT_NEW_OR_UPDATE_FILE'),
            jsonb_build_object(
              'path','cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m9_2/switch_revert_sandbox.py',
              'role','EVIDENCE_ONLY'))),
        'test_execution_contract',
          coalesce(v_specs#>'{NEG_REVERSE,test_execution_contract}','{}'::jsonb)
            || jsonb_build_object(
              'declared_objects',jsonb_build_array(
                'public.lf_capability_current','public.lf_capability_version_registry'),
              'declared_queries',jsonb_build_array(q_current,q_m92),
              'canonical_exit_criterion','SANDBOX canary positive and negative, baseline 1.0.0 restored, zero residue; operational cutover not implied',
              'checkpoint_title_context','Revertir puntero CURRENT 1.0.0 sin residuos'),
        'verification_queries',jsonb_build_array(q_current,q_m92),
        'status','BLOCK_GENUINE_ASSERTION_UNTIL_EXECUTED')),true);

  -- CP6: post-observation must prove baseline unchanged when this is only a
  -- technical sandbox qualification; never assert an operational promotion.
  v_specs := jsonb_set(v_specs,'{SWITCH_READBACK}',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','SWITCH_READBACK',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'action_kind','READBACK_ONCE',
      'status','READY',
      'recipe_mode','OBSERVE_AND_PERSIST',
      'expected','Sandbox final CURRENT remains 1.0.0, same manifest, zero candidate and no activation; operational cutover separately blocked',
      'target',jsonb_build_object('declared_objects',jsonb_build_array(
        'public.lf_capability_current','public.lf_capability_version_registry')),
      'verification_queries',jsonb_build_array(q_current,q_versions),
      'requires_material_execution',false),true);
  v_meta := jsonb_set(v_meta,'{action_specs_v1}',v_specs,true);

  -- Keep SOURCE_PACK consistent with compiled connector inputs. No stale SADM
  -- dependence, no late need to rediscover SQL, no empty readback queries.
  v_source := coalesce(v_meta->'source_pack_v1','{}'::jsonb);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,BINDING_ASIS,inputs,queries}',
    jsonb_build_array(q_current,q_versions,q_m100),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,BINDING_ASIS,missing}','[]'::jsonb,true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,BINDING_ASIS,missing_typed}','[]'::jsonb,true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,REUSE_CAPABILITY_CUTOVER,inputs,queries}',
    jsonb_build_array(q_m92,q_current),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,REUSE_CAPABILITY_CUTOVER,inputs,db_objects}',
    jsonb_build_array('public.lf_capability_current',
     'public.lf_capability_version_registry','programacion.engineering_work_checkpoints'),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,SWITCH_ONLY_MIGRATION,inputs,queries}',
    jsonb_build_array(q_m92,q_current,q_versions),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,SWITCH_ONLY_MIGRATION,inputs,db_objects}',
    jsonb_build_array('public.lf_capability_current',
      'public.lf_capability_version_registry','programacion.engineering_work_checkpoints'),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,RUNTIME_PREFLIGHT,inputs,queries}',
    jsonb_build_array(q_runtime),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,RUNTIME_PREFLIGHT,inputs,db_objects}',
    jsonb_build_array('public.lf_capability_current'),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,NEG_REVERSE,inputs,queries}',
    jsonb_build_array(q_current,q_m92),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,NEG_REVERSE,inputs,db_objects}',
    jsonb_build_array('public.lf_capability_current',
      'public.lf_capability_version_registry'),true);
  v_source := jsonb_set(v_source,'{checkpoint_inputs,SWITCH_READBACK}',
    jsonb_build_object('inputs',jsonb_build_object(
      'queries',jsonb_build_array(q_current,q_versions),
      'db_objects',jsonb_build_array(
        'public.lf_capability_current','public.lf_capability_version_registry'),
      'assets','[]'::jsonb,'events','[]'::jsonb,'artifacts','[]'::jsonb),
      'missing','[]'::jsonb,'missing_typed','[]'::jsonb),true);
  v_meta := jsonb_set(v_meta,'{source_pack_v1}',v_source,true);

  UPDATE programacion.engineering_plan_units
  SET exit_criterion='SANDBOX ENGINEERING: observe INPUT_GOVERNANCE 1.0.0 and the existing M9.2 reversible switch proof; verify a source-bound, bounded pointer-only canary with genuine positive/negative and ROLLBACK; validate runtime preflight; finish with current baseline unchanged and no operational promotion. Operational cutover is separately blocked until registered candidate plus governed authorization from M10.0. No user data DDL/DML.',
      unit_metadata=v_meta WHERE id=v_id;

  UPDATE programacion.engineering_work_items
  SET expected_result='Verified reversible switch qualification in sandbox; no live release activation',
      acceptance_criteria=jsonb_build_array(
        'M9.2 governed mechanism reused; no duplicate CAPABILITY_CUTOVER engine',
        'Source-bound real positive/negative test and rollback, no residues',
        'Edge runtime parity readback; no deploy',
        'CURRENT remains 1.0.0, operational authority remains gated')
  WHERE id=v_work;

  UPDATE programacion.engineering_work_checkpoints
  SET title=CASE checkpoint_code
    WHEN 'BINDING_ASIS' THEN 'Readback CURRENT IG 1.0.0 y gate M10.0 independiente'
    WHEN 'REUSE_CAPABILITY_CUTOVER' THEN 'Reuso comprobado del switch gobernado M9.2 sin motor adicional'
    WHEN 'SWITCH_ONLY_MIGRATION' THEN 'Prueba reversible del switch-only, sin activacion de release real'
    WHEN 'RUNTIME_PREFLIGHT' THEN 'Preflight Edge desplegado versus main, R17, solo evidencia'
    WHEN 'NEG_REVERSE' THEN 'Canario positivo/negativo y rollback a CURRENT 1.0.0 sin residuos'
    WHEN 'SWITCH_READBACK' THEN 'Readback final sandbox: baseline intacto; cutover operativo separado'
    ELSE title END
  WHERE work_item_id=v_work AND checkpoint_code IN (
    'BINDING_ASIS','REUSE_CAPABILITY_CUTOVER','SWITCH_ONLY_MIGRATION',
    'RUNTIME_PREFLIGHT','NEG_REVERSE','SWITCH_READBACK');

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND status='PENDING')<>6
    OR (SELECT version FROM public.lf_capability_current
        WHERE capability_code='INPUT_GOVERNANCE')<>'1.0.0'
    OR (SELECT count(*) FROM public.lf_capability_version_registry
        WHERE capability_code='INPUT_GOVERNANCE')<>1
    OR (SELECT unit_metadata#>>'{m10_2_contract_governance_v1,activation_performed}'
        FROM programacion.engineering_plan_units WHERE id=v_id) IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'M102_POSTSTATE_FAIL_CLOSED'; END IF;
END $m102$;
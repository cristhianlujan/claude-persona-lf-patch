-- IG M10.3 / PAULO-162: preventive contract/governance/source-pack repair.
-- Scope: SANDBOX engineering only. No capability promotion, no runtime switch,
-- no legacy deletion, no checkpoint completion, no production change.
-- EKB: IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001,
-- IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001,
-- IG-M1011-NONMATERIAL-READBACK-MISSING-QUERY-001.
DO $m103_preflight$
DECLARE
  v_plan CONSTANT text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit CONSTANT text := 'M10.3';
  v_exit CONSTANT text := 'CONSTRUCTION_SANDBOX: legacy remains deployed and recoverable; observe INPUT_GOVERNANCE CURRENT 1.0.0 without operational promotion; qualify a pointer-only rollback drill on an isolated sandbox using a real positive and negative test, plus a producer-bound INPUT_GOVERNANCE_REGRESSION run scoped to this checkpoint. Verify restoration of the original CURRENT manifest and zero residual writes. Post-operational-switch zero-legacy-traffic remains a separate release-observability gate, NOT a construction checkpoint; no activation, user-data change, DROP or revoke.';
  v_prev CONSTANT text := 'Legacy 5.13 sin tráfico (0 runs nuevos con componentes legacy post-switch) pero ejecutable: simulacro de rollback por puntero con suite INPUT_GOVERNANCE_REGRESSION en verde y 0 residuos';
  v_md jsonb;
  v_current_query text;
  v_drill_query text;
  v_suite_query text;
  v_terminal_query text;
  v_count integer;
  v_current text;
BEGIN
  SELECT unit_metadata INTO STRICT v_md
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=475
  FOR UPDATE;

  IF (SELECT exit_criterion FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code=v_unit) IS DISTINCT FROM v_prev
  THEN RAISE EXCEPTION 'M103_EXIT_CRITERION_DRIFT'; END IF;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=475) <> 'BACKLOG'
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=475 AND status='PENDING')<>5
  THEN RAISE EXCEPTION 'M103_CHECKPOINT_PRESTATE_CHANGED'; END IF;

  IF (SELECT status FROM programacion.engineering_work_items
       WHERE id=(SELECT work_item_id FROM programacion.engineering_plan_units
                 WHERE plan_code=v_plan AND unit_code='M10.2')) IS DISTINCT FROM 'DONE'
  THEN RAISE EXCEPTION 'M103_UPSTREAM_M102_NOT_DONE'; END IF;

  SELECT count(*), max(version) INTO v_count,v_current
  FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE';
  IF v_count<>1 OR v_current<>'1.0.0'
     OR (SELECT count(*) FROM public.lf_capability_version_registry
         WHERE capability_code='INPUT_GOVERNANCE')<>1
     OR NOT EXISTS (
       SELECT 1 FROM public.lf_capability_current c
       JOIN public.lf_capability_version_registry r
       USING(capability_code,version)
       WHERE c.capability_code='INPUT_GOVERNANCE'
         AND c.previous_version IS NULL
         AND c.manifest_sha256=r.manifest_sha256
         AND r.release_state='RELEASED')
  THEN RAISE EXCEPTION 'M103_CURRENT_REGISTRY_BASELINE_DRIFT'; END IF;

  v_current_query :=
    'SELECT c.capability_code,c.version,c.previous_version,c.promoted_at,c.manifest_sha256,'||
    'r.release_state,r.manifest_sha256 AS registered_sha256,'||
    '(SELECT count(*) FROM public.lf_capability_version_registry vr '||
    'WHERE vr.capability_code=c.capability_code) AS registered_versions '||
    'FROM public.lf_capability_current c '||
    'JOIN public.lf_capability_version_registry r USING(capability_code,version) '||
    'WHERE c.capability_code=''INPUT_GOVERNANCE''';
  v_drill_query :=
    'SELECT u.unit_code,w.status,c.checkpoint_code,c.status AS cp_status,'||
    'c.evidence_ref,c.assertion_receipt_sha256 FROM programacion.engineering_plan_units u '||
    'JOIN programacion.engineering_work_items w ON w.id=u.work_item_id '||
    'JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id '||
    'WHERE u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' '||
    'AND u.unit_code IN (''M9.2'',''M10.2'') '||
    'AND c.checkpoint_code IN (''SWITCH_REVERT_SANDBOX'',''BINDING_READBACK'','||
    '''NEG_REVERSE'',''SWITCH_READBACK'') ORDER BY u.unit_code,c.sequence_no';
  v_suite_query :=
    'SELECT suite_run_id,suite_code,status,tests_total,tests_passed,tests_failed,'||
    'tests_blocked,metadata,started_at,completed_at FROM public.lf_test_suite_runs '||
    'WHERE suite_code=''INPUT_GOVERNANCE_REGRESSION'' '||
    'AND metadata->>''unit_code''=''M10.3'' '||
    'AND metadata->>''checkpoint_code''=''ROLLBACK_SUITE'' '||
    'ORDER BY started_at DESC NULLS LAST LIMIT 5';
  v_terminal_query :=
    'SELECT c.capability_code,c.version,c.previous_version,c.manifest_sha256,'||
    'r.manifest_sha256 AS registered_sha256,r.release_state,'||
    '(SELECT count(*) FROM public.lf_capability_version_registry vr '||
    'WHERE vr.capability_code=c.capability_code) AS version_count '||
    'FROM public.lf_capability_current c '||
    'JOIN public.lf_capability_version_registry r USING(capability_code,version) '||
    'WHERE c.capability_code=''INPUT_GOVERNANCE''';

  -- CP2: source was a historical readiness table with no release_id.
  -- Do not claim 0 post-switch runs when no operational switch exists.
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,NOT_ACTIVE,inputs,queries}',
    jsonb_build_array(v_current_query),true);
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,NOT_ACTIVE,inputs,db_objects}',
    '["public.lf_capability_current","public.lf_capability_version_registry"]'::jsonb,true);
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,NOT_ACTIVE,missing}','[]'::jsonb,true);
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,NOT_ACTIVE,missing_typed}','[]'::jsonb,true);

  -- CP3: preserve exact bounded-test authoring and machine assertion contract;
  -- replace the disabled/post-PASE inference with live CURRENT plus closed M9.2/M10.2.
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,ROLLBACK_DRILL,inputs,queries}',
    jsonb_build_array(v_current_query,v_drill_query),true);
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,ROLLBACK_DRILL,inputs,db_objects}',
    '["public.lf_capability_current","public.lf_capability_version_registry","programacion.engineering_work_checkpoints"]'::jsonb,true);
  v_md := jsonb_set(v_md,
    '{action_specs_v1,ROLLBACK_DRILL,target,declared_objects}',
    '["public.lf_capability_current","public.lf_capability_version_registry","programacion.engineering_work_checkpoints"]'::jsonb,true);
  v_md := jsonb_set(v_md,
    '{action_specs_v1,ROLLBACK_DRILL,verification_queries}',
    jsonb_build_array(v_current_query,v_drill_query),true);
  v_md := jsonb_set(v_md,
    '{action_specs_v1,ROLLBACK_DRILL,test_execution_contract,declared_objects}',
    '["public.lf_capability_current","public.lf_capability_version_registry","programacion.engineering_work_checkpoints"]'::jsonb,true);
  v_md := jsonb_set(v_md,
    '{action_specs_v1,ROLLBACK_DRILL,test_execution_contract,declared_queries}',
    jsonb_build_array(v_current_query,v_drill_query),true);
  v_md := jsonb_set(v_md,
    '{action_specs_v1,ROLLBACK_DRILL,test_execution_contract,canonical_exit_criterion}',
    to_jsonb(v_exit),true);

  -- CP4: a PASSED 1/1 result belonging to a different unit is not this checkpoint.
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,ROLLBACK_SUITE,inputs,queries}',
    jsonb_build_array(v_suite_query),true);
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,ROLLBACK_SUITE,inputs,db_objects}',
    '["public.lf_test_suite_runs"]'::jsonb,true);

  -- CP5: authoritative CURRENT + registered SHA, not unrelated execution bindings.
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,ROLLBACK_READBACK,inputs,queries}',
    jsonb_build_array(v_terminal_query),true);
  v_md := jsonb_set(v_md,
    '{source_pack_v1,checkpoint_inputs,ROLLBACK_READBACK,inputs,db_objects}',
    '["public.lf_capability_current","public.lf_capability_version_registry"]'::jsonb,true);

  v_md := jsonb_set(v_md,'{m103_contract_governance_v1}',
    jsonb_build_object(
      'phase','CONSTRUCTION_SANDBOX',
      'operational_cutover_executed',false,
      'operational_cutover_authorized',false,
      'operational_zero_legacy_traffic_gate','SEPARATE_NOT_EVALUATED',
      'release_promotion_allowed',false,
      'legacy_drop_allowed',false,
      'source_anchor','INPUT_GOVERNANCE@1.0.0',
      'test_requirement','REAL_POINTER_REVERT_POSITIVE_NEGATIVE_AND_PROVIDER_BOUND_SUITE',
      'cp1_edge_validation','DEPLOYED_STATUS_REQUIRES_SEPARATE_READBACK',
      'cp3_test_artifact','NOT_YET_AUTHORED',
      'cp4_suite_run','NOT_YET_VERIFIED',
      'preflight_status','NOT_VERIFIED',
      'admission_rule','NO_CHECKPOINT_DONE_ON_CONTRACT_REPAIR_ONLY',
      'references',jsonb_build_array('M9.2','M10.2',
          'IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001',
          'IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001')),true);

  UPDATE programacion.engineering_plan_units
  SET exit_criterion=v_exit,unit_metadata=v_md
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=475;
  IF NOT FOUND THEN RAISE EXCEPTION 'M103_UNIT_UPDATE_FAILED'; END IF;

  UPDATE programacion.engineering_work_checkpoints
  SET title='Readback de CURRENT y ausencia de cutover operativo (sin inferir 0 tráfico post-switch)',
      updated_at=clock_timestamp()
  WHERE work_item_id=475 AND checkpoint_code='NOT_ACTIVE' AND status='PENDING';
  IF NOT FOUND THEN RAISE EXCEPTION 'M103_CP2_UPDATE_FAILED'; END IF;

  UPDATE programacion.engineering_work_checkpoints
  SET title='Readback final de CURRENT original, SHA registrado y evidencia de 0 residuos del simulacro',
      updated_at=clock_timestamp()
  WHERE work_item_id=475 AND checkpoint_code='ROLLBACK_READBACK' AND status='PENDING';
  IF NOT FOUND THEN RAISE EXCEPTION 'M103_CP5_UPDATE_FAILED'; END IF;

  -- Record root cause as ACTIVE, not falsely validated or solved.
  INSERT INTO transversal.error_knowledge (
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,
    prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,
    lote_origen,estado,evidencia,created_at,updated_at,root_cause_family,source_ref)
  SELECT gen_random_uuid(),'IG-M103-OPERATIONAL-CUTOVER-SANDBOX-CONFLATION-001',
    'ENGINEERING_CONTRACT','M10.3 exigía 0 tráfico posterior a un switch operativo no realizado',
    'La unidad de rollback sandbox confundía un switch reversible en ensayo con producción y consumía consultas que no probaban la obligación.',
    'Contract exit/CP2 exigían una evidencia de tráfico post-cutover no producible antes de la activación. CP4 aceptaba PASSED 1/1 de otro owner. CP5 consultaba bindings en lugar del CURRENT y SHA restaurados.',
    'CONTRACT_GOVERNANCE_SCOPE_AND_PRODUCER_MISMATCH',
    'Separar CONSTRUCTION_SANDBOX de operación; vincular CP2/3/4/5 a productores exactos; comprobar test positivo, negativo, fuente y readback sin promover release.',
    'Migración de reparación propuesta; test material y ledger pendientes. No marcar DONE por definir contrato.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.3','ACTIVO',
    'M10.2 DONE 6/6 pero activation_performed=false; CURRENT INPUT_GOVERNANCE 1.0.0; suite run ajeno 1/1.',
    clock_timestamp(),clock_timestamp(),
    'CONTRACT_GOVERNANCE_SCOPE',
    'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.3'
  WHERE NOT EXISTS (
    SELECT 1 FROM transversal.error_knowledge
    WHERE codigo='IG-M103-OPERATIONAL-CUTOVER-SANDBOX-CONFLATION-001');

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=475 AND status='PENDING')<>5
    OR (SELECT status FROM programacion.engineering_work_items WHERE id=475)<>'BACKLOG'
    OR (SELECT unit_metadata#>>'{m103_contract_governance_v1,preflight_status}'
        FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code=v_unit)
       IS DISTINCT FROM 'NOT_VERIFIED'
  THEN RAISE EXCEPTION 'M103_PRECHECK_REPAIR_MUST_NOT_CLOSE_UNIT'; END IF;
END
$m103_preflight$;
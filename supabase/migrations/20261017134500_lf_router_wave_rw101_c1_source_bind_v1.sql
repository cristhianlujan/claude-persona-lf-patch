-- LF Router wave RW1-01 C1 only: explicit source and read-only action contract.
-- No Router/Train/runtime/authorizer mutations; no checkpoint completion.
BEGIN;
DO $rw101_c1$
DECLARE
  v_plan CONSTANT text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit CONSTANT text := 'RW1-01';
  v_expected_md5 CONSTANT text := '2e5c6f6cac067d04f892d5e25e8cfea8';
  v_actor CONSTANT text := 'MIGRATION_VIA_MERGE_TRAIN_ROUTER_RW101_C1_BIND_V1';
  v_spec jsonb := '{"status":"READY","schema_version":"ENGINEERING_ACTION_SPEC_V3","checkpoint_code":"RW1-01_C1","contract_source":"EXPLICIT_ACTION_SPEC","contract_family":"READ_ONLY_EVIDENCE","precision":"EXACT_ROUTER_NEEDS_AUTHORITY","action_kind":"READBACK_ONCE","recipe_mode":"READBACK_EXACT","mutation_policy":"NO_DOMAIN_MUTATION","target":{"checkpoint":"RW1-01_C1","declared_assets":["ACT-0001"],"declared_events":[21263],"declared_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","public.lf_error_knowledge"],"declared_artifacts":[],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md","role":"EVIDENCE","purpose":"NEEDS_SOURCES_AND_BIASES","target_kind":"EXACT_EXISTING_FILE"}],"mutation_artifacts":[]},"expected":"Read exact existing A16Q C1 source, active EKB and unit readbacks, compare the original needs/bias documentation to each; no architecture selection or E2E claim.","forbidden":["MUTATE_ROUTER_RUNTIME","REPEAT_COMPLETED_A16Q_C1_INVENTORY","ELEVATE_CURRENT_CABLES_TO_NORMATIVE_ARCHITECTURE","MARK_DONE_BECAUSE_DOCUMENT_EXISTS","SYNTHETIC_SOURCE_CURRENTNESS","ACTIVATE_PRODUCTION"],"action_steps":["READ_DECLARED_SOURCES_ONCE","VERIFY_DOCUMENT_FULL_CONTENT_AND_CURRENT_SHA","VERIFY_EKB_AND_CANONICAL_PLAN_CURRENT","SEPARATE_REQUIREMENTS_FROM_DIAGNOSTIC_OBSERVATIONS","PERSIST_CURRENTNESS_ATTESTED_C1_EVIDENCE","CONTINUE_TO_C2_IF_C1_PASS"],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_source_verified":true,"ekb_references_verified":true,"a16q_c1_reused_not_duplicated":true,"needs_traceable":true,"architecture_not_preselected":true,"source_sha_current":true}},"verification_queries":["SELECT u.plan_code,u.unit_code,u.work_item_id,c.checkpoint_code,c.status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id WHERE u.plan_code=''LF_ROUTER_ARCHITECTURE_WAVE_V1'' AND u.unit_code=''RW1-01'' AND c.checkpoint_code=''RW1-01_C1''","SELECT u.unit_code,c.checkpoint_code,c.status,c.evidence_ref FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id WHERE u.plan_code=''PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'' AND u.unit_code=''A16Q'' AND c.checkpoint_code=''A16Q_C1''","SELECT codigo,titulo,causa_raiz,prevencion FROM public.lf_error_knowledge WHERE codigo IN (''LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001'',''LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002'',''LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002'',''LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003'',''CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'') ORDER BY codigo"],"requires_material_execution":false}'::jsonb;
  v_pack jsonb := '{"checkpoint_inputs":{"RW1-01_C1":{"inputs":{"assets":["ACT-0001"],"events":[21263],"queries":["SELECT u.plan_code,u.unit_code,u.work_item_id,c.checkpoint_code,c.status FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id WHERE u.plan_code=''LF_ROUTER_ARCHITECTURE_WAVE_V1'' AND u.unit_code=''RW1-01'' AND c.checkpoint_code=''RW1-01_C1''","SELECT u.unit_code,c.checkpoint_code,c.status,c.evidence_ref FROM programacion.engineering_plan_units u JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id WHERE u.plan_code=''PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'' AND u.unit_code=''A16Q'' AND c.checkpoint_code=''A16Q_C1''","SELECT codigo,titulo,causa_raiz,prevencion FROM public.lf_error_knowledge WHERE codigo IN (''LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001'',''LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002'',''LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002'',''LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003'',''CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'') ORDER BY codigo"],"db_objects":["programacion.engineering_plan_units","programacion.engineering_work_checkpoints","public.lf_error_knowledge"],"artifacts":["docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md","docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md"]},"expected_result":"Verified owner needs and biases are separated from diagnostic source; source current readback reuses A16Q_C1, preserves C2/C3 pending.","missing":[],"missing_typed":[],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md","verification_boundary":"RW1_01_C1_SOURCE_READ_ONLY_NOT_ARCHITECTURE_SELECTION"}}}'::jsonb;
  v_count bigint;
  v_new jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
    JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id
    WHERE u.plan_code=v_plan AND u.unit_code=v_unit
      AND u.work_item_id=1127 AND u.plan_event_id=21263
      AND w.work_code='ROUTER-W1-01' AND w.status='BACKLOG'
      AND c.checkpoint_code='RW1-01_C1' AND c.status='PENDING'
      AND md5(u.unit_metadata::text)=v_expected_md5
      AND u.unit_metadata ? 'checkpoint_contracts'
      AND NOT u.unit_metadata ? 'action_specs_v1'
      AND NOT u.unit_metadata ? 'source_pack_v2'
  ) THEN
    RAISE EXCEPTION 'ROUTER_RW101_C1_SOURCE_STALE_OR_CHECKPOINT_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
    ('LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001',
     'LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002',
     'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',
     'LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003',
     'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL')) <> 5
  THEN RAISE EXCEPTION 'ROUTER_RW101_C1_EKB_REFERENCE_NOT_ATTESTED'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_plan_units u
     JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
     WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'
       AND u.unit_code='A16Q' AND c.checkpoint_code='A16Q_C1'
       AND c.status='DONE' AND c.evidence_ref IS NOT NULL) <> 1
  THEN RAISE EXCEPTION 'ROUTER_RW101_C1_A16Q_CURRENT_SOURCE_MISSING'; END IF;
  v_new := (
    SELECT jsonb_set(
      jsonb_set(u.unit_metadata,
        '{action_specs_v1}',
        jsonb_build_object('RW1-01_C1',v_spec),
        true),
      '{source_pack_v2}',v_pack,true)
    FROM programacion.engineering_plan_units u
    WHERE u.plan_code=v_plan AND u.unit_code=v_unit
  );
  IF jsonb_typeof(v_new->'action_specs_v1'->'RW1-01_C1') IS DISTINCT FROM 'object'
     OR v_new#>>'{action_specs_v1,RW1-01_C1,action_kind}' IS DISTINCT FROM 'READBACK_ONCE'
     OR jsonb_array_length(v_new#>'{source_pack_v2,checkpoint_inputs,RW1-01_C1,inputs,queries}') <> 3
  THEN RAISE EXCEPTION 'ROUTER_RW101_C1_SOURCE_BIND_CONTRACT_INVALID'; END IF;
  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND md5(unit_metadata::text)=v_expected_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count <> 1 THEN RAISE EXCEPTION 'ROUTER_RW101_C1_SOURCE_BIND_WRITE_COUNT:%',v_count; END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND c.status='PENDING') <> 3
      OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units u
           JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
           WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND w.status<>'BACKLOG')
  THEN RAISE EXCEPTION 'ROUTER_RW101_C1_NO_CLOSURE_INVARIANT_BREACHED'; END IF;
  IF v_actor IS NULL THEN RAISE EXCEPTION 'NEVER'; END IF;
END
$rw101_c1$;
COMMIT;

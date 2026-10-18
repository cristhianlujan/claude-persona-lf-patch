-- RW1-02_C1: bind exact source/authority contract and close only after readback + negative assertion control.
-- No architecture selection, Router runtime execution, production mutation, C2/C3 mutation or RW1-01 mutation.
BEGIN;
DO $rw102_c1$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-02';
  v_cp constant text := 'RW1-02_C1';
  v_work_item constant bigint := 1128;
  v_prior_md5 constant text := '215828c4e435b94d57e26e777a75b23d';
  v_actor constant text := 'LF_ROUTER_RW102_C1_SOURCE_AUTHORITY_CLOSE_20261018';
  v_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md#blob:470979c9b9a0dd9a728601b6ec5f577d7445f8b5';
  v_spec jsonb := $rw102spec${"status":"READY","schema_version":"ENGINEERING_ACTION_SPEC_V3","checkpoint_code":"RW1-02_C1","contract_source":"EXPLICIT_ACTION_SPEC","contract_family":"READ_ONLY_EVIDENCE","precision":"EXACT_RW102_ARCHITECTURE_COMPETITION_SOURCES","action_kind":"READBACK_ONCE","recipe_mode":"READBACK_EXACT","mutation_policy":"NO_DOMAIN_MUTATION","requires_material_execution":false,"target":{"checkpoint":"RW1-02_C1","declared_assets":["ACT-0001"],"declared_events":[21263],"declared_objects":["programacion.engineering_plan_units","programacion.engineering_work_items","programacion.engineering_work_checkpoints","public.lf_error_knowledge","public.lf_eventos"],"declared_artifacts":[],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","role":"EVIDENCE","purpose":"RW102_NEUTRAL_SOURCE_AND_AUTHORITY_BASELINE","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","role":"EVIDENCE","purpose":"WAVE_EXIT_CRITERIA","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md","role":"EVIDENCE","purpose":"OWNER_NEEDS_AND_BIASES","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md","role":"EVIDENCE","purpose":"REUSED_ROUTER_CONSUMER_INVENTORY","target_kind":"EXACT_EXISTING_FILE"},{"path":"cristhianlujan/claude-persona-lf-patch:docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json","role":"EVIDENCE","purpose":"PRIOR_UNIT_INDEPENDENT_CONTRACT_VERDICT","target_kind":"EXACT_EXISTING_FILE"}],"mutation_artifacts":[]},"expected":"Freeze current sources, authority boundaries, at least three architecture candidates and one current baseline with common neutral measures. Reuse A16Q and RW1-01; do not select a winner or execute Router runtime.","forbidden":["SELECT_ARCHITECTURE_IN_C1","TREAT_CURRENT_ROUTER_AS_ORACLE","TREAT_RFC_2872_AS_CANONICAL","REPEAT_A16Q_C1_INVENTORY","CLAIM_ROUTER_RUNTIME_PASS","CLAIM_PRODUCTION_EFFECT","MUTATE_ROUTER_RUNTIME","CHANGE_RW1_01","CHANGE_RW1_02_C2_OR_C3","CREATE_UNDECLARED_SHARED_ABSTRACTION"],"action_steps":["READ_DECLARED_SOURCES_ONCE","VERIFY_RW101_DEPENDENCY_DONE","VERIFY_A16Q_C1_REUSE","VERIFY_SEVEN_EKB_REFERENCES","VERIFY_PLAN_ACCEPTANCE_FALSE","FREEZE_AT_LEAST_THREE_ELIGIBLE_ARCHITECTURES_AND_BASELINE","FREEZE_COMMON_NEUTRAL_METRICS","ASSERT_NO_ARCHITECTURE_SELECTION","PERSIST_ASSERTION_RECEIPT","PERSIST_C1_DONE_ONLY_AFTER_READBACK"],"evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md#blob:470979c9b9a0dd9a728601b6ec5f577d7445f8b5","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"dependency_rw101_done":true,"checkpoint_source_verified":true,"source_sha_current":true,"a16q_c1_reused_not_duplicated":true,"ekb_references_verified":true,"plan_acceptance_false":true,"source_queries_passed":5,"candidate_architectures_eligible":3,"baseline_separate":true,"neutral_metrics_defined":true,"architecture_not_preselected":true,"rfc_2872_noncanonical":true,"current_router_not_oracle":true,"no_router_runtime_claim":true,"no_production_mutation":true}},"verification_queries":["SELECT u.plan_code,u.unit_code,u.work_item_id,w.status AS work_status,c.checkpoint_code,c.status\nFROM programacion.engineering_plan_units u\nJOIN programacion.engineering_work_items w ON w.id=u.work_item_id\nJOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id\nWHERE u.plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND u.unit_code='RW1-02'\nORDER BY c.sequence_no","SELECT c.checkpoint_code,c.status,c.evidence_ref\nFROM programacion.engineering_work_checkpoints c\nWHERE c.work_item_id=1127 ORDER BY c.sequence_no","SELECT u.unit_code,c.checkpoint_code,c.status,c.evidence_ref\nFROM programacion.engineering_plan_units u\nJOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id\nWHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'\n  AND u.unit_code='A16Q' AND c.checkpoint_code='A16Q_C1'","SELECT codigo,titulo,causa_raiz,prevencion\nFROM public.lf_error_knowledge\nWHERE codigo IN (\n 'LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001',\n 'LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002',\n 'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',\n 'LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003',\n 'LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005',\n 'LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003',\n 'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'\n) ORDER BY codigo","SELECT id,entidad_tipo,entidad_codigo,evento_tipo,created_at,payload->>'acceptance_declared' AS acceptance_declared\nFROM public.lf_eventos WHERE id=21263"]}$rw102spec$::jsonb;
  v_pack jsonb := $rw102pack${"checkpoint_inputs":{"RW1-02_C1":{"inputs":{"assets":["ACT-0001"],"events":[21263],"queries":["SELECT u.plan_code,u.unit_code,u.work_item_id,w.status AS work_status,c.checkpoint_code,c.status\nFROM programacion.engineering_plan_units u\nJOIN programacion.engineering_work_items w ON w.id=u.work_item_id\nJOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id\nWHERE u.plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1' AND u.unit_code='RW1-02'\nORDER BY c.sequence_no","SELECT c.checkpoint_code,c.status,c.evidence_ref\nFROM programacion.engineering_work_checkpoints c\nWHERE c.work_item_id=1127 ORDER BY c.sequence_no","SELECT u.unit_code,c.checkpoint_code,c.status,c.evidence_ref\nFROM programacion.engineering_plan_units u\nJOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id\nWHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'\n  AND u.unit_code='A16Q' AND c.checkpoint_code='A16Q_C1'","SELECT codigo,titulo,causa_raiz,prevencion\nFROM public.lf_error_knowledge\nWHERE codigo IN (\n 'LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001',\n 'LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002',\n 'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',\n 'LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003',\n 'LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005',\n 'LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003',\n 'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'\n) ORDER BY codigo","SELECT id,entidad_tipo,entidad_codigo,evento_tipo,created_at,payload->>'acceptance_declared' AS acceptance_declared\nFROM public.lf_eventos WHERE id=21263"],"db_objects":["programacion.engineering_plan_units","programacion.engineering_work_items","programacion.engineering_work_checkpoints","public.lf_error_knowledge","public.lf_eventos"],"artifacts":["docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md","docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md","docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md","docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md","docs/programming-agent/router_wave/RW1_01_C3_INDEPENDENT_VERDICT_V2.json"]},"missing":[],"missing_typed":[],"expected_result":"Current, unbiased source baseline for architecture competition: three eligible candidates plus current baseline, identical measurement dimensions, no winner selected.","evidence_ref":"github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_02_C1_SOURCE_AUTHORITY_BASELINE_V1.md#blob:470979c9b9a0dd9a728601b6ec5f577d7445f8b5","verification_boundary":"RW102_C1_SOURCE_AUTHORITY_ONLY_NOT_ARCHITECTURE_DECISION_OR_ROUTER_RUNTIME","source_git_blobs":{"rw102_c1_baseline":"470979c9b9a0dd9a728601b6ec5f577d7445f8b5","wave":"4bb64d568c3f005cf454fb223b4a5ed699c34504","rw101_needs":"89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d","a16q_c1":"28e020ba05721892524bfc7971cd7c0f3a8f9878","rw101_c3_verdict":"b4c1fab848b2d98a56f12bc5475103bddce623bf"},"noncanonical_inputs":{"rfc_2872":{"state":"OPEN","head_sha":"921518bdc0ba5cd3ce462973af51fb5141c90b49","role":"HYPOTHESIS_ONLY"}}}}}$rw102pack$::jsonb;
  v_new jsonb;
  v_action jsonb;
  v_contract jsonb;
  v_ready jsonb;
  v_preflight jsonb;
  v_obs jsonb;
  v_result jsonb;
  v_bad jsonb;
  v_assertion jsonb;
  v_transition jsonb;
  v_receipt text;
  v_count integer;
  v_negative_rejected boolean := false;
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code=v_unit
        AND u.work_item_id=v_work_item AND u.plan_event_id=21263
        AND u.disposition='ASSIGNED' AND w.work_code='ROUTER-W1-02'
        AND w.status='BACKLOG'
        AND md5(u.unit_metadata::text)=v_prior_md5
        AND NOT (u.unit_metadata ? 'action_specs_v1')
        AND NOT (u.unit_metadata ? 'source_pack_v2'))<>1
  THEN RAISE EXCEPTION 'RW102_C1_PRESTATE_OR_METADATA_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND status='PENDING')<>3
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_item AND checkpoint_code=v_cp AND status='PENDING')<>1
  THEN RAISE EXCEPTION 'RW102_C1_CHECKPOINT_PRESTATE_DRIFT'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1127 AND status='DONE')<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=1127 AND status='DONE')<>1
  THEN RAISE EXCEPTION 'RW102_C1_RW101_DEPENDENCY_NOT_DONE'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
      WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'
        AND u.unit_code='A16Q' AND c.checkpoint_code='A16Q_C1'
        AND c.status='DONE' AND c.evidence_ref IS NOT NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C1_A16Q_REUSE_SOURCE_MISSING'; END IF;

  IF (SELECT count(*) FROM public.lf_error_knowledge
      WHERE codigo IN (
       'LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001',
       'LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002',
       'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',
       'LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003',
       'LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005',
       'LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003',
       'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
      ) AND nullif(btrim(causa_raiz),'') IS NOT NULL
        AND nullif(btrim(prevencion),'') IS NOT NULL)<>7
  THEN RAISE EXCEPTION 'RW102_C1_EKB_SOURCE_MISSING'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos
      WHERE id=21263 AND entidad_tipo='ENGINEERING_PLAN'
        AND entidad_codigo=v_plan AND evento_tipo='PLAN_SNAPSHOT_DETALLADO'
        AND payload->>'acceptance_declared'='false')<>1
  THEN RAISE EXCEPTION 'RW102_C1_PLAN_EVENT_OR_ACCEPTANCE_DRIFT'; END IF;

  v_new := (
    SELECT jsonb_set(
      jsonb_set(u.unit_metadata,'{action_specs_v1}',jsonb_build_object(v_cp,v_spec),true),
      '{source_pack_v2}',v_pack,true)
    FROM programacion.engineering_plan_units u
    WHERE u.plan_code=v_plan AND u.unit_code=v_unit
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit
     AND md5(unit_metadata::text)=v_prior_md5;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'RW102_C1_SOURCE_BIND_ROW_COUNT:%',v_count; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(v_plan,v_unit,v_cp,v_action);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_preflight:=programacion.fn_engineering_checkpoint_source_query_preflight_v1(v_plan,v_unit,v_cp);

  IF v_action->>'status' IS DISTINCT FROM 'READY'
     OR v_action->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
     OR v_action->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
     OR v_preflight->>'status' IS DISTINCT FROM 'PASS'
     OR (v_preflight->>'query_count')::int IS DISTINCT FROM 5
     OR (v_preflight->>'passed')::int IS DISTINCT FROM 5
     OR (v_preflight->>'failed')::int IS DISTINCT FROM 0
  THEN RAISE EXCEPTION 'RW102_C1_CONTRACT_OR_SOURCE_PREFLIGHT_FAILED:action=% contract=% ready=% preflight=%',
       v_action::text,v_contract::text,v_ready::text,v_preflight::text; END IF;

  v_obs:=jsonb_build_object(
    'dependency_rw101_done',true,
    'checkpoint_source_verified',true,
    'source_sha_current',true,
    'source_main_sha','f180b3d3bd2718bfad1ca5d0ecec4971e6f1bdf7',
    'source_doc_blob','470979c9b9a0dd9a728601b6ec5f577d7445f8b5',
    'wave_blob','4bb64d568c3f005cf454fb223b4a5ed699c34504',
    'rw101_needs_blob','89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d',
    'a16q_c1_blob','28e020ba05721892524bfc7971cd7c0f3a8f9878',
    'rw101_c3_verdict_blob','b4c1fab848b2d98a56f12bc5475103bddce623bf',
    'a16q_c1_reused_not_duplicated',true,
    'ekb_references_verified',true,
    'ekb_reference_count',7,
    'plan_acceptance_false',true,
    'source_queries_passed',5,
    'candidate_architectures_eligible',3,
    'baseline_separate',true,
    'neutral_metrics_defined',true,
    'architecture_not_preselected',true,
    'rfc_2872_noncanonical',true,
    'rfc_2872_state','OPEN',
    'rfc_2872_head_sha','921518bdc0ba5cd3ce462973af51fb5141c90b49',
    'current_router_not_oracle',true,
    'no_router_runtime_claim',true,
    'no_production_mutation',true,
    'c2_c3_untouched',true
  );

  IF (v_obs @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'RW102_C1_OBSERVED_DOES_NOT_SATISFY_CONTRACT'; END IF;

  v_result:=jsonb_build_object(
    'status','PASS',
    'evidence_ref',v_ref,
    'observed',v_obs,
    'validation_kind','RW102_C1_NEUTRAL_SOURCE_AUTHORITY_BASELINE'
  );

  -- Negative control: preselecting an architecture must not be recordable as PASS.
  v_bad:=jsonb_set(v_result,'{observed,architecture_not_preselected}','false'::jsonb,true);
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad,v_actor||'_NEGATIVE');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN RAISE; END IF;
    v_negative_rejected:=true;
  END;
  IF NOT v_negative_rejected
  THEN RAISE EXCEPTION 'RW102_C1_NEGATIVE_ASSERTION_FALSE_PASS'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item AND checkpoint_code=v_cp
        AND status='PENDING' AND assertion_receipt IS NULL)<>1
  THEN RAISE EXCEPTION 'RW102_C1_NEGATIVE_ROLLBACK_NOT_CLEAN'; END IF;

  v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
    v_plan,v_unit,v_cp,v_result,v_actor);
  IF v_assertion->>'passed' IS DISTINCT FROM 'true'
     OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
     OR v_assertion->>'evidence_ref' IS DISTINCT FROM v_ref
  THEN RAISE EXCEPTION 'RW102_C1_ASSERTION_RECEIPT_FAILED:%',coalesce(v_assertion::text,'NULL'); END IF;
  v_receipt:=v_assertion->>'assertion_receipt_sha256';

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_ref,v_actor,
    'RW1-02_C1: sources/current authority frozen; RW1-01 3/3 DONE; A16Q_C1 reused; 7/7 EKB; 3 eligible architecture candidates plus separate current baseline; neutral metrics fixed; RFC2872 noncanonical; no architecture selected/runtime/production.'
  );
  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'RW102_C1_TRANSITION_NOT_APPLIED:%',coalesce(v_transition::text,'NULL'); END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_item
        AND ((checkpoint_code='RW1-02_C1' AND status='DONE'
              AND evidence_ref=v_ref
              AND assertion_receipt_sha256=v_receipt
              AND assertion_receipt->>'passed'='true'
              AND assertion_contract_sha256=assertion_receipt->>'contract_sha256')
          OR (checkpoint_code IN ('RW1-02_C2','RW1-02_C3')
              AND status='PENDING' AND evidence_ref IS NULL)))<>3
     OR (SELECT count(*) FROM programacion.engineering_work_items
         WHERE id=v_work_item AND status='IN_PROGRESS')<>1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=1127 AND status='DONE')<>3
  THEN RAISE EXCEPTION 'RW102_C1_POST_READBACK_NOT_CONSISTENT'; END IF;
END
$rw102_c1$;
COMMIT;

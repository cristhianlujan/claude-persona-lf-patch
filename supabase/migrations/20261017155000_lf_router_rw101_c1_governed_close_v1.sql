-- Governed C1 source-readback closure, no Router/Train/production mutation.
-- Requires previously merged source pack and exact C1 source evidence.
BEGIN;
DO $rw101_c1_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-01';
  v_cp constant text := 'RW1-01_C1';
  v_actor constant text := 'MIGRATION_VIA_MERGE_TRAIN_ROUTER_RW101_C1_CLOSE_V1';
  v_ref constant text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md@edf61fe3a503f49b6ddcada3232819633efbbace#blob:89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d';
  v_ready jsonb;
  v_preflight jsonb;
  v_action jsonb;
  v_transition jsonb;
BEGIN
  IF (SELECT count(*) FROM public.lf_eventos WHERE id=21263
        AND entidad_tipo='ENGINEERING_PLAN'
        AND entidad_codigo=v_plan)=0
  THEN RAISE EXCEPTION 'RW101_C1_PLAN_EVENT_NOT_FOUND'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_plan_units u
       JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
       JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id
       WHERE u.plan_code=v_plan AND u.unit_code=v_unit
         AND u.work_item_id=1127 AND u.disposition='ASSIGNED'
         AND w.work_code='ROUTER-W1-01' AND w.status='BACKLOG'
         AND c.id=1607 AND c.checkpoint_code=v_cp AND c.status='PENDING'
         AND u.unit_metadata ? 'action_specs_v1'
         AND u.unit_metadata ? 'source_pack_v2')<>1
  THEN RAISE EXCEPTION 'RW101_C1_SOURCE_OR_CHECKPOINT_STALE'; END IF;

  IF (SELECT count(*) FROM programacion.engineering_plan_units u
       JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
       WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'
         AND u.unit_code='A16Q' AND c.checkpoint_code='A16Q_C1'
         AND c.status='DONE' AND c.evidence_ref IS NOT NULL)<>1
  THEN RAISE EXCEPTION 'RW101_C1_A16Q_REUSE_EVIDENCE_MISSING'; END IF;

  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN (
       'LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001',
       'LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002',
       'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',
       'LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003',
       'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
     ) AND nullif(btrim(causa_raiz),'') IS NOT NULL
       AND nullif(btrim(prevencion),'') IS NOT NULL)<>5
  THEN RAISE EXCEPTION 'RW101_C1_EKB_AUTHORITY_SOURCE_MISSING'; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  v_preflight:=programacion.fn_engineering_checkpoint_source_query_preflight_v1(v_plan,v_unit,v_cp);

  IF v_action->>'status' IS DISTINCT FROM 'READY'
     OR v_action->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
     OR v_action->>'contract_source' IS DISTINCT FROM 'EXPLICIT_ACTION_SPEC'
     OR v_ready->>'status' IS DISTINCT FROM 'READY'
     OR coalesce((v_ready->>'execution_ready')::boolean,false) IS NOT TRUE
     OR v_ready#>>'{source_currentness,status}' IS DISTINCT FROM 'CURRENT'
     OR v_preflight->>'status' IS DISTINCT FROM 'PASS'
     OR (v_preflight->>'query_count')::int IS DISTINCT FROM 3
     OR (v_preflight->>'passed')::int IS DISTINCT FROM 3
     OR (v_preflight->>'failed')::int IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'RW101_C1_READBACK_NOT_ADMITTED:action=%,ready=%,source_preflight=%',
      v_action->>'status',v_ready->>'status',v_preflight->>'status';
  END IF;

  v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
      v_plan,v_unit,v_cp,'DONE',v_ref,v_actor,
      'RW1-01_C1: owner needs N01-N12, sources S01-S10, biases B01-B10; Git main PR2876 merge edf61fe3a503f49b6ddcada3232819633efbbace; source 3/3 PASS, A16Q_C1 reusable, 5/5 EKB. No C2/C3 acceptance.'
  );

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
      WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND
        ((c.checkpoint_code='RW1-01_C1' AND c.status='DONE' AND c.evidence_ref=v_ref)
        OR (c.checkpoint_code IN ('RW1-01_C2','RW1-01_C3') AND c.status='PENDING')))<>3
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
         JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
         WHERE u.plan_code=v_plan AND c.status='DONE')<>1
    OR (SELECT count(*) FROM programacion.engineering_work_items WHERE work_code='ROUTER-W1-01' AND status='IN_PROGRESS')<>1
  THEN RAISE EXCEPTION 'RW101_C1_CLOSURE_READBACK_FAILED'; END IF;
  IF v_transition IS NULL THEN RAISE EXCEPTION 'RW101_C1_TRANSITION_RECEIPT_MISSING'; END IF;
END
$rw101_c1_close$;
COMMIT;

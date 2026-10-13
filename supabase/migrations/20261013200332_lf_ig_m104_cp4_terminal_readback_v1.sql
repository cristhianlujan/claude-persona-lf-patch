-- M10.4 CP4 exact baseline verification; terminal readback, no runtime or legacy changes.
-- Preflight: EKB IG-M104-LEGACY-ACTIVE-FREEZE-SCOPE-001 and
-- IG-M1011-NONMATERIAL-READBACK-MISSING-QUERY-001, avoid old prefix scans.
BEGIN;
DO $m104_cp4$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text := 'M10.4';
 v_cp constant text := 'FREEZE_READBACK';
 v_query text := $exact_readback$
WITH frozen AS (
  SELECT pu.unit_metadata->'m104_freeze_baseline_v1' AS baseline,
         pu.unit_metadata->'m104_freeze_rule_v1' AS ci_rule
  FROM programacion.engineering_plan_units pu
  WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND pu.unit_code='M10.4'
    AND pu.work_item_id=476
), items AS (
  SELECT z.value->>'identity' AS sig,z.value->>'prosrc_md5' AS expected_md5
  FROM frozen b CROSS JOIN LATERAL jsonb_array_elements(b.baseline->'legacy_functions') z
), live AS (
  SELECT i.sig,i.expected_md5,p.oid,md5(p.prosrc) AS live_md5
  FROM items i LEFT JOIN LATERAL (
    SELECT p.oid,p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname=split_part(split_part(i.sig,'(',1),'.',1)
      AND p.proname=split_part(split_part(i.sig,'(',1),'.',2)
      AND n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=i.sig
  ) p ON true
), agg AS (
  SELECT count(*) AS expected_count,
         count(*) FILTER (WHERE oid IS NOT NULL) AS resolved_count,
         count(*) FILTER (WHERE oid IS NULL OR live_md5 IS DISTINCT FROM expected_md5) AS drift_count,
         md5(string_agg(sig||':'||coalesce(live_md5,'MISSING'),'|' ORDER BY sig)) AS live_aggregate_md5
  FROM live
)
SELECT jsonb_build_object(
  'status',CASE WHEN a.expected_count>0
    AND a.expected_count=a.resolved_count AND a.drift_count=0
    AND a.live_aggregate_md5=b.baseline->>'sql_aggregate_md5'
    AND b.ci_rule->>'status'='INSTALLED_ENGINEERING_CI'
    AND b.ci_rule->>'adversarial_live_pr_test'='CI_FAIL_EXPECTED_PR2464_CLOSED_UNMERGED_LEDGER_ZERO'
    THEN 'PASS' ELSE 'FAIL' END,
  'frozen_functions',a.expected_count,
  'resolved_functions',a.resolved_count,
  'drift_count',a.drift_count,
  'current_aggregate_md5',a.live_aggregate_md5,
  'expected_aggregate_md5',b.baseline->>'sql_aggregate_md5',
  'guard_status',b.ci_rule->>'status',
  'adversarial_ci_status',b.ci_rule->>'adversarial_live_pr_test',
  'edge_legacy_count',b.baseline->>'legacy_edge_count',
  'source_classification_event_id',b.baseline->>'classification_event_id'
)
FROM agg a CROSS JOIN frozen b
$exact_readback$;
 v_metadata jsonb;
 v_spec jsonb;
 v_cp_input jsonb;
 v_state jsonb;
 v_ready jsonb;
 v_report jsonb;
 v_out jsonb;
 v_evidence text;
 v_missing integer;
BEGIN
 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
    OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'M104_CP4_NOT_CURRENT'; END IF;
 SELECT count(*) INTO v_missing
 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=476
   AND c.checkpoint_code IN ('FROZEN_SET_ASIS','FREEZE_RULE','NEG_NEW_MIGRATION')
   AND (c.status<>'DONE' OR nullif(c.evidence_ref,'') IS NULL);
 IF v_missing<>0 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=476 AND status='DONE')<>3
 THEN RAISE EXCEPTION 'M104_CP4_UPSTREAM_CP_NOT_VALIDATED'; END IF;
 IF NOT EXISTS (
 SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=476 AND checkpoint_code='NEG_NEW_MIGRATION'
   AND assertion_receipt->>'passed'='true'
   AND nullif(assertion_receipt_sha256,'') IS NOT NULL
 ) THEN RAISE EXCEPTION 'M104_CP4_NEGATIVE_RECEIPT_MISSING'; END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations
     WHERE name IN (
      'lf_ig_m104_cp1_legacy_exact_baseline_v1',
      'lf_ig_m104_cp2_guard_admission_v1',
      'lf_ig_m104_cp3_negative_ci_receipt_v1'
     ))<>3
 THEN RAISE EXCEPTION 'M104_CP4_CANONICAL_MIGRATIONS_MISSING'; END IF;
 IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
            WHERE name='lf_ig_m104_negative_ci_probe_reject')
 THEN RAISE EXCEPTION 'M104_CP4_NEGATIVE_MIGRATION_HAS_LEDGER'; END IF;

 -- Replace broad fn_input_governance% legacy query with the pinned exact-signature baseline.
 SELECT unit_metadata INTO v_metadata
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476
 FOR UPDATE;
 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
 IF v_spec->>'status'<>'READY' OR v_spec->>'action_kind'<>'READBACK_ONCE'
 THEN RAISE EXCEPTION 'M104_CP4_SOURCE_ACTION_NOT_READY'; END IF;
 v_spec:=jsonb_set(v_spec,'{verification_queries}',to_jsonb(array[v_query,
  'select version,name from supabase_migrations.schema_migrations where name like ''%m104_cp%'' order by version'
 ]),true);
 v_spec:=jsonb_set(v_spec,'{target,declared_objects}',
  '["pg_catalog.pg_proc","programacion.engineering_plan_units","supabase_migrations.schema_migrations"]'::jsonb,true);
 v_metadata:=jsonb_set(v_metadata,'{action_specs_v1,FREEZE_READBACK}',v_spec,true);
 v_cp_input:=v_metadata#>'{source_pack_v1,checkpoint_inputs,FREEZE_READBACK,inputs}';
 v_cp_input:=jsonb_set(v_cp_input,'{queries}',v_spec->'verification_queries',true);
 v_cp_input:=jsonb_set(v_cp_input,'{db_objects}',
  '["pg_catalog.pg_proc","programacion.engineering_plan_units","supabase_migrations.schema_migrations"]'::jsonb,true);
 v_metadata:=jsonb_set(v_metadata,
  '{source_pack_v1,checkpoint_inputs,FREEZE_READBACK,inputs}',v_cp_input,true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_metadata
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476;

 EXECUTE v_query INTO v_report;
 IF v_report->>'status'<>'PASS'
    OR (v_report->>'frozen_functions')::integer<>26
    OR (v_report->>'resolved_functions')::integer<>26
    OR (v_report->>'drift_count')::integer<>0
 THEN RAISE EXCEPTION 'M104_CP4_EXACT_READBACK_FAILED:%',v_report; END IF;

 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'M104_CP4_CONNECTOR_READINESS_FAILED:%',v_ready; END IF;

 v_evidence:='supabase://programacion.engineering_plan_units/M10.4#m104_freeze_baseline_v1'
  ||';supabase://pg_catalog.pg_proc/26-of-26-no-drift'
  ||';github://cristhianlujan/claude-persona-lf-patch/pull/2460'
  ||';github://cristhianlujan/claude-persona-lf-patch/pull/2462'
  ||';github://cristhianlujan/claude-persona-lf-patch/pull/2466'
  ||';github://cristhianlujan/claude-persona-lf-patch/pull/2464'
  ||';supabase://supabase_migrations.schema_migrations/M104_CP1_CP2_CP3_EXACT';
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,v_unit,v_cp,'ACTION_STARTED',NULL,'{}'::jsonb,
   v_evidence,'IG_M104_CP4_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP4_START_FAILED:%',v_out; END IF;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(
   v_plan,v_unit,v_cp,'ACTION_DONE',NULL,'{}'::jsonb,
   v_evidence,'IG_M104_CP4_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP4_END_FAILED:%',v_out; END IF;

 v_out:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,v_cp,'DONE',v_evidence,'IG_M104_CP4_TRAIN',
    '26/26 SQL legacy exact signatures unchanged vs immutable CP1; 0 drift; CI freeze installed; negative PR rejected and never applied');
 IF v_out#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M104_CP4_TRANSITION_FAILED:%',v_out; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=476 AND status='DONE')<>4
    OR (SELECT progress_pct FROM programacion.v_engineering_work_progress
        WHERE work_code='PAULO-163')<>100
    OR (SELECT status FROM programacion.engineering_work_items WHERE id=476)<>'DONE'
 THEN RAISE EXCEPTION 'M104_CP4_UNIT_NOT_TERMINAL_DONE'; END IF;
 -- Terminal evidence is distinct from source CP1 baseline.
 UPDATE programacion.engineering_plan_units SET
    unit_metadata=jsonb_set(
      unit_metadata,'{m104_terminal_readback_v1}',
      v_report || jsonb_build_object('readback_class','ENGINEERING_TERMINAL','runtime_activated',false,
          'production_activation',false,'destructive_change',false),true)
 WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=476;

 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,lote_origen,source_ref,evidencia)
 SELECT
 'IG-M104-TERMINAL-PREFIX-READBACK-INSUFFICIENT-001','ENGINEERING_GOVERNANCE',
 'Readback terminal por prefijo no demuestra congelamiento legacy exacto',
 'La consulta original FREEZE_READBACK recorria fn_input_governance% y no comparaba identidades ni hashes de CP1 ni Edge clasificados; solo presencia SQL.',
 'Contrato terminal de READBACK_ONCE sin comparador contra baseline inmutable ni guard CI.',
 'BROAD_CURRENT_FUNCTION_QUERY_MISTAKEN_FOR_ZERO_DRIFT_PROOF',
 'Usar identidades de firma exacta congeladas en CP1, comparar md5(prosrc) por identidad, exigir 0 drift, verificar fuente del guard y negativo CI; mantener PR no aplicado sin ledger y separar activacion de engineering.',
 'M10.4 CP4: 26/26 SQL legacy sin drift, agregado actual igual a CP1; CP2 guard en admision y CP3 adversarial PR2464 rechazado sin merge/ledger; Git-first paridad.',
 'HIGH','RESUELTO',v_plan||'/'||v_unit,
 'programacion.engineering_plan_units/M10.4',v_evidence
 WHERE NOT EXISTS(
   SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='IG-M104-TERMINAL-PREFIX-READBACK-INSUFFICIENT-001'
 );
END $m104_cp4$;
COMMIT;

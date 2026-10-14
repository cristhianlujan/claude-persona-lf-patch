-- M10.5 CP2 operational sample, authorized: one screen / five contrasting families.
-- Preserves original 13-screen cohort AS-IS snapshot as history; does not mutate
-- INPUT_GOVERNANCE engine, capability version or previously issued results.
BEGIN;

DO $gate$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5'
    AND c.checkpoint_code='NEW_RUNS_VNEXT' AND c.status='PENDING')
 THEN RAISE EXCEPTION 'CP2_SAMPLE_EXPECTED_PENDING_CHECKPOINT_NOT_FOUND'; END IF;
 IF NOT EXISTS (SELECT 1 FROM lf_ops.pantallas WHERE id=1 AND codigo='ONB_001')
 THEN RAISE EXCEPTION 'CP2_SAMPLE_SCREEN_IDENTITY_DRIFT'; END IF;
END $gate$;

-- Operational acceptance is a sample test, NEVER a screen-wide readiness certificate.
-- Fixed five sample strata selected before the test: state risk P0, security P1,
-- data contract P1, source freshness P4, accessibility P4. Preserve statuses.
CREATE OR REPLACE VIEW programacion.v_ig_m105_cp2_sample_readback_v1
WITH (security_invoker=true) AS
WITH sample(family_code,slot) AS (
 VALUES ('STATES','STATE_FLOW'),
        ('SECURITY','SECURITY'),
        ('API_DATA_CONTRACT','DATA_CONTRACT'),
        ('FRESHNESS_INVALIDATION','SOURCE_FRESHNESS'),
        ('ACCESSIBILITY','ACCESSIBILITY')
), pilot AS (
 SELECT v.pantalla_id,v.screen_code,v.run_id,v.run_status,v.source_current,
        v.validator_elapsed_ms
 FROM programacion.v_ig_m105_cp2_verdict_v1 v WHERE v.pantalla_id=1
), details AS (
 SELECT p.*,s.family_code,s.slot,a.validator_outcome,a.applicability,a.coverage_status,
        a.production_ready_status,a.validator_identity,a.validator_sha256,
        a.validator_findings,a.validator_assessed_at,
        (a.validator_outcome IN ('PASS','FAIL','BLOCKED')
         AND a.applicability IS NOT NULL AND a.coverage_status IS NOT NULL
         AND a.validator_identity IS NOT NULL
         AND a.validator_sha256 ~ '^[0-9a-f]{64}$'
         AND a.validator_assessed_at IS NOT NULL
         AND jsonb_typeof(a.validator_findings)='array') AS valid_evidence
 FROM pilot p CROSS JOIN sample s
 LEFT JOIN programacion.input_family_assessments a ON a.run_id=p.run_id
  AND a.family_code=s.family_code
), aggregated AS (
 SELECT d.pantalla_id,d.screen_code,d.run_id,d.run_status,d.source_current,
        d.validator_elapsed_ms,
        count(*)::integer AS sample_family_count,
        count(*) FILTER(WHERE d.valid_evidence)::integer AS valid_family_count,
        count(*) FILTER(WHERE d.coverage_status IN ('PARTIAL','MISSING')
             OR d.production_ready_status IN ('BLOCKED','NOT_READY','PENDING'))::integer
             AS semantic_observation_count,
        jsonb_agg(jsonb_build_object('slot',d.slot,'family',d.family_code,
             'validation',d.validator_outcome,'coverage',d.coverage_status,
             'production_ready',d.production_ready_status,'valid_evidence',coalesce(d.valid_evidence,false))
             ORDER BY d.slot) AS sample_families,
        EXISTS (SELECT 1 FROM programacion.input_readiness_runs previous
          WHERE previous.pantalla_id=d.pantalla_id AND previous.id<d.run_id
            AND NOT programacion.fn_input_run_is_source_current(previous.id))
            AS stale_negative_verified
 FROM details d GROUP BY d.pantalla_id,d.screen_code,d.run_id,d.run_status,
   d.source_current,d.validator_elapsed_ms
)
SELECT 'IG_M105_CP2_SAMPLE_READBACK_V1'::text AS schema_version,
 a.pantalla_id AS sample_screen_id,a.screen_code,a.run_id AS sample_run_id,
 1 AS sampled_screen_count,a.sample_family_count,a.valid_family_count,
 a.semantic_observation_count,a.sample_families,a.run_status,a.source_current,
 a.stale_negative_verified,a.validator_elapsed_ms,
 false AS authorizes_production,
 CASE WHEN a.run_id IS NULL THEN 'NO_EJECUCION'
   WHEN a.run_status IS DISTINCT FROM 'COMPLETED' THEN 'EN_EVALUACION_NO_ERROR'
   WHEN NOT coalesce(a.source_current,false) THEN 'NO_EJECUCION_VIGENTE'
   WHEN a.sample_family_count<>5 OR a.valid_family_count<>5 THEN 'ERROR_MUESTRA'
   WHEN NOT a.stale_negative_verified THEN 'ERROR_NEGATIVO'
   ELSE 'PASS_CP2_MUESTRA' END AS sample_verdict
FROM aggregated a;

DO $contract$
DECLARE m jsonb; cp text;
cp2_query text :=
 'SELECT schema_version,sample_screen_id,sample_run_id,sampled_screen_count,sample_family_count,valid_family_count,semantic_observation_count,source_current,stale_negative_verified,sample_verdict,authorizes_production,sample_families FROM programacion.v_ig_m105_cp2_sample_readback_v1';
m7_query text :=
 'SELECT CASE WHEN sample_verdict=''PASS_CP2_MUESTRA'' AND valid_family_count=5 AND jsonb_array_length(sample_families)=5 THEN ''PASS'' ELSE ''FAIL'' END AS verdict,sample_run_id,sample_families,semantic_observation_count FROM programacion.v_ig_m105_cp2_sample_readback_v1';
m8_query text :=
 'SELECT CASE WHEN sample_verdict=''PASS_CP2_MUESTRA'' AND validator_elapsed_ms IS NOT NULL AND validator_elapsed_ms <= 150000 AND EXISTS (SELECT 1 FROM programacion.fn_ig_performance_timing_metrics_v1() t WHERE t.scope=''SUMMARY'' AND t.status=''PUBLISHED'' AND t.sample_count>0) THEN ''PASS'' ELSE ''FAIL'' END AS verdict,sample_run_id,validator_elapsed_ms,150000 AS budget_ms FROM programacion.v_ig_m105_cp2_sample_readback_v1';
negative_query text :=
 'SELECT CASE WHEN stale_negative_verified AND source_current AND sample_verdict=''PASS_CP2_MUESTRA'' THEN ''PASS'' ELSE ''FAIL'' END AS verdict,sample_run_id,stale_negative_verified FROM programacion.v_ig_m105_cp2_sample_readback_v1';
terminal_query text :=
 'SELECT CASE WHEN s.sample_verdict=''PASS_CP2_MUESTRA'' AND (SELECT count(*) FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=477 AND c.checkpoint_code IN (''NEW_RUNS_VNEXT'',''SUITE_M7_GREEN'',''PERF_M8_GREEN'',''NEG_STALE_RUN'') AND c.status=''DONE'')=4 THEN ''PASS'' ELSE ''FAIL'' END AS verdict,s.sample_run_id,s.sample_family_count,s.valid_family_count,s.sample_verdict,s.authorizes_production FROM programacion.v_ig_m105_cp2_sample_readback_v1 s';
BEGIN
 SELECT unit_metadata INTO STRICT m FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
 m:=jsonb_set(m,'{m105_cp2_sampling_v1}',jsonb_build_object(
  'schema_version','M105_CP2_REPRESENTATIVE_SAMPLE_V1',
  'source_scope','m105_scope_v1_is_historical_only',
  'sampled_screen_id',1,'sampled_screen_code','ONB_001',
  'sample_family_codes',jsonb_build_array('STATES','SECURITY','API_DATA_CONTRACT',
     'FRESHNESS_INVALIDATION','ACCESSIBILITY'),
  'selection_reason','State/flow, security, API contract, source freshness, accessibility',
  'required_family_count',5,'sample_kind','OPERATIONAL_SMOKE_NOT_EXHAUSTIVE',
  'sample_run_current_required',true,
  'negative_run_requires_source_stale',true,
  'preserve_semantic_observations',true,
  'no_production_admission',true),true);
 m:=jsonb_set(m,'{validation_scope_class_v1}',
      to_jsonb('REPRESENTATIVE_SAMPLE_SINGLE_SCREEN_FIVE_FAMILIES'::text),true);
 m:=jsonb_set(m,'{m105_validation_contract_v3,scope_origin}',
      to_jsonb('M105_CP2_REPRESENTATIVE_SAMPLE_V1'::text),true);
 m:=jsonb_set(m,'{m105_validation_contract_v3,semantic_gate}',
      to_jsonb('FIVE_INDEPENDENT_FAMILY_VALIDATOR_PROOFS_ONE_SCREEN'::text),true);
 m:=jsonb_set(m,'{m105_validation_contract_v3,performance_gate}',
      to_jsonb('SAMPLED_SCREEN_VERIFIED_VALIDATOR_ELAPSED_UNDER_BUDGET'::text),true);
 m:=jsonb_set(m,'{m105_validation_contract_v3,shared_readback}',
      to_jsonb('programacion.v_ig_m105_cp2_sample_readback_v1'::text),true);
 m:=jsonb_set(m,'{m105_cp2_governance_v1,sample_required}', 'true'::jsonb,true);
 m:=jsonb_set(m,'{m105_cp2_governance_v1,sample_family_count}','5'::jsonb,true);
 m:=jsonb_set(m,'{m105_cp2_governance_v1,all_13_screen_requirement}','false'::jsonb,true);
 m:=jsonb_set(m,'{m105_cp2_governance_v1,all_47_family_requirement}','false'::jsonb,true);
 m:=jsonb_set(m,'{m105_cp2_producer_v1,readback_rpc}',
      to_jsonb('programacion.v_ig_m105_cp2_sample_readback_v1'::text),true);
 m:=jsonb_set(m,'{m105_cp2_producer_v1,execution_route}',
      to_jsonb('EXISTING_ONB001_RUN_RECEIPT_SAMPLE_READBACK'::text),true);
 m:=jsonb_set(m,'{m105_cp2_producer_v1,execution_status}',
      to_jsonb('REUSE_EXISTING_CURRENT_ONB001_RUN_NO_NEW_EXECUTION'::text),true);
 m:=jsonb_set(m,'{m105_preflight_v1,cp6_terminal}',
      to_jsonb('SAMPLED_ONE_SCREEN_FIVE_FAMILIES_NO_RELEASE'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,assertion_contract,pass_when}',
   jsonb_build_object('sampled_screen_count',1,'sample_family_count',5,
    'valid_family_count',5,'source_current',true,
    'stale_negative_verified',true,'sample_verdict','PASS_CP2_MUESTRA',
    'authorizes_production',false),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,test_scope_contract,screen_scope}',
   to_jsonb('SAMPLE_ONE_SCREEN_FIVE_FAMILIES'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,verification_queries}',
   jsonb_build_array(cp2_query),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,test_execution_contract,canonical_exit_criterion}',
   to_jsonb('One ONB_001 current-source run with five independent validator family receipts and stale negative; no 13-screen or 47-family obligation'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,expected}',
   to_jsonb('PASS_CP2_MUESTRA on one current ONB_001 run, exactly five representative families, negative stale evidence and no production authorization'::text),true);
 FOR cp IN SELECT unnest(ARRAY['SUITE_M7_GREEN','PERF_M8_GREEN','NEG_STALE_RUN','E2E_READBACK'])
 LOOP
  m:=jsonb_set(m,ARRAY['action_specs_v1',cp,'verification_queries'],jsonb_build_array(
   CASE cp WHEN 'SUITE_M7_GREEN' THEN m7_query
     WHEN 'PERF_M8_GREEN' THEN m8_query
     WHEN 'NEG_STALE_RUN' THEN negative_query
     ELSE terminal_query END),true);
 END LOOP;
 m:=jsonb_set(m,'{action_specs_v1,SUITE_M7_GREEN,expected}',
    to_jsonb('Five independent validator outcomes on frozen ONB_001 sample, classified findings preserved'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,PERF_M8_GREEN,expected}',
    to_jsonb('Verified ONB_001 validator timing receipt under 150000 ms and published M8 summary'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,E2E_READBACK,expected}',
    to_jsonb('One current ONB_001 sample, five validated families, negative stale proof and four prior checkpoints DONE'::text),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m,
  title='M10.5 — CP2: muestra representativa de una pantalla',
  exit_criterion='Sample ONB_001 current-source run, five distinct family checks, semantic M7 sample, validator timing M8, stale negative and terminal readback; no 13-screen/47-family requirement and no new release'
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5';
 UPDATE programacion.engineering_work_items SET
  title='M10.5 — Validacion CP2 por muestra (una pantalla, cinco familias)',
  objective='Comprobar el funcionamiento de CP2 con muestra representativa y negativo real sin exigir censo de 13 pantallas o 47 familias',
  expected_result='Current ONB_001 sampled PASS, five valid independent family receipts, M7 semantics, M8 timing, stale negative and terminal readback',
  acceptance_criteria=jsonb_build_array(
  'Exactly 1 representative current-source screen ONB_001; no other screens required',
  '5 frozen family strata with independent validator evidence; semantic BLOCKED remains data not engine error',
  'Real previous stale run rejected, no synthetic receipt or release change',
  'M7 semantic sample, M8 measured timing, terminal readback tied to sample run',
  'Sample success does not certify production readiness or all families/screens')
 WHERE id=477 AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'CP2_SAMPLE_WORK_ITEM_CHANGED'; END IF;
 UPDATE programacion.engineering_work_checkpoints SET
  title=CASE checkpoint_code
  WHEN 'POST_CUTOVER_ASIS' THEN 'Baseline histórico del universo de 13 pantallas (no alcance requerido)'
  WHEN 'NEW_RUNS_VNEXT' THEN 'CP2 muestra ONB_001: cinco familias y negativo de vigencia'
  WHEN 'SUITE_M7_GREEN' THEN 'M7: semántica en cinco familias de la muestra'
  WHEN 'PERF_M8_GREEN' THEN 'M8: tiempo observado del validador sobre pantalla muestral'
  WHEN 'NEG_STALE_RUN' THEN 'Negativo muestral: no aprobar ejecución anterior sin fuentes vigentes'
  WHEN 'E2E_READBACK' THEN 'Readback final de muestra y checkpoints anteriores'
  END
 WHERE work_item_id=477 AND checkpoint_code IN
 ('POST_CUTOVER_ASIS','NEW_RUNS_VNEXT','SUITE_M7_GREEN','PERF_M8_GREEN','NEG_STALE_RUN','E2E_READBACK');
END $contract$;

INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,severidad,estado,lote_origen,source_context,source_ref)
SELECT 'IG-M105-CP2-EXHAUSTIVE-SCOPE-UNNECESSARY-018','GOVERNANCE',
 'M10.5 CP2 confundia prueba muestral con censo de 13 pantallas y 47 familias',
 'CP2 prueba operativa, no censo de calidad ni autorización de producción.',
 'El criterio de salida y los controles M7/M8/readback heredaron 13/13 y family_count/47.',
 'Seleccionar una pantalla y cinco familias diversas con prueba vigente, evidencia independiente y negativo stale; conservar baseline histórica y observaciones sin inventar PASS de producción.',
 'Consultar v_ig_m105_cp2_sample_readback_v1, verificar 5/5, positivo ONB_001 y negativo stale; probar M7/M8 en readback.',
 'ALTA','ACTIVO','M10.5/CP2','IG_CURATOR_VALIDATOR_REFACTOR_V2',
 'supabase://programacion.v_ig_m105_cp2_sample_readback_v1'
 WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M105-CP2-EXHAUSTIVE-SCOPE-UNNECESSARY-018');

-- Positive and negative evidence must both exist before new contract becomes live.
DO $proof$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM programacion.v_ig_m105_cp2_sample_readback_v1
    WHERE sample_screen_id=1 AND sampled_screen_count=1 AND sample_family_count=5
      AND valid_family_count=5 AND source_current AND stale_negative_verified
      AND sample_verdict='PASS_CP2_MUESTRA' AND NOT authorizes_production)
 THEN RAISE EXCEPTION 'CP2_SAMPLE_REAL_POSITIVE_OR_STALE_NEGATIVE_NOT_PROVEN'; END IF;
 IF EXISTS (SELECT 1 FROM programacion.v_ig_m105_cp2_sample_readback_v1
   WHERE run_status<>'COMPLETED' AND sample_verdict='PASS_CP2_MUESTRA')
 THEN RAISE EXCEPTION 'CP2_SAMPLE_INCOMPLETE_FALSIFIED'; END IF;
END $proof$;
COMMIT;

-- SELECT SOLO LECTURA. SHA256 JSONB canónico, ordenación por texto de objeto.
-- SRC RUNS n=232 sha256=b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0
WITH source_rows AS MATERIALIZED (

WITH asof AS (SELECT now() AS observed_at),
base AS (
 SELECT r.*,a.observed_at AS inspected_at FROM public.lf_operation_execution r CROSS JOIN asof a
 WHERE r.status='IN_PROGRESS'
),
d AS (
 SELECT
  r.execution_id AS run_id,r.operation_code AS operacion,
  coalesce(nullif(r.manifest->>'profile_code',''),
           CASE WHEN r.target_code ILIKE 'PERFIL-%' THEN r.target_code END,
           'NO_REGISTRADO') AS perfil,
  r.target_code, r.started_at, r.updated_at,r.inspected_at,
  round((extract(epoch from(r.inspected_at-r.started_at))/86400)::numeric,1) AS antiguedad_dias,
  round((extract(epoch from(r.inspected_at-greatest(r.updated_at,coalesce(sl.last_step_at,r.updated_at))))/86400)::numeric,2) AS inactividad_dias,
  sl.step_id AS ultimo_paso,sl.status AS ultimo_paso_estado,
  sl.last_step_at AS ultimo_paso_fecha,sl.evidence_ref AS ultimo_paso_evidencia,
  coalesce(sc.step_count,0) AS pasos_registrados,coalesce(sc.github_write_pass,0) AS github_write_pass,
  coalesce(sc.other_write_step,0) AS other_write_steps,
  r.lease_owner,r.lease_expires_at,r.lease_fence,r.checkpoint_seq,
  (r.lease_owner IS NOT NULL) AS tiene_lease_owner,
  (r.lease_expires_at IS NOT NULL AND r.lease_expires_at>r.inspected_at) AS lease_vigente,
  (r.lease_expires_at IS NOT NULL AND r.lease_expires_at<=r.inspected_at) AS lease_vencido,
  coalesce(g.guard_count,0) AS guard_total,
  coalesce(g.succeeded,0) AS guard_succeeded,
  coalesce(g.reserved,0) AS guard_reserved,
  coalesce(g.abandoned,0) AS guard_abandoned,
  coalesce(e.activos,0) AS activos_affected,
  coalesce(e.cards,0) AS cards_affected,
  coalesce(e.knowledge,0) AS knowledge_affected,
  coalesce(e.capture_records,0) AS capture_records_affected,
  coalesce(e.capture_runs,0) AS capture_runs_affected,
  coalesce(e.pipeline_runs,0) AS pipeline_runs_affected,
  coalesce(e.homologated_records,0) AS homologated_records_affected,
  coalesce(e.decisiones,0) AS decisions_affected,
  coalesce(e.operation_registry,0) AS operation_registry_affected,
  coalesce(e.product_rules,0) AS product_rules_affected,
  coalesce(e.promotion,0) AS rule_promotion_affected,
  coalesce(e.events,0) AS audit_events,
  coalesce(e.gate_checks,0) AS gate_check_records,
  (r.manifest->>'no_write'='true' OR r.manifest->>'read_only'='true') AS self_declared_no_write,
  coalesce(r.manifest->>'write_executed',r.manifest->>'github_write_executed',r.manifest->>'runtime_write_executed') AS manifest_write_declaration
 FROM base r
 LEFT JOIN LATERAL(
  SELECT step_id,status,evidence_ref,coalesce(observed_at,updated_at,created_at) last_step_at
  FROM public.lf_operation_execution_steps s
  WHERE s.execution_id=r.execution_id ORDER BY coalesce(observed_at,updated_at,created_at) DESC,step_order DESC,step_id DESC LIMIT 1
 ) sl ON true
 LEFT JOIN LATERAL(
  SELECT count(*)::int step_count,
   count(*) FILTER(WHERE step_id='github_write' AND status IN('STEP_PASS_WITH_EVIDENCE','STEP_CLEAN_PASS','WRITE_COMMITTED','PASS_CLEAN'))::int github_write_pass,
   count(*) FILTER(WHERE step_id ~* '(^|_)(capture_store|db_write|write_committed|publish|apply_migration|record_capture|persist|promotion_apply)($|_)' OR status='WRITE_COMMITTED')::int other_write_step
  FROM public.lf_operation_execution_steps s WHERE s.execution_id=r.execution_id
 ) sc ON true
 LEFT JOIN LATERAL(
  SELECT count(*)::int guard_count,count(*) FILTER(WHERE state='SUCCEEDED')::int succeeded,
  count(*) FILTER(WHERE state='RESERVED')::int reserved,count(*) FILTER(WHERE state='ABANDONED')::int abandoned
  FROM public.lf_operation_effect_guard g WHERE g.execution_id=r.execution_id
 ) g ON true
 LEFT JOIN LATERAL(
  SELECT
   (SELECT count(*)::int FROM public.lf_activos a WHERE a.created_by_execution_id=r.execution_id OR a.updated_by_execution_id=r.execution_id) activos,
   (SELECT count(*)::int FROM public.lf_cards c WHERE c.created_by_execution_id=r.execution_id OR c.updated_by_execution_id=r.execution_id) cards,
   (SELECT count(*)::int FROM public.lf_knowledge_base k WHERE k.updated_by_execution_id=r.execution_id) knowledge,
   (SELECT count(*)::int FROM public.lf_capture_records c WHERE c.updated_by_execution_id=r.execution_id) capture_records,
   (SELECT count(*)::int FROM public.lf_capture_runs c WHERE c.updated_by_execution_id=r.execution_id) capture_runs,
   (SELECT count(*)::int FROM public.lf_pipeline_runs p WHERE p.execution_id=r.execution_id OR p.updated_by_execution_id=r.execution_id) pipeline_runs,
   (SELECT count(*)::int FROM public.lf_homologated_records h WHERE h.updated_by_execution_id=r.execution_id) homologated_records,
   (SELECT count(*)::int FROM public.lf_decisiones_gov d WHERE d.created_by_execution_id=r.execution_id OR d.updated_by_execution_id=r.execution_id) decisiones,
   (SELECT count(*)::int FROM public.lf_operation_registry o WHERE o.created_by_execution_id=r.execution_id OR o.updated_by_execution_id=r.execution_id) operation_registry,
   (SELECT count(*)::int FROM public.lf_product_rules p WHERE p.created_by_execution_id=r.execution_id OR p.updated_by_execution_id=r.execution_id) product_rules,
   (SELECT count(*)::int FROM public.lf_rule_promotion_v1 p WHERE p.request_execution_id=r.execution_id) promotion,
   (SELECT count(*)::int FROM public.lf_eventos ev WHERE ev.created_by_execution_id=r.execution_id OR ev.updated_by_execution_id=r.execution_id) events,
   (SELECT count(*)::int FROM public.lf_operation_gate_check_results ck WHERE ck.execution_id=r.execution_id) gate_checks
 ) e ON true
),
classified AS (
 SELECT d.*,
   (activos_affected+cards_affected+knowledge_affected+capture_records_affected+capture_runs_affected+pipeline_runs_affected+homologated_records_affected+decisions_affected+operation_registry_affected+product_rules_affected+rule_promotion_affected) AS total_direct_sinks,
   CASE
    WHEN guard_succeeded>0 OR github_write_pass>0 OR other_write_steps>0
      OR activos_affected+cards_affected+knowledge_affected+capture_records_affected+capture_runs_affected+pipeline_runs_affected+homologated_records_affected+decisions_affected+operation_registry_affected+product_rules_affected+rule_promotion_affected>0
      THEN 'B_HUERFANO_CON_EFECTOS_PARCIALES_PROPUESTO'
    WHEN lease_vigente OR inactividad_dias <=2 THEN 'C_POSIBLEMENTE_VIVO'
    WHEN self_declared_no_write AND guard_total=0 AND github_write_pass=0 AND other_write_steps=0 AND inactividad_dias>7
      THEN 'A_HUERFANO_SIN_EFECTOS_OBSERVADOS_PROPUESTO'
    ELSE 'D_NO_DETERMINABLE'
   END AS clase_propuesta
 FROM d
)
SELECT * FROM classified ORDER BY
CASE clase_propuesta WHEN 'B_HUERFANO_CON_EFECTOS_PARCIALES_PROPUESTO' THEN 1 WHEN 'C_POSIBLEMENTE_VIVO' THEN 2 WHEN 'A_HUERFANO_SIN_EFECTOS_OBSERVADOS_PROPUESTO' THEN 3 ELSE 4 END,
inactividad_dias ASC,run_id
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows)
SELECT jsonb_array_length(rows) AS n,encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS result_sha256,rows AS result_rows FROM packed;

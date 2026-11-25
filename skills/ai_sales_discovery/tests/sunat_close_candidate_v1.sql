-- CANDIDATO DE DESARROLLO. NO EJECUTAR contra SALY ni incorporar al Train sin Paso 07.
-- Contratos: SALY_SUNAT_PASO04_CONTRATO_CIERRE_V1, PASO05_RECUPERACION_LEASE_V1.
-- ALCANCE: solo RUN comercial SUNAT existente; cero nuevos grants, cero ingestas.
BEGIN;
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

-- Sustituto de la prohibicion general de CERRADO. El RUN solo puede cerrarse
-- DESPUES del cierre de la operacion y con evidencia de cierre coherente.
CREATE OR REPLACE FUNCTION saly.ventas_discovery_close_gate_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public, saly AS $fn$
DECLARE v_exec public.lf_operation_execution%ROWTYPE;
DECLARE v_policy jsonb;
BEGIN
 -- Restrict INSERT as well as UPDATE: dropping the old CHECK must not open INSERT bypass.
 IF TG_OP = 'INSERT' THEN
   IF NEW.estado = 'CERRADO' THEN
     RAISE EXCEPTION 'SUNAT_CLOSE_INSERT_FORBIDDEN';
   END IF;
   RETURN NEW;
 END IF;
 IF OLD.estado = 'CERRADO' THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_TERMINAL_IMMUTABLE';
 END IF;
 IF NEW.estado IS DISTINCT FROM 'CERRADO' THEN
   RETURN NEW;
 END IF;
 IF OLD.estado IS DISTINCT FROM 'EN_EJECUCION'
    OR NEW.finished_at IS NULL
    OR NEW.plan_hash IS DISTINCT FROM OLD.plan_hash
    OR NEW.run_ref IS DISTINCT FROM OLD.run_ref
    OR NEW.id IS DISTINCT FROM OLD.id
    OR NEW.catalog_version IS DISTINCT FROM OLD.catalog_version
    OR NEW.scope IS DISTINCT FROM OLD.scope THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_BAD_RUN_TRANSITION';
 END IF;
 SELECT * INTO v_exec FROM public.lf_operation_execution
  WHERE execution_id = NEW.run_ref;
 SELECT config_value::jsonb INTO v_policy FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
    AND value_status='REAL' AND valid_from <= clock_timestamp()
  ORDER BY valid_from DESC LIMIT 1;
 IF v_policy IS NULL OR NEW.run_ref IS DISTINCT FROM v_policy->>'commercial_run_ref'
   OR v_exec.operation_code IS DISTINCT FROM 'INGESTA_EMPRESARIAL_SALY'
   OR v_exec.status IS DISTINCT FROM 'COMPLETED'
   OR v_exec.completed_at IS NULL
   OR v_exec.manifest->>'sunat_close_contract' IS DISTINCT FROM 'SALY_SUNAT_CLOSE_V1'
   OR v_exec.manifest->>'sunat_close_plan_hash' IS DISTINCT FROM NEW.plan_hash
   OR NEW.plan_hash IS DISTINCT FROM v_policy->>'manifest_digest_sha256'
   OR NEW.finished_at IS DISTINCT FROM v_exec.completed_at THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_GATE_REJECTED';
 END IF;
 RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_saly_ventas_discovery_close_gate_v1 ON saly.ventas_discovery_runs;
CREATE TRIGGER trg_saly_ventas_discovery_close_gate_v1
BEFORE INSERT OR UPDATE ON saly.ventas_discovery_runs
FOR EACH ROW EXECUTE FUNCTION saly.ventas_discovery_close_gate_v1();

-- CERRADO deja de estar totalmente prohibido, pero queda restringido por
-- el gate precedente. La funcion tiene SECURITY INVOKER y NO recibe GRANT.
ALTER TABLE saly.ventas_discovery_runs
  DROP CONSTRAINT saly_l28_run_close_disabled;

CREATE OR REPLACE FUNCTION saly.ventas_sunat_commercial_close_v1(
 p_execution_id text,
 p_actor_execution_id text,
 p_lease_owner text,
 p_evidence_sha256 text
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public, saly AS $fn$
DECLARE
 v_exec public.lf_operation_execution%ROWTYPE;
 v_run saly.ventas_discovery_runs%ROWTYPE;
 v_old saly.ventas_discovery_runs%ROWTYPE;
 v_policy jsonb;
 v_ttl_text text;
 v_ttl integer;
 v_lease jsonb;
 v_now timestamptz;
 v_found integer;
 v_rows bigint;
 v_ingestas integer;
 v_bad integer;
 v_effects integer;
 v_receipts integer;
 v_missing integer;
 v_digest text;
 v_min_workers integer;
 v_unique_ruc bigint;
BEGIN
 IF p_execution_id IS NULL OR btrim(p_execution_id)=''
  OR p_actor_execution_id IS NULL OR btrim(p_actor_execution_id)=''
  OR p_lease_owner IS NULL OR btrim(p_lease_owner)=''
  OR p_evidence_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_INVALID_INPUT';
 END IF;
 -- IMPORTANT: the native GitHub/Train caller executes as the DB owner; no
 -- authenticated/service_role/anon privileges can be extended by this function.
 IF current_user <> 'postgres' THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_CALLER_NOT_GOVERNED';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));
 SELECT * INTO v_exec FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id FOR UPDATE;
 SELECT * INTO v_run FROM saly.ventas_discovery_runs
  WHERE run_ref=p_execution_id FOR UPDATE;
 IF v_exec.execution_id IS NULL OR v_run.id IS NULL
   OR v_exec.operation_code IS DISTINCT FROM 'INGESTA_EMPRESARIAL_SALY'
   THEN RAISE EXCEPTION 'SUNAT_CLOSE_IDENTITY'; END IF;
 IF v_exec.status='COMPLETED' AND v_run.estado='CERRADO' THEN
   IF v_exec.manifest->>'sunat_close_evidence_sha256'=p_evidence_sha256
      AND v_exec.manifest->>'sunat_close_plan_hash'=v_run.plan_hash
      AND v_exec.completed_at=v_run.finished_at THEN
      RETURN jsonb_build_object('result','ALREADY_CLOSED_SAME_EVIDENCE',
        'run_ref',p_execution_id,'completed_at',v_exec.completed_at);
   END IF;
   RAISE EXCEPTION 'SUNAT_CLOSE_REPLAY_CONFLICT';
 END IF;
 IF v_exec.status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_run.estado IS DISTINCT FROM 'EN_EJECUCION' THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_STATE';
 END IF;
 SELECT config_value::jsonb INTO v_policy FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
  AND value_status='REAL' AND valid_from<=clock_timestamp()
  ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF v_policy IS NULL OR v_policy->>'commercial_run_ref' IS DISTINCT FROM p_execution_id
   OR v_policy->>'pilot_scope' IS DISTINCT FROM 'NEW_COMMERCIAL_RUN_ONLY'
   OR v_policy->>'old_manifest_replay_allowed' IS DISTINCT FROM 'false'
   OR v_policy->>'enabled' IS DISTINCT FROM 'true'
   OR v_run.plan_hash IS DISTINCT FROM v_policy->>'manifest_digest_sha256'
   OR jsonb_typeof(v_policy->'expected_batches') IS DISTINCT FROM 'number'
   OR jsonb_typeof(v_policy->'expected_rows') IS DISTINCT FROM 'number'
   OR (v_policy->>'expected_batches')::integer < 1
   OR (v_policy->>'expected_rows')::bigint < 1
   OR v_exec.manifest->'sunat_plan'->>'source_id' IS DISTINCT FROM 'PE-SUNAT-RUC'
   OR v_exec.manifest->'sunat_plan'->>'business' IS DISTINCT FROM 'SALY'
   OR v_exec.manifest->'sunat_plan'->>'scope_key' IS DISTINCT FROM 'LIMA_ICA'
   OR v_exec.manifest->'sunat_plan'->>'manifest_digest_sha256'
      IS DISTINCT FROM v_run.plan_hash
   OR v_exec.manifest->'sunat_plan'->'snapshot_sha256'
      IS DISTINCT FROM v_policy->'snapshot_sha256' THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_POLICY_OR_MANIFEST';
 END IF;
 -- Explicitly configured TTL is not present in current SALY: fail closed.
 SELECT config_value INTO v_ttl_text FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_CLOSE_TTL_SECONDS_V1'
  AND value_type='INTEGER' AND value_status='REAL' AND valid_from<=clock_timestamp()
  ORDER BY valid_from DESC LIMIT 1;
 IF v_ttl_text IS NULL OR v_ttl_text !~ '^[0-9]{1,4}$' THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_TTL_POLICY_MISSING';
 END IF;
 v_ttl:=v_ttl_text::integer;
 IF v_ttl < 5 OR v_ttl > 3600 THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_TTL_POLICY_INVALID';
 END IF;
 SELECT * INTO v_old FROM saly.ventas_discovery_runs
   WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' FOR SHARE;
 IF v_old.estado IS DISTINCT FROM 'HOLD' THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_HISTORICAL_HOLD';
 END IF;
 -- Historical preservation uses exact previously reconciled pilot baseline.
 -- Do not alter the historical 479-batch plan or its 130725-row delete ledger.
 IF (SELECT count(*) FROM saly.ventas_discovery_plan_batches
       WHERE run_id=v_old.id) <> 479
 OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches
       WHERE run_id=v_old.id AND estado='FOUND') <> 136
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas
       WHERE run_ref=v_old.run_ref AND source_id='PE-SUNAT-RUC') <> 136
 OR (SELECT count(*) FROM saly.ventas_hallazgos h
       JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
       WHERE i.run_ref=v_old.run_ref AND i.source_id='PE-SUNAT-RUC') <> 5275
 OR (SELECT count(*) FROM saly.ventas_sunat_bulk_delete_ledger_v1
       WHERE run_ref=v_old.run_ref) <> 130725
 THEN RAISE EXCEPTION 'SUNAT_CLOSE_HISTORICAL_BASELINE_CHANGED'; END IF;
 SELECT count(*) FILTER (WHERE estado='FOUND'),count(*) INTO v_found,v_ingestas
 FROM saly.ventas_discovery_plan_batches WHERE run_id=v_run.id;
 IF v_found<>(v_policy->>'expected_batches')::integer
 OR v_ingestas<>v_found THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_PLAN_INCOMPLETE';
 END IF;
 SELECT count(*),coalesce(sum(i.filas_reportadas),0) INTO v_ingestas,v_rows
 FROM saly.ventas_discovery_ingestas i
 WHERE i.run_ref=p_execution_id AND i.source_id='PE-SUNAT-RUC'
   AND i.estado='VALIDADA';
 IF v_ingestas<>v_found OR v_rows<>(v_policy->>'expected_rows')::bigint THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_INGESTA_INCOMPLETE';
 END IF;
 SELECT count(*) INTO v_missing FROM saly.ventas_discovery_plan_batches p
 LEFT JOIN saly.ventas_discovery_ingestas i
 ON i.run_ref=p_execution_id AND i.batch_key=p.batch_key
 AND i.scope_key=p.scope_key AND i.source_id=p.source_id
 WHERE p.run_id=v_run.id AND
    (p.estado<>'FOUND' OR i.id IS NULL
     OR i.archivo_sha256 IS DISTINCT FROM p.filtros->>'capture_sha256'
     OR i.filas_reportadas IS DISTINCT FROM (p.filtros->>'rows')::integer);
 IF v_missing<>0 THEN RAISE EXCEPTION 'SUNAT_CLOSE_BATCH_MISMATCH'; END IF;
 SELECT count(*) INTO v_rows FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE i.run_ref=p_execution_id AND i.source_id='PE-SUNAT-RUC';
 IF v_rows<>(v_policy->>'expected_rows')::bigint THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_HALLAZGOS_MISMATCH';
 END IF;
 IF (SELECT count(*) FROM saly.ventas_hallazgos h
       JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
       WHERE i.source_id='PE-SUNAT-RUC') <> 7514
 THEN RAISE EXCEPTION 'SUNAT_CLOSE_TOTAL_SUNAT_CHANGED'; END IF;
 SELECT config_value::integer INTO v_min_workers
 FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'
   AND value_type='INTEGER' AND value_status='REAL'
   AND valid_from<=clock_timestamp() ORDER BY valid_from DESC LIMIT 1;
 IF v_min_workers IS NULL OR v_min_workers<1 THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_MIN_WORKERS_POLICY_MISSING';
 END IF;
 SELECT count(*),count(*) FILTER (
    WHERE clasificacion_comercial IS DISTINCT FROM 'ELEGIBLE'
       OR nrotrab IS NULL OR nrotrab<v_min_workers)
 INTO v_missing,v_bad
 FROM saly.ventas_sunat_elegibilidad_v1
 WHERE run_ref=p_execution_id;
 IF v_missing<>v_rows THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_ELIGIBILITY_COVERAGE';
 END IF;
 IF v_bad<>0 THEN RAISE EXCEPTION 'SUNAT_CLOSE_INELIGIBLE'; END IF;
 SELECT count(DISTINCT h.ruc_candidato) INTO v_unique_ruc
 FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i
 ON i.id=h.ingesta_id
 WHERE i.run_ref=p_execution_id AND i.source_id='PE-SUNAT-RUC';
 IF v_unique_ruc<>v_rows THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_DUPLICATE_RUC';
 END IF;
 SELECT count(*),count(*) FILTER(WHERE state='SUCCEEDED' AND receipt IS NOT NULL)
 INTO v_effects,v_receipts FROM public.lf_operation_effect_guard
 WHERE execution_id=p_execution_id;
 IF v_effects<>v_found OR v_receipts<>v_effects THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_EFFECTS';
 END IF;
 -- Independent, deterministic terminal digest. A caller cannot invent a SHA:
 -- persisted plan, effects/receipts and current policy define the exact value.
 SELECT encode(sha256(convert_to(jsonb_build_object(
    'contract','SALY_SUNAT_CLOSE_V1',
    'run_ref',p_execution_id,
    'plan_hash',v_run.plan_hash,
    'expected_batches',v_found,
    'expected_rows',v_rows,
    'effect_receipt_digest',(SELECT encode(sha256(convert_to(
        coalesce(jsonb_agg(jsonb_build_object('scope',g.effect_scope,
         'dispatch',g.dispatch_key,'receipt',g.receipt)
          ORDER BY g.effect_scope)::text,'[]'),'UTF8')),'hex')
         FROM public.lf_operation_effect_guard g
         WHERE g.execution_id=p_execution_id)
 )::text,'UTF8')),'hex') INTO v_digest;
 IF p_evidence_sha256 IS DISTINCT FROM v_digest THEN
    RAISE EXCEPTION 'SUNAT_CLOSE_EVIDENCE_HASH_MISMATCH';
 END IF;
 v_lease:=public.fn_lf_operation_acquire_lease_v1(
   p_execution_id,p_lease_owner,v_ttl,p_actor_execution_id);
 IF v_lease->>'result' IS DISTINCT FROM 'LEASE_ACQUIRED' THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_LEASE';
 END IF;
 v_now:=clock_timestamp();
 IF v_lease->>'lease_owner' IS DISTINCT FROM p_lease_owner
 OR (v_lease->>'lease_expires_at')::timestamptz<=v_now THEN
   RAISE EXCEPTION 'SUNAT_CLOSE_LEASE_FENCE';
 END IF;
 UPDATE public.lf_operation_execution
 SET status='COMPLETED',completed_at=v_now,
 lease_owner=NULL,lease_expires_at=NULL,
 manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
   'sunat_close_contract','SALY_SUNAT_CLOSE_V1',
   'sunat_close_evidence_sha256',p_evidence_sha256,
   'sunat_close_plan_hash',v_run.plan_hash,
   'sunat_close_effects',v_effects),
 updated_by_execution_id=p_actor_execution_id,updated_at=v_now
 WHERE execution_id=p_execution_id AND status='IN_PROGRESS'
 AND lease_owner=p_lease_owner AND lease_fence=(v_lease->>'lease_fence')::bigint;
 IF NOT FOUND THEN RAISE EXCEPTION 'SUNAT_CLOSE_OPERATION_UPDATE_FAILED'; END IF;
 UPDATE saly.ventas_discovery_runs
 SET estado='CERRADO',finished_at=v_now
 WHERE id=v_run.id AND estado='EN_EJECUCION';
 IF NOT FOUND THEN RAISE EXCEPTION 'SUNAT_CLOSE_RUN_UPDATE_FAILED'; END IF;
 RETURN jsonb_build_object('result','SUCCESS','run_ref',p_execution_id,
 'rows',v_rows,'batches',v_found,'effects',v_effects,
 'completed_at',v_now,'evidence_sha256',p_evidence_sha256);
END $fn$;

-- Restrictive: this migration adds NO grants, and does not execute closure.
-- Any new signature is explicitly revoked from non-owner roles.
REVOKE ALL ON FUNCTION saly.ventas_sunat_commercial_close_v1(text,text,text,text)
 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION saly.ventas_discovery_close_gate_v1()
 FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
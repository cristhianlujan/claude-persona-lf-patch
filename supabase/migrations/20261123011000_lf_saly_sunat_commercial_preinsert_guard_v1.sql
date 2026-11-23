-- SALY-only fail-closed commercial guard at the single persisted SUNAT capture table.
-- Even if an extraction caller accidentally skips its filter, noneligible or
-- already registered companies never reach saly.ventas_hallazgos.
-- Install through governed Migration Merge Train only. Does not enable ingestion.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';

DO $pre$
BEGIN
 IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_DB_LF'
        AND target_type='MIGRATION'
        AND target_code LIKE '%lf_saly_sunat_commercial_preinsert_guard_v1'
        AND status='IN_PROGRESS')<>1
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_GUARD_TRAIN_REQUIRED'; END IF;
 IF to_regprocedure('saly.ventas_sunat_ingesta_core_v1(uuid,text)') IS NULL
 OR to_regclass('saly.ventas_hallazgos') IS NULL
 OR to_regclass('saly.ventas_discovery_ingestas') IS NULL
 OR EXISTS(SELECT 1 FROM pg_trigger
           WHERE tgrelid='saly.ventas_hallazgos'::regclass
             AND tgname='trg_saly_sunat_commercial_admission_v1')
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_GUARD_PRESTATE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.ventas_discovery_runs
               WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' AND estado='HOLD')
 OR (SELECT config_value::jsonb->'enabled'
     FROM public.lf_global_config
     WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
       AND value_type='JSON' AND value_status='REAL'
     ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_GUARD_OLD_SOURCE_NOT_FROZEN'; END IF;
END $pre$;

CREATE FUNCTION saly.ventas_sunat_commercial_admission_v1()
RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER
SET search_path=pg_catalog,saly,public AS $admission$
DECLARE
 v_source text;
 v_run text;
 v_run_status text;
 v_operation_status text;
 v_policy jsonb;
 v_min_literal text;
 v_min_workers integer;
 v_workers text;
 v_ruc text;
 v_capture jsonb;
BEGIN
 SELECT i.source_id,i.run_ref INTO STRICT v_source,v_run
 FROM saly.ventas_discovery_ingestas i WHERE i.id=NEW.ingesta_id;
 -- Existing PTE and other non-SUNAT sources are unaffected.
 IF v_source IS DISTINCT FROM 'PE-SUNAT-RUC' THEN RETURN NEW; END IF;

 SELECT r.estado,o.status INTO v_run_status,v_operation_status
 FROM saly.ventas_discovery_runs r
 JOIN public.lf_operation_execution o ON o.execution_id=r.run_ref
 WHERE r.run_ref=v_run AND o.operation_code='INGESTA_EMPRESARIAL_SALY';
 IF NOT FOUND OR v_run='EXEC-SALY-SUNAT-PILOT-20261122-001'
    OR v_run_status NOT IN ('EN_EJECUCION','PARTIAL')
    OR v_operation_status IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_NEW_RUN_REQUIRED'; END IF;

 SELECT config_value::jsonb INTO v_policy
 FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
   AND value_type='JSON' AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1;
 IF NOT FOUND OR v_policy->'enabled' IS DISTINCT FROM 'true'::jsonb
 OR v_policy->'commercial_mode' IS DISTINCT FROM 'true'::jsonb
 OR v_policy->>'commercial_run_ref' IS DISTINCT FROM v_run
 OR v_policy->'old_manifest_replay_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_POLICY_NOT_ACTIVE'; END IF;

 SELECT config_value INTO v_min_literal FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'
   AND value_type='INTEGER' AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1;
 IF NOT FOUND OR coalesce(v_min_literal,'') !~ '^[1-9][0-9]{0,7}$'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_MIN_WORKERS_INVALID'; END IF;
 v_min_workers:=v_min_literal::integer;

 v_capture:=NEW.captura_empresarial->'capture';
 v_ruc:=NEW.captura_empresarial #>> '{capture,normalized,ruc}';
 v_workers:=NEW.captura_empresarial #>> '{capture,normalized,workers_integer_literal}';
 IF v_capture IS NULL OR jsonb_typeof(v_capture)<>'object'
 OR v_capture->>'version' IS DISTINCT FROM 'sunat.company.v1'
 OR v_capture->>'source' IS DISTINCT FROM 'SUNAT'
 OR coalesce(v_ruc,'') !~ '^20[0-9]{9}$'
 OR v_ruc IS DISTINCT FROM NEW.ruc_candidato
 OR coalesce(v_workers,'') !~ '^[0-9]{1,9}$'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_CAPTURE_SHAPE'; END IF;

 IF v_workers::integer < v_min_workers
 OR upper(btrim(coalesce(NEW.captura_empresarial #>> '{capture,observations,monthly,raw,Estado}','')))<>'ACTIVO'
 OR upper(btrim(coalesce(NEW.captura_empresarial #>> '{capture,observations,reduced,raw,estado}','')))<>'ACTIVO'
 OR upper(btrim(coalesce(NEW.captura_empresarial #>> '{capture,observations,monthly,raw,Condicion}','')))<>'HABIDO'
 OR upper(btrim(coalesce(NEW.captura_empresarial #>> '{capture,observations,reduced,raw,condicion}','')))<>'HABIDO'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_NOT_ELIGIBLE'; END IF;

 IF coalesce(NEW.captura_empresarial->>'capture_sha256','') !~
    '^[0-9a-f]{64}$'
 OR NEW.captura_empresarial->>'capture_sha256' IS DISTINCT FROM
    encode(sha256(convert_to(saly.ventas_capture_canonical_v1(v_capture),'UTF8')),'hex')
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_CAPTURE_HASH'; END IF;

 -- Existing companies from SUNAT or PTE are not imported again.
 IF EXISTS(SELECT 1 FROM saly.ventas_hallazgos h
           WHERE h.ruc_candidato=v_ruc LIMIT 1)
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_RUC_ALREADY_REGISTERED'; END IF;
 RETURN NEW;
END $admission$;

REVOKE ALL ON FUNCTION saly.ventas_sunat_commercial_admission_v1()
FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;

CREATE TRIGGER trg_saly_sunat_commercial_admission_v1
BEFORE INSERT ON saly.ventas_hallazgos
FOR EACH ROW EXECUTE FUNCTION saly.ventas_sunat_commercial_admission_v1();

COMMENT ON FUNCTION saly.ventas_sunat_commercial_admission_v1() IS
'SALY: source-side commercial eligibility is also mandatory on SUNAT INSERT; reads governed threshold, both ACTIVO/HABIDO facts and current NEW run policy; rejects known RUC in any source. PTE bypasses unchanged.';
COMMIT;

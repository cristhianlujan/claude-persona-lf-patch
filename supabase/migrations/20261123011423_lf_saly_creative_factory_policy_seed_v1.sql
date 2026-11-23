-- SALY Creative Factory: four initial operational parameters, owner request 2026-11-22.
-- Engineering-selected conservative starting values, NOT measured performance.
-- QUEUE_MAX=1 (serial), MAX_ATTEMPTS=2 (one retry),
-- QUEUE_TIMEOUT_SECONDS=900 (15m admission), LEASE_SECONDS=600 (10m worker).
-- Policy seed DOES NOT grant RENDER, deploy queue candidates, or attest host.
-- Must enter Supabase ONLY through PR -> PASE -> ready-to-merge -> Merge Train.
BEGIN;
DO $policy$
DECLARE
  v_inserted integer;
  v_policy jsonb;
BEGIN
  IF to_regclass('saly.config_global') IS NULL
     OR to_regclass('saly.creative_runs') IS NULL
     OR to_regprocedure('saly.creative_execution_policy_v1(timestamptz)') IS NULL
  THEN RAISE EXCEPTION 'SALY_CREATIVE_POLICY_SCHEMA_REQUIRED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:policy:seed:v1',0));
  IF EXISTS (SELECT 1 FROM saly.config_global WHERE scope='CREATIVE_FACTORY')
  THEN RAISE EXCEPTION 'SALY_CREATIVE_POLICY_ALREADY_DEFINED'; END IF;
  IF EXISTS (SELECT 1 FROM saly.creative_runs WHERE state IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'SALY_CREATIVE_POLICY_ACTIVE_RUN_BLOCK'; END IF;

  INSERT INTO saly.config_global
    (scope,config_key,config_value,value_type,value_status,description,valid_from)
  SELECT 'CREATIVE_FACTORY',p.key,p.val,'INTEGER','REAL',p.reason,now()
  FROM (VALUES
    ('QUEUE_MAX','1','Inicial: una admisión RUN en cola; ejecución serial. Decisión técnica PR #4616, no dato medido.'),
    ('MAX_ATTEMPTS','2','Inicial: intento original y un reintento; no repetir sin límite. Decisión técnica PR #4616.'),
    ('QUEUE_TIMEOUT_SECONDS','900','Inicial: 15 minutos de espera máxima para RUN EN_COLA; calibrar con evidencia. Decisión técnica PR #4616.'),
    ('LEASE_SECONDS','600','Inicial: 10 minutos de lease de worker; no es SLA ni permiso de generación. Decisión técnica PR #4616.')
  ) AS p(key,val,reason);
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted <> 4
  THEN RAISE EXCEPTION 'SALY_CREATIVE_POLICY_INSERT_COUNT_MISMATCH:%',v_inserted; END IF;

  SELECT saly.creative_execution_policy_v1(now()) INTO v_policy;
  IF v_policy->>'schema_version' IS DISTINCT FROM 'CREATIVE_EXECUTION_POLICY_V1'
     OR v_policy->>'config_scope' IS DISTINCT FROM 'CREATIVE_FACTORY'
     OR v_policy->>'QUEUE_MAX' IS DISTINCT FROM '1'
     OR v_policy->>'MAX_ATTEMPTS' IS DISTINCT FROM '2'
     OR v_policy->>'QUEUE_TIMEOUT_SECONDS' IS DISTINCT FROM '900'
     OR v_policy->>'LEASE_SECONDS' IS DISTINCT FROM '600'
     OR (SELECT count(*) FROM jsonb_object_keys(coalesce(v_policy->'versions','{}'::jsonb))) <> 4
     OR (SELECT count(*) FROM saly.config_global
         WHERE scope='CREATIVE_FACTORY' AND value_type='INTEGER'
           AND value_status='REAL' AND valid_from=now()) <> 4
  THEN RAISE EXCEPTION 'SALY_CREATIVE_POLICY_READBACK_MISMATCH'; END IF;
  RAISE NOTICE 'PASS_SALY_CREATIVE_FACTORY_4_VALUES_REGISTERED_NO_RENDER_AUTHORITY';
END $policy$;
COMMIT;

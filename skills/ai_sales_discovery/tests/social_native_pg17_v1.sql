\set ON_ERROR_STOP on
-- Disposable PostgreSQL 17: all fixtures, schema and writer inside one transaction.
SELECT current_setting('server_version_num')::int >= 170000
  AND current_setting('server_version_num')::int < 180000 AS pg17;
BEGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE supabase_read_only_user NOLOGIN;
CREATE SCHEMA saly;
CREATE TABLE saly.ventas_discovery_catalogo(
  catalog_version text NOT NULL, source_id text NOT NULL,
  rights_status text NOT NULL, rights_checked_at timestamptz,
  habilitada boolean NOT NULL, persist_business_data boolean NOT NULL,
  rights_evidence_ref text NOT NULL, PRIMARY KEY(catalog_version,source_id)
);
CREATE TABLE public.lf_operation_execution(
  execution_id text PRIMARY KEY, operation_code text NOT NULL,
  target_type text NOT NULL, target_code text NOT NULL,
  status text NOT NULL, lease_owner text,
  lease_fence bigint, lease_expires_at timestamptz, manifest jsonb NOT NULL
);
CREATE TABLE public.lf_operation_contracts(
  operation_code text NOT NULL,contract_code text NOT NULL,status text NOT NULL,
  PRIMARY KEY(operation_code,contract_code)
);
CREATE TABLE public.lf_stub_effects(
  execution_id text NOT NULL,effect_key text NOT NULL,payload_hash text NOT NULL,
  receipt jsonb,PRIMARY KEY(execution_id,effect_key)
);
CREATE FUNCTION public.fn_lf_operation_reserve_effect_v1(
 p_exec text,p_owner text,p_fence bigint,p_key text,p_hash text,p_group text,p_actor text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE found public.lf_stub_effects%ROWTYPE;
BEGIN
 SELECT * INTO found FROM public.lf_stub_effects
 WHERE execution_id=p_exec AND effect_key=p_key FOR UPDATE;
 IF FOUND THEN
   IF found.payload_hash IS DISTINCT FROM p_hash THEN
     RAISE EXCEPTION 'STUB_HASH_DRIFT';
   END IF;
   IF found.receipt IS NOT NULL THEN
     RETURN jsonb_build_object('result','REPLAY_SUCCEEDED_EFFECT','receipt',found.receipt);
   END IF;
   RAISE EXCEPTION 'STUB_PENDING_EFFECT';
 END IF;
 INSERT INTO public.lf_stub_effects VALUES(p_exec,p_key,p_hash,NULL);
 RETURN '{"result":"EFFECT_RESERVED_NEW","dispatch_permitted":true}'::jsonb;
END $$;
CREATE FUNCTION public.fn_lf_operation_mark_effect_succeeded_v1(
 p_exec text,p_owner text,p_fence bigint,p_key text,p_receipt jsonb,p_actor text)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 UPDATE public.lf_stub_effects SET receipt=p_receipt
 WHERE execution_id=p_exec AND effect_key=p_key AND receipt IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'STUB_EFFECT_NOT_RESERVED'; END IF;
 RETURN '{"result":"EFFECT_SUCCEEDED"}'::jsonb;
END $$;

\i supabase/migrations/20261122233000_lf_saly_social_evidence_schema_v1.sql
\i skills/ai_sales_discovery/adapters/social_native_writer_candidate_v1.sql

INSERT INTO saly.ventas_discovery_catalogo VALUES
('SALY-SOCIAL-V1','PE-INSTAGRAM','PERSISTENCIA_PERMITIDA',now(),true,true,'fixture-rights'),
('SALY-SOCIAL-V1','PE-FACEBOOK','PERSISTENCIA_PERMITIDA',now(),true,true,'fixture-rights');
INSERT INTO public.lf_operation_contracts
 VALUES('INGESTA_EMPRESARIAL_SALY','SALY_SOCIAL_INGESTION_V1','ACTIVE_ENFORCEMENT');
INSERT INTO public.lf_operation_execution VALUES
('EXEC-IG','INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE','PE-INSTAGRAM',
 'IN_PROGRESS','pg17-worker',1,now()+interval '1 hour',
 '{"social_scope":{"source_id":"PE-INSTAGRAM","business_key":"GARDEN_KIDS_EIRL",
 "window_start":"2026-09-22T00:00:00-05:00","window_end":"2026-11-22T23:59:59-05:00"}}'),
('EXEC-FB','INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE','PE-FACEBOOK',
 'IN_PROGRESS','pg17-worker',1,now()+interval '1 hour',
 '{"social_scope":{"source_id":"PE-FACEBOOK","business_key":"GARDEN_KIDS_EIRL",
 "window_start":"2026-09-22T00:00:00-05:00","window_end":"2026-11-22T23:59:59-05:00"}}');

CREATE FUNCTION public.saly_social_fixture(
 p_source text,p_external text,p_claim_state text,p_date text,
 p_hash text,p_claim text DEFAULT 'taller_digital')
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
  'business_key','GARDEN_KIDS_EIRL','source_id',p_source,
  'external_ref',p_external,
  'url',CASE WHEN p_source='PE-INSTAGRAM'
     THEN 'https://www.instagram.com/p/'||p_external||'/'
     ELSE 'https://www.facebook.com/reel/'||p_external||'/' END,
  'window_start','2026-09-22T00:00:00-05:00',
  'window_end','2026-11-22T23:59:59-05:00',
  'event_key','taller_educar_digitales',
  'event_title','Taller institucional de educación digital',
  'claim_key',p_claim,
  'claim_state',p_claim_state,'polarity','FAVORABLE',
  'identity_state','VALIDADA','match_state','REVISADO',
  'summary_non_personal','Actividad institucional, sin datos personales',
  'published_at',p_date,'rights_evidence_ref','fixture-rights',
  'source_sha256',p_hash
 )
$$;

DO $test$
DECLARE r jsonb; n int; h1 text:=repeat('a',64);h2 text:=repeat('b',64);
BEGIN
  -- First social insertion
  r:=saly.ventas_social_ingesta_execute_v1('EXEC-IG','pg17-worker',1,
      public.saly_social_fixture('PE-INSTAGRAM','Dg001','ANUNCIADO',
       '2026-11-12T09:00:00-05:00',h1));
  IF r->>'result'<>'INSERTADO' THEN RAISE EXCEPTION 'TEST_FIRST_INSERT %',r; END IF;
  -- Same-source exact replay has no second event/claim
  r:=saly.ventas_social_ingesta_execute_v1('EXEC-IG','pg17-worker',1,
      public.saly_social_fixture('PE-INSTAGRAM','Dg001','ANUNCIADO',
       '2026-11-12T09:00:00-05:00',h1));
  IF r->>'result'<>'INSERTADO' THEN RAISE EXCEPTION 'TEST_REPLAY %',r; END IF;
  -- Other channel same fact: only concurrency, no second canonical claim
  r:=saly.ventas_social_ingesta_execute_v1('EXEC-FB','pg17-worker',1,
      public.saly_social_fixture('PE-FACEBOOK','1234567890','ANUNCIADO',
       '2026-11-13T08:00:00-05:00',h2));
  IF r->>'result'<>'CONCURRENCIA_INTERCANAL'
      THEN RAISE EXCEPTION 'TEST_CONCURRENCY %',r; END IF;
  -- Other channel confirms event is completed: distinct claim and complement
  r:=saly.ventas_social_ingesta_execute_v1('EXEC-FB','pg17-worker',1,
      public.saly_social_fixture('PE-FACEBOOK','2222222222','REALIZADO',
       '2026-11-16T08:00:00-05:00',repeat('c',64)));
  IF r->>'result'<>'INSERTADO' THEN RAISE EXCEPTION 'TEST_COMPLEMENT %',r; END IF;
  IF (SELECT count(*) FROM saly.ventas_social_eventos_v1)<>1
   OR (SELECT count(*) FROM saly.ventas_social_publicaciones_v1)<>2
   OR (SELECT count(*) FROM saly.ventas_social_afirmaciones_v1)<>2
   OR (SELECT count(*) FROM saly.ventas_social_concurrencias_v1)<>2
   THEN RAISE EXCEPTION 'TEST_COUNTS'; END IF;
  -- Tampered source, rejected without inserting any record.
  BEGIN
   PERFORM saly.ventas_social_ingesta_execute_v1('EXEC-IG','pg17-worker',1,
      public.saly_social_fixture('PE-INSTAGRAM','DgBAD','ANUNCIADO',
       '2026-11-17T09:00:00-05:00',repeat('d',64)) ||
       '{"rights_evidence_ref":"unverified"}'::jsonb);
   RAISE EXCEPTION 'TEST_RIGHTS_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='TEST_RIGHTS_ACCEPTED' THEN RAISE; END IF;
   IF SQLERRM<>'SOCIAL_INGESTA_SOURCE_RIGHTS'
    THEN RAISE EXCEPTION 'WRONG_RIGHTS_FAILURE %',SQLERRM; END IF;
  END;
  BEGIN
   PERFORM saly.ventas_social_ingesta_execute_v1('EXEC-IG','pg17-worker',0,
      public.saly_social_fixture('PE-INSTAGRAM','DgBAD','ANUNCIADO',
       '2026-11-17T09:00:00-05:00',repeat('d',64)));
   RAISE EXCEPTION 'TEST_STALE_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='TEST_STALE_ACCEPTED' THEN RAISE; END IF;
   IF SQLERRM<>'SOCIAL_INGESTA_CALL_CONTRACT'
    THEN RAISE EXCEPTION 'WRONG_LEASE_FAILURE %',SQLERRM; END IF;
  END;
  IF (SELECT count(*) FROM saly.ventas_social_afirmaciones_v1)<>2
     THEN RAISE EXCEPTION 'TEST_NEGATIVE_ROLLBACK'; END IF;
  RAISE NOTICE 'PASS_SOCIAL_PG17_INSERT_REPLAY_CONCURRENCY_COMPLEMENT_RIGHTS';
END $test$;
ROLLBACK;
DO $check$
BEGIN
 IF to_regclass('saly.ventas_social_eventos_v1') IS NOT NULL
   THEN RAISE EXCEPTION 'ROLLBACK_NOT_CLEAN'; END IF;
 RAISE NOTICE 'PASS_SOCIAL_PG17_ROLLBACK_CLEAN';
END $check$;

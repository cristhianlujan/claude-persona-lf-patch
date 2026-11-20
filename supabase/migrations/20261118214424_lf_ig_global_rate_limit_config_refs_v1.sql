-- Owner correction 2026-11-18 16:35 Lima: global-config is the single
-- source of numerical rate limits. Follows PR #4104, without modifying reglas.
-- New AUTH six variables: D1/D1b; other seven existing rate policies carry
-- their current values forward into individual RATE_LIMIT config variables.
-- Policy metadata contains references/family only, never copied integer values.
BEGIN;

DO $pre$
DECLARE v_policy_md5 text; v_config_count int;
BEGIN
  IF to_regclass('public.lf_global_config') IS NULL
      OR to_regclass('lf_ops.politicas_rate_limit') IS NULL
      OR to_regclass('lf_ops.reglas') IS NULL THEN
    RAISE EXCEPTION 'IG_CHAT9_CONFIG_MISSING_TABLE';
  END IF;
  IF (SELECT count(*) FROM public.lf_global_config) <> 12
     OR (SELECT count(*) FROM lf_ops.politicas_rate_limit) <> 10
     OR (SELECT count(*) FROM lf_ops.reglas) <> 579
     OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE') <> 438
  THEN RAISE EXCEPTION 'IG_CHAT9_CONFIG_PREIMAGE_ROW_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.politicas_rate_limit
      WHERE rate_limit_policy_id IN (7,8,10)
        AND max_requests=5 AND burst_limit=5 AND window_seconds=900
        AND scope_key='USER') <> 3
  THEN RAISE EXCEPTION 'IG_CHAT9_CONFIG_PREIMAGE_D1_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM lf_ops.politicas_rate_limit
            WHERE window_seconds IS NULL OR max_requests IS NULL
               OR burst_limit IS NULL)
     OR EXISTS(SELECT 1 FROM information_schema.columns
               WHERE table_schema='lf_ops' AND table_name='politicas_rate_limit'
                 AND column_name='config_refs')
     OR to_regclass('lf_ops.v_politicas_rate_limit_effective_v1') IS NOT NULL
  THEN RAISE EXCEPTION 'IG_CHAT9_CONFIG_ALREADY_MIGRATED'; END IF;
  IF EXISTS(
     SELECT 1 FROM public.lf_global_config
     WHERE (scope='AUTH' AND config_key IN (
       'OTP_MAX_ATTEMPTS','OTP_WINDOW_SECONDS','OTP_BURST_LIMIT',
       'PASSWORD_FAIL_MAX_ATTEMPTS','PASSWORD_FAIL_WINDOW_SECONDS',
       'PASSWORD_FAIL_BURST_LIMIT'))
     OR (scope='RATE_LIMIT' AND config_key LIKE 'RATE_%')
  ) THEN RAISE EXCEPTION 'IG_CHAT9_CONFIG_KEY_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM lf_ops.politicas_rate_limit p
            WHERE p.rate_limit_policy_id NOT IN (1,2,3,4,5,6,7,8,9,10)
               OR p.policy_code !~ '^RATE-[A-Z0-9-]+$')
  THEN RAISE EXCEPTION 'IG_CHAT9_CONFIG_POLICY_SCOPE_DRIFT'; END IF;
END $pre$;

-- Exactly six owner-approved AUTH variables (no new numeric authority).
INSERT INTO public.lf_global_config
  (scope,config_key,config_value,value_type,value_status,description)
VALUES
('AUTH','OTP_MAX_ATTEMPTS','5','INTEGER','REAL',
 'Maximo de envios OTP por ventana, compartido por recuperacion B2B y nuevo dispositivo.'),
('AUTH','OTP_WINDOW_SECONDS','900','INTEGER','REAL',
 'Ventana movil de rate limit de envio OTP B2B en segundos.'),
('AUTH','OTP_BURST_LIMIT','5','INTEGER','REAL',
 'Burst limite OTP B2B. No duplicar su valor en politicas_rate_limit.'),
('AUTH','PASSWORD_FAIL_MAX_ATTEMPTS','5','INTEGER','REAL',
 'Intentos de contrasena fallida por usuario; separado de los tramos de bloqueo AUTH existentes.'),
('AUTH','PASSWORD_FAIL_WINDOW_SECONDS','900','INTEGER','REAL',
 'Ventana de contrasena fallida por usuario en segundos.'),
('AUTH','PASSWORD_FAIL_BURST_LIMIT','5','INTEGER','REAL',
 'Burst de contrasena fallida por usuario.');

-- Seven other already-existing policies: source values become config rows
-- without changing thresholds. Derive only from rows validated above.
INSERT INTO public.lf_global_config
  (scope,config_key,config_value,value_type,value_status,description)
SELECT 'RATE_LIMIT'::text,
       replace(p.policy_code,'-','_')||'.'||m.field_name,
       m.value::text,'INTEGER','REAL',
       'Migracion sin cambio funcional del limite existente '||
        p.policy_code||' / '||m.field_name||'. Familia RATE_LIMIT_LEGACY, mantenimiento global.'
FROM lf_ops.politicas_rate_limit p
CROSS JOIN LATERAL (VALUES
  ('window_seconds',p.window_seconds),
  ('max_requests',p.max_requests),
  ('burst_limit',p.burst_limit)
) AS m(field_name,value)
WHERE p.rate_limit_policy_id IN (1,2,3,4,5,6,9);

ALTER TABLE lf_ops.politicas_rate_limit
  ADD COLUMN config_refs jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE lf_ops.politicas_rate_limit
  ALTER COLUMN window_seconds DROP NOT NULL,
  ALTER COLUMN max_requests DROP NOT NULL,
  ALTER COLUMN burst_limit DROP NOT NULL;

-- Per-row canonical reference and inheritance semantics. No numeric shadow.
UPDATE lf_ops.politicas_rate_limit p
SET config_refs=jsonb_build_object(
    'family', CASE
       WHEN p.rate_limit_policy_id IN (7,8) THEN 'AUTH_OTP'
       WHEN p.rate_limit_policy_id=10 THEN 'AUTH_PASSWORD_FAIL'
       WHEN p.rate_limit_policy_id=9 THEN 'CLIENT_OTP_LEGACY'
       WHEN p.rate_limit_policy_id=1 THEN 'B2B_LOGIN_LEGACY'
       ELSE 'RATE_LIMIT_LEGACY' END,
    'inheritance',CASE WHEN p.rate_limit_policy_id IN (7,8)
                       THEN 'FAMILY_SHARED' ELSE 'POLICY_SPECIFIC' END,
    'window_seconds',jsonb_build_object(
       'scope',CASE WHEN p.rate_limit_policy_id IN (7,8,10) THEN 'AUTH' ELSE 'RATE_LIMIT' END,
       'config_key',CASE
         WHEN p.rate_limit_policy_id IN (7,8) THEN 'OTP_WINDOW_SECONDS'
         WHEN p.rate_limit_policy_id=10 THEN 'PASSWORD_FAIL_WINDOW_SECONDS'
         ELSE replace(p.policy_code,'-','_')||'.window_seconds' END),
    'max_requests',jsonb_build_object(
       'scope',CASE WHEN p.rate_limit_policy_id IN (7,8,10) THEN 'AUTH' ELSE 'RATE_LIMIT' END,
       'config_key',CASE
         WHEN p.rate_limit_policy_id IN (7,8) THEN 'OTP_MAX_ATTEMPTS'
         WHEN p.rate_limit_policy_id=10 THEN 'PASSWORD_FAIL_MAX_ATTEMPTS'
         ELSE replace(p.policy_code,'-','_')||'.max_requests' END),
    'burst_limit',jsonb_build_object(
       'scope',CASE WHEN p.rate_limit_policy_id IN (7,8,10) THEN 'AUTH' ELSE 'RATE_LIMIT' END,
       'config_key',CASE
         WHEN p.rate_limit_policy_id IN (7,8) THEN 'OTP_BURST_LIMIT'
         WHEN p.rate_limit_policy_id=10 THEN 'PASSWORD_FAIL_BURST_LIMIT'
         ELSE replace(p.policy_code,'-','_')||'.burst_limit' END)
  ),
  window_seconds=NULL,
  max_requests=NULL,
  burst_limit=NULL;

-- Structural guard: reject any later literal reintroduction or missing refs.
ALTER TABLE lf_ops.politicas_rate_limit
 ADD CONSTRAINT politicas_rate_limit_only_global_refs_ck CHECK(
   window_seconds IS NULL AND max_requests IS NULL AND burst_limit IS NULL
   AND jsonb_typeof(config_refs)='object'
   AND nullif(config_refs->>'family','') IS NOT NULL
   AND (config_refs->>'inheritance') IN ('FAMILY_SHARED','POLICY_SPECIFIC')
   AND nullif(config_refs#>>'{window_seconds,scope}','') IS NOT NULL
   AND nullif(config_refs#>>'{window_seconds,config_key}','') IS NOT NULL
   AND nullif(config_refs#>>'{max_requests,scope}','') IS NOT NULL
   AND nullif(config_refs#>>'{max_requests,config_key}','') IS NOT NULL
   AND nullif(config_refs#>>'{burst_limit,scope}','') IS NOT NULL
   AND nullif(config_refs#>>'{burst_limit,config_key}','') IS NOT NULL
 );

-- One consumer read model. Latest valid config version only. Missing/invalid
-- values => resolution_status=BLOCKED; never silently fall back to literals.
CREATE VIEW lf_ops.v_politicas_rate_limit_effective_v1 AS
WITH cfg AS (
  SELECT DISTINCT ON (scope,config_key)
    scope,config_key,config_value,value_type,value_status
  FROM public.lf_global_config
  WHERE valid_from <= now()
  ORDER BY scope,config_key,valid_from DESC,created_at DESC
), joined AS (
 SELECT p.rate_limit_policy_id,p.policy_code,p.resource_code,p.scope_key,
        p.error_id,p.error_code,p.status,p.source_decision_id,
        p.source_decision_number,p.parameter_provenance,p.config_refs,
        p.created_at,p.updated_at,
        CASE WHEN cw.value_type='INTEGER' AND cw.value_status='REAL'
            AND cw.config_value ~ '^[0-9]{1,9}$'
            THEN cw.config_value::integer END AS window_seconds,
        CASE WHEN cm.value_type='INTEGER' AND cm.value_status='REAL'
            AND cm.config_value ~ '^[0-9]{1,9}$'
            THEN cm.config_value::integer END AS max_requests,
        CASE WHEN cb.value_type='INTEGER' AND cb.value_status='REAL'
            AND cb.config_value ~ '^[0-9]{1,9}$'
            THEN cb.config_value::integer END AS burst_limit
 FROM lf_ops.politicas_rate_limit p
 LEFT JOIN cfg cw ON cw.scope=p.config_refs#>>'{window_seconds,scope}'
                 AND cw.config_key=p.config_refs#>>'{window_seconds,config_key}'
 LEFT JOIN cfg cm ON cm.scope=p.config_refs#>>'{max_requests,scope}'
                 AND cm.config_key=p.config_refs#>>'{max_requests,config_key}'
 LEFT JOIN cfg cb ON cb.scope=p.config_refs#>>'{burst_limit,scope}'
                 AND cb.config_key=p.config_refs#>>'{burst_limit,config_key}'
)
SELECT j.*,
  CASE WHEN j.window_seconds>0 AND j.max_requests>0
            AND j.burst_limit>=j.max_requests
       THEN 'READY' ELSE 'BLOCKED' END AS resolution_status
FROM joined j;
COMMENT ON VIEW lf_ops.v_politicas_rate_limit_effective_v1 IS
 'Runtime/contract read model; always resolve from lf_global_config. Base policies carry references and NULL numeric values. Do not use base policy literal limits.';
REVOKE ALL ON lf_ops.v_politicas_rate_limit_effective_v1 FROM PUBLIC,anon,authenticated;
DO $readonly_grant$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN
    GRANT SELECT ON lf_ops.v_politicas_rate_limit_effective_v1 TO supabase_read_only_user;
  END IF;
END $readonly_grant$;

-- Two existing function consumers construct JSON rate-limit contracts; keep
-- their signatures and all other content unchanged, replace only FROM source.
DO $rewire$
DECLARE
  name text; def text; old_from text :=
    'from lf_ops.politicas_rate_limit rp';
  new_from text :=
    'from lf_ops.v_politicas_rate_limit_effective_v1 rp';
BEGIN
  FOREACH name IN ARRAY ARRAY[
   'fn_b2b_backoffice_login_contract','fn_screen_contract_v1']
  LOOP
   SELECT pg_get_functiondef(p.oid) INTO def
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='lf_ops' AND p.proname=name;
   IF def IS NULL
      OR length(def)-length(replace(def,old_from,''))<>length(old_from)
   THEN RAISE EXCEPTION 'IG_CHAT9_CONSUMER_SOURCE_DRIFT:%',name; END IF;
   EXECUTE replace(def,old_from,new_from);
  END LOOP;
END $rewire$;

DO $post$
DECLARE n integer;
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config)<>39
    OR (SELECT count(*) FROM public.lf_global_config
        WHERE scope='AUTH')<>16
    OR (SELECT count(*) FROM public.lf_global_config
        WHERE scope='RATE_LIMIT')<>21
    OR (SELECT count(*) FROM lf_ops.politicas_rate_limit)<>10
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
    OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>438
    OR EXISTS(SELECT 1 FROM lf_ops.politicas_rate_limit
              WHERE window_seconds IS NOT NULL OR max_requests IS NOT NULL
                   OR burst_limit IS NOT NULL)
    OR (SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1
        WHERE resolution_status='READY')<>10
    OR (SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1
        WHERE rate_limit_policy_id IN (7,8,10)
         AND window_seconds=900 AND max_requests=5 AND burst_limit=5)<>3
    OR EXISTS(
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='lf_ops'
        AND p.proname IN ('fn_screen_contract_v1','fn_b2b_backoffice_login_contract')
        AND (p.prosrc LIKE '%from lf_ops.politicas_rate_limit rp%'
             OR p.prosrc NOT LIKE '%from lf_ops.v_politicas_rate_limit_effective_v1 rp%')
    )
 THEN RAISE EXCEPTION 'IG_CHAT9_GLOBAL_REF_POSTIMAGE_MISMATCH'; END IF;
 RAISE NOTICE 'IG_CHAT9_CONFIG_PASS global_config=12_to_39 policies=10_all_refs literal_values=0 rules=579 runtime_view=10_ready';
END $post$;
COMMIT;

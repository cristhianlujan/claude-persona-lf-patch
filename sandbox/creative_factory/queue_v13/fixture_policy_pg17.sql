-- Disposable PostgreSQL 17 fixture, NOT SALY live database.
DROP SCHEMA IF EXISTS saly CASCADE;
CREATE SCHEMA saly;
CREATE TABLE saly.config_global (
  scope text NOT NULL CONSTRAINT config_global_scope_nonempty CHECK (btrim(scope)<>''),
  config_key text NOT NULL CONSTRAINT config_global_key_nonempty CHECK (btrim(config_key)<>''),
  config_value text NOT NULL CONSTRAINT config_global_value_nonempty CHECK (btrim(config_value)<>''),
  value_type text NOT NULL CONSTRAINT config_global_type_check CHECK (value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
  value_status text NOT NULL CONSTRAINT config_global_status_check CHECK (value_status IN ('FICTICIO','REAL')),
  description text,
  valid_from timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT config_global_unique_version UNIQUE(scope,config_key,valid_from)
);
CREATE TABLE saly.creative_runs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  state text NOT NULL
);
-- Exact policy lookup behavior from migrations/20261121080001.
CREATE FUNCTION saly.creative_execution_policy_v1(p_asof timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path TO pg_catalog,saly,pg_temp
AS $fn$
DECLARE k text; c record; result jsonb:='{}'; pins jsonb:='{}';
BEGIN
 IF p_asof IS NULL THEN RAISE EXCEPTION 'CREATIVE_CONFIG_ASOF_REQUIRED'; END IF;
 FOREACH k IN ARRAY ARRAY['QUEUE_MAX','MAX_ATTEMPTS','QUEUE_TIMEOUT_SECONDS','LEASE_SECONDS'] LOOP
   SELECT config_value,value_type,value_status,valid_from INTO c FROM saly.config_global
   WHERE scope='CREATIVE_FACTORY' AND config_key=k AND valid_from<=p_asof
   ORDER BY valid_from DESC LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CONFIG_MISSING:%',k; END IF;
   IF c.value_type<>'INTEGER' OR c.value_status<>'REAL' OR c.config_value !~ '^[1-9][0-9]*$'
   THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   IF c.config_value::numeric>2147483647 THEN RAISE EXCEPTION 'CREATIVE_CONFIG_INVALID:%',k; END IF;
   result:=result||jsonb_build_object(k,c.config_value::integer);
   pins:=pins||jsonb_build_object(k,c.valid_from);
 END LOOP;
 RETURN result||jsonb_build_object('schema_version','CREATIVE_EXECUTION_POLICY_V1','config_scope','CREATIVE_FACTORY','versions',pins);
END $fn$;

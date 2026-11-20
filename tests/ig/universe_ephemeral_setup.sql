\set ON_ERROR_STOP on
-- Disposable Postgres only: 4 synthetic families, not the 47 production registry.
CREATE SCHEMA programacion;
CREATE SCHEMA lf_ops;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_ops.reglas (
 id bigint PRIMARY KEY,codigo text not null,valor_config jsonb not null);
CREATE TABLE programacion.contratos(
 id bigint generated always as identity,version_id bigint,contrato_codigo text,
 estado text,fail_closed boolean,especificacion jsonb);
CREATE TABLE programacion.input_readiness_runs(
 id bigint primary key,universe_rule_id bigint,family_count int,
 universe_snapshot_sha256 text);
-- Copies of actual deployed canonical JSON hashing, not a substitute digest.
CREATE OR REPLACE FUNCTION programacion.fn_v09_canonical_jsonb_text(j jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE STRICT
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  r text := '';
  kv record;
  elem record;
  first boolean := true;
  t text;
begin
  t := jsonb_typeof(j);
  if t = 'object' then
    r := '{';
    for kv in select key, value from jsonb_each(j) order by key collate "C" loop
      if not first then r := r || ','; end if;
      first := false;
      r := r || to_json(kv.key)::text || ':' || programacion.fn_v09_canonical_jsonb_text(kv.value);
    end loop;
    return r || '}';
  elsif t = 'array' then
    r := '[';
    first := true;
    for elem in select value from jsonb_array_elements(j) with ordinality as a(value, ord) order by ord loop
      if not first then r := r || ','; end if;
      first := false;
      r := r || programacion.fn_v09_canonical_jsonb_text(elem.value);
    end loop;
    return r || ']';
  else
    return j::text;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_v09_sha256_jsonb(j jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select encode(
    extensions.digest(
      convert_to(programacion.fn_v09_canonical_jsonb_text($1), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

INSERT INTO lf_ops.reglas(id,codigo,valor_config)
VALUES (10,'REGISTRY_RULE_GOOD','{"families":["F_A","F_B","F_C","F_D"]}'::jsonb);
INSERT INTO programacion.contratos(version_id,contrato_codigo,estado,fail_closed,especificacion)
VALUES(19,'INPUT_FAMILY_POLICY_REGISTRY','defined',true,
 '{"canonical_universe_rule":"REGISTRY_RULE_GOOD","family_count":4,
   "families":{"F_A":{},"F_B":{},"F_C":{},"F_D":{}}}'::jsonb);
INSERT INTO programacion.input_readiness_runs(id,universe_rule_id,family_count,universe_snapshot_sha256)
SELECT 833,r.id,4,
programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code',r.codigo,'families',r.valor_config->'families'))
FROM lf_ops.reglas r WHERE r.id=10;

-- LF IG G3 PostgreSQL 17.6 ONLY, sanitized development fixture (no PII).
-- Generated from Supabase READ-ONLY canonical contexts + 14 ACTIVE selectors on
-- 2026-10-28. This is TEST DATA: historical IDs are not runtime hardcodes.
-- Read-only projection parity independently verified: 812 pairs/52 matches/0 drift.
-- Never execute outside the disposable database guarded by the verifier.
-- Rebuild if live source hashes or selector set change. Not a migration.
CREATE SCHEMA IF NOT EXISTS programacion;

-- PREIMAGE programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb) md5 1123257c0c6c7eb1e2aa26783f3ccc0a
CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_clause_matches_v1(p_clause jsonb, p_context jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_path text[];
  v_actual jsonb;
  v_op text;
begin
  if jsonb_typeof(p_clause) <> 'object' or jsonb_typeof(p_context) <> 'object' then
    return false;
  end if;
  if jsonb_typeof(p_clause->'path') <> 'array' or jsonb_array_length(p_clause->'path') = 0 then
    return false;
  end if;

  select array_agg(value order by ordinality)
    into v_path
  from jsonb_array_elements_text(p_clause->'path') with ordinality as x(value, ordinality);

  if v_path is null or cardinality(v_path) = 0 or v_path[1] is distinct from 'target' then
    return false;
  end if;

  v_op := upper(coalesce(p_clause->>'op',''));
  v_actual := p_context #> v_path;

  if v_op = 'EXISTS' then
    return v_actual is not null;
  elsif v_op = 'EQ' then
    if not (p_clause ? 'value') or v_actual is null then return false; end if;
    return v_actual = p_clause->'value';
  elsif v_op = 'IN' then
    if jsonb_typeof(p_clause->'values') <> 'array' or v_actual is null then return false; end if;
    return exists (
      select 1 from jsonb_array_elements(p_clause->'values') as x(value)
      where x.value = v_actual
    );
  end if;

  return false;
end;
$function$;


-- PREIMAGE programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb) md5 3b912c7872aceff83de24e9e8d1ad934
CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_matches_v1(p_selector jsonb, p_context jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_all jsonb;
  v_any jsonb;
  v_clause jsonb;
  v_any_match boolean := false;
  v_clause_count integer := 0;
begin
  if jsonb_typeof(p_selector) <> 'object' or jsonb_typeof(p_context) <> 'object' then return false; end if;
  if p_selector->>'schema_version' is distinct from 'lf-rule-applicability/v1' then return false; end if;
  if p_selector->>'status' is distinct from 'ACTIVE' then return false; end if;

  if exists (
    select 1 from jsonb_object_keys(p_selector) as k(key)
    where k.key not in ('schema_version','status','consumer_roles','all','any','provenance')
  ) then return false; end if;

  if jsonb_typeof(p_selector->'consumer_roles') <> 'array'
     or jsonb_array_length(p_selector->'consumer_roles') = 0 then return false; end if;
  if not exists (
    select 1 from jsonb_array_elements_text(p_selector->'consumer_roles') as c(role_code)
    where c.role_code = p_context->>'consumer_role'
  ) then return false; end if;

  v_all := coalesce(p_selector->'all','[]'::jsonb);
  v_any := coalesce(p_selector->'any','[]'::jsonb);
  if jsonb_typeof(v_all) <> 'array' or jsonb_typeof(v_any) <> 'array' then return false; end if;
  v_clause_count := jsonb_array_length(v_all) + jsonb_array_length(v_any);
  -- Consumer-only applicability would be an implicit global. N-4 forbids it.
  if v_clause_count = 0 then return false; end if;

  for v_clause in select value from jsonb_array_elements(v_all)
  loop
    if programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) is not true then return false; end if;
  end loop;

  if jsonb_array_length(v_any) > 0 then
    for v_clause in select value from jsonb_array_elements(v_any)
    loop
      if programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) is true then
        v_any_match := true; exit;
      end if;
    end loop;
    if not v_any_match then return false; end if;
  end if;

  return true;
end;
$function$;

DROP TABLE IF EXISTS public.ig_n4_rule_fixtures;
DROP TABLE IF EXISTS public.ig_n4_screen_fixtures;
CREATE TABLE public.ig_n4_rule_fixtures(rule_id integer PRIMARY KEY, rule_code text NOT NULL, selector jsonb NOT NULL);
CREATE TABLE public.ig_n4_screen_fixtures(screen_id integer PRIMARY KEY, context jsonb NOT NULL);
INSERT INTO public.ig_n4_rule_fixtures(rule_id,rule_code,selector) VALUES
(139,'REG_ATQ_019','{"all":[],"any":[{"op":"IN","path":["target","module","module_code"],"values":["CLIENT_HOME"]},{"op":"IN","path":["target","screen","id"],"values":[7,8,10,12,13,15,16,17,21,24,25,27,28,30,33,34]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(368,'NEG-RESPALDO-SIN-CAJAS-VACIAS-01','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[37]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(373,'UX-RUTA-MODELO-2CAPAS-01','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[4,41]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(379,'NEG-RUTA-ELEGIBILIDAD-B2B-01','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[41]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(387,'B2B-RULE-DESIGN-001','{"all":[],"any":[{"op":"IN","path":["target","app_shell","app_shell_code"],"values":["ADMIN_APP_SHELL"]},{"op":"IN","path":["target","module","module_code"],"values":["B2B_AUTENTICACION"]},{"op":"IN","path":["target","screen","id"],"values":[43,44,45,46,47]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(456,'REG_AUTH_PHONE_OWNERSHIP_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[1,2]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(463,'B2B-RULE-STORY-READINESS-001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[51]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(537,'REG_CLIENT_AUTH_HEADER_CAPABILITY_GATING_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[21]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(550,'REG_CLIENT_HOME_CLARITY_CONTENT_FRESHNESS_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[39,41]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(556,'REG_CLIENT_PUBLIC_LEGAL_NAV_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[38,57]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(593,'REG_LF_BENEFITS_REVERSIBILITY_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[5]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(594,'REG_LF_BENEFITS_CONFIG_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[5]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(595,'REG_LF_BENEFITS_SURFACE_RESOLUTION_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[5]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb),
(597,'REG_LF_BENEFITS_B2B_CAMPAIGN_001','{"all":[],"any":[{"op":"IN","path":["target","screen","id"],"values":[5]}],"status":"ACTIVE","provenance":{"authority":"OWNER_AUTHORIZED_GOVERNED_MIGRATION","r14_event_id":19951,"migration_source":"LEGACY_POSITIVE_BINDINGS_FOR_EQUIVALENCE_ONLY","decision_event_id":19948,"migration_version":"20261002173000"},"consumer_roles":["INPUT_GOVERNANCE"],"schema_version":"lf-rule-applicability/v1"}'::jsonb);
INSERT INTO public.ig_n4_screen_fixtures(screen_id,context) VALUES
(1,'{"target":{"module":{"module_code":"CLIENT_ONBOARDING"},"screen":{"id":1},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(2,'{"target":{"module":{"module_code":"CLIENT_ONBOARDING"},"screen":{"id":2},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(3,'{"target":{"module":{"module_code":"CLIENT_ONBOARDING"},"screen":{"id":3},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(4,'{"target":{"module":{"module_code":"CLIENT_HOME"},"screen":{"id":4},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(5,'{"target":{"module":{"module_code":"CLIENT_HOME"},"screen":{"id":5},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(6,'{"target":{"module":{"module_code":"CLIENT_HOME"},"screen":{"id":6},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(7,'{"target":{"module":null,"screen":{"id":7},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(8,'{"target":{"module":null,"screen":{"id":8},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(9,'{"target":{"module":null,"screen":{"id":9},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(10,'{"target":{"module":null,"screen":{"id":10},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(11,'{"target":{"module":{"module_code":"CLIENT_HOME"},"screen":{"id":11},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(12,'{"target":{"module":null,"screen":{"id":12},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(13,'{"target":{"module":null,"screen":{"id":13},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(15,'{"target":{"module":null,"screen":{"id":15},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(16,'{"target":{"module":null,"screen":{"id":16},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(17,'{"target":{"module":null,"screen":{"id":17},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(18,'{"target":{"module":{"module_code":"CLIENT_HOME"},"screen":{"id":18},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(19,'{"target":{"module":{"module_code":"CLIENT_HOME"},"screen":{"id":19},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(21,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":21},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(24,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":24},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(25,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":25},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(26,'{"target":{"module":null,"screen":{"id":26},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(27,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":27},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(28,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":28},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(30,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":30},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(33,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":33},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(34,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":34},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(36,'{"target":{"module":null,"screen":{"id":36},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(37,'{"target":{"module":null,"screen":{"id":37},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(38,'{"target":{"module":null,"screen":{"id":38},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(39,'{"target":{"module":null,"screen":{"id":39},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(41,'{"target":{"module":null,"screen":{"id":41},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(42,'{"target":{"module":null,"screen":{"id":42},"app_shell":null},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(43,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":43},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(44,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":44},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(45,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":45},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(46,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":46},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(47,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":47},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(48,'{"target":{"module":{"module_code":"B2B_ADMINISTRACION"},"screen":{"id":48},"app_shell":{"app_shell_code":"ADMIN_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(49,'{"target":{"module":{"module_code":"B2B_ADMINISTRACION"},"screen":{"id":49},"app_shell":{"app_shell_code":"ADMIN_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(50,'{"target":{"module":{"module_code":"B2B_ADMINISTRACION"},"screen":{"id":50},"app_shell":{"app_shell_code":"ADMIN_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(51,'{"target":{"module":{"module_code":"B2B_AUTENTICACION"},"screen":{"id":51},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(52,'{"target":{"module":{"module_code":"B2B_AUTENTICACION"},"screen":{"id":52},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(53,'{"target":{"module":{"module_code":"B2B_AUTENTICACION"},"screen":{"id":53},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(54,'{"target":{"module":{"module_code":"B2B_AUTENTICACION"},"screen":{"id":54},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(55,'{"target":{"module":{"module_code":"B2B_AUTENTICACION"},"screen":{"id":55},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(56,'{"target":{"module":{"module_code":"B2B_AUTENTICACION"},"screen":{"id":56},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(57,'{"target":{"module":{"module_code":"CLIENT_ONBOARDING"},"screen":{"id":57},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(58,'{"target":{"module":{"module_code":"CLIENT_ONBOARDING"},"screen":{"id":58},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(59,'{"target":{"module":{"module_code":"CLIENT_PAYMENTS"},"screen":{"id":59},"app_shell":{"app_shell_code":"CLIENT_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(60,'{"target":{"module":{"module_code":"B2B_DASHBOARD"},"screen":{"id":60},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(61,'{"target":{"module":{"module_code":"B2B_SIMULA"},"screen":{"id":61},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(62,'{"target":{"module":{"module_code":"B2B_SIMULA"},"screen":{"id":62},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(63,'{"target":{"module":{"module_code":"B2B_SIMULA"},"screen":{"id":63},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(64,'{"target":{"module":{"module_code":"B2B_OFERTAS"},"screen":{"id":64},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(65,'{"target":{"module":{"module_code":"B2B_SIMULA"},"screen":{"id":65},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(66,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":66},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb),
(67,'{"target":{"module":{"module_code":"B2B_CARGAS"},"screen":{"id":67},"app_shell":{"app_shell_code":"B2B_APP_SHELL"}},"consumer_role":"INPUT_GOVERNANCE"}'::jsonb);
DO $fixture$
BEGIN
 IF (SELECT count(*) FROM public.ig_n4_rule_fixtures) <> 14
 OR (SELECT count(*) FROM public.ig_n4_screen_fixtures) <> 58
 THEN RAISE EXCEPTION 'IG_N4_FIXTURE_SNAPSHOT_DRIFT'; END IF;
END
$fixture$;

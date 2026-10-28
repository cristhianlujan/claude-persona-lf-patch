-- LF IG G3 post-DDL ACL contract. Isolated PostgreSQL 17.6 ONLY.
-- This is concatenated INSIDE the runner's BEGIN / ROLLBACK transaction.
-- Test principals and schema grants are reversible; no Supabase or real roles.
-- The TEST verifies actual function invocation under SET LOCAL ROLE, not
-- merely the presence of grants in pg_catalog.
DO $preflight_acl$
BEGIN
 IF current_database() IS DISTINCT FROM 'lf_ig_n4_isolated_ci'
   OR to_regprocedure('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)') IS NULL
 THEN RAISE EXCEPTION 'IG_G3_ACL_NOT_ISOLATED_POST_DDL'; END IF;
END
$preflight_acl$;

CREATE ROLE ig_n4_untrusted_acl_probe NOLOGIN;
CREATE ROLE ig_n4_governed_acl_probe NOLOGIN;
GRANT USAGE ON SCHEMA programacion TO ig_n4_governed_acl_probe;

DO $acl_structural$
DECLARE
 v_sig text;
 v_proc regprocedure;
 v_definer boolean;
 v_volatility "char";
BEGIN
 IF has_schema_privilege('ig_n4_untrusted_acl_probe','programacion','USAGE')
    OR has_schema_privilege('ig_n4_untrusted_acl_probe','programacion','CREATE')
 THEN RAISE EXCEPTION 'FAIL_ACL_UNTRUSTED_SCHEMA_PRIVILEGES'; END IF;
 IF NOT has_schema_privilege('ig_n4_governed_acl_probe','programacion','USAGE')
    OR has_schema_privilege('ig_n4_governed_acl_probe','programacion','CREATE')
 THEN RAISE EXCEPTION 'FAIL_ACL_GOVERNED_SCHEMA_PRIVILEGES'; END IF;
 FOR v_sig IN SELECT sig FROM (VALUES
  ('programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'),
  ('programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'),
  ('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)')
 ) AS signatures(sig)
 LOOP
  v_proc := to_regprocedure(v_sig);
  IF v_proc IS NULL THEN RAISE EXCEPTION 'FAIL_ACL_FUNCTION_MISSING: %',v_sig; END IF;
  SELECT prosecdef,provolatile INTO v_definer,v_volatility FROM pg_proc WHERE oid=v_proc;
  IF v_definer OR v_volatility IS DISTINCT FROM 'i' THEN
    RAISE EXCEPTION 'FAIL_ACL_FUNCTION_FLAGS: %',v_sig; END IF;
 END LOOP;
END
$acl_structural$;

-- Negative: role without schema USAGE must get SQLSTATE 42501 on each
-- actual invocation. Any unexpected success/error fails the whole test.
SET LOCAL ROLE ig_n4_untrusted_acl_probe;
DO $acl_negative$
DECLARE
 v_sig text;
 v_sql text;
BEGIN
 FOR v_sig IN SELECT sig FROM (VALUES
  ('programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'),
  ('programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'),
  ('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)')
 ) AS signatures(sig)
 LOOP
  v_sql := format('SELECT %s',CASE
   WHEN v_sig LIKE '%clause_schema_valid%' THEN
    'programacion.fn_input_rule_selector_clause_schema_valid_v1(''{}''::jsonb)'
   WHEN v_sig LIKE '%clause_matches%' THEN
    'programacion.fn_input_rule_selector_clause_matches_v1(''{}''::jsonb,''{}''::jsonb)'
   ELSE
    'programacion.fn_input_rule_selector_matches_v1(''{}''::jsonb,''{}''::jsonb)'
  END);
  BEGIN
   EXECUTE v_sql;
   RAISE EXCEPTION 'FAIL_ACL_UNTRUSTED_INVOKED: %',v_sig;
  EXCEPTION WHEN insufficient_privilege THEN
   NULL; -- expected 42501, no escalation
  END;
 END LOOP;
END
$acl_negative$;
RESET ROLE;

-- Positive: a principal with explicitly granted schema USAGE can invoke
-- each function and receives a typed false for empty invalid selectors.
SET LOCAL ROLE ig_n4_governed_acl_probe;
DO $acl_positive$
DECLARE
 v_selector boolean;
 v_clause boolean;
 v_valid boolean;
BEGIN
 SELECT programacion.fn_input_rule_selector_matches_v1('{}'::jsonb,'{}'::jsonb)
 INTO v_selector;
 SELECT programacion.fn_input_rule_selector_clause_matches_v1('{}'::jsonb,'{}'::jsonb)
 INTO v_clause;
 SELECT programacion.fn_input_rule_selector_clause_schema_valid_v1('{}'::jsonb)
 INTO v_valid;
 IF v_selector IS DISTINCT FROM false OR
    v_clause IS DISTINCT FROM false OR v_valid IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'FAIL_ACL_GOVERNED_INVALID_INPUT_NOT_DENIED'; END IF;
END
$acl_positive$;
RESET ROLE;

-- Check session context returned to the original trusted test superuser.
DO $acl_restored$
BEGIN
 IF current_user IS DISTINCT FROM 'ig_n4_local'
 THEN RAISE EXCEPTION 'FAIL_ACL_SESSION_ROLE_NOT_RESTORED'; END IF;
END
$acl_restored$;
SELECT 'ACL_G3_POST_DDL_REAL_INVOCATION|PASS';

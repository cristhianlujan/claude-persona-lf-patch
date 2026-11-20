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
CREATE ROLE ig_n4_schema_only_acl_probe NOLOGIN;
GRANT USAGE ON SCHEMA programacion TO ig_n4_governed_acl_probe;
GRANT USAGE ON SCHEMA programacion TO ig_n4_schema_only_acl_probe;

-- Observe AS-IS ACL before any test-only change: helper inherits PUBLIC EXECUTE,
-- effective for a principal that already has schema USAGE.
DO $acl_baseline$
BEGIN
 IF NOT has_function_privilege('ig_n4_schema_only_acl_probe',
   'programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL_ACL_BASELINE_EXPECTED_PUBLIC_EXECUTE'; END IF;
 RAISE NOTICE 'ACL_BASELINE|helper|PUBLIC_EXECUTE_TRUE';
END
$acl_baseline$;

-- Explicit EXECUTE isolation is a *sandbox simulation*, NOT the live candidate ACL.
-- Keep a separate negative that detects the consequence of a missing grant.
REVOKE EXECUTE ON FUNCTION programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb) TO ig_n4_governed_acl_probe;

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
 IF NOT has_schema_privilege('ig_n4_schema_only_acl_probe','programacion','USAGE')
   OR has_schema_privilege('ig_n4_schema_only_acl_probe','programacion','CREATE')
   OR has_function_privilege('ig_n4_schema_only_acl_probe',
     'programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL_ACL_SCHEMA_ONLY_EXECUTE_ISOLATION'; END IF;
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
   RAISE NOTICE 'ACL_NEGATIVE|%|42501',CASE
    WHEN v_sig LIKE '%clause_schema_valid%' THEN 'clause_schema_valid'
    WHEN v_sig LIKE '%clause_matches%' THEN 'clause_matches'
    ELSE 'selector_matches' END;
  END;
 END LOOP;
END
$acl_negative$;
RESET ROLE;

-- Separate real invocation with schema USAGE but without helper EXECUTE.
SET LOCAL ROLE ig_n4_schema_only_acl_probe;
DO $acl_schema_only$
BEGIN
 BEGIN
  PERFORM programacion.fn_input_rule_selector_clause_schema_valid_v1('{}'::jsonb);
  RAISE EXCEPTION 'FAIL_ACL_SCHEMA_ONLY_EXECUTED_HELPER';
 EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ACL_RESTRICTED_SIM|schema_only|helper|42501';
 END;
END
$acl_schema_only$;
RESET ROLE;

-- Positive: a principal with explicitly granted schema USAGE can invoke
-- each function and receives a typed false for empty invalid selectors.
SET LOCAL ROLE ig_n4_governed_acl_probe;
DO $acl_positive$
DECLARE
 v_selector boolean;
 v_clause boolean;
 v_valid boolean;
 v_true boolean;
 v_cross_consumer boolean;
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
 RAISE NOTICE 'ACL_POSITIVE|selector_matches|false';
 RAISE NOTICE 'ACL_POSITIVE|clause_matches|false';
 RAISE NOTICE 'ACL_POSITIVE|clause_schema_valid|false';
 -- Authorized consumer and exact target path: actual user-role invocation
 -- should return TRUE; different consumer must fail closed.
 SELECT programacion.fn_input_rule_selector_matches_v1(
   '{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","id"],"op":"EQ","value":1}]}'::jsonb,
   '{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":1}}}'::jsonb
 ) INTO v_true;
 SELECT programacion.fn_input_rule_selector_matches_v1(
   '{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","id"],"op":"EQ","value":1}]}'::jsonb,
   '{"consumer_role":"OTHER_CONSUMER","target":{"screen":{"id":1}}}'::jsonb
 ) INTO v_cross_consumer;
 IF v_true IS DISTINCT FROM true OR v_cross_consumer IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'FAIL_ACL_GOVERNED_POSITIVE_OR_CONSUMER_NEGATIVE'; END IF;
 RAISE NOTICE 'ACL_POSITIVE|selector_allowed|true';
 RAISE NOTICE 'ACL_POSITIVE|cross_consumer|false';
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

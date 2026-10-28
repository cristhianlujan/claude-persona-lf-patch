-- LF IG G3 ACL negative tests, DEV ISOLATED ONLY, PostgreSQL 17.6.
-- Use INSIDE an already opened BEGIN, after candidate function DDL, before ROLLBACK.
-- Roles created here are fictional test principals and rolled back with the test.
-- Mirrors live ACL POLICY boundary, not an independently authenticated live role test.
DO $preflight_acl$
BEGIN
 IF current_database() NOT LIKE 'lf_ig_n4_isolated_%'
   OR to_regprocedure('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)') IS NULL
 THEN RAISE EXCEPTION 'IG_G3_ACL_NOT_ISOLATED_POST_DDL'; END IF;
END
$preflight_acl$;

CREATE ROLE ig_n4_untrusted_acl_probe NOLOGIN;
CREATE ROLE ig_n4_governed_acl_probe NOLOGIN;
GRANT USAGE ON SCHEMA programacion TO ig_n4_governed_acl_probe;

DO $assert_acl$
DECLARE
 v_role text;
 v_sig text;
 v_proc regprocedure;
 v_security_definer boolean;
 v_volatility char;
BEGIN
 IF has_schema_privilege('ig_n4_untrusted_acl_probe','programacion','USAGE') THEN
  RAISE EXCEPTION 'FAIL_ACL_UNTRUSTED_SCHEMA_ACCESS'; END IF;
 IF NOT has_schema_privilege('ig_n4_governed_acl_probe','programacion','USAGE') THEN
  RAISE EXCEPTION 'FAIL_ACL_GOVERNED_SCHEMA_ACCESS'; END IF;
 FOR v_sig IN
  SELECT x.sig FROM (VALUES
   ('programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'),
   ('programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'),
   ('programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)')
  ) AS x(sig)
 LOOP
  v_proc:=to_regprocedure(v_sig);
  IF v_proc IS NULL THEN RAISE EXCEPTION 'FAIL_ACL_MISSING_FUNCTION:%',v_sig; END IF;
  SELECT prosecdef,provolatile INTO v_security_definer,v_volatility
  FROM pg_proc WHERE oid=v_proc;
  IF v_security_definer OR v_volatility<>'i' THEN
    RAISE EXCEPTION 'FAIL_ACL_FUNCTION_FLAGS:%',v_sig; END IF;
  -- PUBLIC has a default EXECUTE grant but no USAGE on this isolated schema:
  -- effective invocation must stay FALSE until a governed schema grant exists.
  IF has_schema_privilege('ig_n4_untrusted_acl_probe','programacion','USAGE')
     AND has_function_privilege('ig_n4_untrusted_acl_probe',v_proc,'EXECUTE')
  THEN RAISE EXCEPTION 'FAIL_ACL_UNTRUSTED_EFFECTIVE_ACCESS:%',v_sig; END IF;
  IF NOT (has_schema_privilege('ig_n4_governed_acl_probe','programacion','USAGE')
     AND has_function_privilege('ig_n4_governed_acl_probe',v_proc,'EXECUTE'))
  THEN RAISE EXCEPTION 'FAIL_ACL_GOVERNED_CANNOT_EXECUTE:%',v_sig; END IF;
 END LOOP;
END
$assert_acl$;
SELECT 'ACL_G3_POST_DDL|PASS';
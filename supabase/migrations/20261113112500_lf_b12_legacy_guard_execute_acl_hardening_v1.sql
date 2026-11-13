-- LF B12/G08 governed, single migration. Source of four frozen MD5/ACL:
-- audits/rule-quality-lote28/b12/01_preimagen_S21_04_live_20261113.json
-- Exact live as_of 2026-11-13T08:21:46.706817Z. No source function body changes.
-- One change only: remove trigger-function EXECUTE grants from PUBLIC/anon/authenticated.
BEGIN;
DO $b12_preflight$
DECLARE v record; f pg_proc%ROWTYPE; v_oid oid;
BEGIN
  FOR v IN
    SELECT * FROM (VALUES
  ('public.lf_rule_promotion_apply_batch_v1(text[])', 'lf_rule_promotion_apply_batch_v1', '4e98f486f5ff65b596e5999f22cc8dde', '{postgres=X/postgres,service_role=X/postgres}', 'p_ids text[]', 'jsonb', false, false),
  ('public.lf_rule_promotion_decide_batch_v1(text[],text,text,text)', 'lf_rule_promotion_decide_batch_v1', '6cdf2aa9a03c6abc7315b7ebc9d2f3ce', '{postgres=X/postgres,service_role=X/postgres}', 'p_ids text[], p_decision text, p_decided_by text, p_note text', 'jsonb', false, false),
  ('public.lf_rule_promotion_guard_v1()', 'lf_rule_promotion_guard_v1', 'ee782e4bd0128c80ee13881899c0d74e', '{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}', '', 'trigger', true, true),
  ('public.lf_rule_promotion_report_v1(integer,integer)', 'lf_rule_promotion_report_v1', 'e3e521aaa933604de88d697196f54564', '{postgres=X/postgres,service_role=X/postgres}', 'p_page integer, p_size integer', 'jsonb', false, false)
    ) AS src(signature,name,expected_md5,expected_acl,expected_args,expected_result,anon_expected,auth_expected)
  LOOP
    v_oid:=to_regprocedure(v.signature);
    IF v_oid IS NULL THEN RAISE EXCEPTION 'B12_G08_REQUIRED_FUNCTION_MISSING:%',v.name; END IF;
    SELECT * INTO f FROM pg_proc WHERE oid=v_oid;
    IF md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM v.expected_md5
    THEN RAISE EXCEPTION 'B12_G08_PREIMAGE_MD5_DRIFT:%',v.name; END IF;
    IF f.prosecdef IS DISTINCT FROM true OR f.provolatile IS DISTINCT FROM 'v'
      OR f.proparallel IS DISTINCT FROM 'u' OR f.proisstrict IS DISTINCT FROM false
      OR f.proleakproof IS DISTINCT FROM false OR f.proretset IS DISTINCT FROM false
      OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, extensions']::text[]
      OR pg_get_userbyid(f.proowner) IS DISTINCT FROM 'postgres'
      OR pg_get_function_identity_arguments(v_oid) IS DISTINCT FROM v.expected_args
      OR pg_get_function_result(v_oid) IS DISTINCT FROM v.expected_result
    THEN RAISE EXCEPTION 'B12_G08_PREIMAGE_ATTRIBUTES_DRIFT:%',v.name; END IF;
    IF f.proacl::text IS DISTINCT FROM v.expected_acl
      OR has_function_privilege('anon',v_oid,'EXECUTE') IS DISTINCT FROM v.anon_expected
      OR has_function_privilege('authenticated',v_oid,'EXECUTE') IS DISTINCT FROM v.auth_expected
      OR has_function_privilege('service_role',v_oid,'EXECUTE') IS DISTINCT FROM true
    THEN RAISE EXCEPTION 'B12_G08_PREIMAGE_ACL_DRIFT:%',v.name; END IF;
  END LOOP;
END $b12_preflight$;

REVOKE EXECUTE ON FUNCTION public.lf_rule_promotion_guard_v1()
FROM PUBLIC, anon, authenticated;

DO $b12_postflight$
DECLARE v record; v_oid oid;
BEGIN
  FOR v IN SELECT * FROM (VALUES
    ('public.lf_rule_promotion_apply_batch_v1(text[])','lf_rule_promotion_apply_batch_v1','4e98f486f5ff65b596e5999f22cc8dde'),
    ('public.lf_rule_promotion_decide_batch_v1(text[],text,text,text)','lf_rule_promotion_decide_batch_v1','6cdf2aa9a03c6abc7315b7ebc9d2f3ce'),
    ('public.lf_rule_promotion_guard_v1()','lf_rule_promotion_guard_v1','ee782e4bd0128c80ee13881899c0d74e'),
    ('public.lf_rule_promotion_report_v1(integer,integer)','lf_rule_promotion_report_v1','e3e521aaa933604de88d697196f54564')
  ) AS src(signature,name,expected_md5)
  LOOP
    v_oid:=to_regprocedure(v.signature);
    IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM v.expected_md5
    THEN RAISE EXCEPTION 'B12_G08_POSTFLIGHT_MD5_DRIFT:%',v.name; END IF;
  END LOOP;
  v_oid:=to_regprocedure('public.lf_rule_promotion_guard_v1()');
  IF has_function_privilege('anon',v_oid,'EXECUTE')
     OR has_function_privilege('authenticated',v_oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',v_oid,'EXECUTE')
     OR (SELECT proacl::text FROM pg_proc WHERE oid=v_oid) IS DISTINCT FROM
        '{postgres=X/postgres,service_role=X/postgres}'
  THEN RAISE EXCEPTION 'B12_G08_POSTFLIGHT_EXECUTE_ACL_INVALID'; END IF;
END $b12_postflight$;
COMMIT;

-- Prototype of a TECHNICAL_ASSET definition provider (FUNCTION kind only).
-- Test-only: every object lives in a schema created inside this transaction and the
-- script ends with ROLLBACK. Not a migration, not an admitted provider, no hosted effect.
--
--   psql -X -v ON_ERROR_STOP=1 -f test_technical_definition_provider_prototype_v1.sql
--
-- Contract: technical_definition_contract_v1.json (SOURCE_ONLY_CANDIDATE).

\set ON_ERROR_STOP 1
BEGIN;
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $r$;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA tdp;

-- Observed state of one function: exact identity, body, attributes and normalized ACL.
CREATE FUNCTION tdp.observe_v1(p_ref text, p_project text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO pg_catalog AS $f$
DECLARE m text[]; v_oid oid; f pg_proc%rowtype; v_canon text; v_acl jsonb; v_attrs jsonb;
BEGIN
  m := regexp_match(p_ref, '^lf-technical-definition://([a-z0-9]+)/([A-Z_]+)/(.+)$');
  IF m IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','DEFINITION_REF_SCHEME_UNSUPPORTED'); END IF;
  IF m[1] IS DISTINCT FROM p_project THEN RETURN jsonb_build_object('ok',false,'reason','PROJECT_MISMATCH'); END IF;
  IF m[2] IS DISTINCT FROM 'FUNCTION' THEN RETURN jsonb_build_object('ok',false,'reason','KIND_UNSUPPORTED'); END IF;
  IF position('(' in m[3]) = 0 THEN RETURN jsonb_build_object('ok',false,'reason','IDENTITY_SIGNATURE_REQUIRED'); END IF;
  BEGIN
    v_oid := to_regprocedure(m[3]);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok',false,'reason','IDENTITY_SIGNATURE_INVALID');
  END;
  IF v_oid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','DEFINITION_NOT_FOUND'); END IF;
  SELECT * INTO f FROM pg_proc WHERE oid = v_oid;
  v_canon := format('%I.%I(%s)', (SELECT nspname FROM pg_namespace WHERE oid=f.pronamespace), f.proname,
                    oidvectortypes(f.proargtypes));
  IF v_canon IS DISTINCT FROM m[3] THEN
    RETURN jsonb_build_object('ok',false,'reason','SIGNATURE_NOT_CANONICAL','canonical_identity',v_canon);
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('grantee',g,'privilege',p,'grantable',w) ORDER BY g,p),'[]'::jsonb) INTO v_acl
  FROM (SELECT CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END g, a.privilege_type p, a.is_grantable w
        FROM aclexplode(coalesce(f.proacl, acldefault('f', f.proowner))) a) x;
  v_attrs := jsonb_build_object('owner',pg_get_userbyid(f.proowner),
    'language',(SELECT lanname FROM pg_language WHERE oid=f.prolang),
    'security_definer',f.prosecdef,'volatility',f.provolatile::text,
    'config',coalesce(to_jsonb(f.proconfig),'[]'::jsonb),'returns',pg_get_function_result(v_oid));
  RETURN jsonb_build_object('ok',true,'definition_ref',p_ref,'kind','FUNCTION','identity',v_canon,
    'body_sha256',encode(extensions.digest(convert_to(f.prosrc,'UTF8'),'sha256'),'hex'),
    'attrs_sha256',encode(extensions.digest(convert_to(v_attrs::text,'UTF8'),'sha256'),'hex'),
    'acl',v_acl,'acl_sha256',encode(extensions.digest(convert_to(v_acl::text,'UTF8'),'sha256'),'hex'));
END $f$;

-- Currentness: the pinned observation must still hold.
CREATE FUNCTION tdp.currentness_v1(p_pin jsonb, p_project text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO pg_catalog, tdp AS $f$
DECLARE o jsonb;
BEGIN
  IF jsonb_typeof(p_pin->'source') IS DISTINCT FROM 'object'
     OR coalesce(p_pin#>>'{source,repo}','') = ''
     OR coalesce(p_pin#>>'{source,commit}','') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_pin#>>'{source,path}','') !~ '^supabase/migrations/[0-9]{14}_[a-z0-9_]+\.sql$'
     OR coalesce(p_pin#>>'{source,blob_sha1}','') !~ '^[0-9a-f]{40}$' THEN
    RETURN jsonb_build_object('current',false,'reason','SOURCE_PIN_MISSING');
  END IF;
  o := tdp.observe_v1(p_pin->>'definition_ref', p_project);
  IF (o->>'ok')::boolean IS DISTINCT FROM true THEN RETURN jsonb_build_object('current',false,'reason',o->>'reason'); END IF;
  IF o->>'body_sha256' IS DISTINCT FROM p_pin->>'body_sha256' THEN RETURN jsonb_build_object('current',false,'reason','DEFINITION_CHANGED_BODY'); END IF;
  IF o->>'attrs_sha256' IS DISTINCT FROM p_pin->>'attrs_sha256' THEN RETURN jsonb_build_object('current',false,'reason','DEFINITION_CHANGED_ATTRS'); END IF;
  IF o->>'acl_sha256' IS DISTINCT FROM p_pin->>'acl_sha256' THEN RETURN jsonb_build_object('current',false,'reason','DEFINITION_CHANGED_ACL'); END IF;
  RETURN jsonb_build_object('current',true,'reason','DEFINITION_CURRENT');
END $f$;

-- Delta scope: a repair may only touch the refs it declares, and only in declared dimensions.
CREATE FUNCTION tdp.delta_scope_v1(p_def jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE c jsonb; v jsonb;
BEGIN
  IF jsonb_typeof(p_def) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok',false,'reason','DELTA_INVALID');
  END IF;
  -- Separate structural validation from membership predicates: SQL NULL must
  -- never turn a missing field into a successful scope check.
  IF jsonb_typeof(p_def->'changes') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_def->'allowed_refs') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_def->'allowed_dimensions') IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('ok',false,'reason','DELTA_INVALID');
  END IF;
  IF jsonb_array_length(p_def->'changes') = 0 THEN
    RETURN jsonb_build_object('ok',false,'reason','DELTA_EMPTY');
  END IF;
  IF jsonb_array_length(p_def->'allowed_refs') = 0
     OR jsonb_array_length(p_def->'allowed_dimensions') = 0 THEN
    RETURN jsonb_build_object('ok',false,'reason','DELTA_INVALID');
  END IF;
  FOR v IN SELECT value FROM jsonb_array_elements(p_def->'allowed_refs') LOOP
    IF jsonb_typeof(v) IS DISTINCT FROM 'string' OR nullif(btrim(v#>>'{}'),'') IS NULL THEN
      RETURN jsonb_build_object('ok',false,'reason','DELTA_INVALID');
    END IF;
  END LOOP;
  FOR v IN SELECT value FROM jsonb_array_elements(p_def->'allowed_dimensions') LOOP
    IF jsonb_typeof(v) IS DISTINCT FROM 'string' OR (v#>>'{}') NOT IN ('ACL','BODY','ATTRS') THEN
      RETURN jsonb_build_object('ok',false,'reason','DELTA_INVALID');
    END IF;
  END LOOP;
  FOR c IN SELECT value FROM jsonb_array_elements(p_def->'changes') LOOP
    IF jsonb_typeof(c) IS DISTINCT FROM 'object'
       OR jsonb_typeof(c->'definition_ref') IS DISTINCT FROM 'string'
       OR nullif(btrim(c->>'definition_ref'),'') IS NULL
       OR jsonb_typeof(c->'dimension') IS DISTINCT FROM 'string'
       OR (c->>'dimension') NOT IN ('ACL','BODY','ATTRS') THEN
      RETURN jsonb_build_object('ok',false,'reason','DELTA_INVALID');
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_def->'changes') x
             WHERE NOT (p_def->'allowed_refs') ? (x->>'definition_ref')) THEN
    RETURN jsonb_build_object('ok',false,'reason','SCOPE_OUT_OF_BOUNDS');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_def->'changes') x
             WHERE NOT (p_def->'allowed_dimensions') ? (x->>'dimension')) THEN
    RETURN jsonb_build_object('ok',false,'reason','DIMENSION_OUT_OF_BOUNDS');
  END IF;
  RETURN jsonb_build_object('ok',true,'reason','DELTA_IN_SCOPE');
END $f$;

-- Success criterion: the observed ACL equals the declared target ACL.
CREATE FUNCTION tdp.delta_satisfied_v1(p_ref text, p_project text, p_target_acl jsonb) RETURNS boolean
LANGUAGE sql STABLE AS $f$ SELECT tdp.observe_v1(p_ref, p_project)->'acl' = p_target_acl $f$;

-- Fixtures: the subject plus an overload with the same name.
CREATE FUNCTION public.fn_demo_writer_v1(p jsonb, a text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
  SET search_path TO pg_catalog, public AS $$ SELECT p $$;
CREATE FUNCTION public.fn_demo_writer_v1(p text) RETURNS text LANGUAGE sql AS $$ SELECT upper(p) $$;
GRANT EXECUTE ON FUNCTION public.fn_demo_writer_v1(jsonb,text) TO anon, authenticated, service_role;

CREATE TEMP TABLE r(case_id text PRIMARY KEY, passed boolean NOT NULL, detail text);
\set prj 'lfproj'
\set ref 'lf-technical-definition://lfproj/FUNCTION/public.fn_demo_writer_v1(jsonb, text)'
\set ref_short 'lf-technical-definition://lfproj/FUNCTION/public.fn_demo_writer_v1(jsonb,text)'

SELECT tdp.observe_v1(:'ref', :'prj') AS obs \gset
SELECT jsonb_build_object('definition_ref', :'ref',
  'body_sha256', (:'obs'::jsonb)->>'body_sha256', 'attrs_sha256', (:'obs'::jsonb)->>'attrs_sha256',
  'acl_sha256', (:'obs'::jsonb)->>'acl_sha256',
  'source', jsonb_build_object('repo','cristhianlujan/claude-persona-lf-patch',
     'commit','94674fd745bc05f4e401505acd5a8ad554b75317',
     'path','supabase/migrations/20261004144500_t_decctx_decision_context_asof_v1.sql',
     'blob_sha1','0000000000000000000000000000000000000000')) AS pin \gset

-- Identity
INSERT INTO r SELECT 'T01_OBSERVE_EXACT_IDENTITY', (:'obs'::jsonb->>'ok')::boolean, :'obs'::jsonb->>'identity';
INSERT INTO r SELECT 'T02_NON_CANONICAL_SPELLING_REJECTED', o->>'reason'='SIGNATURE_NOT_CANONICAL', o->>'reason' FROM tdp.observe_v1(:'ref_short', :'prj') o;
INSERT INTO r SELECT 'T03_WRONG_OVERLOAD_NOT_SUBJECT', o->>'identity' IS DISTINCT FROM :'obs'::jsonb->>'identity' AND o->>'body_sha256' IS DISTINCT FROM :'obs'::jsonb->>'body_sha256', o->>'identity'
  FROM tdp.observe_v1('lf-technical-definition://lfproj/FUNCTION/public.fn_demo_writer_v1(text)', :'prj') o;
INSERT INTO r SELECT 'T04_MISSING_SIGNATURE_NOT_FOUND', o->>'reason'='DEFINITION_NOT_FOUND', o->>'reason' FROM tdp.observe_v1('lf-technical-definition://lfproj/FUNCTION/public.fn_demo_writer_v1(integer)', :'prj') o;
INSERT INTO r SELECT 'T05_NAME_WITHOUT_SIGNATURE_REJECTED', o->>'reason'='IDENTITY_SIGNATURE_REQUIRED', o->>'reason' FROM tdp.observe_v1('lf-technical-definition://lfproj/FUNCTION/public.fn_demo_writer_v1', :'prj') o;
INSERT INTO r SELECT 'T06_SCREEN_REF_IS_NOT_TECHNICAL', o->>'reason'='DEFINITION_REF_SCHEME_UNSUPPORTED', o->>'reason' FROM tdp.observe_v1('lf-screen-contract://B2B/AUTH/B2B-AUTH-001', :'prj') o;
INSERT INTO r SELECT 'T07_KIND_NOT_SUPPORTED', o->>'reason'='KIND_UNSUPPORTED', o->>'reason' FROM tdp.observe_v1('lf-technical-definition://lfproj/TABLE/public.t', :'prj') o;
INSERT INTO r SELECT 'T08_OTHER_PROJECT_REJECTED', o->>'reason'='PROJECT_MISMATCH', o->>'reason' FROM tdp.observe_v1(replace(:'ref','lfproj','otherproj'), :'prj') o;

-- Currentness
INSERT INTO r SELECT 'T09_PIN_CURRENT', (c->>'current')::boolean, c->>'reason' FROM tdp.currentness_v1(:'pin'::jsonb, :'prj') c;
INSERT INTO r SELECT 'T10_SOURCE_PIN_MISSING', c->>'reason'='SOURCE_PIN_MISSING', c->>'reason' FROM tdp.currentness_v1(:'pin'::jsonb - 'source', :'prj') c;
SAVEPOINT s_acl;
REVOKE EXECUTE ON FUNCTION public.fn_demo_writer_v1(jsonb,text) FROM anon;
SELECT tdp.currentness_v1(:'pin'::jsonb, :'prj')->>'reason' AS t11 \gset
ROLLBACK TO SAVEPOINT s_acl;
INSERT INTO r SELECT 'T11_ACL_DRIFT_DETECTED', :'t11'='DEFINITION_CHANGED_ACL', :'t11';
SAVEPOINT s_body;
CREATE OR REPLACE FUNCTION public.fn_demo_writer_v1(p jsonb, a text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
  SET search_path TO pg_catalog, public AS $$ SELECT p || '{}'::jsonb $$;
SELECT tdp.currentness_v1(:'pin'::jsonb, :'prj')->>'reason' AS t12 \gset
ROLLBACK TO SAVEPOINT s_body;
INSERT INTO r SELECT 'T12_BODY_DRIFT_DETECTED', :'t12'='DEFINITION_CHANGED_BODY', :'t12';
SAVEPOINT s_attrs;
ALTER FUNCTION public.fn_demo_writer_v1(jsonb,text) SECURITY INVOKER;
SELECT tdp.currentness_v1(:'pin'::jsonb, :'prj')->>'reason' AS t13 \gset
ROLLBACK TO SAVEPOINT s_attrs;
INSERT INTO r SELECT 'T13_ATTRS_DRIFT_DETECTED', :'t13'='DEFINITION_CHANGED_ATTRS', :'t13';
SAVEPOINT s_drop;
DROP FUNCTION public.fn_demo_writer_v1(jsonb,text);
SELECT tdp.currentness_v1(:'pin'::jsonb, :'prj')->>'reason' AS t14 \gset
ROLLBACK TO SAVEPOINT s_drop;
INSERT INTO r SELECT 'T14_DROPPED_SUBJECT_NOT_FOUND', :'t14'='DEFINITION_NOT_FOUND', :'t14';

-- Delta scope and success criterion
INSERT INTO r SELECT 'T15_DELTA_IN_SCOPE', d->>'reason'='DELTA_IN_SCOPE', d->>'reason' FROM tdp.delta_scope_v1(jsonb_build_object(
  'allowed_refs', jsonb_build_array(:'ref'), 'allowed_dimensions', '["ACL"]'::jsonb,
  'changes', jsonb_build_array(jsonb_build_object('definition_ref',:'ref','dimension','ACL')))) d;
INSERT INTO r SELECT 'T16_FOREIGN_SCOPE_REJECTED', d->>'reason'='SCOPE_OUT_OF_BOUNDS', d->>'reason' FROM tdp.delta_scope_v1(jsonb_build_object(
  'allowed_refs', jsonb_build_array(:'ref'), 'allowed_dimensions', '["ACL"]'::jsonb,
  'changes', jsonb_build_array(jsonb_build_object('definition_ref','lf-technical-definition://lfproj/FUNCTION/public.other_v1()','dimension','ACL')))) d;
INSERT INTO r SELECT 'T17_BODY_CHANGE_IN_ACL_ONLY_REPAIR_REJECTED', d->>'reason'='DIMENSION_OUT_OF_BOUNDS', d->>'reason' FROM tdp.delta_scope_v1(jsonb_build_object(
  'allowed_refs', jsonb_build_array(:'ref'), 'allowed_dimensions', '["ACL"]'::jsonb,
  'changes', jsonb_build_array(jsonb_build_object('definition_ref',:'ref','dimension','BODY')))) d;
\set target_acl '[{"grantee":"postgres","privilege":"EXECUTE","grantable":false},{"grantee":"service_role","privilege":"EXECUTE","grantable":false}]'
INSERT INTO r SELECT 'T18_TARGET_NOT_YET_SATISFIED', NOT tdp.delta_satisfied_v1(:'ref', :'prj', :'target_acl'::jsonb), NULL;
REVOKE ALL ON FUNCTION public.fn_demo_writer_v1(jsonb,text) FROM PUBLIC, anon, authenticated;
INSERT INTO r SELECT 'T19_TARGET_SATISFIED_AFTER_DELTA', tdp.delta_satisfied_v1(:'ref', :'prj', :'target_acl'::jsonb), (tdp.observe_v1(:'ref', :'prj')->'acl')::text;
INSERT INTO r SELECT 'T20_BODY_UNCHANGED_BY_ACL_DELTA', tdp.observe_v1(:'ref', :'prj')->>'body_sha256' = :'obs'::jsonb->>'body_sha256', NULL;

-- Malformed deltas must be rejected before any membership checks.
INSERT INTO r
SELECT t.case_id, d->'ok' IS NOT DISTINCT FROM 'false'::jsonb
  AND d->>'reason' IS NOT DISTINCT FROM t.expected, d::text
FROM (VALUES
 ('T21_SQL_NULL',NULL::jsonb,'DELTA_INVALID'),
 ('T22_JSON_NULL','null'::jsonb,'DELTA_INVALID'),
 ('T23_ROOT_ARRAY','[]'::jsonb,'DELTA_INVALID'),
 ('T24_ROOT_STRING','"x"'::jsonb,'DELTA_INVALID'),
 ('T25_CHANGES_MISSING','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"]}'::jsonb,'DELTA_INVALID'),
 ('T26_CHANGES_NULL','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": null}'::jsonb,'DELTA_INVALID'),
 ('T27_CHANGES_OBJECT','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": {}}'::jsonb,'DELTA_INVALID'),
 ('T28_CHANGES_STRING','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": "ACL"}'::jsonb,'DELTA_INVALID'),
 ('T29_CHANGES_NUMBER','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": 1}'::jsonb,'DELTA_INVALID'),
 ('T30_CHANGES_EMPTY','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": []}'::jsonb,'DELTA_EMPTY'),
 ('T31_ALLOWED_REFS_MISSING','{"allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T32_ALLOWED_REFS_NULL','{"allowed_refs": null, "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T33_ALLOWED_REFS_OBJECT','{"allowed_refs": {}, "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T34_ALLOWED_REFS_STRING','{"allowed_refs": "ACL", "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T35_ALLOWED_REFS_NUMBER','{"allowed_refs": 1, "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T36_ALLOWED_REFS_EMPTY','{"allowed_refs": [], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T37_ALLOWED_DIMENSIONS_MISSING','{"allowed_refs": ["EXPECTED"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T38_ALLOWED_DIMENSIONS_NULL','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": null, "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T39_ALLOWED_DIMENSIONS_OBJECT','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": {}, "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T40_ALLOWED_DIMENSIONS_STRING','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": "ACL", "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T41_ALLOWED_DIMENSIONS_NUMBER','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": 1, "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T42_ALLOWED_DIMENSIONS_EMPTY','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": [], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T43_CHANGE_ITEM_NULL','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [null]}'::jsonb,'DELTA_INVALID'),
 ('T44_CHANGE_ITEM_ARRAY','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [[]]}'::jsonb,'DELTA_INVALID'),
 ('T45_CHANGE_ITEM_STRING','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": ["ACL"]}'::jsonb,'DELTA_INVALID'),
 ('T46_CHANGE_ITEM_NUMBER','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [1]}'::jsonb,'DELTA_INVALID'),
 ('T47_CHANGE_ITEM_OBJECT','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{}]}'::jsonb,'DELTA_INVALID'),
 ('T48_CHANGE_DEFINITION_REF_MISSING','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T49_CHANGE_DEFINITION_REF_NULL','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": null, "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T50_CHANGE_DEFINITION_REF_NUMBER','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": 1, "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T51_CHANGE_DEFINITION_REF_BLANK','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": " ", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T52_CHANGE_DIMENSION_MISSING','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED"}]}'::jsonb,'DELTA_INVALID'),
 ('T53_CHANGE_DIMENSION_NULL','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": null}]}'::jsonb,'DELTA_INVALID'),
 ('T54_CHANGE_DIMENSION_NUMBER','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": 1}]}'::jsonb,'DELTA_INVALID'),
 ('T55_CHANGE_DIMENSION_BLANK','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": " "}]}'::jsonb,'DELTA_INVALID'),
 ('T56_ALLOWED_REFS_NULL_ITEM','{"allowed_refs": [null], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T57_ALLOWED_REFS_NUMBER_ITEM','{"allowed_refs": [1], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T58_ALLOWED_REFS_BLANK_ITEM','{"allowed_refs": [" "], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T59_ALLOWED_DIMENSIONS_NULL_ITEM','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": [null], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T60_ALLOWED_DIMENSIONS_NUMBER_ITEM','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": [1], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T61_ALLOWED_DIMENSIONS_BLANK_ITEM','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": [" "], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T62_UNKNOWN_ALLOWED_DIMENSION','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["DROP"], "changes": [{"definition_ref": "EXPECTED", "dimension": "ACL"}]}'::jsonb,'DELTA_INVALID'),
 ('T63_UNKNOWN_CHANGE_DIMENSION','{"allowed_refs": ["EXPECTED"], "allowed_dimensions": ["ACL"], "changes": [{"definition_ref": "EXPECTED", "dimension": "DROP"}]}'::jsonb,'DELTA_INVALID')
) t(case_id,payload,expected) CROSS JOIN LATERAL tdp.delta_scope_v1(t.payload) d;

SELECT case_id, passed, detail FROM r ORDER BY case_id;
DO $f$ DECLARE n int; t int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT passed), count(*) INTO n, t FROM r;
  IF t <> 63 OR n <> 0 THEN RAISE EXCEPTION 'TECHNICAL_DEFINITION_PROVIDER_PROTOTYPE_FAILED failed=% total=%', n, t; END IF;
  RAISE NOTICE 'TECHNICAL_DEFINITION_PROVIDER_PROTOTYPE_PASS %/%', t, t;
END $f$;
ROLLBACK;

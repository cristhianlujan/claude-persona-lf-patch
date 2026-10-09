-- IG package 2b: contract obligation trace v2 - explicit links to the existing assurance catalog.
-- Read-only. Replaces the name-mention case link with the links that already exist in the system:
--   public.lf_assurance_obligation_catalog (latest version per obligation_code; clause_key + contract_id)
--   lf_test_suite_cases.input_payload->>'obligation_code' (carried by the 91 contract negative cases)
-- No parallel scheme is introduced. Obligations of the contracts not yet in the catalog are reported as
-- NOT_IN_CATALOG (measured gap), not invented.
-- case_link_basis: CATALOG_EXPLICIT (clause in catalog and >=1 case carries its obligation_code)
--   CATALOG_NO_CASE (clause in catalog, no case carries the code) | NOT_IN_CATALOG (+ weak name mention in
--   case_codes only if a case names the leaf: NAME_MENTION_WEAK) | LEAF_TOO_GENERIC.
DROP FUNCTION IF EXISTS programacion.fn_input_contract_obligation_trace_v1();
CREATE FUNCTION programacion.fn_input_contract_obligation_trace_v1()
 RETURNS TABLE(contract_id bigint, contract_code text, obligation_key text, obligation_class text,
               validator_kind text, validator_ref text, static_status text, static_detail text,
               case_codes text[], case_link_basis text,
               catalog_obligation_code text, catalog_status text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $fn$
WITH cur AS (
  SELECT DISTINCT ON (c.contrato_codigo) c.id, c.contrato_codigo, c.especificacion
  FROM programacion.contratos c
  WHERE c.estado='defined' AND c.contrato_codigo IN (
    'INPUT_READINESS_CONTRACT','INPUT_CONTEXT_MANIFEST_CONTRACT','INPUT_FRESHNESS_DELTA_CONTRACT',
    'INPUT_RETRIEVAL_HANDLE_CONTRACT','INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT',
    'INPUT_GOVERNANCE_EXECUTION_CONTRACT','INPUT_EXPLAIN_FAMILY_ASSESSMENT_CONTRACT')
  ORDER BY c.contrato_codigo, c.id DESC
), top AS (
  SELECT cur.id, cur.contrato_codigo, k.key, k.value v
  FROM cur, jsonb_each(cur.especificacion) k
  WHERE k.key NOT IN ('revision_lineage','audit_remediation','family_stage_requirements',
        'negative_tests','contract_revision','schema_version','consumer','remediation_revision')
), atoms AS (
  SELECT t.id, t.contrato_codigo, t.key||'.'||c.key akey, c.key leaf, c.value v
  FROM top t, jsonb_each(CASE WHEN jsonb_typeof(t.v)='object' THEN t.v ELSE '{}'::jsonb END) c
  UNION ALL
  SELECT t.id, t.contrato_codigo, t.key, t.key, t.v FROM top t WHERE jsonb_typeof(t.v)<>'object'
), cl AS (
  SELECT a.*,
   CASE
    WHEN jsonb_typeof(v)='boolean' AND v::text='false' THEN 'A'
    WHEN jsonb_typeof(v)='string' AND v::text ~ '"(DENY|NONE|BLOCK|REJECT)' THEN 'A'
    WHEN jsonb_typeof(v)='boolean' THEN 'B'
    WHEN jsonb_typeof(v)='array' AND akey ~ 'required_fields|required_keys' THEN 'D'
    WHEN jsonb_typeof(v)='array' THEN 'C'
    WHEN jsonb_typeof(v)='string' AND v::text ~ 'programacion\.|lf_ops\.|lf_design\.|SUPABASE_EDGE' THEN 'E'
    WHEN jsonb_typeof(v)='string' AND v::text ~ 'DEC-' THEN 'F'
    WHEN jsonb_typeof(v)='string' AND v::text = '"PASS"' THEN 'G'
    WHEN jsonb_typeof(v)='string' AND akey ~ '(^|\.)(scope|human_owner|checkpoint_owner|followup_implementation_checkpoint|implementation_state|type|run_id|family_code|consumer_interface|operation|logical_field|source|metadata)$' THEN 'I'
    WHEN jsonb_typeof(v)='string' AND (v::text ~ '_V[0-9]' OR akey ~ '(_contract|handle_kind|binding_graph|schema_version)$') THEN 'H'
    WHEN jsonb_typeof(v)='string' THEN 'J'
    WHEN jsonb_typeof(v)='object' THEN 'K'
    ELSE 'L' END cls
  FROM atoms a
), fs AS (
  SELECT string_agg(p.prosrc,' ') s FROM pg_proc p
  WHERE p.pronamespace IN ('programacion'::regnamespace,'public'::regnamespace)
), chk AS (
  SELECT coalesce(string_agg(pg_get_constraintdef(oid),' '),'') s FROM pg_constraint WHERE contype='c'
), cases AS (
  SELECT c.test_code,
         lower(c.test_code||' '||coalesce(c.title,'')||' '||coalesce(c.input_payload::text,'')||' '||
               coalesce(c.expected_output::text,'')||' '||coalesce(c.metadata::text,'')) txt
  FROM public.lf_test_suite_cases c JOIN public.lf_test_suites s ON s.suite_code=c.suite_code
  WHERE s.module_code='INPUT_GOVERNANCE'
), catl AS (
  SELECT DISTINCT ON (o.obligation_code) o.obligation_code, o.status,
         (o.evidence_contract->>'contract_id')::bigint cid, o.evidence_contract->>'clause_key' ck
  FROM public.lf_assurance_obligation_catalog o
  WHERE o.obligation_code LIKE 'IG-%'
  ORDER BY o.obligation_code, o.version DESC
), cc AS (
  SELECT k.input_payload->>'obligation_code' oc, k.test_code
  FROM public.lf_test_suite_cases k JOIN public.lf_test_suites s ON s.suite_code=k.suite_code
  WHERE s.module_code='INPUT_GOVERNANCE' AND k.input_payload ? 'obligation_code'
), ev AS (
  SELECT cl.*,
   CASE WHEN cls='E' THEN
     CASE WHEN v::text ~ 'SUPABASE_EDGE' THEN ARRAY['NOT_CHECKABLE_FROM_DB','edge function runtime is outside the database']
     ELSE (SELECT CASE WHEN count(*)=0 THEN ARRAY['NOT_CHECKABLE_FROM_DB','no schema-qualified object in text']
                       WHEN bool_and(ok) THEN ARRAY['PASS',count(*)||' object(s) resolved']
                       ELSE ARRAY['FAIL',string_agg(CASE WHEN NOT ok THEN ref END,',')||' not found'] END
           FROM (SELECT m[1]||'.'||m[2]||coalesce(m[3],'') ref,
                   CASE WHEN m[3] IS NOT NULL THEN to_regprocedure(m[1]||'.'||m[2]||m[3]) IS NOT NULL
                        ELSE to_regclass(m[1]||'.'||m[2]) IS NOT NULL
                          OR EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace=m[1]::regnamespace AND p.proname=m[2]) END ok
                 FROM regexp_matches(v #>> '{}','(programacion|lf_ops|lf_design)\.([a-z_0-9]+)(\([^)]*\))?','g') m
                 WHERE to_regnamespace(m[1]) IS NOT NULL) r) END
   WHEN cls='F' THEN
     (SELECT CASE WHEN count(*)=0 THEN ARRAY['NOT_CHECKABLE_FROM_DB','no DEC code in text']
                  WHEN bool_and(ok) THEN ARRAY['PASS',count(*)||' decision(s) in lf_decision_log']
                  ELSE ARRAY['FAIL',string_agg(CASE WHEN NOT ok THEN d END,',')||' not in lf_decision_log'] END
      FROM (SELECT m[1] d, EXISTS(SELECT 1 FROM public.lf_decision_log l WHERE l.adr=m[1]) ok
            FROM regexp_matches(v #>> '{}','(DEC-[A-Z0-9.-]*[A-Z0-9])','g') m) r)
   WHEN cls='H' THEN
     (SELECT CASE WHEN position(v #>> '{}' IN (SELECT s FROM fs))>0
                    OR EXISTS(SELECT 1 FROM programacion.contratos c2 WHERE c2.estado='defined' AND c2.id<>cl.id AND position(v #>> '{}' IN c2.especificacion::text)>0)
                  THEN ARRAY['TRACED','identity string found in live function source or another contract']
                  ELSE ARRAY['UNTRACED','identity string found in no live function source and no other contract'] END)
   WHEN cls='C' THEN
     (SELECT CASE WHEN count(*)=0 THEN ARRAY['NEEDS_CASE','list has no string elements']
                  WHEN bool_and(t) THEN ARRAY['TRACED',count(*)||'/'||count(*)||' elements found']
                  WHEN bool_or(t) THEN ARRAY['PARTIAL',count(*) filter (WHERE t)||'/'||count(*)||' elements found']
                  ELSE ARRAY['UNTRACED','0/'||count(*)||' elements found'] END
      FROM (SELECT position(e.value #>> '{}' IN (SELECT s FROM fs))>0
                   OR position(e.value #>> '{}' IN (SELECT s FROM chk))>0 t
            FROM jsonb_array_elements(v) e WHERE jsonb_typeof(e.value)='string') z)
   WHEN cls IN ('A','B','G','J','D') THEN ARRAY['NEEDS_CASE','only a real case against the live function can verify it']
   WHEN cls='I' THEN ARRAY['NA','descriptive']
   ELSE ARRAY['OPEN','needs owner classification'] END st
  FROM cl
)
SELECT ev.id, ev.contrato_codigo, ev.akey, ev.cls,
  CASE ev.cls WHEN 'A' THEN 'LF_TEST_CASE_NEGATIVE' WHEN 'B' THEN 'LF_TEST_CASE_POSITIVE'
    WHEN 'J' THEN 'LF_TEST_CASE' WHEN 'G' THEN 'LF_TEST_RUN'
    WHEN 'D' THEN 'LF_TEST_CASE' WHEN 'C' THEN 'CONTRACT_TRACE'
    WHEN 'E' THEN 'CONTRACT_TRACE' WHEN 'F' THEN 'CONTRACT_TRACE' WHEN 'H' THEN 'CONTRACT_TRACE'
    WHEN 'I' THEN 'NONE' ELSE 'OWNER_CLASSIFICATION' END,
  'programacion.fn_input_contract_obligation_trace_v1',
  ev.st[1], ev.st[2],
  CASE WHEN EXISTS(SELECT 1 FROM catl WHERE catl.cid=ev.id AND catl.ck=split_part(ev.akey,'.',1)) THEN
    coalesce((SELECT array_agg(DISTINCT cc.test_code ORDER BY cc.test_code) FROM catl JOIN cc ON cc.oc=catl.obligation_code
              WHERE catl.cid=ev.id AND catl.ck=split_part(ev.akey,'.',1)),'{}'::text[])
  WHEN length(ev.leaf)>=10 AND ev.leaf LIKE '%\_%' THEN
    coalesce((SELECT array_agg(c.test_code ORDER BY c.test_code) FROM cases c WHERE c.txt LIKE '%'||lower(ev.leaf)||'%'),'{}'::text[])
  ELSE '{}'::text[] END,
  CASE WHEN EXISTS(SELECT 1 FROM catl WHERE catl.cid=ev.id AND catl.ck=split_part(ev.akey,'.',1)) THEN
    CASE WHEN EXISTS(SELECT 1 FROM catl JOIN cc ON cc.oc=catl.obligation_code WHERE catl.cid=ev.id AND catl.ck=split_part(ev.akey,'.',1))
         THEN 'CATALOG_EXPLICIT' ELSE 'CATALOG_NO_CASE' END
  WHEN length(ev.leaf)>=10 AND ev.leaf LIKE '%\_%' THEN
    CASE WHEN EXISTS(SELECT 1 FROM cases c WHERE c.txt LIKE '%'||lower(ev.leaf)||'%') THEN 'NAME_MENTION_WEAK' ELSE 'NOT_IN_CATALOG' END
  ELSE 'LEAF_TOO_GENERIC' END,
  (SELECT string_agg(catl.obligation_code,',' ORDER BY catl.obligation_code) FROM catl WHERE catl.cid=ev.id AND catl.ck=split_part(ev.akey,'.',1)),
  (SELECT string_agg(DISTINCT catl.status,',') FROM catl WHERE catl.cid=ev.id AND catl.ck=split_part(ev.akey,'.',1))
FROM ev
ORDER BY ev.id, ev.akey
$fn$;

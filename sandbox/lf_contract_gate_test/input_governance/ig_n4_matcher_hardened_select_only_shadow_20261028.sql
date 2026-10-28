-- SELECT-ONLY DEV shadow; code equivalent to isolated SQL candidate shape/match semantics.
-- Never modifies Supabase. No authority or publication claims.
-- MATERIALIZED caches fixtures, normalized selectors and per-clause decisions
-- because each is reused by multiple downstream branches/EXISTS probes.
WITH fixtures(case_id,description,selector,context,expected) AS MATERIALIZED (
  VALUES
    ('T01'::text,'EQ matches verified module'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module","module_code"],"op":"EQ","value":"ALPHA"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":{"module_code":"ALPHA"}}}'::jsonb,true),
    ('T02'::text,'EQ excludes different module'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module","module_code"],"op":"EQ","value":"ALPHA"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":{"module_code":"BETA"}}}'::jsonb,false),
    ('T03'::text,'IN matches one of allowed modules'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module","module_code"],"op":"IN","values":["ALPHA","BETA"]}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":{"module_code":"BETA"}}}'::jsonb,true),
    ('T04'::text,'IN excludes other module'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module","module_code"],"op":"IN","values":["ALPHA","BETA"]}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":{"module_code":"GAMMA"}}}'::jsonb,false),
    ('T05'::text,'EXISTS on sourced nonnull value'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","objective"],"op":"EXISTS"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"objective":"test"}}}'::jsonb,true),
    ('T06'::text,'EXISTS missing attribute fails closed'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","unknown"],"op":"EXISTS"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{}}}'::jsonb,false),
    ('T07'::text,'EXISTS JSON null must not authorize'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module"],"op":"EXISTS"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":null}}'::jsonb,false),
    ('T08'::text,'EQ JSON null must not authorize automatically'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module"],"op":"EQ","value":null}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":null}}'::jsonb,false),
    ('T09'::text,'IN JSON null must not authorize automatically'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","module"],"op":"IN","values":[null]}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"module":null}}'::jsonb,false),
    ('T10'::text,'Consumer mismatch'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}],"any":[]}'::jsonb,'{"consumer_role":"UNAUTHORIZED_CONSUMER","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T11'::text,'UNRESOLVED selector'::text,'{"schema_version":"lf-rule-applicability/v1","status":"UNRESOLVED","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T12'::text,'AND plus OR success'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}],"any":[{"path":["target","module","module_code"],"op":"EQ","value":"ALPHA"},{"path":["target","module","module_code"],"op":"EQ","value":"BETA"}]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"},"module":{"module_code":"BETA"}}}'::jsonb,true),
    ('T13'::text,'AND failure even if OR matches'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}],"any":[{"path":["target","module","module_code"],"op":"EQ","value":"BETA"}]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"FAKE"},"module":{"module_code":"BETA"}}}'::jsonb,false),
    ('T14'::text,'Unknown operator fails closed'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"NOT","value":"FAKE"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T15'::text,'Unknown top-level selector field fails closed'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}],"any":[],"injected":"yes"}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T16'::text,'Consumer-only selector forbidden'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T17'::text,'New compatible target, no id enumeration'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","capabilities","session"],"op":"EQ","value":"YES"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":990001},"capabilities":{"session":"YES"}}}'::jsonb,true),
    ('T18'::text,'New target same module but missing capacity'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","capabilities","session"],"op":"EQ","value":"YES"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":990002},"module":{"module_code":"ALPHA"}}}'::jsonb,false),
    ('T19'::text,'New target explicit false capacity'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","capabilities","session"],"op":"EQ","value":"YES"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":990003},"capabilities":{"session":"NO"}}}'::jsonb,false),
    ('T20'::text,'Invalid schema version fails closed'::text,'{"schema_version":"lf-rule-applicability/v0","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T21'::text,'Path outside target rejected'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["consumer_role"],"op":"EQ","value":"INPUT_GOVERNANCE"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T22'::text,'Tautology EXISTS target must not authorize implicit all-target'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target"],"op":"EXISTS"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"id":1}}}'::jsonb,false),
    ('T23'::text,'Unexpected clause key must fail closed'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL","extra_guard":"CHECK_COMPETENCE"}],"any":[]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false)
,
    ('T24'::text,'Malformed second OR clause must not be ignored'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[],"any":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"},{"path":["target","screen","mode"],"op":"EQ","value":"REAL","unknown_required_guard":true}]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T25'::text,'Null second OR clause must fail schema validation'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[],"any":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"},{"path":["target","screen","unused"],"op":"EQ","value":null}]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T26'::text,'Unsupported second OR operator must not be ignored'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[],"any":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"},{"path":["target","screen","mode"],"op":"GREATER","value":"A"}]}'::jsonb,'{"consumer_role":"INPUT_GOVERNANCE","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T27'::text,'Consumer role values must be strings'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":[42],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}]}'::jsonb,'{"consumer_role":"42","target":{"screen":{"mode":"REAL"}}}'::jsonb,false),
    ('T28'::text,'Context consumer role must be a text value'::text,'{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["42"],"all":[{"path":["target","screen","mode"],"op":"EQ","value":"REAL"}]}'::jsonb,'{"consumer_role":42,"target":{"screen":{"mode":"REAL"}}}'::jsonb,false)
),
selector_struct AS MATERIALIZED (
 SELECT f.*,
 CASE WHEN jsonb_typeof(f.selector->'all')='array' THEN f.selector->'all' ELSE '[]'::jsonb END as all_clauses,
 CASE WHEN jsonb_typeof(f.selector->'any')='array' THEN f.selector->'any' ELSE '[]'::jsonb END as any_clauses,
 CASE WHEN jsonb_typeof(f.selector->'consumer_roles')='array' THEN f.selector->'consumer_roles' ELSE '[]'::jsonb END as roles
 FROM fixtures f
),
clauses AS(
 SELECT f.case_id,'all'::text as grp, x.value AS clause
 FROM selector_struct f CROSS JOIN LATERAL jsonb_array_elements(f.all_clauses) x(value)
 UNION ALL
 SELECT f.case_id,'any',x.value FROM selector_struct f
 CROSS JOIN LATERAL jsonb_array_elements(f.any_clauses) x(value)
),
typed AS(
 SELECT c.*,
 upper(coalesce(c.clause->>'op','')) op,
 CASE WHEN jsonb_typeof(c.clause->'path')='array' THEN c.clause->'path' ELSE '[]'::jsonb END path_json,
 CASE WHEN jsonb_typeof(c.clause->'values')='array' THEN c.clause->'values' ELSE '[]'::jsonb END values_json
 FROM clauses c
),
validations AS (
 SELECT t.*,
 (SELECT array_agg(x.value ORDER BY x.ordinality)
  FROM jsonb_array_elements_text(t.path_json) WITH ORDINALITY x(value,ordinality)) AS path,
 (
  jsonb_typeof(t.clause)='object'
  AND jsonb_typeof(t.clause->'path')='array'
  AND jsonb_array_length(t.path_json)>=2
  AND t.clause#>>'{path,0}'='target'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(t.path_json) x(value)
    WHERE jsonb_typeof(x.value)<>'string' OR btrim(x.value#>>'{}')='')
  AND jsonb_typeof(t.clause->'op')='string'
  AND t.op IN('EXISTS','EQ','IN')
  AND NOT EXISTS(
    SELECT 1 FROM jsonb_object_keys(CASE WHEN jsonb_typeof(t.clause)='object' THEN t.clause ELSE '{}'::jsonb END) k(key)
    WHERE k.key NOT IN ('path','op')
      AND NOT(t.op='EQ' AND k.key='value')
      AND NOT(t.op='IN' AND k.key='values')
  )
  AND (
    t.op='EXISTS'
    OR (t.op='EQ' AND (t.clause?'value') AND jsonb_typeof(t.clause->'value')<>'null')
    OR (t.op='IN' AND jsonb_typeof(t.clause->'values')='array'
      AND jsonb_array_length(t.values_json)>0
      AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(t.values_json) x(value)
       WHERE jsonb_typeof(x.value)='null'))
  )
 ) AS schema_valid
 FROM typed t
),
clause_match AS MATERIALIZED (
 SELECT c.case_id,c.grp,c.schema_valid,
 CASE WHEN c.schema_valid IS NOT TRUE THEN false
      WHEN (f.context#>c.path) IS NULL OR jsonb_typeof(f.context#>c.path)='null' THEN false
      WHEN c.op='EXISTS' THEN true
      WHEN c.op='EQ' THEN (f.context#>c.path)=(c.clause->'value')
      WHEN c.op='IN' THEN EXISTS(SELECT 1 FROM jsonb_array_elements(c.values_json) x(value)
        WHERE x.value=(f.context#>c.path))
      ELSE false END AS match
 FROM validations c JOIN selector_struct f ON f.case_id=c.case_id
),
shadow AS (
 SELECT f.case_id,
 CASE
 WHEN jsonb_typeof(f.selector) IS DISTINCT FROM 'object'
 OR jsonb_typeof(f.context) IS DISTINCT FROM 'object'
 OR f.selector->>'schema_version' IS DISTINCT FROM 'lf-rule-applicability/v1'
 OR f.selector->>'status' IS DISTINCT FROM 'ACTIVE'
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(f.selector) k(key)
   WHERE k.key NOT IN('schema_version','status','consumer_roles','all','any','provenance'))
 OR jsonb_typeof(f.context->'consumer_role') IS DISTINCT FROM 'string'
 OR jsonb_typeof(f.selector->'consumer_roles') IS DISTINCT FROM 'array'
 OR jsonb_array_length(f.roles)=0
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(f.roles) x(value)
   WHERE jsonb_typeof(x.value)<>'string' OR btrim(x.value#>>'{}')='')
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(f.roles) x(value)
   WHERE x.value=f.context->>'consumer_role')
 OR jsonb_typeof(coalesce(f.selector->'all','[]'::jsonb)) IS DISTINCT FROM 'array'
 OR jsonb_typeof(coalesce(f.selector->'any','[]'::jsonb)) IS DISTINCT FROM 'array'
 OR jsonb_array_length(f.all_clauses)+jsonb_array_length(f.any_clauses)=0
 OR EXISTS(SELECT 1 FROM clause_match e WHERE e.case_id=f.case_id AND e.schema_valid IS NOT TRUE)
 THEN false
 ELSE
  NOT EXISTS(SELECT 1 FROM clause_match e WHERE e.case_id=f.case_id
    AND e.grp='all' AND e.match IS NOT TRUE)
  AND (
    jsonb_array_length(f.any_clauses)=0
    OR EXISTS(SELECT 1 FROM clause_match e WHERE e.case_id=f.case_id
      AND e.grp='any' AND e.match IS TRUE)
  )
 END AS candidate_match
 FROM selector_struct f
)
SELECT f.case_id,f.description,f.expected,
       programacion.fn_input_rule_selector_matches_v1(f.selector,f.context) as old_result,
       s.candidate_match,
       CASE WHEN s.candidate_match=f.expected THEN 'PASS' ELSE 'FAIL' END AS candidate_verdict
FROM fixtures f JOIN shadow s ON s.case_id=f.case_id ORDER BY f.case_id;

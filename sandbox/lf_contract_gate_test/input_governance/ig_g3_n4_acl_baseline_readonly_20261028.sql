-- LF G3 read-only effective N4 ACL audit.
-- This tests baseline permissions only. Helper ACLs after candidate DDL
-- still require a separate isolated role test / independent review.
WITH roles AS MATERIALIZED (
 SELECT rolname,
   rolname IN ('anon','authenticated','service_role') AS must_not_reach_n4
 FROM pg_roles
 WHERE rolname IN (
   'anon','authenticated','service_role',
   'programacion_builder','programacion_auditor',
   'programacion_verifier','programacion_human_authority',
   'programacion_promoter','programacion_test_generator'
 )
),
access_matrix AS MATERIALIZED (
 SELECT r.rolname,r.must_not_reach_n4,
 has_schema_privilege(r.rolname,'programacion','USAGE') AS schema_usage,
 has_function_privilege(r.rolname,
   'programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)','EXECUTE') AS selector_exec,
 has_function_privilege(r.rolname,
   'programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)','EXECUTE') AS clause_exec
 FROM roles r
),
checked AS MATERIALIZED (
 SELECT *,schema_usage AND selector_exec AS can_invoke_selector,
 schema_usage AND clause_exec AS can_invoke_clause
 FROM access_matrix
)
SELECT COUNT(*) tested_roles,
 COUNT(*) FILTER (WHERE must_not_reach_n4) public_roles_checked,
 COUNT(*) FILTER (WHERE must_not_reach_n4 AND
   (can_invoke_selector OR can_invoke_clause)) unauthorized_reachable,
 COUNT(*) FILTER (WHERE NOT must_not_reach_n4) governed_roles_checked,
 COUNT(*) FILTER (WHERE NOT must_not_reach_n4 AND
   (NOT can_invoke_selector OR NOT can_invoke_clause)) governed_roles_missing_access,
 (SELECT to_regprocedure(
 'programacion.fn_input_rule_selector_clause_schema_valid_v1(jsonb)') IS NULL) new_helper_not_live
FROM checked;
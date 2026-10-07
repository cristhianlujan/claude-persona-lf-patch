-- M7.10 upstream immutability regression/acceptance (diagnostic test, read-only).
-- PASS requires zero post-INSERT curator-field UPDATEs on immutable assessment rows.
-- The correct contract 5.13 guard MUST remain intact.
-- Never disable the guard or accept success only because the Curator returned a run_id.
with bindings as (
 select pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure) as top_level,
        pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure) as immutable_guard
), checks as (
 select
   coalesce(regexp_count(lower(top_level),'update[[:space:]]+programacion[.]input_family_assessments'),0) as postinsert_curator_update_count,
   position('CURATOR_FIELDS_IMMUTABLE' in immutable_guard)>0 as immutability_guard_present,
   position('M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1' in top_level)>0 as core_route_retained,
   position('M5_4_SEMANTIC_PLAN_V1' in top_level)>0 as semantic_route_retained
 from bindings
)
select 'IG_M7_10_CURATOR_IMMUTABILITY_COMPATIBILITY_V1' test_code,
       case when postinsert_curator_update_count=0
           and immutability_guard_present
           and core_route_retained
           and semantic_route_retained
            then 'PASS' else 'FAIL' end as status,
       postinsert_curator_update_count,
       immutability_guard_present,
       core_route_retained,
       semantic_route_retained,
       'Test only static route preservation; separate live rollback-receipt E2E required for terminal PASS' as limitation
from checks;

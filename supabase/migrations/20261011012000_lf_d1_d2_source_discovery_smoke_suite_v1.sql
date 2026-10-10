-- LF D1/D2: registered developmental smoke scenarios in canonical Supabase tests.
-- NOT a holdout, not a scored benchmark, not an activation or permission change.
-- No demo business data or actor impersonation; no effects beyond test metadata.
-- Runtime policies, weights, rankings and source authorities remain Supabase-owned.
DO $preimage$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_test_suites WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1')
 THEN RAISE EXCEPTION 'D1D2_SMOKE_SUITE_ALREADY_EXISTS'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_test_suite_cases WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1')
 THEN RAISE EXCEPTION 'D1D2_SMOKE_CASES_ALREADY_EXIST'; END IF;
END $preimage$;

INSERT INTO public.lf_test_suites
(suite_code,module_code,name,version,status,execution_policy,metadata,created_by_execution_id)
VALUES
('TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1','PROFILE_RUNTIME_GOVERNANCE',
 'LF Transversal Source Discovery D1/D2 Dev Smoke','v1','CANDIDATO',
 jsonb_build_object('scope','METADATA_AND_PLANNER_ONLY','read_only',true,
  'baseline_candidate_paired',true,'blind_holdout_required_for_admission',true,
  'zero_critical_false_pass',true,'no_business_rows',true,
  'runtime_activation',false,'real_tenant_authorization_test_required',true,
  'no_automatic_execution',true),
 jsonb_build_object('project','LF','workstream','D1_D2_AUTONOMOUS_DISCOVERY',
  'test_tier','DEVELOPMENT_SMOKE_ONLY','case_source','SUPABASE_CANONICAL',
  'score_authority','SUPABASE_ONLY','holdout_separate',true,
  'source_pr',2190,'source_merge_commit','c77b2d93accc7804709181843cf33ac2ea1fac6e',
  'no_excel_authority',true),
 'EXEC-LF-D1D2-MACRO-LOT-20261010-001');

INSERT INTO public.lf_test_suite_cases
(suite_code,test_code,test_order,title,test_type,execution_mode,severity,
 input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id)
SELECT
 'TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1',
 x.test_code,x.ordinality,
 'D1/D2 '||x.scenario_code,
 'DETERMINISTIC','AUTOMATED',
 CASE WHEN x.family IN ('SECURITY','AUTHORIZATION') THEN 'CRITICAL' ELSE 'HIGH' END,
 jsonb_build_object('objective',x.objective,'scenario',x.scenario_code,
  'fixture_scope','METADATA_ONLY','fixture_kind',x.family,'input_contains_expected_answers',false),
 jsonb_build_object('expected_state',x.expected_state,'expected_candidate_family',x.expected_family,
  'data_access_granted',false,'discovery_exhausted',false),
 jsonb_build_object('must_not_grant_business_access',true,
  'must_not_claim_global_exhaustion',true,'must_not_select_unadmitted_source',true),
 'CANDIDATO',
 jsonb_build_object('scenario_code',x.scenario_code,'case_family',x.family,
  'oracle_visible_to_producer',false,'scored',false,'requires_live_authority',x.family='AUTHORIZATION',
  'no_synthetic_pass_for_real_access',true),
 'EXEC-LF-D1D2-MACRO-LOT-20261010-001'
FROM (VALUES
 ('D1D201',10,'METADATA_LOAD','Subí una carga y no aparece','CANDIDATES_FOUND','SCHEMA_METADATA','CATALOG'),
 ('D1D202',20,'METADATA_LOGIN','Revisar reglas de login B2B','CANDIDATES_FOUND','SOURCE_REGISTRY','CATALOG'),
 ('D1D203',30,'ASSET_PAYMENT','Mi pago no aparece','CANDIDATES_FOUND','SOURCE_REGISTRY','CATALOG'),
 ('D1D204',40,'ASSET_OFFER','No encuentro una oferta','CANDIDATES_FOUND','SOURCE_REGISTRY','CATALOG'),
 ('D1D205',50,'UNKNOWN_DOMAIN','nanoreactor cuántico','NO_MATCH_IN_SCOPE','NONE','NEGATIVE'),
 ('D1D206',60,'POLICY_DRIFT','Subí una carga y no aparece','ERROR_FAIL_CLOSED','NONE','SECURITY'),
 ('D1D207',70,'SCHEMA_SCOPE_EMPTY','Subí una carga y no aparece','ERROR_FAIL_CLOSED','NONE','SECURITY'),
 ('D1D208',80,'BUDGET_INVALID','Subí una carga y no aparece','ERROR_FAIL_CLOSED','NONE','SECURITY'),
 ('D1D209',90,'NO_CANONICAL_BINDING','Subí una carga y no aparece','BLOCK_CANONICAL_READ_BINDING_ABSENT','NONE','AUTHORIZATION'),
 ('D1D210',100,'NO_B2B_ACTOR','Subí una carga y no aparece','BLOCK_ACTOR_NOT_AUTHENTICATED','NONE','AUTHORIZATION'),
 ('D1D211',110,'TENANT_CROSS_SCOPE','Subí una carga y no aparece','DENY_TENANT','NONE','AUTHORIZATION'),
 ('D1D212',120,'PLANNER_LOCAL_EXHAUSTION','Subí una carga y no aparece','RETURN_TO_SOURCE_DISCOVERY','NONE','REPLANNING')
) AS x(test_code,ordinality,scenario_code,objective,expected_state,expected_family,family);

DO $verify$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.lf_test_suite_cases
 WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1';
 IF n<>12 THEN RAISE EXCEPTION 'D1D2_SMOKE_CASE_COUNT_WRONG:%',n; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_test_suites
  WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1'
   AND status='CANDIDATO'
   AND execution_policy->>'runtime_activation'='false')
 THEN RAISE EXCEPTION 'D1D2_SMOKE_SUITE_SCOPE_DRIFT'; END IF;
END $verify$;

-- AUD-0.5 Canon vs Objective Gap v2
-- Replaces keyword-count gap matrix. Read-only; does not use AUDSYS claim/obligation rows.
-- Freeze: main dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- schema_fp: 56c2af889d3f6a4781b1ac74ba7da5bb
with matrix(code,objective,canonical_assets,asset_state,control_ref,threshold,current_measurement,gap_state) as (values
('Q01','Operar sin errores',
 jsonb_build_array('public.lf_error_knowledge','public.lf_backlog_errores_operativos','public.v_lf_architecture_closure_current'),
 'VIGENTE + AUDIT_READ_ONLY',
 'audit/system_integral/aud07_root_cause_clustering_v1.sql + public.v_lf_architecture_closure_current',
 '0 CRITICAL/HIGH root findings on critical paths; architecture closure READY',
 jsonb_build_object('audit_root_findings',39,'critical_root_findings',4,'architecture_closure','NOT_READY','failed_gate_tests',45),
 'GAP_OPEN_ERRORS_AND_CLOSURE_NOT_READY'),

('Q02','Sin dependencias frágiles',
 jsonb_build_array('AUD-7 unified dependency graph','public.lf_operation_step_contracts','DB FK/view/function dependencies'),
 'AUDIT_READ_ONLY + VIGENTE',
 'audit/system_integral/aud07_unified_blast_radius_v1.py',
 'All material dependencies represented; unresolved dynamic/material references=0; inferred edges never treated as material',
 jsonb_build_object('material_edges',2971,'material_nodes',2071,'dynamic_unresolved',19,'candidate_unqualified_excluded',true),
 'GAP_UNRESOLVED_DYNAMIC_REFS'),

('Q03','Sin bloqueos genéricos; first-bad-hop causal',
 jsonb_build_array('public.lf_operation_execution','public.lf_operation_execution_steps','public.lf_operation_step_contracts'),
 'VIGENTE',
 'audit/system_integral/aud06_failure_recovery_v1.sql',
 '100% nonterminal executions resolve to explicit first-bad-hop or explicit terminal/reconcile state',
 jsonb_build_object('in_progress',65,'first_bad_hop_resolved',61,'all_required_clean_but_open',4),
 'GAP_TERMINAL_AND_CAUSAL_COVERAGE'),

('Q04','Sin datos/configuración en duro',
 jsonb_build_array('repository@freeze','live DB functions'),
 'VIGENTE + AUDIT_READ_ONLY',
 'audit/system_integral/aud03_repo_architecture_scan_v1.py + AUD-3 O12 live-function SQL control',
 '0 material hardcodes in live/runtime source unless explicitly governed and justified',
 jsonb_build_object('non_test_sha40_sources',23,'live_functions_with_sha40',3,'sql_sha40_occurrences',198,'pooler_host_files',11),
 'GAP_MATERIAL_HARDCODES_PRESENT'),

('Q05','Componentes transversales realmente adoptados',
 jsonb_build_array('public.v_lf_fuente_operativa','public.lf_capability_registry','public.lf_capability_binding'),
 'VIGENTE',
 'audit/system_integral/aud02_capability_repo_refs_v1.py + AUD-7 capability adoption SQL',
 'Every operational capability consumer has durable binding + enforcement/readback; no capability counted adopted by text reference alone',
 jsonb_build_object('capabilities',44,'repo_referenced',35,'repo_text_edges',244,'registry_rows',3,'formal_bindings',0),
 'GAP_COMPONENT_EXISTS_WITHOUT_FORMAL_ADOPTION'),

('Q06','Un proceso estándar, no metodología por artefacto',
 jsonb_build_array('public.lf_operation_registry','public.lf_operation_steps','POL-LF-OPERATION-LIFECYCLE','C05_GENERIC_EXECUTION_RELIABILITY'),
 'VIGENTE',
 'audit/system_integral/aud06_failure_recovery_v1.sql',
 '100% governed operations use one lifecycle protocol: reserve→lease/fence→checkpoint→fenced writes/effects→terminal close/reconcile',
 jsonb_build_object('operations',45,'operations_without_report_output',26,'reserve_callers',9,'full_reliability_chain_callers',0),
 'GAP_LIFECYCLE_PROTOCOL_FRAGMENTED'),

('Q07','Pruebas robustas claims→precondiciones→subprocesos→predecesores→evidencia',
 jsonb_build_array('public.lf_assurance_claim_catalog','public.lf_assurance_obligation_catalog','public.lf_test_requirement_bindings','public.lf_test_runs'),
 'VIGENTE; AUDSYS rows CANDIDATO excluded',
 'audit/system_integral/aud05_test_assurance_v1.sql',
 '100% applicable claims/obligations and operation branches bind to executable tests; every run persists contract/dependency evidence',
 jsonb_build_object('preexisting_claims',23,'preexisting_claims_without_evaluation',22,'operations_with_required_test_binding',9,'operations_total',45,'test_runs',1170,'runs_with_contract_codes',0,'cases_with_preconditions',78,'test_cases',221),
 'GAP_TRACEABILITY_AND_REQUIRED_COVERAGE'),

('Q08','SHA/currentness estable sin invalidación no causal',
 jsonb_build_array('CURRENTNESS_AUTHORITY','material dependency graph','test evidence currentness'),
 'VIGENTE + AUDIT_READ_ONLY',
 'audit/system_integral/aud07_unified_blast_radius_v1.py + AUD-5 material-currentness criterion',
 'Invalidate evidence only when its material dependency footprint changed; global SHA mismatch alone is insufficient',
 jsonb_build_object('exact_sha_is_not_staleness',true,'test_dependency_binding_available',false,'runs_with_contract_codes',0),
 'GAP_MATERIAL_CURRENTNESS_UNRESOLVED_DUE_TO_TRACEABILITY'),

('Q09','Arquitectura correcta y sin bypass de owner/layer',
 jsonb_build_array('public.v_lf_architecture_closure_current','public.lf_operation_registry','ACT-0001 router authority'),
 'VIGENTE',
 'AUD-3 architecture-conformance controls + public.v_lf_architecture_closure_current',
 'closure_ready=true; failed_gate_tests=0; owner/authority bypass=0',
 jsonb_build_object('closure_ready',false,'failed_gate_tests',45,'owner_missing_assets',42,'router_resolver_candidates',3),
 'GAP_ARCHITECTURE_NOT_READY'),

('Q10','Separación determinístico / semántico',
 jsonb_build_array('public.lf_operation_step_contracts','public.lf_operation_judges','GPT_RUNTIME_*'),
 'VIGENTE',
 'audit/system_integral/aud05_test_assurance_v1.sql + aud03_gpt_runtime_classification_v1.sql',
 '100% steps classified by behavior; deterministic work has deterministic executor/control; semantic runtime only for irreducible reasoning',
 jsonb_build_object('gpt_runtime_population',210,'deterministic_executor_present',19,'contract_bound_without_deterministic_executor',88,'partial_behavior_contract_without_executor',103),
 'GAP_FUNCTIONAL_CLASSIFICATION_INCOMPLETE'),

('Q11','Sin acumulación de contexto',
 jsonb_build_array('private.lf_context_budget_events_v2','CONTEXT_BUDGET_GOVERNANCE'),
 'VIGENTE',
 'audit/system_integral/aud04_execution_performance_v1.sql',
 '100% model/runtime executions expose bounded context-budget telemetry; no unmeasured transport path',
 jsonb_build_object('operation_executions_observed',590,'context_budget_events',1,'max_observed_tokens',163000,'token_threshold_source','NO_CANONICAL_1500_3000_THRESHOLD_USED'),
 'GAP_OBSERVABILITY_NOT_SYSTEMWIDE'),

('Q12','Sin transporte pesado/repetido',
 jsonb_build_array('PREV-PROFILE-MODEL-CONTEXT-TRANSPORT-001','CONTEXT_BUDGET_GOVERNANCE','runtime source transport paths'),
 'VIGENTE + AUDIT_READ_ONLY',
 'AUD-4.3 context/payload scan + PREV-PROFILE-MODEL-CONTEXT-TRANSPORT-001 consumer-enforcement readback',
 '0 runtime paths transport canonical/full packs when deterministic projection suffices; consumer enforcement must be observable',
 jsonb_build_object('context_budget_coverage','1/590','systemwide_full_pack_transport_measurement',false),
 'GAP_SYSTEMWIDE_TRANSPORT_MEASUREMENT_NOT_COMPLETE'),

('Q13','Consultas eficientes, índices correctos y búsquedas acotadas',
 jsonb_build_array('extensions.pg_stat_statements','pg indexes/stats','runtime SQL/query sources'),
 'VIGENTE + MUTABLE_TELEMETRY',
 'audit/system_integral/aud04_execution_performance_v1.sql + aud04_repo_performance_scan_v1.py',
 '0 material FK/index candidates; no unbounded runtime query patterns; performance window explicitly timestamped and audit/catalog traffic excluded',
 jsonb_build_object('exact_material_fk_index_candidates',14,'runtime_select_star_candidates',4,'slow_application_shapes_at_review',16,'planner_stats_stale_tables',6),
 'GAP_QUERY_INDEX_AND_STATS')
)
select jsonb_build_object(
 'schema_version','aud00-5-canon-gap/v2',
 'freeze',jsonb_build_object('main_sha','dafe10a6a730d63bc59ce036360f214cd6fd8d96','schema_fp','56c2af889d3f6a4781b1ac74ba7da5bb'),
 'method','CONCRETE_CANONICAL_ASSETS_PLUS_EXECUTABLE_CONTROL_AND_THRESHOLD',
 'keyword_match_counts_used',false,
 'audsys_catalog_rows_used',false,
 'criteria_count',count(*),
 'criteria',jsonb_agg(jsonb_build_object(
    'code',code,'objective',objective,'canonical_assets',canonical_assets,'asset_state',asset_state,
    'control_ref',control_ref,'threshold',threshold,'current_measurement',current_measurement,'gap_state',gap_state
 ) order by code)
) aud00_5_canon_gap_v2
from matrix;

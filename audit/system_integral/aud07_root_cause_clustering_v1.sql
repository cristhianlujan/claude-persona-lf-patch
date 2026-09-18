-- AUD-7 root-cause clustering v1
-- Read-only. Freeze: main dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- schema_fp: 56c2af889d3f6a4781b1ac74ba7da5bb
-- Clusters are explicit invariant buckets. Broad text matches are recurrence indexes only and may overlap.
with
findings as (
 select id,estado,categoria,prioridad,activo_relacionado,metadata,
        metadata->>'finding_code' finding_code,
        case
          when estado='RESUELTA' then 'HISTORY_RESOLVED'
          when id=152 then 'SYMPTOM_PARENT'
          when id=139 then 'SUPERSEDED_MEASUREMENT'
          when id=157 then 'TOOLING_MEASUREMENT_BIAS'
          when id in (129,131,160) then 'QUEUED_EXTERNAL_DECISION'
          else 'ROOT_FINDING'
        end lineage_role,
        case
          when categoria='CAPABILITY_ADOPTION_BINDING' then 'RC01_CONNECTION_ENFORCEMENT'
          when categoria in ('EXECUTION_LIFECYCLE_PERFORMANCE','EXECUTION_FIRST_BAD_HOP','CHECKPOINT_RESUME_RECOVERY','EXECUTION_RELIABILITY_ARCHITECTURE','CONCURRENCY_MULTIWRITER','EXECUTION_CLOSURE_PROTOCOL','EFFECT_RECOVERY','ROLLBACK_RECOVERY_COVERAGE') then 'RC02_EXECUTION_LIFECYCLE'
          when categoria in ('ASSURANCE_TRACEABILITY','ASSURANCE_TEST_BINDING','TEST_REQUIREMENT_COVERAGE','TEST_CONTRACT_TRACEABILITY','TEST_STRUCTURAL_COVERAGE','ADVERSARIAL_TEST_COVERAGE') then 'RC03_TEST_ASSURANCE_TRACEABILITY'
          when categoria in ('SCHEMA_CURRENTNESS','CURRENTNESS_METADATA','HARDCODE_CONFIG','WORKFLOW_REFERENCE_CURRENTNESS','TEST_EVIDENCE_CURRENTNESS') then 'RC04_CURRENTNESS_IDENTITY'
          when categoria in ('DETERMINISTIC_SEMANTIC_SPLIT','DETERMINISTIC_SEMANTIC_CLASSIFICATION') then 'RC05_DETERMINISTIC_SEMANTIC'
          when categoria in ('QUERY_PERFORMANCE','INDEX_QUERY_SHAPING','CONTEXT_PAYLOAD_PERFORMANCE','RUNTIME_CONTROL_STANDARDIZATION','CACHE_REPEATED_READ','EXECUTION_LATENCY','QUERY_SHAPING','DATABASE_STATISTICS_CURRENTNESS','PERFORMANCE_MEASUREMENT_CURRENTNESS') then 'RC06_PERFORMANCE_BOUNDED_EXECUTION'
          when categoria in ('SCOPE_GOVERNANCE','CI_CONTROL_COVERAGE','INVENTORY_COVERAGE','OWNERSHIP_COVERAGE','AUTHORITY_CONFORMANCE','ARCHITECTURE_CLOSURE','DUPLICATE_IMPLEMENTATION') then 'RC07_AUTHORITY_GOVERNANCE'
          when categoria in ('AUDIT_METHOD','AUDIT_COVERAGE','AUDIT_CONTROL','PROCESS_DISCIPLINE','AUDIT_UNIVERSE','AUDIT_REPRODUCIBILITY','AUDIT_MEASUREMENT_CONTAMINATION','DEPENDENCY_GRAPH','GRAPH_COMPLETENESS') then 'RC08_AUDIT_MEASUREMENT'
          when categoria='KNOWLEDGE_RULE_TAXONOMY' then 'RC09_KNOWLEDGE_TAXONOMY'
          when categoria='TRANSVERSAL_ACTIVATION_ENFORCEMENT' then 'RCP01_ACTIVATION_BINDING_PARENT'
          else 'RC99_OTHER'
        end root_cluster
 from public.lf_backlog_errores_operativos
 where metadata->>'audit_program_code'='LF_SYSTEM_INTEGRAL_AUDIT_AUD0_AUD8_V1'
   and metadata->>'record_kind'='AUDIT_FINDING'
),
root_findings as (
 select * from findings where lineage_role='ROOT_FINDING' and estado<>'RESUELTA'
),
finding_clusters as (
 select root_cluster,count(*) findings,
        count(*) filter(where prioridad='CRITICA') critical,
        count(*) filter(where prioridad='ALTA') high,
        count(*) filter(where prioridad='MEDIA') medium,
        jsonb_agg(id order by id) finding_ids
 from root_findings group by root_cluster
),
ekb as (
 select e.*,lower(concat_ws(' ',codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,coalesce(root_cause_family,''),coalesce(source_context,''))) txt
 from public.lf_error_knowledge e
),
rules as (
 select r.*,lower(concat_ws(' ',regla_codigo,error_codigo,regla,justificacion,coalesce(categoria,''),coalesce(lifecycle_phase,''))) txt,
        lower(regexp_replace(btrim(regla),'\s+',' ','g')) norm_rule
 from public.lf_prevention_rules r
),
strict_binding_ekb as (
 select * from ekb
 where txt ~ '(unbound|unresolved.{0,20}bind|binding.{0,20}(missing|absent|unresolved|orphan)|not[_ -]?materialized|materializ.{0,20}(missing|absent)|orphan|hu[eé]rfan|wiring.{0,15}(missing|absent)|consumer.{0,20}(binding|enforcement).{0,20}(missing|absent))'
),
strict_binding_rules as (
 select * from rules
 where txt ~ '(unbound|unresolved.{0,20}bind|binding.{0,20}(missing|absent|unresolved|orphan)|not[_ -]?materialized|materializ.{0,20}(missing|absent)|orphan|hu[eé]rfan|consumer.{0,20}(binding|enforcement))'
),
exact_rule_duplicates as (
 select norm_rule,count(*) n from rules where norm_rule<>'' group by norm_rule having count(*)>1
),
gpt_ops as (
 select distinct operation_code from public.lf_operation_step_contracts
 where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE') and resolver_ref like 'GPT_RUNTIME%'
),
cap_ops as (
 with caps as (select codigo_activo capability_code from public.v_lf_fuente_operativa where tipo_activo='CAPABILITY')
 select distinct s.operation_code
 from caps c join public.lf_operation_step_contracts s
   on concat_ws(' ',coalesce(s.resolver_ref,''),coalesce(s.notes,''),coalesce(s.execution_sql,''),
                coalesce(s.input_required::text,''),coalesce(s.output_payload::text,''),coalesce(s.required_evidence_keys::text,''))
      ~ ('(^|[^A-Z0-9_-])'||regexp_replace(c.capability_code,'([\W])','\\\1','g')||'([^A-Z0-9_-]|$)')
 where s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
),
usage7 as (
 select jsonb_build_object(
   'window_start',now()-interval '7 days','window_end',now(),
   'operation_executions',(select count(*) from public.lf_operation_execution where started_at>=now()-interval '7 days'),
   'distinct_operations',(select count(distinct operation_code) from public.lf_operation_execution where started_at>=now()-interval '7 days'),
   'completed_operations',(select count(*) from public.lf_operation_execution where started_at>=now()-interval '7 days' and status='COMPLETED'),
   'inprogress_started',(select count(*) from public.lf_operation_execution where started_at>=now()-interval '7 days' and status='IN_PROGRESS'),
   'gpt_runtime_operation_executions',(select count(*) from public.lf_operation_execution e where e.started_at>=now()-interval '7 days' and exists(select 1 from gpt_ops g where g.operation_code=e.operation_code)),
   'capability_observed_operation_executions',(select count(*) from public.lf_operation_execution e where e.started_at>=now()-interval '7 days' and exists(select 1 from cap_ops c where c.operation_code=e.operation_code)),
   'test_runs',(select count(*) from public.lf_test_runs where coalesce(started_at,created_at)>=now()-interval '7 days'),
   'test_identities',(select count(distinct (suite_code,test_code)) from public.lf_test_runs where coalesce(started_at,created_at)>=now()-interval '7 days'),
   'gate_check_results',(select count(*) from public.lf_operation_gate_check_results where observed_at>=now()-interval '7 days'),
   'ekb_touched',(select count(*) from public.lf_error_knowledge where greatest(created_at,updated_at)>=now()-interval '7 days'),
   'prevention_rules_created',(select count(*) from public.lf_prevention_rules where created_at>=now()-interval '7 days')
 ) j
),
mother_candidates as (
 select * from (values
  ('MR01_ACTIVATION_REQUIRES_DURABLE_BINDING_AND_CONSUMER_READBACK',
   'PARENT_PROCESS_INVARIANT',
   'A component is not operational merely because it exists or is referenced. Activation requires durable consumer binding, enforcement at the execution path and independent consumer readback.',
   jsonb_build_array(178,176,171,161,162),
   jsonb_build_array('capabilities 44 / formal bindings 0','reliability reserve callers 9 / acquire-checkpoint-release callers 0','test runs 1170 / populated contract_codes 0','operation required-test binding 9/45'),
   'CONFIRMED_CROSS_DOMAIN_PATTERN_NOT_SINGLE_TECHNICAL_BUG'),
  ('MR02_STANDARD_OPERATION_LIFECYCLE_PROTOCOL',
   'DOMAIN_MOTHER_INVARIANT',
   'Every governed operation must use one lifecycle protocol: reserve identity -> acquire fenced lease -> durable checkpoint -> fenced step/effect writes -> terminal close or explicit reconcile/resume/supersede.',
   jsonb_build_array(169,170,171,172,173,174,175),
   jsonb_build_array('65 IN_PROGRESS','38 with zero steps','58 without checkpoint','0 reaper/resume cron','10 unresolved RESERVED effects'),
   'HIGH_CONFIDENCE'),
  ('MR03_CLAIM_CONTRACT_BRANCH_TEST_TRACEABILITY',
   'DOMAIN_MOTHER_INVARIANT',
   'Applicable claims/obligations/branches must resolve to required tests; each run must persist contract/dependency identity, executable oracle evidence and material currentness.',
   jsonb_build_array(159,161,162,163,164,165),
   jsonb_build_array('22/23 preexisting claims without evaluation','9/45 operations with required test binding','1170 runs / 0 populated contract_codes','221 cases / 78 with preconditions'),
   'HIGH_CONFIDENCE'),
  ('MR04_MATERIAL_CURRENTNESS_DEPENDENCY_FOOTPRINT',
   'DOMAIN_MOTHER_INVARIANT',
   'Currentness is invalidated by material dependency change, not by unrelated global SHA drift. Evidence must bind canonical source identity plus dependency footprint.',
   jsonb_build_array(125,141,143,155,165),
   jsonb_build_array('global SHA mismatch not sufficient','workflow/currentness/version gaps observed'),
   'HIGH_CONFIDENCE'),
  ('MR05_DETERMINISTIC_FIRST_SEMANTIC_BOUNDARY',
   'DOMAIN_MOTHER_INVARIANT',
   'Deterministic eligibility and execution must be explicit from inputs/outputs/evidence/executor; semantic runtime is reserved for irreducible reasoning and receives bounded projected context.',
   jsonb_build_array(166,149),
   jsonb_build_array('210 GPT_RUNTIME contracts','19 with execution_sql','143 GPT_RUNTIME-operation executions in 7d','context budget telemetry 1/590'),
   'MEDIUM_HIGH_CONFIDENCE'),
  ('MR06_BOUNDED_DATA_ACCESS_AND_RUNTIME',
   'DOMAIN_MOTHER_INVARIANT',
   'Database access and runtime work must be bounded by selective queries, current planner statistics, appropriate indexes, phase timeouts, cache/read reuse and context budgets.',
   jsonb_build_array(147,148,149,150,151,153,154,156,158),
   jsonb_build_array('9 root findings','297 operation executions in 7d'),
   'HIGH_CONFIDENCE'),
  ('MR07_CANONICAL_AUTHORITY_OWNER_SOURCE',
   'DOMAIN_MOTHER_INVARIANT',
   'Every action must resolve one canonical owner/authority/source and prove the binding before execution or closure; duplicates and orphan authority are fail-closed.',
   jsonb_build_array(134,135,140,142,144),
   jsonb_build_array('42/132 assets missing owner','architecture closure NOT_READY'),
   'MEDIUM_HIGH_CONFIDENCE'),
  ('MR08_AUDIT_MEASUREMENT_MUST_BE_EXECUTABLE_AND_NON_SELF_CONTAMINATING',
   'AUDIT_MOTHER_INVARIANT',
   'Audit controls must be executable, freeze/delta bound, source complete, and must not mutate the measured universe unless the mutation is explicitly excluded from denominators.',
   jsonb_build_array(126,127,128,130),
   jsonb_build_array('AUD-0 regex gap','missing canon sources','descriptive controls','instruction deviation'),
   'HIGH_CONFIDENCE'),
  ('MR09_KNOWLEDGE_RULE_TAXONOMY_AND_PARENT_CHILD',
   'KNOWLEDGE_MOTHER_INVARIANT',
   'EKB and prevention rules must preserve specific evidence while mapping to explicit root-cause family, lifecycle and parent invariant; consolidation is parent-child, not destructive deduplication.',
   jsonb_build_array(177),
   jsonb_build_array('138 EKB root family NULL','66 UNCLASSIFIED_WITH_REASON','119 rules category NULL','121 rules lifecycle NULL','0 exact rule-text duplicate groups'),
   'HIGH_CONFIDENCE')
 ) v(code,kind,invariant,direct_finding_ids,evidence_summary,confidence)
)
select jsonb_build_object(
 'schema_version','aud07-root-cause-clustering/v1',
 'freeze',jsonb_build_object('main_sha','dafe10a6a730d63bc59ce036360f214cd6fd8d96','schema_fp','56c2af889d3f6a4781b1ac74ba7da5bb'),
 'finding_normalization',jsonb_build_object(
   'raw',(select count(*) from findings),
   'resolved_history',(select count(*) from findings where lineage_role='HISTORY_RESOLVED'),
   'active_nonresolved',(select count(*) from findings where estado<>'RESUELTA'),
   'root_findings',(select count(*) from root_findings),
   'symptom_parents',(select count(*) from findings where lineage_role='SYMPTOM_PARENT'),
   'superseded_measurements',(select count(*) from findings where lineage_role='SUPERSEDED_MEASUREMENT'),
   'tooling_measurement_bias',(select count(*) from findings where lineage_role='TOOLING_MEASUREMENT_BIAS'),
   'queued_external_decisions',(select count(*) from findings where lineage_role='QUEUED_EXTERNAL_DECISION')
 ),
 'finding_clusters',coalesce((select jsonb_agg(to_jsonb(finding_clusters) order by critical desc,high desc,findings desc,root_cluster) from finding_clusters),'[]'::jsonb),
 'ekb',jsonb_build_object(
   'rows',(select count(*) from ekb),
   'root_family_null',(select count(*) from ekb where nullif(btrim(root_cause_family),'') is null),
   'unclassified_with_reason',(select count(*) from ekb where root_cause_family='UNCLASSIFIED_WITH_REASON'),
   'strict_binding_rows',(select count(*) from strict_binding_ekb),
   'strict_binding_frequency_sum',(select coalesce(sum(greatest(coalesce(frecuencia,1),1)),0) from strict_binding_ekb)
 ),
 'prevention',jsonb_build_object(
   'rows',(select count(*) from rules),
   'active',(select count(*) from rules where activa),
   'inactive',(select count(*) from rules where not activa),
   'category_null',(select count(*) from rules where nullif(btrim(categoria),'') is null),
   'lifecycle_null',(select count(*) from rules where nullif(btrim(lifecycle_phase),'') is null),
   'exact_duplicate_groups',(select count(*) from exact_rule_duplicates),
   'strict_binding_rules',(select count(*) from strict_binding_rules),
   'strict_binding_active',(select count(*) from strict_binding_rules where activa)
 ),
 'usage_7d',(select j from usage7),
 'mother_rule_candidates',coalesce((select jsonb_agg(jsonb_build_object(
    'code',code,'kind',kind,'invariant',invariant,'direct_finding_ids',direct_finding_ids,
    'evidence_summary',evidence_summary,'confidence',confidence
 ) order by code) from mother_candidates),'[]'::jsonb)
) aud07_root_cause_clustering;

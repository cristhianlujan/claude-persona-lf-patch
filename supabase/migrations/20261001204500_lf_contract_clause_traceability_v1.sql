-- M1.A6 / PAULO-125
-- Canonical Supabase storage for contract-clause traceability.
-- No runtime/deploy/production activation changes.

create table programacion.contract_traceability_matrices (
  id bigint generated always as identity primary key,
  matrix_code text not null,
  matrix_revision integer not null,
  contract_id bigint not null references programacion.contratos(id),
  contract_revision text not null,
  contract_spec_md5 text not null check (contract_spec_md5 ~ '^[0-9a-f]{32}$'),
  source_plan_code text not null,
  source_unit_code text not null,
  source_event_id bigint,
  upstream_classification_sha256 text not null check (upstream_classification_sha256 ~ '^[0-9a-f]{64}$'),
  upstream_snapshot_sha256 text not null check (upstream_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  locator_scope text not null,
  matrix_sha256 text not null check (matrix_sha256 ~ '^[0-9a-f]{64}$'),
  clause_count integer not null check (clause_count > 0),
  semantic_test_covered_count integer not null default 0 check (semantic_test_covered_count >= 0),
  semantic_test_pending_count integer not null default 0 check (semantic_test_pending_count >= 0),
  status text not null check (status in ('DEFINED','SUPERSEDED','RETIRED')),
  source_ref text not null,
  created_by_execution_id text not null,
  created_at timestamptz not null default now(),
  unique (matrix_code, matrix_revision),
  unique (contract_id, contract_revision, matrix_revision)
);

create table programacion.contract_traceability_rows (
  id bigint generated always as identity primary key,
  matrix_id bigint not null references programacion.contract_traceability_matrices(id) on delete restrict,
  clause_key text not null,
  target_layer text not null check (target_layer in ('CORE','SEMANTIC','READINESS_POLICY','ORCHESTRATION','EVIDENCE','PERSISTENCE')),
  target_owner text not null,
  target_enforcement text not null,
  current_function_refs text[] not null default '{}',
  current_trigger_refs text[] not null default '{}',
  current_enforcement_status text not null check (current_enforcement_status in ('CURRENT_LOCATOR_OBSERVED_NOT_SEMANTIC_PROOF','NO_DIRECT_LOCATOR_OBSERVED')),
  integrity_test_refs text[] not null default '{}',
  semantic_test_status text not null check (semantic_test_status in ('PENDING_CLAUSE_SEMANTIC_TEST','COVERED','NOT_APPLICABLE')),
  row_status text not null check (row_status in ('DEFINED','SUPERSEDED','RETIRED')),
  observed_at timestamptz not null,
  source_ref text not null,
  created_by_execution_id text not null,
  created_at timestamptz not null default now(),
  unique (matrix_id, clause_key)
);

comment on table programacion.contract_traceability_matrices is 'Versioned contract traceability matrix header: contract identity, scope and aggregate digest.';
comment on table programacion.contract_traceability_rows is 'One readable row per contract clause: target owner/layer, enforcement locator and test coverage state.';

alter table programacion.contract_traceability_matrices enable row level security;
alter table programacion.contract_traceability_matrices force row level security;
alter table programacion.contract_traceability_rows enable row level security;
alter table programacion.contract_traceability_rows force row level security;

create policy p_contract_traceability_matrices_read
  on programacion.contract_traceability_matrices
  for select
  to programacion_auditor, programacion_builder, programacion_verifier, programacion_human_authority
  using (true);

create policy p_contract_traceability_rows_read
  on programacion.contract_traceability_rows
  for select
  to programacion_auditor, programacion_builder, programacion_verifier, programacion_human_authority
  using (true);

revoke all on programacion.contract_traceability_matrices from public;
revoke all on programacion.contract_traceability_rows from public;
grant select on programacion.contract_traceability_matrices to programacion_auditor, programacion_builder, programacion_verifier, programacion_human_authority;
grant select on programacion.contract_traceability_rows to programacion_auditor, programacion_builder, programacion_verifier, programacion_human_authority;

create trigger trg_contract_traceability_matrices_append_only
  before update or delete on programacion.contract_traceability_matrices
  for each row execute function programacion.fn_v09_append_only();

create trigger trg_contract_traceability_rows_append_only
  before update or delete on programacion.contract_traceability_rows
  for each row execute function programacion.fn_v09_append_only();

create temporary table _m1a6_trace_rows (
  clause_key text primary key,
  target_layer text not null,
  target_owner text not null,
  target_enforcement text not null,
  current_function_refs text[] not null,
  current_trigger_refs text[] not null,
  current_enforcement_status text not null,
  integrity_test_refs text[] not null,
  semantic_test_status text not null
) on commit drop;

insert into _m1a6_trace_rows (
  clause_key,target_layer,target_owner,target_enforcement,
  current_function_refs,current_trigger_refs,current_enforcement_status,
  integrity_test_refs,semantic_test_status
)
with clauses as (
  select k as clause_key
  from programacion.contratos c
  cross join lateral jsonb_object_keys(c.especificacion) k
  where c.id=37
), classified as (
  select clause_key,
    case
      when clause_key = any(array['canonical_universe_rule','family_universe_source','screen_graph_contract','screen_graph_scoping','source_precedence']) then 'CORE'
      when clause_key = any(array['api_data_contract_readiness','applicability_source_grounding','assertion_contract','assertion_relevance_policy','assertion_required_fields','assertion_truth_evaluated','design_system_readiness','empty_collection_semantics','semantic_coherence_contract','semantic_component_sufficiency','semantic_depth_contract']) then 'SEMANTIC'
      when clause_key = any(array['applicability_status_invariants','auto_promotion','candidate_as_own_authority','deterministic_stage_summary','family_stage_requirements','freshness_gate','governance_authority_policy','legacy_contract_v1_authoritative','legacy_contract_v2_authoritative','llm_as_sole_gate','not_applicable_positive_authority_contract','not_applicable_requires_reason','production_activation','readiness_levels','readiness_stage_hierarchy','semantic_fail_closed','stage_authority_policy','stage_boundary_contract','story_ready_rule']) then 'READINESS_POLICY'
      when clause_key = any(array['canon_vs_proposal_separation','consumer','contract_revision','parameterization_contract','proposal_contract','schema_version','statuses','validator_component_binding','validator_identity_must_differ_from_curator','validator_independence_required','validator_requires_run_status']) then 'ORCHESTRATION'
      when clause_key = any(array['audit_remediation','builder_regression_v2','builder_regression_v3','direct_source_readback_required','negative_tests','remediation_revision','revision_lineage','source_manifest','source_ref_contract','source_refs_required_per_family','source_snapshot_binding','validator_evidence_required_fields']) then 'EVIDENCE'
      when clause_key = any(array['curator_fields_immutable_after_insert','data_placement']) then 'PERSISTENCE'
      else null
    end as target_layer
  from clauses
), mapped as (
  select c.clause_key,c.target_layer,
    case c.target_layer
      when 'CORE' then 'CANONICAL_CONTEXT'
      when 'SEMANTIC' then 'SEMANTIC_RESOLVER'
      when 'READINESS_POLICY' then 'READINESS_POLICY'
      when 'ORCHESTRATION' then 'AGENT_CURATOR_VALIDATOR_CONTRACT'
      when 'EVIDENCE' then 'EVIDENCE_AND_ASSURANCE'
      when 'PERSISTENCE' then 'PERSISTENCE_GUARD'
    end as target_owner,
    case c.target_layer
      when 'CORE' then 'DETERMINISTIC_CANONICAL_RESOLUTION'
      when 'SEMANTIC' then 'SEMANTIC_RESOLVER_OR_ASSERTION_ORACLE'
      when 'READINESS_POLICY' then 'FAIL_CLOSED_READINESS_POLICY'
      when 'ORCHESTRATION' then 'TYPED_LIFECYCLE_AND_IDENTITY_CONTRACT'
      when 'EVIDENCE' then 'EVIDENCE_READBACK_AND_DIGEST_BINDING'
      when 'PERSISTENCE' then 'DB_GUARD_CONSTRAINT_WRITE_BOUNDARY'
    end as target_enforcement
  from classified c
), live as (
  select m.*,
    coalesce((
      select array_agg(x.proname order by x.proname)
      from (
        select distinct p.proname
        from pg_proc p
        where p.pronamespace='programacion'::regnamespace
          and p.prosrc like '%'||m.clause_key||'%'
          and (p.proname like 'fn_input_%' or p.proname='fn_lf_router_input_governance_resolve_v1' or p.proname='fn_source_rule_authority')
      ) x
    ),'{}'::text[]) as fn_refs,
    coalesce((
      select array_agg(x.tgname order by x.tgname)
      from (
        select distinct tr.tgname
        from pg_trigger tr join pg_proc p on p.oid=tr.tgfoid
        where not tr.tgisinternal
          and p.prosrc like '%'||m.clause_key||'%'
          and tr.tgrelid::regclass::text like 'programacion.input_%'
      ) x
    ),'{}'::text[]) as trg_refs
  from mapped m
)
select clause_key,target_layer,target_owner,target_enforcement,
       fn_refs,trg_refs,
       case when cardinality(fn_refs)>0 or cardinality(trg_refs)>0
            then 'CURRENT_LOCATOR_OBSERVED_NOT_SEMANTIC_PROOF'
            else 'NO_DIRECT_LOCATOR_OBSERVED' end,
       case
         when clause_key='consumer' then array['M7_1_CONTRACT_SHA','M7_1_ROUTER_SHA']::text[]
         when clause_key like 'validator_%' then array['M7_1_CONTRACT_SHA','M7_1_VALIDATOR_SHA']::text[]
         when target_layer='CORE' then array['M7_1_CONTRACT_SHA','M7_1_REGISTRY_SHA']::text[]
         when target_layer='SEMANTIC' then array['M7_1_CONTRACT_SHA','M7_1_SEMANTIC_SHA']::text[]
         when target_layer='READINESS_POLICY' and clause_key='freshness_gate' then array['M7_1_CONTRACT_SHA','M7_1_CURRENTNESS_SHA']::text[]
         when target_layer='READINESS_POLICY' then array['M7_1_CONTRACT_SHA','M7_1_EXECUTION_SHA']::text[]
         when target_layer='ORCHESTRATION' then array['M7_1_CONTRACT_SHA','M7_1_EXECUTION_SHA']::text[]
         when target_layer='PERSISTENCE' then array['M7_1_CONTRACT_SHA','M7_1_CURATOR_SHA']::text[]
         else array['M7_1_CONTRACT_SHA']::text[]
       end,
       'PENDING_CLAUSE_SEMANTIC_TEST'
from live
order by clause_key;

do $$
declare
  v_count integer;
  v_unowned integer;
  v_contract_revision text;
  v_spec_md5 text;
  v_sha text;
  v_matrix_id bigint;
  v_rows integer;
begin
  select c.especificacion->>'contract_revision', md5(c.especificacion::text)
    into v_contract_revision,v_spec_md5
  from programacion.contratos c where c.id=37 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_contract_revision is distinct from '5.13' or v_spec_md5 is distinct from '1d9709b94d20ee8036ad985edffaaf01' then
    raise exception 'M1.A6 contract identity drift: revision %, md5 %',v_contract_revision,v_spec_md5;
  end if;

  select count(*),count(*) filter(where target_layer is null or target_owner is null or target_enforcement is null)
    into v_count,v_unowned
  from _m1a6_trace_rows;

  if v_count<>60 or v_unowned<>0 then
    raise exception 'M1.A6 trace matrix guard failed: rows %, unowned %',v_count,v_unowned;
  end if;

  select encode(digest(jsonb_agg(jsonb_build_object(
    'clause_key',clause_key,
    'target_layer',target_layer,
    'target_owner',target_owner,
    'target_enforcement',target_enforcement,
    'current_function_refs',to_jsonb(current_function_refs),
    'current_trigger_refs',to_jsonb(current_trigger_refs),
    'current_enforcement_status',current_enforcement_status,
    'integrity_test_refs',to_jsonb(integrity_test_refs),
    'semantic_test_status',semantic_test_status
  ) order by clause_key)::text,'sha256'),'hex') into v_sha
  from _m1a6_trace_rows;

  insert into programacion.contract_traceability_matrices(
    matrix_code,matrix_revision,contract_id,contract_revision,contract_spec_md5,
    source_plan_code,source_unit_code,source_event_id,
    upstream_classification_sha256,upstream_snapshot_sha256,locator_scope,
    matrix_sha256,clause_count,semantic_test_covered_count,semantic_test_pending_count,
    status,source_ref,created_by_execution_id
  ) values (
    'INPUT_READINESS_CONTRACT_5_13_TRACEABILITY',1,37,'5.13',v_spec_md5,
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M1.A6',19195,
    '2104c02aaa2828cfc0476ca9307c9eacb88db0e1090d9641c1d9971a692fe118',
    'c22492d0b7d4f3873b3cd595a12106683bcfd546947bd410c436b2338931e59f',
    'INPUT_GOVERNANCE_FUNCTIONS_AND_INPUT_TABLE_TRIGGERS_V1',
    v_sha,60,0,60,'DEFINED',
    'supabase://programacion.contratos/37#5.13',
    'CHATGPT-IG-CV-M1A6-SUPABASE-TRACE-20261001'
  ) returning id into v_matrix_id;

  insert into programacion.contract_traceability_rows(
    matrix_id,clause_key,target_layer,target_owner,target_enforcement,
    current_function_refs,current_trigger_refs,current_enforcement_status,
    integrity_test_refs,semantic_test_status,row_status,observed_at,source_ref,created_by_execution_id
  )
  select v_matrix_id,clause_key,target_layer,target_owner,target_enforcement,
         current_function_refs,current_trigger_refs,current_enforcement_status,
         integrity_test_refs,semantic_test_status,'DEFINED',now(),
         'supabase://programacion.contratos/37#5.13/'||clause_key,
         'CHATGPT-IG-CV-M1A6-SUPABASE-TRACE-20261001'
  from _m1a6_trace_rows
  order by clause_key;

  get diagnostics v_rows=row_count;
  if v_rows<>60 then raise exception 'M1.A6 inserted rows %',v_rows; end if;
end $$;

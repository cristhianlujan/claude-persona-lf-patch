-- RUN_TEST receipt mode v1.
-- Capability-bound executions retain binding/dispatch/operation requirements.
-- Explicit local test executions use suite graph + exact case ownership and do
-- not fabricate capability receipts that do not exist.

do $pre$
declare
  v_md5 text;
begin
  v_md5:=md5(pg_get_functiondef(
    'programacion.fn_engineering_run_test_receipt_bundle_v1(uuid)'::regprocedure
  ));
  if v_md5 is distinct from '0cd619d447f252e9fdb7f33ce6363f56' then
    raise exception 'RUN_TEST_RECEIPT_BUNDLE_BASE_DRIFT expected=0cd619d447f252e9fdb7f33ce6363f56 actual=%',v_md5;
  end if;
end;
$pre$;

create or replace function programacion.fn_engineering_run_test_receipt_bundle_v1(
  p_suite_run_id uuid
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','private','pg_catalog'
as $function$
with sr as materialized (
  select
    s.suite_run_id,
    s.suite_code,
    s.execution_id as suite_execution_id,
    s.status as suite_status,
    s.tests_total,
    s.tests_passed,
    s.tests_failed,
    s.tests_blocked,
    s.tests_review_required,
    s.manifest,
    s.metadata,
    nullif(s.manifest->>'binding_execution_id','') as binding_execution_id,
    case
      when nullif(s.manifest->>'binding_execution_id','') is not null
        then 'CAPABILITY_BOUND_EXECUTION'
      when s.manifest->>'receipt_mode'='LOCAL_DECLARED_TEST_EXECUTION'
        then 'LOCAL_DECLARED_TEST_EXECUTION'
      else 'UNRESOLVED'
    end as receipt_mode
  from public.lf_test_suite_runs s
  where s.suite_run_id=p_suite_run_id
),
binding as materialized (
  select
    b.execution_id,
    b.capability_code,
    b.binding_state,
    b.binding_mode,
    b.bound_by_execution_id,
    b.last_checked_by_execution_id
  from public.lf_capability_binding b
  join sr on sr.binding_execution_id=b.execution_id
),
dispatch_rows as materialized (
  select d.*
  from private.lf_orchestrator_dispatch_receipts_v1 d
  join sr on d.consumer_execution_id=sr.binding_execution_id
),
execution_ids as materialized (
  select binding_execution_id execution_id,'CONSUMER' role
  from sr where binding_execution_id is not null
  union
  select orchestrator_execution_id,'ORCHESTRATOR'
  from dispatch_rows
  where orchestrator_execution_id is not null
),
ops as materialized (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'role',ids.role,
        'execution_id',o.execution_id,
        'operation_code',o.operation_code,
        'status',o.status,
        'completed_at',o.completed_at
      )
      order by ids.role,o.execution_id
    ) filter (where o.execution_id is not null),
    '[]'::jsonb
  ) rows
  from execution_ids ids
  left join public.lf_operation_execution o on o.execution_id=ids.execution_id
),
test_graph as materialized (
  select
    count(distinct tr.test_run_id)::int test_run_count,
    count(ar.*)::int assertion_count,
    count(distinct tr.test_run_id) filter(where tr.status='PASS')::int test_runs_passed,
    count(ar.*) filter(where ar.status='PASS')::int assertions_passed
  from public.lf_test_runs tr
  left join public.lf_test_assertion_results ar on ar.test_run_id=tr.test_run_id
  where tr.suite_run_id=p_suite_run_id
),
local_ownership as materialized (
  select
    count(distinct tr.test_run_id)::int local_test_run_count,
    count(distinct tr.test_run_id) filter(
      where c.test_code is not null
        and c.metadata->>'unit_code'=sr.metadata->>'unit_code'
        and c.metadata->>'checkpoint_code'=sr.metadata->>'checkpoint_code'
    )::int owned_test_run_count
  from sr
  left join public.lf_test_runs tr on tr.suite_run_id=sr.suite_run_id
  left join public.lf_test_suite_cases c
    on c.suite_code=tr.suite_code and c.test_code=tr.test_code
  group by sr.metadata
),
dispatch as materialized (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'receipt_id',d.receipt_id,
        'orchestrator_execution_id',d.orchestrator_execution_id,
        'consumer_execution_id',d.consumer_execution_id,
        'capability_code',d.capability_code,
        'plan_digest',d.plan_digest,
        'receipt_sha256',d.receipt_sha256
      )
      order by d.issued_at desc
    ),
    '[]'::jsonb
  ) rows
  from dispatch_rows d
),
assembled as (
  select jsonb_build_object(
    'schema_version','ENGINEERING_RUN_TEST_RECEIPT_BUNDLE_V1_1',
    'suite_run_id',sr.suite_run_id,
    'receipt_mode',sr.receipt_mode,
    'suite',jsonb_build_object(
      'suite_code',sr.suite_code,
      'execution_id',sr.suite_execution_id,
      'status',sr.suite_status,
      'tests_total',sr.tests_total,
      'tests_passed',sr.tests_passed,
      'tests_failed',sr.tests_failed,
      'tests_blocked',sr.tests_blocked,
      'tests_review_required',sr.tests_review_required,
      'metadata',sr.metadata
    ),
    'binding',case when b.execution_id is null then null else jsonb_build_object(
      'execution_id',b.execution_id,
      'capability_code',b.capability_code,
      'binding_state',b.binding_state,
      'binding_mode',b.binding_mode,
      'bound_by_execution_id',b.bound_by_execution_id,
      'last_checked_by_execution_id',b.last_checked_by_execution_id
    ) end,
    'operation_receipts',(select rows from ops),
    'test_graph',jsonb_build_object(
      'test_run_count',tg.test_run_count,
      'assertion_count',tg.assertion_count,
      'test_runs_passed',tg.test_runs_passed,
      'assertions_passed',tg.assertions_passed
    ),
    'local_ownership',jsonb_build_object(
      'local_test_run_count',lo.local_test_run_count,
      'owned_test_run_count',lo.owned_test_run_count,
      'owner_unit',sr.metadata->>'unit_code',
      'checkpoint_code',sr.metadata->>'checkpoint_code'
    ),
    'dispatch_receipts',(select rows from dispatch),
    'verification',jsonb_build_object(
      'suite_passed',sr.suite_status='PASSED' and sr.tests_total=sr.tests_passed,
      'test_graph_complete',
        tg.test_run_count=sr.tests_total
        and tg.assertion_count>=sr.tests_total
        and tg.test_runs_passed=sr.tests_total
        and tg.assertions_passed>=sr.tests_total,
      'local_case_ownership_complete',
        lo.local_test_run_count=sr.tests_total
        and lo.owned_test_run_count=sr.tests_total,
      'binding_bound',coalesce(b.binding_state='BOUND',false),
      'consumer_operation_completed',exists(
        select 1
        from execution_ids ids
        join public.lf_operation_execution o on o.execution_id=ids.execution_id
        where ids.role='CONSUMER' and o.status='COMPLETED'
      ),
      'orchestrator_operation_completed',exists(
        select 1
        from execution_ids ids
        join public.lf_operation_execution o on o.execution_id=ids.execution_id
        where ids.role='ORCHESTRATOR' and o.status='COMPLETED'
      ),
      'dispatch_receipt_present',
        jsonb_array_length((select rows from dispatch))>0,
      'binding_required',sr.receipt_mode='CAPABILITY_BOUND_EXECUTION',
      'dispatch_required',sr.receipt_mode='CAPABILITY_BOUND_EXECUTION'
    )
  ) payload
  from sr
  left join binding b on true
  cross join test_graph tg
  cross join local_ownership lo
)
select case
  when payload is null then jsonb_build_object(
    'schema_version','ENGINEERING_RUN_TEST_RECEIPT_BUNDLE_V1_1',
    'status','NOT_FOUND',
    'suite_run_id',p_suite_run_id
  )
  else payload || jsonb_build_object(
    'status',case
      when payload->>'receipt_mode'='LOCAL_DECLARED_TEST_EXECUTION'
       and coalesce((payload#>>'{verification,suite_passed}')::boolean,false)
       and coalesce((payload#>>'{verification,test_graph_complete}')::boolean,false)
       and coalesce((payload#>>'{verification,local_case_ownership_complete}')::boolean,false)
      then 'VERIFIED'
      when payload->>'receipt_mode'='CAPABILITY_BOUND_EXECUTION'
       and coalesce((payload#>>'{verification,suite_passed}')::boolean,false)
       and coalesce((payload#>>'{verification,binding_bound}')::boolean,false)
       and coalesce((payload#>>'{verification,consumer_operation_completed}')::boolean,false)
       and coalesce((payload#>>'{verification,orchestrator_operation_completed}')::boolean,false)
       and coalesce((payload#>>'{verification,test_graph_complete}')::boolean,false)
       and coalesce((payload#>>'{verification,dispatch_receipt_present}')::boolean,false)
      then 'VERIFIED'
      else 'INCOMPLETE'
    end
  )
end
from assembled;
$function$;

comment on function programacion.fn_engineering_run_test_receipt_bundle_v1(uuid)
is 'Mode-aware RUN_TEST receipt verification. Capability-bound runs require binding/dispatch/consumer/orchestrator receipts. Explicit local runs require explicit manifest receipt_mode=LOCAL_DECLARED_TEST_EXECUTION plus suite PASS, complete test/assertion graph and exact unit/checkpoint case ownership.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-RUN-TEST-RECEIPT-MODE-001',
  'ENGINEERING_ORCHESTRATION',
  'RUN_TEST receipt requirements must match local vs capability-bound execution mode',
  'fn_engineering_run_test_receipt_bundle_v1 required capability binding, dispatch and consumer/orchestrator operation receipts for every suite run. This made a valid DECLARED_TEST_EXECUTION local test impossible to persist without fabricating capability receipts.',
  'The receipt bundle conflated capability-owned orchestration evidence with local exact-case RUN_TEST evidence.',
  'LOCAL_DECLARED_TEST_EXECUTION_FORCED_THROUGH_CAPABILITY_RECEIPT_REQUIREMENTS',
  'Require an explicit receipt mode. CAPABILITY_BOUND_EXECUTION preserves binding/dispatch/operation requirements. LOCAL_DECLARED_TEST_EXECUTION never fabricates capability receipts and verifies suite PASS, complete test/assertion graph and exact unit/checkpoint case ownership.',
  'PASS when a local declared test with explicit receipt_mode persists and receives VERIFIED from suite/test graph + ownership only; capability-bound runs still require binding, dispatch and completed consumer/orchestrator operations; unresolved mode remains INCOMPLETE.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_run_test_receipt_bundle_v1; supabase://programacion.fn_engineering_run_test_persist_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.6 CROSS_FAMILY_CASES RUN_TEST persistence',
  'supabase://programacion.fn_engineering_run_test_receipt_bundle_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

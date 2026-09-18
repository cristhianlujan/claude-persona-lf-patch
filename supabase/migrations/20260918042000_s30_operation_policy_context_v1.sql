-- S30 transversal operation policy consumer coverage v1.
-- Fixes EKB: OPERATION-POLICY-CONTEXT-AMBIGUOUS-NONE-001.
-- Architecture correction: do not invent NONE_EXPLICIT for operational consumers.
-- Reuse the existing four transversal LF policies and the existing policy snapshot engine.
-- No new policy table, resolver, lifecycle engine or policy mode column.

do $pre$
declare
  v_ops text[] := array[
    'ANALISIS_RIESGO_CONTENIDO_LF',
    'ESCRITURA_BASE_CONOCIMIENTO_LF',
    'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
    'EXTRACCION_FUENTES_DIGITALES_LF',
    'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
    'HOMOLOGACION_FUENTES_DIGITALES_LF',
    'ORQUESTACION_PIPELINE_LF',
    'VULNERABILITY_COVERAGE_REPAIR_LF'
  ];
  v_policies text[] := array[
    'POL-LF-OPERATION-LIFECYCLE',
    'POL-LF-POLICY-CONSUMPTION',
    'POL-LF-SOURCE-RESOLUTION',
    'POL-LF-STATE-MODEL'
  ];
  v_missing_ops text[];
  v_missing_policies text[];
  v_existing integer;
begin
  select array_agg(x order by x)
    into v_missing_ops
  from unnest(v_ops) x
  where not exists (
    select 1
    from public.lf_operation_registry r
    where r.operation_code=x
      and r.lifecycle_state_code='OP_OPERATIONAL'
  );
  if coalesce(array_length(v_missing_ops,1),0)<>0 then
    raise exception 'BLOCK_POLICY_COVERAGE_OPERATION_NOT_OPERATIONAL:%',v_missing_ops;
  end if;

  select array_agg(x order by x)
    into v_missing_policies
  from unnest(v_policies) x
  where not exists (
    select 1
    from public.lf_policy_versions p
    where p.policy_code=x
      and p.status='ACTIVE'
      and p.policy_sha ~ '^[0-9a-f]{64}$'
  );
  if coalesce(array_length(v_missing_policies,1),0)<>0 then
    raise exception 'BLOCK_POLICY_COVERAGE_ACTIVE_POLICY_MISSING:%',v_missing_policies;
  end if;

  select count(*) into v_existing
  from public.lf_operation_policy_bindings b
  where b.operation_code=any(v_ops)
    and b.binding_status='ACTIVE';
  if v_existing<>0 then
    raise exception 'BLOCK_POLICY_COVERAGE_PREEXISTING_BINDINGS:%',v_existing;
  end if;
end
$pre$;

-- Create one governed provenance execution per consumer operation.
-- These executions exist only to record the operation-owned policy binding change.
insert into public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id,idempotency_key,request_sha256,lease_fence
)
select
  'EXEC-POLICY-COVERAGE-' || replace(operation_code,'_','-') || '-20260918-001',
  operation_code,
  'POLICY_BINDING',
  'TRANSVERSAL_POLICY_COVERAGE_V1',
  'IN_PROGRESS',
  jsonb_build_object(
    'scope','TRANSVERSAL_POLICY_CONSUMER_COVERAGE_V1',
    'policy_bundle',jsonb_build_array(
      'POL-LF-OPERATION-LIFECYCLE',
      'POL-LF-POLICY-CONSUMPTION',
      'POL-LF-SOURCE-RESOLUTION',
      'POL-LF-STATE-MODEL'
    ),
    'source_migration','20260918042000_s30_operation_policy_context_v1.sql',
    'production_activation',false
  ),
  'EXEC-POLICY-COVERAGE-' || replace(operation_code,'_','-') || '-20260918-001',
  'EXEC-POLICY-COVERAGE-' || replace(operation_code,'_','-') || '-20260918-001',
  'POLICY:COVERAGE:' || operation_code || ':20260918:001',
  encode(
    extensions.digest(
      convert_to('POLICY:COVERAGE:' || operation_code || ':20260918:001','UTF8'),
      'sha256'
    ),
    'hex'
  ),
  1
from unnest(array[
  'ANALISIS_RIESGO_CONTENIDO_LF',
  'ESCRITURA_BASE_CONOCIMIENTO_LF',
  'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
  'EXTRACCION_FUENTES_DIGITALES_LF',
  'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
  'HOMOLOGACION_FUENTES_DIGITALES_LF',
  'ORQUESTACION_PIPELINE_LF',
  'VULNERABILITY_COVERAGE_REPAIR_LF'
]) operation_code;

-- Materialize the existing transversal policy bundle as explicit consumer bindings.
with ops(operation_code) as (
  values
  ('ANALISIS_RIESGO_CONTENIDO_LF'),
  ('ESCRITURA_BASE_CONOCIMIENTO_LF'),
  ('EXTRACCION_DOCUMENTOS_REGULATORIOS_LF'),
  ('EXTRACCION_FUENTES_DIGITALES_LF'),
  ('EXTRACCION_NOTICIAS_FINANCIERAS_LF'),
  ('HOMOLOGACION_FUENTES_DIGITALES_LF'),
  ('ORQUESTACION_PIPELINE_LF'),
  ('VULNERABILITY_COVERAGE_REPAIR_LF')
),
policies(policy_code,policy_role) as (
  values
  ('POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE'),
  ('POL-LF-POLICY-CONSUMPTION','POLICY_CONSUMPTION'),
  ('POL-LF-SOURCE-RESOLUTION','SOURCE_RESOLUTION'),
  ('POL-LF-STATE-MODEL','STATE_MODEL')
)
insert into public.lf_operation_policy_bindings(
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,
  created_by_execution_id,updated_by_execution_id
)
select
  o.operation_code,
  p.policy_code,
  p.policy_role,
  true,
  array['DIRECT']::text[],
  'ACTIVE',
  'EXEC-POLICY-COVERAGE-' || replace(o.operation_code,'_','-') || '-20260918-001',
  'EXEC-POLICY-COVERAGE-' || replace(o.operation_code,'_','-') || '-20260918-001'
from ops o
cross join policies p;

-- Backfill the exact start snapshot into the eight policy-registration executions,
-- then close them through the existing immutable lifecycle guard.
with snapshots as (
  select
    e.execution_id,
    e.operation_code,
    e.started_at,
    jsonb_object_agg(
      p.policy_role,
      case
        when p.binding_updated_at is null then
          jsonb_build_object(
            'policy_code',p.policy_code,
            'policy_version',p.policy_version,
            'policy_sha',p.policy_sha,
            'effective_at',p.effective_at
          )
        else
          jsonb_build_object(
            'policy_code',p.policy_code,
            'policy_version',p.policy_version,
            'policy_sha',p.policy_sha,
            'policy_payload',p.policy_payload,
            'distribution_modes',to_jsonb(p.distribution_modes),
            'effective_at',p.effective_at,
            'source_ref',p.source_ref
          )
      end
      order by p.policy_role
    ) as policy_snapshots
  from public.lf_operation_execution e
  join public.v_lf_operation_policy_snapshot p
    on p.operation_code=e.operation_code
   and p.policy_sha is not null
  where e.execution_id like 'EXEC-POLICY-COVERAGE-%-20260918-001'
    and e.target_code='TRANSVERSAL_POLICY_COVERAGE_V1'
  group by e.execution_id,e.operation_code,e.started_at
)
update public.lf_operation_execution e
set manifest =
      e.manifest
      || jsonb_build_object(
        'operation_policy_snapshots',s.policy_snapshots,
        'operation_policy_snapshot_at',e.started_at,
        'operation_policy_source','SUPABASE',
        'policy_binding_count',4,
        'policy_binding_result','PASS_CLOSED'
      ),
    status='COMPLETED',
    completed_at=clock_timestamp(),
    checkpoint_seq=1,
    checkpoint_payload=jsonb_build_object(
      'state','PASS_CLOSED',
      'policy_binding_count',4,
      'policy_codes',jsonb_build_array(
        'POL-LF-OPERATION-LIFECYCLE',
        'POL-LF-POLICY-CONSUMPTION',
        'POL-LF-SOURCE-RESOLUTION',
        'POL-LF-STATE-MODEL'
      )
    ),
    updated_by_execution_id=e.execution_id
from snapshots s
where e.execution_id=s.execution_id;

do $post$
declare
  v_ops text[] := array[
    'ANALISIS_RIESGO_CONTENIDO_LF',
    'ESCRITURA_BASE_CONOCIMIENTO_LF',
    'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
    'EXTRACCION_FUENTES_DIGITALES_LF',
    'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
    'HOMOLOGACION_FUENTES_DIGITALES_LF',
    'ORQUESTACION_PIPELINE_LF',
    'VULNERABILITY_COVERAGE_REPAIR_LF'
  ];
  v_bad text[];
  v_binding_count integer;
  v_execution_count integer;
begin
  select count(*) into v_binding_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=any(v_ops)
    and b.binding_status='ACTIVE'
    and b.required
    and b.policy_code=any(array[
      'POL-LF-OPERATION-LIFECYCLE',
      'POL-LF-POLICY-CONSUMPTION',
      'POL-LF-SOURCE-RESOLUTION',
      'POL-LF-STATE-MODEL'
    ]);
  if v_binding_count<>32 then
    raise exception 'BLOCK_POLICY_COVERAGE_BINDING_COUNT:%',v_binding_count;
  end if;

  select array_agg(operation_code order by operation_code)
    into v_bad
  from (
    select r.operation_code
    from public.lf_operation_registry r
    where r.operation_code=any(v_ops)
      and (
        select count(*)
        from public.v_lf_operation_policy_snapshot p
        where p.operation_code=r.operation_code
          and p.required
          and p.policy_sha is not null
      )<>4
  ) q;
  if coalesce(array_length(v_bad,1),0)<>0 then
    raise exception 'BLOCK_POLICY_COVERAGE_SNAPSHOT_COUNT:%',v_bad;
  end if;

  select count(*) into v_execution_count
  from public.lf_operation_execution e
  where e.execution_id like 'EXEC-POLICY-COVERAGE-%-20260918-001'
    and e.target_code='TRANSVERSAL_POLICY_COVERAGE_V1'
    and e.status='COMPLETED'
    and e.checkpoint_payload->>'state'='PASS_CLOSED'
    and jsonb_typeof(e.manifest->'operation_policy_snapshots')='object';
  if v_execution_count<>8 then
    raise exception 'BLOCK_POLICY_COVERAGE_EXECUTION_CLOSE_COUNT:%',v_execution_count;
  end if;
end
$post$;

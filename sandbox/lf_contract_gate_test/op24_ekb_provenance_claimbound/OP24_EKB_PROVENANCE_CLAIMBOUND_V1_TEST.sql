\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_CLAIMBOUND_V1.sql

do $verify$
declare
  v_manifest_id bigint;
  v_bound integer;
begin
  select id into v_manifest_id
  from public.lf_eventos
  where entidad_codigo='LF_LEARNED_CONTEXT_MEMORY_OPERATIONAL_PLAN_20260904'
    and payload->>'checkpoint_id'='GPT_CP_OP24_P1_CONTAINER_CLAIM_BINDING_001';

  select count(*) into v_bound
  from transversal.error_knowledge e
  where e.source_ref like '%|supabase://mhwmirqcgxxukpctffuv/public/lf_eventos/'||v_manifest_id::text||'#binding=%';

  if v_bound <> 41 then
    raise exception 'OP24_CLAIM_BOUND_TEST_EXPECTED_41 observed=%',v_bound;
  end if;
end
$verify$;

rollback;

do $post$
declare
  v_nonnull integer;
begin
  select count(*) into v_nonnull
  from transversal.error_knowledge
  where codigo in (
    select value->>'code'
    from public.lf_eventos e
    cross join lateral jsonb_array_elements(e.payload->'bindings') value
    where e.entidad_codigo='LF_LEARNED_CONTEXT_MEMORY_OPERATIONAL_PLAN_20260904'
      and e.payload->>'checkpoint_id'='GPT_CP_OP24_P1_CONTAINER_CLAIM_BINDING_001'
  ) and source_ref is not null;

  if v_nonnull <> 0 then
    raise exception 'OP24_CLAIM_BOUND_TEST_LEFT_DURABLE_SOURCE_REFS:%',v_nonnull;
  end if;
end
$post$;

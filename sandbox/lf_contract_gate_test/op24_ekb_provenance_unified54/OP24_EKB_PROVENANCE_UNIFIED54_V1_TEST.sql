\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_UNIFIED54_V1.sql

do $verify$
declare
  v_bound integer;
begin
  select count(*) into v_bound
  from transversal.error_knowledge k
  where k.source_ref like '%supabase://mhwmirqcgxxukpctffuv/public/lf_eventos/%#binding=%'
    and k.codigo in (
      select b->>'code' from public.lf_eventos e, jsonb_array_elements(e.payload->'bindings') b
      where e.payload->>'checkpoint_id' in (
        'GPT_CP_OP24_P1_CONTAINER_CLAIM_BINDING_001',
        'GPT_CP_OP24_P1_EXACT_CLAIM_BINDING_001'
      )
    );
  if v_bound <> 54 then
    raise exception 'OP24_P1_TEST_EXPECTED_54_BOUND observed=%',v_bound;
  end if;
end
$verify$;

rollback;

do $post$
declare
  v_total integer;
  v_null integer;
  v_nonnull integer;
begin
  with targets as (
    select distinct b->>'code' code
    from public.lf_eventos e, jsonb_array_elements(e.payload->'bindings') b
    where e.payload->>'checkpoint_id' in (
      'GPT_CP_OP24_P1_CONTAINER_CLAIM_BINDING_001',
      'GPT_CP_OP24_P1_EXACT_CLAIM_BINDING_001'
    )
  )
  select count(*),count(*) filter(where k.source_ref is null),count(*) filter(where k.source_ref is not null)
    into v_total,v_null,v_nonnull
  from targets t join transversal.error_knowledge k on k.codigo=t.code;

  if v_total <> 54 or v_null <> 54 or v_nonnull <> 0 then
    raise exception 'OP24_P1_POST_ROLLBACK_RESIDUE total=% null=% nonnull=%',v_total,v_null,v_nonnull;
  end if;
end
$post$;

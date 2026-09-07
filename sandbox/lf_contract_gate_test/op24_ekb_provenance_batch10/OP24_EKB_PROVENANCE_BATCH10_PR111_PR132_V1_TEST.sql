\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_BATCH10_PR111_PR132_V1.sql

do $assert$
declare
  v_total integer;
  v_bound integer;
begin
  select count(*),
         count(*) filter (where source_ref in (
           'github://cristhianlujan/claude-persona-lf-patch/pull/111',
           'github://cristhianlujan/claude-persona-lf-patch/pull/132'
         ))
    into v_total,v_bound
  from transversal.error_knowledge
  where codigo in ('EKB-P0-015','EKB-PR111-004');
  if v_total<>2 or v_bound<>2 then
    raise exception 'BATCH10_ASSERT_FAIL total=% bound=%',v_total,v_bound;
  end if;
end
$assert$;

rollback;

do $post$
declare
  v_nonnull integer;
begin
  select count(*) into v_nonnull
  from transversal.error_knowledge
  where codigo in ('EKB-P0-015','EKB-PR111-004') and source_ref is not null;
  if v_nonnull<>0 then
    raise exception 'BATCH10_ROLLBACK_RESIDUE:%',v_nonnull;
  end if;
end
$post$;

\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_BATCH9_PR115_PR133_V1.sql

do $assert$
declare
  v_total integer;
  v_bound integer;
begin
  select count(*),
         count(*) filter (where source_ref in (
           'github://cristhianlujan/claude-persona-lf-patch/pull/115',
           'github://cristhianlujan/claude-persona-lf-patch/pull/133'
         ))
    into v_total,v_bound
  from transversal.error_knowledge
  where codigo in ('AUD-020','CLI-001','EKB-P0-016','EKB-P0-019','PERF-001','RTE-007');

  if v_total<>6 or v_bound<>6 then
    raise exception 'BATCH9_ASSERT_FAIL total=% bound=%',v_total,v_bound;
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
  where codigo in ('AUD-020','CLI-001','EKB-P0-016','EKB-P0-019','PERF-001','RTE-007')
    and source_ref is not null;
  if v_nonnull<>0 then
    raise exception 'BATCH9_ROLLBACK_RESIDUE:%',v_nonnull;
  end if;
end
$post$;

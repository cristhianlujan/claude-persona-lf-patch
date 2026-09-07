\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_BATCH8_PR93_V1.sql

do $assert$
declare
  v_total integer;
  v_bound integer;
  v_bad_pr integer;
begin
  select count(*),
         count(*) filter (where source_ref='github://cristhianlujan/claude-persona-lf-patch/pull/93'),
         count(*) filter (where regexp_replace(coalesce(pr,''),'[^0-9]','','g')<>'93')
    into v_total,v_bound,v_bad_pr
  from transversal.error_knowledge
  where codigo in ('GOV-008','RTE-006','UX-001');

  if v_total<>3 or v_bound<>3 or v_bad_pr<>0 then
    raise exception 'BATCH8_ASSERT_FAIL total=% bound=% bad_pr=%',v_total,v_bound,v_bad_pr;
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
  where codigo in ('GOV-008','RTE-006','UX-001') and source_ref is not null;
  if v_nonnull<>0 then
    raise exception 'BATCH8_ROLLBACK_RESIDUE:%',v_nonnull;
  end if;
end
$post$;

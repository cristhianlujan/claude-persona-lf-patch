\set ON_ERROR_STOP on

begin;

\ir OP24_EKB_PROVENANCE_BATCH3_V1.sql

do $assert$
declare
  v_total integer;
  v_bound integer;
  v_bad integer;
begin
  select count(*),
         count(*) filter (where source_ref='github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda'),
         count(*) filter (where position('PR115@f40d8063' in coalesce(evidencia,''))=0)
    into v_total,v_bound,v_bad
  from transversal.error_knowledge
  where codigo in ('EKB-P0-001','EKB-P0-005','EKB-P0-007','EKB-P0-008','EKB-P0-012');

  if v_total<>5 or v_bound<>5 or v_bad<>0 then
    raise exception 'BATCH3_ASSERT_FAIL total=% bound=% bad=%',v_total,v_bound,v_bad;
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
  where codigo in ('EKB-P0-001','EKB-P0-005','EKB-P0-007','EKB-P0-008','EKB-P0-012')
    and source_ref is not null;
  if v_nonnull<>0 then
    raise exception 'BATCH3_ROLLBACK_RESIDUE:%',v_nonnull;
  end if;
end
$post$;

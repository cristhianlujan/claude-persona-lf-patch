\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_BATCH4_V1.sql

do $assert$
declare
  v_total integer;
  v_bound integer;
  v_bad integer;
begin
  select count(*),
         count(*) filter (where source_ref is not null),
         count(*) filter (
           where (codigo='AUD-012' and position('a6bf03ac1660f09bf0e2d09b215b0e7f8c1fe6d2' in coalesce(evidencia,''))=0)
              or (codigo='EKB-P0-006' and position('84f8234440fe5f2dcfd163fa2b99b1318b2aa776' in coalesce(evidencia,''))=0)
              or (codigo='EKB-PR111-003' and position('baa06972161de32a8c334c4f2e686a4ff74a241afad5c64edc2cbb23066c2a72' in coalesce(evidencia,''))=0)
         )
    into v_total,v_bound,v_bad
  from transversal.error_knowledge
  where codigo in ('AUD-012','EKB-P0-006','EKB-PR111-003');

  if v_total<>3 or v_bound<>3 or v_bad<>0 then
    raise exception 'BATCH4_ASSERT_FAIL total=% bound=% bad=%',v_total,v_bound,v_bad;
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
  where codigo in ('AUD-012','EKB-P0-006','EKB-PR111-003')
    and source_ref is not null;
  if v_nonnull<>0 then
    raise exception 'BATCH4_ROLLBACK_RESIDUE:%',v_nonnull;
  end if;
end
$post$;

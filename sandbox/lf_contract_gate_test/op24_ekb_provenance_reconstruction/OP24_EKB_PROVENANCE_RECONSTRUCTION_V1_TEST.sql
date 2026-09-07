\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_RECONSTRUCTION_V1.sql

do $test$
declare
  v_source_ref text := 'github://cristhianlujan/claude-persona-lf-patch/commit/f40d8063fc8a8bc5c4a22ba29a7e9a4be8127dda';
  v_count integer;
begin
  select count(*) into v_count
  from transversal.error_knowledge e
  where e.codigo in ('EKB-P0-001','EKB-P0-005','EKB-P0-007','EKB-P0-008','EKB-P0-012')
    and e.source_ref = v_source_ref;
  if v_count <> 5 then
    raise exception 'EXPECTED_FIVE_RECONSTRUCTED_REFS observed=%', v_count;
  end if;

  if exists (
    select 1
    from transversal.error_knowledge e
    where e.codigo in ('EKB-P0-001','EKB-P0-005','EKB-P0-007','EKB-P0-008','EKB-P0-012')
      and e.evidencia not like '%PR115@f40d8063%'
  ) then
    raise exception 'TARGET_EVIDENCE_BINDING_LOST';
  end if;
end
$test$;

rollback;

do $post$
begin
  if exists (
    select 1
    from transversal.error_knowledge e
    where e.codigo in ('EKB-P0-001','EKB-P0-005','EKB-P0-007','EKB-P0-008','EKB-P0-012')
      and e.source_ref is not null
  ) then
    raise exception 'ROLLBACK_DID_NOT_RESTORE_SOURCE_REF_NULL';
  end if;
end
$post$;

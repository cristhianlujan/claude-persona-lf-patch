\set ON_ERROR_STOP on

begin;
\ir OP24_EKB_PROVENANCE_RECONSTRUCTION_BATCH2.sql

-- All five candidates must be set inside the transaction.
do $assert$
declare
  v_count integer;
begin
  select count(*) into v_count
  from transversal.error_knowledge
  where codigo in ('CI-004','EKB-P0-013','EKB-PR111-001','EKB-PR111-002','EKB-PR111-007')
    and source_ref is not null;
  if v_count <> 5 then
    raise exception 'OP24_BATCH2_TEST_EXPECTED_5:%', v_count;
  end if;
end
$assert$;

rollback;

-- Postcondition: no durable EKB mutation.
do $postrollback$
declare
  v_nonnull integer;
begin
  select count(*) into v_nonnull
  from transversal.error_knowledge
  where codigo in ('CI-004','EKB-P0-013','EKB-PR111-001','EKB-PR111-002','EKB-PR111-007')
    and source_ref is not null;
  if v_nonnull <> 0 then
    raise exception 'OP24_BATCH2_ROLLBACK_RESIDUE:%', v_nonnull;
  end if;
end
$postrollback$;

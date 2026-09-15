\set ON_ERROR_STOP on

begin;
\ir OP24_LEARNED_CONTEXT_LINEAGE_V1.sql

-- Positive: one-to-one.
insert into private.sbx_lf_learned_context_lineage_v1(
  transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
  disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
) values (
  '00000000-0000-0000-0000-000000000001','KB','KB:1','CARD','CARD:1','TRANSFORMED_TO',
  'fixture','evidence://1','authority://1',true,'OP24-LINEAGE-TEST'
);

-- Positive: split, one source to many targets in the same transformation group.
insert into private.sbx_lf_learned_context_lineage_v1(
  transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
  disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
) values
('00000000-0000-0000-0000-000000000002','KB','KB:2','CARD','CARD:2A','SPLIT_INTO','fixture','evidence://2','authority://1',true,'OP24-LINEAGE-TEST'),
('00000000-0000-0000-0000-000000000002','KB','KB:2','CARD','CARD:2B','SPLIT_INTO','fixture','evidence://2','authority://1',true,'OP24-LINEAGE-TEST');

-- Positive: merge, many sources to one target in the same transformation group.
insert into private.sbx_lf_learned_context_lineage_v1(
  transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
  disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
) values
('00000000-0000-0000-0000-000000000003','KB','KB:3A','CARD','CARD:3','MERGED_INTO','fixture','evidence://3','authority://1',true,'OP24-LINEAGE-TEST'),
('00000000-0000-0000-0000-000000000003','KB','KB:3B','CARD','CARD:3','MERGED_INTO','fixture','evidence://3','authority://1',true,'OP24-LINEAGE-TEST');

do $test$
begin
  -- Negative: self-loop must be rejected by the table constraint.
  begin
    insert into private.sbx_lf_learned_context_lineage_v1(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values (
      '00000000-0000-0000-0000-000000000004','KB','KB:4','KB','KB:4','SUPERSEDES',
      'fixture','evidence://4','authority://1',true,'OP24-LINEAGE-TEST'
    );
    raise exception 'EXPECTED_SELF_LOOP_REJECTION';
  exception when check_violation then
    null;
  end;

  -- Negative: missing evidence must be rejected.
  begin
    insert into private.sbx_lf_learned_context_lineage_v1(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values (
      '00000000-0000-0000-0000-000000000005','KB','KB:5','CARD','CARD:5','MOVED_TO',
      'fixture','', 'authority://1',true,'OP24-LINEAGE-TEST'
    );
    raise exception 'EXPECTED_EVIDENCE_REJECTION';
  exception when check_violation then
    null;
  end;
end
$test$;

-- Adversarial: an indirect SUPERSEDES cycle is detected by the verifier.
insert into private.sbx_lf_learned_context_lineage_v1(
  transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
  disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
) values
('00000000-0000-0000-0000-000000000006','KB','KB:A','KB','KB:B','SUPERSEDES','fixture','evidence://6','authority://1',true,'OP24-LINEAGE-TEST'),
('00000000-0000-0000-0000-000000000007','KB','KB:B','KB','KB:A','SUPERSEDES','fixture','evidence://7','authority://1',true,'OP24-LINEAGE-TEST');

do $test$
begin
  if private.sbx_fn_lf_learned_context_lineage_cycle_v1('SUPERSEDES') is distinct from true then
    raise exception 'EXPECTED_CYCLE_DETECTION';
  end if;
end
$test$;

rollback;

-- Postcondition: rollback-only test leaves no sandbox object behind.
do $post$
begin
  if to_regclass('private.sbx_lf_learned_context_lineage_v1') is not null then
    raise exception 'LINEAGE_TEST_LEFT_TABLE_RESIDUE';
  end if;
  if to_regprocedure('private.sbx_fn_lf_learned_context_lineage_cycle_v1(text)') is not null then
    raise exception 'LINEAGE_TEST_LEFT_FUNCTION_RESIDUE';
  end if;
end
$post$;

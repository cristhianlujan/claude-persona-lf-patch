\set ON_ERROR_STOP on

begin;
\ir OP24_LEARNED_CONTEXT_LINEAGE_V2.sql

do $test$
declare
  kb1 text; kb2 text; card1 text; card2 text; ekb1 text; exec_id text;
  failed boolean;
begin
  select kb_id::text into kb1 from public.lf_knowledge_base order by created_at desc limit 1;
  select kb_id::text into kb2 from public.lf_knowledge_base where kb_id::text<>kb1 order by created_at desc limit 1;
  select id_card into card1 from public.lf_cards order by updated_at desc limit 1;
  select id_card into card2 from public.lf_cards where id_card<>card1 order by updated_at desc limit 1;
  select codigo into ekb1 from public.lf_error_knowledge where codigo is not null order by updated_at desc nulls last limit 1;
  select execution_id into exec_id from public.lf_operation_execution order by created_at desc limit 1;
  if kb1 is null or kb2 is null or card1 is null or card2 is null or ekb1 is null or exec_id is null then
    raise exception 'LINEAGE_FIXTURE_SOURCE_MISSING';
  end if;

  insert into private.sbx_lf_learned_context_lineage_v2(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
  ) values(gen_random_uuid(),'KB',kb1,'CARD',card1,'TRANSFORMED_TO','fixture','evidence://1','authority://1',true,exec_id);

  insert into private.sbx_lf_learned_context_lineage_v2(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
  ) values
  ('10000000-0000-4000-8000-000000000001','KB',kb1,'CARD',card1,'SPLIT_INTO','fixture','evidence://2','authority://1',true,exec_id),
  ('10000000-0000-4000-8000-000000000001','KB',kb1,'CARD',card2,'SPLIT_INTO','fixture','evidence://2','authority://1',true,exec_id);

  insert into private.sbx_lf_learned_context_lineage_v2(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
  ) values
  ('20000000-0000-4000-8000-000000000001','KB',kb1,'CARD',card1,'MERGED_INTO','fixture','evidence://3','authority://1',true,exec_id),
  ('20000000-0000-4000-8000-000000000001','KB',kb2,'CARD',card1,'MERGED_INTO','fixture','evidence://3','authority://1',true,exec_id);

  insert into private.sbx_lf_learned_context_lineage_v2(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
  ) values(gen_random_uuid(),'EKB',ekb1,'CARD',card1,'DERIVED_FROM','fixture','evidence://4','authority://1',true,exec_id);

  failed:=false;
  begin
    insert into private.sbx_lf_learned_context_lineage_v2(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values(gen_random_uuid(),'EKB','EKB-DOES-NOT-EXIST','CARD',card1,'DERIVED_FROM','fixture','evidence://5','authority://1',true,exec_id);
  exception when others then failed:=sqlerrm like 'LINEAGE_SOURCE_REF_NOT_RESOLVED:%'; end;
  if failed is not true then raise exception 'MISSING_SOURCE_MUST_REJECT'; end if;

  failed:=false;
  begin
    insert into private.sbx_lf_learned_context_lineage_v2(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values(gen_random_uuid(),'KB',kb1,'CARD','CARD-DOES-NOT-EXIST','TRANSFORMED_TO','fixture','evidence://6','authority://1',true,exec_id);
  exception when others then failed:=sqlerrm like 'LINEAGE_TARGET_REF_NOT_RESOLVED:%'; end;
  if failed is not true then raise exception 'MISSING_TARGET_MUST_REJECT'; end if;

  failed:=false;
  begin
    insert into private.sbx_lf_learned_context_lineage_v2(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values(gen_random_uuid(),'KB',kb1,'CARD',card1,'MOVED_TO','fixture','evidence://7','authority://1',true,'EXEC-DOES-NOT-EXIST');
  exception when others then failed:=sqlerrm like 'LINEAGE_EXECUTION_PROVENANCE_NOT_RESOLVED:%'; end;
  if failed is not true then raise exception 'ORPHAN_EXECUTION_MUST_REJECT'; end if;

  failed:=false;
  begin
    insert into private.sbx_lf_learned_context_lineage_v2(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values(gen_random_uuid(),'KB',kb1,'KB',kb1,'SUPERSEDES','fixture','evidence://8','authority://1',true,exec_id);
  exception when others then failed:=sqlerrm='LINEAGE_SELF_LOOP_FORBIDDEN'; end;
  if failed is not true then raise exception 'SELF_LOOP_MUST_REJECT'; end if;

  insert into private.sbx_lf_learned_context_lineage_v2(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
  ) values(gen_random_uuid(),'KB',kb1,'KB',kb2,'SUPERSEDES','fixture','evidence://9','authority://1',false,exec_id);

  failed:=false;
  begin
    insert into private.sbx_lf_learned_context_lineage_v2(
      transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
      disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
    ) values(gen_random_uuid(),'KB',kb2,'KB',kb1,'SUPERSEDES','fixture','evidence://10','authority://1',false,exec_id);
  exception when others then failed:=sqlerrm='LINEAGE_SUPERSESSION_CYCLE_FORBIDDEN'; end;
  if failed is not true then raise exception 'SUPERSESSION_CYCLE_MUST_REJECT'; end if;

  failed:=false;
  begin
    update private.sbx_lf_learned_context_lineage_v2 set disposition_reason='mutated' where relation_type='TRANSFORMED_TO';
  exception when others then failed:=sqlerrm='LINEAGE_EDGES_ARE_APPEND_ONLY'; end;
  if failed is not true then raise exception 'LINEAGE_UPDATE_MUST_REJECT'; end if;

  failed:=false;
  begin
    delete from private.sbx_lf_learned_context_lineage_v2 where relation_type='TRANSFORMED_TO';
  exception when others then failed:=sqlerrm='LINEAGE_EDGES_ARE_APPEND_ONLY'; end;
  if failed is not true then raise exception 'LINEAGE_DELETE_MUST_REJECT'; end if;
end
$test$;

rollback;

do $post$
begin
  if to_regclass('private.sbx_lf_learned_context_lineage_v2') is not null then raise exception 'LINEAGE_V2_TABLE_RESIDUE'; end if;
  if to_regprocedure('private.sbx_fn_lf_lineage_ref_resolves_v2(text,text)') is not null then raise exception 'LINEAGE_V2_RESOLVER_RESIDUE'; end if;
  if to_regprocedure('private.sbx_fn_lf_lineage_guard_v2()') is not null then raise exception 'LINEAGE_V2_GUARD_RESIDUE'; end if;
  if to_regprocedure('private.sbx_fn_lf_lineage_append_only_v2()') is not null then raise exception 'LINEAGE_V2_APPEND_ONLY_RESIDUE'; end if;
end
$post$;

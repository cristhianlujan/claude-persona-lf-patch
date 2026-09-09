\set ON_ERROR_STOP on

begin;
\ir OP24_LEARNED_CONTEXT_LINEAGE_DURABLE_CANDIDATE_V1.sql

do $test$
declare
  kb1 text; kb2 text; card1 text; card2 text; ekb1 text; exec_id text;
  edge_id bigint; failed boolean;
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

  edge_id := programacion.record_learned_context_lineage_v1(
    'EKB',ekb1,'CARD',card1,'TRANSFORMED_TO',exec_id,
    jsonb_build_object('disposition_reason','Experience promoted to Card candidate','evidence_ref','evidence://g4/positive','authority_ref','Strategy24:v0.3','reversible',true)
  );
  if edge_id is null then raise exception 'LINEAGE_RECORDER_ID_REQUIRED'; end if;

  perform programacion.record_learned_context_lineage_v1(
    'KB',kb1,'CARD',card1,'SPLIT_INTO',exec_id,
    jsonb_build_object('transformation_group_id','10000000-0000-4000-8000-000000000001','disposition_reason','split','evidence_ref','evidence://split','authority_ref','Strategy24:v0.3','reversible',true)
  );
  perform programacion.record_learned_context_lineage_v1(
    'KB',kb1,'CARD',card2,'SPLIT_INTO',exec_id,
    jsonb_build_object('transformation_group_id','10000000-0000-4000-8000-000000000001','disposition_reason','split','evidence_ref','evidence://split','authority_ref','Strategy24:v0.3','reversible',true)
  );

  perform programacion.record_learned_context_lineage_v1(
    'KB',kb1,'CARD',card1,'MERGED_INTO',exec_id,
    jsonb_build_object('transformation_group_id','20000000-0000-4000-8000-000000000001','disposition_reason','merge','evidence_ref','evidence://merge','authority_ref','Strategy24:v0.3','reversible',true)
  );
  perform programacion.record_learned_context_lineage_v1(
    'KB',kb2,'CARD',card1,'MERGED_INTO',exec_id,
    jsonb_build_object('transformation_group_id','20000000-0000-4000-8000-000000000001','disposition_reason','merge','evidence_ref','evidence://merge','authority_ref','Strategy24:v0.3','reversible',true)
  );

  failed:=false;
  begin
    perform programacion.record_learned_context_lineage_v1('EKB','EKB-DOES-NOT-EXIST','CARD',card1,'DERIVED_FROM',exec_id,jsonb_build_object('disposition_reason','x','evidence_ref','e://x','authority_ref','a://x','reversible',true));
  exception when others then failed:=sqlerrm like 'LINEAGE_SOURCE_REF_NOT_RESOLVED:%'; end;
  if failed is not true then raise exception 'MISSING_SOURCE_MUST_REJECT'; end if;

  failed:=false;
  begin
    perform programacion.record_learned_context_lineage_v1('KB',kb1,'CARD','CARD-DOES-NOT-EXIST','TRANSFORMED_TO',exec_id,jsonb_build_object('disposition_reason','x','evidence_ref','e://x','authority_ref','a://x','reversible',true));
  exception when others then failed:=sqlerrm like 'LINEAGE_TARGET_REF_NOT_RESOLVED:%'; end;
  if failed is not true then raise exception 'MISSING_TARGET_MUST_REJECT'; end if;

  failed:=false;
  begin
    perform programacion.record_learned_context_lineage_v1('KB',kb1,'CARD',card1,'MOVED_TO','EXEC-DOES-NOT-EXIST',jsonb_build_object('disposition_reason','x','evidence_ref','e://x','authority_ref','a://x','reversible',true));
  exception when others then failed:=sqlerrm like 'LINEAGE_EXECUTION_PROVENANCE_NOT_RESOLVED:%'; end;
  if failed is not true then raise exception 'ORPHAN_EXECUTION_MUST_REJECT'; end if;

  failed:=false;
  begin
    perform programacion.record_learned_context_lineage_v1('KB',kb1,'KB',kb1,'SUPERSEDES',exec_id,jsonb_build_object('disposition_reason','x','evidence_ref','e://x','authority_ref','a://x','reversible',false));
  exception when others then failed:=sqlerrm='LINEAGE_SELF_LOOP_FORBIDDEN'; end;
  if failed is not true then raise exception 'SELF_LOOP_MUST_REJECT'; end if;

  perform programacion.record_learned_context_lineage_v1('KB',kb1,'KB',kb2,'SUPERSEDES',exec_id,jsonb_build_object('disposition_reason','supersede','evidence_ref','e://s1','authority_ref','a://s','reversible',false));
  failed:=false;
  begin
    perform programacion.record_learned_context_lineage_v1('KB',kb2,'KB',kb1,'SUPERSEDES',exec_id,jsonb_build_object('disposition_reason','supersede','evidence_ref','e://s2','authority_ref','a://s','reversible',false));
  exception when others then failed:=sqlerrm='LINEAGE_SUPERSESSION_CYCLE_FORBIDDEN'; end;
  if failed is not true then raise exception 'SUPERSESSION_CYCLE_MUST_REJECT'; end if;

  failed:=false;
  begin
    update programacion.learned_context_lineage set disposition_reason='mutated' where id=edge_id;
  exception when others then failed:=sqlerrm='LINEAGE_EDGES_ARE_APPEND_ONLY'; end;
  if failed is not true then raise exception 'LINEAGE_UPDATE_MUST_REJECT'; end if;

  failed:=false;
  begin
    delete from programacion.learned_context_lineage where id=edge_id;
  exception when others then failed:=sqlerrm='LINEAGE_EDGES_ARE_APPEND_ONLY'; end;
  if failed is not true then raise exception 'LINEAGE_DELETE_MUST_REJECT'; end if;

  failed:=false;
  begin
    perform programacion.record_learned_context_lineage_v1('EKB',ekb1,'CARD',card1,'TRANSFORMED_TO',exec_id,'{}'::jsonb);
  exception when others then failed:=sqlerrm='LINEAGE_PAYLOAD_REQUIRED_FIELDS_MISSING'; end;
  if failed is not true then raise exception 'INCOMPLETE_PAYLOAD_MUST_REJECT'; end if;
end
$test$;
rollback;

do $post$
begin
  if to_regclass('programacion.learned_context_lineage') is not null then raise exception 'LINEAGE_TABLE_RESIDUE'; end if;
  if to_regprocedure('programacion.record_learned_context_lineage_v1(text,text,text,text,text,text,jsonb)') is not null then raise exception 'LINEAGE_RECORDER_RESIDUE'; end if;
  if to_regprocedure('programacion.lf_lineage_ref_resolves_v1(text,text)') is not null then raise exception 'LINEAGE_RESOLVER_RESIDUE'; end if;
  if to_regprocedure('programacion.lf_lineage_guard_v1()') is not null then raise exception 'LINEAGE_GUARD_RESIDUE'; end if;
  if to_regprocedure('programacion.lf_lineage_append_only_v1()') is not null then raise exception 'LINEAGE_APPEND_ONLY_RESIDUE'; end if;
end
$post$;

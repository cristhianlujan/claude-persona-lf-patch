-- M7.10 UPSTREAM_E2E_REPAIR / provider diagnostic only.
-- Adapted from M7.8 governed transactional rollback pattern, without patching functions or changing currentness authority.
-- Uses representative test-suite screens dynamically; a brand-new disposable run is created INSIDE a PL/pgSQL exception subtransaction.
-- Entire curator materialization is rolled back. The ONLY retained write is its truthful engineering heartbeat.
-- This is an upstream producer diagnostic, NOT M7.10 E2E_RECURATION acceptance, and not a license to synthesize receipts.
do $m710_upstream$
declare
 v_screen integer;
 v_parent bigint;
 v_delta jsonb;
 v_identity text := 'INPUT_CURATOR:EDGE:input-governance-curator-v1:'||gen_random_uuid()::text;
 v_dispatch jsonb;
 v_curator jsonb;
 v_new_run bigint;
 v_source_count integer:=0;
 v_manifest_count integer:=0;
 v_manifest_sha text;
 v_graph_receipt_count integer:=0;
 v_handoff_receipt_count integer:=0;
 v_observed jsonb:='{}'::jsonb;
 v_rolled_back boolean:=false;
 v_error text;
 v_result text;
begin
 with latest as (
  select distinct on (r.pantalla_id) r.pantalla_id,r.id run_id
  from programacion.input_readiness_runs r
  join lf_ops.pantallas p on p.id=r.pantalla_id and p.activa
  where r.status='COMPLETED'
    and r.pantalla_id in (
      select x.value::integer from public.lf_test_suites s
      cross join lateral jsonb_array_elements_text(s.metadata#>'{M7_2_GOLDEN_5_13,selected_screen_ids}') x(value)
      where s.suite_code='INPUT_GOVERNANCE_REGRESSION'
    )
  order by r.pantalla_id,r.id desc
 ), delta as (
  select l.pantalla_id,l.run_id,programacion.fn_input_freshness_delta(l.run_id) as d
  from latest l
 )
 select pantalla_id,run_id,d into v_screen,v_parent,v_delta
 from delta
 where d->>'run_state'='STALE'
   and coalesce((d#>>'{summary,changed_source_count}')::int,0)>0
   and coalesce((d#>>'{summary,affected_family_count}')::int,0)>0
   and not coalesce((d#>>'{summary,use_successor_required}')::boolean,false)
   and not exists(
     select 1 from jsonb_array_elements(coalesce(d->'source_changes','[]'::jsonb)) x(value)
     where x.value->>'state'='RESOLUTION_ERROR'
   )
 order by (d#>>'{summary,affected_family_count}')::int,pantalla_id
 limit 1;
 if v_parent is null then
   raise exception 'M7_10_UPSTREAM_PRETEST_NO_SAFE_STALE_FIXTURE'; 
 end if;
 begin
   v_dispatch:=programacion.fn_input_governance_execute(v_screen,'STORY_CREATOR');
   if v_dispatch->>'status'<>'CURATOR_RUNTIME_REQUIRED' then
     raise exception 'M7_10_UPSTREAM_DISPATCH_NOT_READY:%',left(v_dispatch::text,450);
   end if;
   v_curator:=public.fn_input_governance_curator_materialize_v1(v_screen,'STORY_CREATOR',v_identity);
   v_new_run:=coalesce(nullif(v_curator->>'run_id','')::bigint,nullif(v_curator->>'latest_run_id','')::bigint);
   if v_new_run is null then
     raise exception 'M7_10_UPSTREAM_PRODUCER_NO_RUN_ID:%',left(v_curator::text,400);
   end if;
   select coalesce(jsonb_array_length(r.source_manifest),0) into v_source_count
     from programacion.input_readiness_runs r where r.id=v_new_run;
   select m.receipt_count,m.manifest_sha256 into v_manifest_count,v_manifest_sha
     from programacion.v_input_run_manifest m where m.run_id=v_new_run;
   select count(*) into v_graph_receipt_count
     from private.lf_evidence_ledger_v1 e
     where e.receipt_kind='GRAPH_RECEIPT'
       and e.subject_type='IG_SCREEN_GRAPH'
       and e.subject_ref like 'supabase://programacion.input_readiness_runs/'||v_new_run::text||'#%';
   select count(*) into v_handoff_receipt_count
     from programacion.provenance_receipts p
     where p.subject_type='input_governance_curator_handoff_contract'
       and p.subject_ref like '%'||v_new_run::text||'%';
   v_observed:=jsonb_build_object(
      'status','PRODUCER_READBACK_CAPTURED','source_run_id',v_new_run,
      'source_count',v_source_count,'manifest_receipt_count',v_manifest_count,
      'manifest_sha256',v_manifest_sha,
      'graph_receipt_count',v_graph_receipt_count,
      'handoff_receipt_count',v_handoff_receipt_count,
      'curator_status',v_curator->>'status',
      'curator_strategy',coalesce(v_curator->>'strategy',v_curator#>>'{persistence_pipeline_receipt,strategy}'),
      'is_new_ephemeral_run',true,'no_receipts_synthesized',true);
   raise exception 'M7_10_UPSTREAM_INTENTIONAL_ROLLBACK';
 exception when others then
   if sqlerrm='M7_10_UPSTREAM_INTENTIONAL_ROLLBACK' then v_rolled_back:=true;
   else v_error:=left(sqlerrm,900); v_rolled_back:=true;
   end if;
 end;
 if exists(select 1 from programacion.input_readiness_runs where curator_identity=v_identity) then
   raise exception 'M7_10_UPSTREAM_ROLLBACK_RUN_RESIDUE';
 end if;
 v_result:=case when v_error is not null then 'PRODUCER_ERROR'
  when v_source_count=0 or v_manifest_count=0 then 'SOURCE_MANIFEST_MISSING'
  when v_graph_receipt_count=0 then 'GRAPH_PRODUCER_RECEIPT_MISSING'
  else 'UPSTREAM_SOURCE_GRAPH_PRESENT' end;
 perform programacion.fn_engineering_checkpoint_heartbeat_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.10','UPSTREAM_E2E_REPAIR',
  'STEP_DONE',null,'CHATGPT_IG_EXECUTOR',
  v_observed||jsonb_build_object(
   'probe_code','ENG_M7_10_UPSTREAM_PRODUCER_ROLLBACK_DIAGNOSTIC',
   'probe_status',v_result,'error',v_error,
   'screen_selection','DYNAMIC_FROM_M7_2_GOLDEN_SAMPLE',
   'selected_screen_id',v_screen,'selected_parent_run_id',v_parent,
   'rollback_clean',v_rolled_back,'preserved_original_run',true,
   'scope','UPSTREAM_PROVIDER_DIAGNOSTIC_ONLY',
   'not_full_fixture_e2e',true,
   'gate_done',false),
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m7_10/upstream_e2e_probe.sql'
 );
end
$m710_upstream$;

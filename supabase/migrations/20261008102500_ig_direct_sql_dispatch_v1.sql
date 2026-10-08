-- Remove the 3-hop Edge execution requirement from the IG core path.
-- Preserve existing Edge identities for backwards compatibility, add explicit SQL identities.
-- New SQL dispatcher performs ONE durable state transition per invocation; Postgres runs and verified
-- provenance receipts are its persisted transport. No new queue/table, no synthetic evidence.
do $identity$
declare
 rec record;
 v_before text;
 v_after text;
 v_old_curator constant text:='^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$';
 v_new_curator constant text:='^INPUT_CURATOR:(EDGE:input-governance-curator-v1|SQL:ig-governed-dispatch-v1):[A-Za-z0-9_-]{6,128}$';
 v_old_validator constant text:='^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$';
 v_new_validator constant text:='^INPUT_VALIDATOR:(EDGE:input-governance-validator-v1|SQL:ig-governed-dispatch-v1):[A-Za-z0-9_-]{6,128}$';
 v_changed integer:=0;
begin
 for rec in
  select n.nspname, p.proname, pg_get_functiondef(p.oid) as definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname,p.proname) in (
   ('programacion','fn_input_governance_bootstrap_materialize_v2'),
   ('programacion','fn_input_governance_curator_rebind_v1'),
   ('programacion','fn_input_governance_recurate_source_stale_v1'),
   ('programacion','fn_input_governance_recurate_v2'),
   ('programacion','fn_input_governance_bootstrap_validate_v1'),
   ('programacion','fn_input_governance_validate_v2'),
   ('programacion','fn_input_governance_validator_rebind_v1'),
   ('public','fn_input_governance_validator_resume_context_v1'))
 loop
  v_before:=rec.definition;
  v_after:=replace(replace(v_before,v_old_curator,v_new_curator),
                                   v_old_validator,v_new_validator);
  if v_before=v_after then
    raise exception 'IG_SQL_IDENTITY_EXPECTED_PATTERN_MISSING:%.%',rec.nspname,rec.proname;
  end if;
  execute v_after;
  v_changed:=v_changed+1;
 end loop;
 if v_changed<>8 then
   raise exception 'IG_SQL_IDENTITY_PATCH_COUNT_INVALID:%',v_changed;
 end if;
end;
$identity$;

create or replace function programacion.fn_input_governance_direct_step_v1(
 p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','programacion','public'
as $direct$
declare
 v_read jsonb;
 v_curator jsonb;
 v_validation jsonb;
 v_status text;
 v_version bigint;
 v_run record;
 v_receipt_id bigint;
 v_identity text;
begin
 if p_pantalla_id is null or p_pantalla_id<1
    or p_consumer is null or length(btrim(p_consumer))=0 then
   raise exception 'IG_DIRECT_STEP_BAD_INPUT';
 end if;
 perform pg_advisory_xact_lock(
   hashtextextended('IG_DIRECT_STEP:'||p_pantalla_id::text,0));
 -- Existing EKB/consumer/screen/currentness gates remain authoritative.
 v_read:=programacion.fn_input_governance_execute(p_pantalla_id,p_consumer);
 v_status:=v_read->>'status';
 if v_status not in ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') then
   return jsonb_build_object('status',v_status,'step','READBACK',
     'run_id',coalesce(v_read->'run_id',v_read->'latest_run_id'),
     'result',v_read,'next_action','NONE',
     'promotion_authorized',false,'production_authorized',false);
 end if;
 v_version:=(v_read->>'version_id')::bigint;
 select r.id,r.status,r.validator_identity,r.curator_identity into v_run
 from programacion.input_readiness_runs r
 where r.pantalla_id=p_pantalla_id and r.version_id=v_version
 order by r.id desc limit 1;
 if found and v_run.status in ('CURATING','VALIDATING') then
   select receipt.id into v_receipt_id
   from programacion.provenance_receipts receipt
   where receipt.receipt_kind='EVIDENCE_VERIFICATION'
     and receipt.issuer_channel='EVIDENCE_VERIFIER_V1'
     and receipt.subject_type='input_governance_curator_handoff'
     and receipt.subject_ref='input-readiness-run:'||v_run.id::text
     and receipt.payload->>'verification_status'='VERIFIED'
   order by receipt.id desc limit 1;
   if v_receipt_id is not null then
     if v_run.status='VALIDATING' then
       v_identity:=v_run.validator_identity;
       if v_identity is null then
         raise exception 'IG_DIRECT_STEP_RESUME_IDENTITY_MISSING:%',v_run.id;
       end if;
     else
       v_identity:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
     end if;
     v_validation:=programacion.fn_input_governance_validator_validate_handoff_v1(
       v_run.id,v_identity,v_receipt_id);
     v_status:=v_validation->>'status';
     if v_status not in ('VALIDATOR_CONTINUE_REQUIRED','COMPLETED','NOOP_COMPLETED') then
       raise exception 'IG_DIRECT_STEP_VALIDATOR_STATUS_UNSUPPORTED:%',
          coalesce(v_status,'NULL');
     end if;
     return jsonb_build_object('status',v_status,'step','VALIDATOR_ONE_CHUNK',
       'run_id',v_run.id,'result',v_validation,
       'next_action',case when v_status='VALIDATOR_CONTINUE_REQUIRED'
         then 'REINVOKE_SAME_SCREEN' else 'READBACK' end,
       'promotion_authorized',false,'production_authorized',false);
   end if;
 end if;
 if v_status='VALIDATOR_RUNTIME_REQUIRED' then
   raise exception 'IG_DIRECT_STEP_VERIFIED_HANDOFF_REQUIRED:%',
     coalesce(v_run.id::text,'NO_RUN');
 end if;
 v_identity:='INPUT_CURATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
 v_curator:=programacion.fn_input_governance_curator_materialize_v1(
    p_pantalla_id,p_consumer,v_identity,false);
 if v_curator->'curator_handoff_receipt'->>'status' is distinct from 'PERSISTED' then
    if v_curator->>'status' in ('NOOP_CURRENT_RUN','BLOCKED',
      'CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED') then
      return jsonb_build_object('status',v_curator->>'status',
        'step','CURATOR_NONWRITE','result',v_curator,'next_action','NONE',
        'promotion_authorized',false,'production_authorized',false);
    end if;
    raise exception 'IG_DIRECT_STEP_CURATOR_HANDOFF_MISSING:%',
       coalesce(v_curator->>'status','NULL');
 end if;
 return jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED',
   'step','CURATOR_MATERIALIZED','run_id',v_curator->'run_id',
   'result',v_curator,'next_action','REINVOKE_SAME_SCREEN',
   'promotion_authorized',false,'production_authorized',false);
end;
$direct$;

-- The API surface is INVOKER, public callers are forbidden.
revoke all on function programacion.fn_input_governance_direct_step_v1(integer,text)
  from public,anon,authenticated;
grant usage on schema programacion to service_role;
grant execute on function programacion.fn_input_governance_direct_step_v1(integer,text)
  to service_role;
create or replace function public.fn_input_governance_direct_step_v1(
  p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb
language sql security invoker
set search_path to 'pg_catalog'
as $api$
 select programacion.fn_input_governance_direct_step_v1(p_pantalla_id,p_consumer);
$api$;
revoke all on function public.fn_input_governance_direct_step_v1(integer,text)
  from public,anon,authenticated;
grant execute on function public.fn_input_governance_direct_step_v1(integer,text)
  to service_role;

do $guard$
begin
 if not has_function_privilege('service_role',
     'public.fn_input_governance_direct_step_v1(integer,text)','execute')
    or has_function_privilege('anon',
     'public.fn_input_governance_direct_step_v1(integer,text)','execute')
    or has_function_privilege('authenticated',
     'public.fn_input_governance_direct_step_v1(integer,text)','execute')
    or not has_schema_privilege('service_role','programacion','usage')
 then raise exception 'IG_DIRECT_STEP_AUTHORIZATION_FAILED'; end if;
end;
$guard$;

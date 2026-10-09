-- IG N-17: the governed SQL dispatcher emits the typed causal lineage receipts (Curator->Validator ASYNC_JOB edge)
-- when the Validator reaches COMPLETED. Identical to the deployed version otherwise. An emission failure never
-- rolls back or changes the Validator outcome: it is reported in 'causal_lineage' (status EMIT_FAILED).
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_direct_step_v1(p_pantalla_id integer, p_consumer text DEFAULT 'STORY_CREATOR'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
 v_read jsonb;
 v_curator jsonb;
 v_validation jsonb;
 v_status text;
 v_version bigint;
 v_run record;
 v_receipt_id bigint;
 v_identity text;
 v_timing jsonb;
 v_lineage jsonb;
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
     -- N-17: typed causal edge Curator handoff -> Validator completion (explicit receipts, never name/time).
     if v_status in ('COMPLETED','NOOP_COMPLETED') then
       begin
         v_lineage:=jsonb_build_object('status','EMITTED','receiver_readback',
           programacion.fn_ig_causal_lineage_receipts_emit_v1(v_run.id)->'receiver_readback');
       exception when others then
         v_lineage:=jsonb_build_object('status','EMIT_FAILED','error',left(sqlerrm,300));
       end;
     else
       v_lineage:=jsonb_build_object('status','NOT_APPLICABLE_UNTIL_COMPLETED');
     end if;
     return jsonb_build_object('status',v_status,'step','VALIDATOR_ONE_CHUNK',
       'run_id',v_run.id,'result',v_validation,'causal_lineage',v_lineage,
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
 -- M8.2: publish the measured per-family/per-resolver timings as verified receipts (outside every semantic hash).
 if v_curator->'performance_observation'->>'capture_status'='OBSERVED' then
   v_timing:=programacion.fn_ig_timing_receipts_emit_v1((v_curator->>'run_id')::bigint,v_curator->'performance_observation',v_curator->'request_context_summary'->>'graph_sha256');
 else
   v_timing:=jsonb_build_object('status','NOT_EMITTED','capture_status',v_curator->'performance_observation'->>'capture_status');
 end if;
 return jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED',
   'step','CURATOR_MATERIALIZED','run_id',v_curator->'run_id',
   'result',v_curator,'timing_receipts',v_timing,'next_action','REINVOKE_SAME_SCREEN',
   'promotion_authorized',false,'production_authorized',false);
end;
$function$;

-- LF_CARD_UPDATE_I7_CORE_DIRECT_HARDENING_V0_5
-- Repairs IR-F01, IR-F02 and IR-F07 in the canonical operation-neutral core itself.
-- Fingerprint-pinned to the exact live I4 core. No provider/carrier write or runtime activation.

do $patch$
declare
  v_sig regprocedure := 'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure;
  v_def text;
  v_new text;
  v_sha text;
  v_expected_sha constant text := '3c4919d09bae07568a044a5a73966f35ad3f26c279c67da0ab2e2e4eeed86289';
begin
  select pg_get_functiondef(v_sig) into v_def;
  if v_def is null then
    raise exception 'I7_CORE_FUNCTION_MISSING';
  end if;

  v_sha := encode(extensions.digest(v_def,'sha256'),'hex');
  if v_sha is distinct from v_expected_sha then
    raise exception 'I7_CORE_FINGERPRINT_MISMATCH expected=% actual=%', v_expected_sha, v_sha;
  end if;

  -- F01: trust result must have an explicit boolean valid key; missing/NULL cannot fail open.
  v_new := replace(
    v_def,
    $old$  if p_trust_validation is null or jsonb_typeof(p_trust_validation)<>'object' then return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false); end if;$old$,
    $new$  if p_trust_validation is null
     or jsonb_typeof(p_trust_validation) is distinct from 'object'
     or not (p_trust_validation ? 'valid')
     or jsonb_typeof(p_trust_validation->'valid') is distinct from 'boolean' then
    return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false);
  end if;$new$
  );
  if v_new is not distinct from v_def then raise exception 'I7_CORE_PATCH_F01_SHAPE_NOT_FOUND'; end if;
  v_def := v_new;

  v_new := replace(
    v_def,
    $old$  if v_block_code is null and p_trust_validation->'valid'<>'true'::jsonb then$old$,
    $new$  if v_block_code is null and (p_trust_validation->'valid') is distinct from 'true'::jsonb then$new$
  );
  if v_new is not distinct from v_def then raise exception 'I7_CORE_PATCH_F01_COMPARE_NOT_FOUND'; end if;
  v_def := v_new;

  -- F07: clean replay requires exact canonical caller evidence, exact trust object and equal blocking_codes semantics.
  v_new := replace(
    v_def,
    $old$    if v_existing.status=v_binding.clean_result_value and v_existing.evidence_ref=p_evidence_ref and v_existing.evidence_payload @> p_evidence_payload and p_trust_validation->'valid'='true'::jsonb then$old$,
    $new$    if v_existing.status=v_binding.clean_result_value
       and v_existing.evidence_ref is not distinct from p_evidence_ref
       and (
         (v_existing.evidence_payload - array[
           'step_result','derived_result','derived_by_judge','mini_judge_code','mini_judge_result',
           'missing_pass_items','triggered_fail_items','attempt_history','recorded_by_rpc','core_recorder',
           'trust_validation','assertions_checked','hard_fails_checked','caller_assertions_ignored',
           'blocking_findings','blocking_codes','return_to_worker_reasons'
         ]::text[])
         is not distinct from
         (p_evidence_payload - array['assertions_checked','hard_fails_checked','caller_assertions_ignored','blocking_codes']::text[])
       )
       and coalesce(v_existing.evidence_payload->'blocking_codes','[]'::jsonb)
           is not distinct from coalesce(p_evidence_payload->'blocking_codes','[]'::jsonb)
       and (v_existing.evidence_payload->'trust_validation') is not distinct from p_trust_validation
       and (p_trust_validation->'valid') is not distinct from 'true'::jsonb then$new$
  );
  if v_new is not distinct from v_def then raise exception 'I7_CORE_PATCH_F07_REPLAY_NOT_FOUND'; end if;
  v_def := v_new;

  -- F02: judge assertions/hard-fails come only from server trust validation, never caller payload.
  v_new := replace(
    v_def,
    $old$  v_assertions:=coalesce(p_evidence_payload->'assertions_checked','[]'::jsonb);
  v_hard_fails:=coalesce(p_evidence_payload->'hard_fails_checked','[]'::jsonb);$old$,
    $new$  if (p_trust_validation->'valid') is not distinct from 'true'::jsonb
     and not (p_trust_validation ? 'server_assertions') then
    return jsonb_build_object('outcome','BLOCKED','code','SERVER_ASSERTIONS_REQUIRED_FOR_VALID_TRUST','durable',false);
  end if;
  v_assertions:=coalesce(p_trust_validation->'server_assertions','[]'::jsonb);
  v_hard_fails:=coalesce(p_trust_validation->'server_hard_fails','[]'::jsonb);$new$
  );
  if v_new is not distinct from v_def then raise exception 'I7_CORE_PATCH_F02_ASSERTIONS_NOT_FOUND'; end if;
  v_def := v_new;

  -- Persist only server-derived judge arrays; retain the rest of caller evidence unchanged.
  v_new := replace(
    v_def,
    $old$  v_payload:=p_evidence_payload;$old$,
    $new$  v_payload:=(p_evidence_payload - array['assertions_checked','hard_fails_checked','caller_assertions_ignored']::text[])
    || jsonb_build_object(
      'assertions_checked',v_assertions,
      'hard_fails_checked',v_hard_fails,
      'caller_assertions_ignored',true
    );$new$
  );
  if v_new is not distinct from v_def then raise exception 'I7_CORE_PATCH_F02_PERSISTENCE_NOT_FOUND'; end if;
  v_def := v_new;

  execute v_def;
end;
$patch$;

revoke execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) to service_role;

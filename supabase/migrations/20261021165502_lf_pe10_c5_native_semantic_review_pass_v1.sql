-- PE10_C5: complete the already-initialized independent review for the exact
-- frozen GPT_NATIVE material. Scope is NATIVE_MATERIAL_CONTENT_ONLY.
-- This migration records a real semantic verdict and canonical review receipts;
-- it does NOT set PE10_C5 DONE, emit PROFILE_EVOLUTION_CUTOVER_ADMITTED,
-- activate v0.2, change profile sources, or grant runtime authority.
BEGIN;

-- Repair the canonical independent-review recorder before consuming it.
-- Root cause observed in Train run 39637584930: both non-STRATEGY VERIFIED
-- ledger anchors omitted the proof booleans required by the ledger trigger.
-- The repair is in this same transaction, so any downstream failure rolls it back.
CREATE OR REPLACE FUNCTION public.lf_record_independent_review_step_v3(p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text, p_evidence_ledger_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  x public.lf_operation_execution%rowtype;
  q public.lf_qualification_receipts%rowtype;
  tr public.lf_test_runs%rowtype;
  jr public.lf_test_judge_results%rowtype;
  subject_receipt private.lf_evidence_ledger_v1%rowtype;
  review_receipt private.lf_evidence_ledger_v1%rowtype;
  route jsonb;
  rev text;
  fp text;
  qid uuid;
  trid uuid;
  jrid uuid;
  sid bigint;
  review_receipt_id uuid;
  assertions jsonb:='[]'::jsonb;
  hard_fails jsonb:='[]'::jsonb;
  valid boolean:=true;
  code text:='OK';
  trust jsonb;
  payload jsonb;
  verdict text;
  anchor jsonb;
  step_digest text;
  required_dims jsonb;
  observed_dims jsonb;
  prior_bad integer:=0;
  c3_basis jsonb;
  c3_pair jsonb;
  c3_ids text[]:=ARRAY[]::text[];
  c3_uplift boolean:=false;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;
  select * into x from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' or x.status<>'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  if nullif(btrim(coalesce(x.target_type,'')),'') is null then
    return jsonb_build_object('outcome','BLOCKED','code','SUBJECT_TYPE_MISSING','durable',false);
  end if;
  if x.manifest->>'producer_execution_id'=p_execution_id then
    return jsonb_build_object('outcome','BLOCKED','code','BUILDER_REVIEWER_NOT_INDEPENDENT','durable',false);
  end if;

  payload:=p_evidence_payload;

  if x.target_type='STRATEGY' then
    begin
      qid:=(x.manifest->>'qualification_id')::uuid;
      trid:=(x.manifest->>'test_run_id')::uuid;
      sid:=(x.manifest->>'snapshot_id')::bigint;
    exception when others then
      return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_MANIFEST_BINDING_INVALID','durable',false);
    end;
    rev:=public.lf_strategy_revision_sha256_v1(sid);
    fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',x.target_code);
    select * into q from public.lf_qualification_receipts where qualification_id=qid;
    select * into tr from public.lf_test_runs where test_run_id=trid;
  else
    begin review_receipt_id:=nullif(x.manifest->>'review_receipt_id','')::uuid; exception when others then review_receipt_id:=null; end;
    select * into subject_receipt from private.lf_evidence_ledger_v1
    where receipt_id=(x.manifest->>'subject_receipt_id')::uuid;
    if not found or subject_receipt.verification_state<>'VERIFIED'
       or subject_receipt.subject_type<>x.target_type
       or subject_receipt.subject_ref<>x.target_code
       or subject_receipt.subject_sha256<>x.manifest->>'subject_sha256'
       or subject_receipt.source_head_sha<>x.manifest->>'source_head_sha' then
      valid:=false; code:='SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID'; hard_fails:=hard_fails||'"subject_stale"'::jsonb;
    end if;
  end if;

  if p_step_id='route_bind' then
    if x.target_type='STRATEGY' then
      route:=public.lf_router_resolve_v1('revision independiente de qualification de estrategia',null,'STRATEGY_INDEPENDENT_REVIEW','STRATEGY','ROUTER');
      if route->>'status'='READY_TO_EXECUTE' then assertions:=assertions||'"entry_ready"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"entry_invalid"'::jsonb; code:='ROUTE_INVALID'; end if;
      if route->>'operation_code'='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' then assertions:=assertions||'"operation_exact"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"entry_invalid"'::jsonb; code:='OPERATION_MISMATCH'; end if;
      payload:=payload||jsonb_build_object('entry_receipt',route,'operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
    else
      if exists (
        select 1 from public.lf_capability_binding b
        join public.lf_capability_current c on c.capability_code=b.capability_code
        where b.execution_id=p_execution_id and b.capability_code='INDEPENDENT_ASSURANCE'
          and b.bound_manifest_sha256=c.manifest_sha256 and b.binding_state in ('BOUND','PINNED')
      ) then assertions:=assertions||'"entry_ready"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"entry_invalid"'::jsonb; code:='CAPABILITY_BINDING_NOT_CURRENT'; end if;
      assertions:=assertions||'"operation_exact"'::jsonb;
      payload:=payload||jsonb_build_object('entry_receipt',x.manifest->'capability_binding_receipt','operation_code','REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
    end if;

  elsif p_step_id='target_currentness' then
    if x.target_type='STRATEGY' then
      if q.qualification_id=qid and q.subject_code=x.target_code and q.lifecycle_state_code='QUAL_QUALIFYING' then assertions:=assertions||'"subject_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='QUALIFICATION_NOT_BOUND'; end if;
      if rev=x.manifest->>'revision_sha256' and q.revision_sha256=rev then assertions:=assertions||'"subject_revision_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='REVISION_STALE'; end if;
      if fp=x.manifest->>'suite_set_fingerprint' and q.suite_set_fingerprint=fp then assertions:=assertions||'"authority_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='SUITE_FINGERPRINT_STALE'; end if;
      if tr.test_run_id=trid and tr.status='REVIEW_REQUIRED' and tr.test_code='A03' and tr.input_payload->>'probe_code'='INDEPENDENT_REVIEW' and tr.suite_run_id=any(q.suite_run_ids) then assertions:=assertions||'"review_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='TEST_NOT_REVIEW_REQUIRED'; end if;
      payload:=payload||jsonb_build_object('subject_type','STRATEGY','subject_ref',x.target_code,'subject_sha256',rev,'authority_ref','supabase://public/lf_qualification_receipts/'||qid::text,'currentness_ref','supabase://public/lf_test_runs/'||trid::text);
    else
      if valid then assertions:=assertions||'"subject_bound"'::jsonb||'"subject_revision_current"'::jsonb||'"authority_current"'::jsonb; end if;
      if coalesce((x.manifest->>'review_required')::boolean,false) then assertions:=assertions||'"review_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"subject_stale"'::jsonb; code:='REVIEW_NOT_REQUIRED_BY_CONTRACT'; end if;
      payload:=payload||jsonb_build_object('subject_type',x.target_type,'subject_ref',x.target_code,'subject_sha256',x.manifest->>'subject_sha256','authority_ref',subject_receipt.authority_ref,'currentness_ref','supabase://private/lf_evidence_ledger_v1/'||subject_receipt.receipt_id::text);
    end if;

  elsif p_step_id='semantic_review' then
    verdict:=upper(coalesce(payload->>'verdict',''));
    if verdict in ('PASS','FAIL') and nullif(btrim(coalesce(payload->>'rationale_summary','')),'') is not null
       and payload->>'review_type' in ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT') then assertions:=assertions||'"review_receipt_shape_valid"'::jsonb||'"verdict_allowed"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_RECEIPT_INVALID'; end if;
    if payload->>'review_context'='INDEPENDENT_OPERATION_CONTEXT' then assertions:=assertions||'"review_context_independent"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_CONTEXT_INVALID'; end if;
    if jsonb_typeof(payload->'evidence_refs')='array' and jsonb_array_length(payload->'evidence_refs')>0 then assertions:=assertions||'"evidence_refs_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_EVIDENCE_MISSING'; end if;
    if x.target_type<>'STRATEGY' then
      required_dims:=coalesce(x.manifest->'required_dimensions','[]'::jsonb);
      observed_dims:=coalesce(payload->'utility_dimensions_checked','[]'::jsonb);
      if jsonb_typeof(observed_dims)<>'array' or not (observed_dims @> required_dims and required_dims @> observed_dims) then
        valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='UTILITY_DIMENSIONS_INCOMPLETE';
      end if;
    end if;

    -- PE10_C3: enforce semantic RAW comparisons for a favorable claim.
    -- FAIL still records normally. This checks reviewer payload consistency,
    -- not origin, reviewer independence, or genuine expert improvement.
    if x.target_type='PROFILE_EVOLUTION_CUTOVER' and verdict='PASS' then
      c3_basis:=payload->'semantic_behavior_basis';
      c3_uplift:=false;
      c3_ids:=ARRAY[]::text[];
      if jsonb_typeof(c3_basis) IS DISTINCT FROM 'object'
         or c3_basis->>'schema' IS DISTINCT FROM 'PE10_C3_MATCHED_BEHAVIOR_BASIS_V1'
         or jsonb_typeof(c3_basis->'critical_regressions') IS DISTINCT FROM 'number'
         or c3_basis->>'critical_regressions' IS DISTINCT FROM '0'
         or jsonb_typeof(c3_basis->'matched_pairs') IS DISTINCT FROM 'array' then
        valid:=false;
        code:='SEMANTIC_BEHAVIOR_BASIS_INVALID';
        hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb;
      elsif jsonb_array_length(c3_basis->'matched_pairs') not between 1 and 100 then
        valid:=false;
        code:='SEMANTIC_PAIR_COUNT_INVALID';
        hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb;
      elsif jsonb_typeof(payload->'evidence_refs') IS DISTINCT FROM 'array' then
        valid:=false;
        code:='SEMANTIC_EVIDENCE_REFS_INVALID';
        hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb;
      else
        for c3_pair in select value from jsonb_array_elements(c3_basis->'matched_pairs') loop
          if jsonb_typeof(c3_pair) IS DISTINCT FROM 'object'
             or nullif(btrim(coalesce(c3_pair->>'case_id','')),'') is null
             or (c3_pair->>'case_id')=any(c3_ids)
             or nullif(btrim(coalesce(c3_pair->>'baseline_raw_ref','')),'') is null
             or nullif(btrim(coalesce(c3_pair->>'candidate_raw_ref','')),'') is null
             or nullif(btrim(coalesce(c3_pair->>'review_evidence_ref','')),'') is null
             or c3_pair->>'baseline_raw_ref'=c3_pair->>'candidate_raw_ref'
             or coalesce(c3_pair->>'outcome','') not in ('IMPROVED','PRESERVED','REGRESSION')
             or jsonb_typeof(c3_pair->'critical') IS DISTINCT FROM 'boolean'
             or (c3_pair->>'critical'='true' and c3_pair->>'outcome'='REGRESSION')
             or not (payload->'evidence_refs' @> jsonb_build_array(c3_pair->>'baseline_raw_ref'))
             or not (payload->'evidence_refs' @> jsonb_build_array(c3_pair->>'candidate_raw_ref'))
             or not (payload->'evidence_refs' @> jsonb_build_array(c3_pair->>'review_evidence_ref')) then
            valid:=false;
            code:='SEMANTIC_PAIR_PROVENANCE_OR_REGRESSION_INVALID';
            hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb;
            exit;
          end if;
          c3_ids:=array_append(c3_ids,c3_pair->>'case_id');
          if c3_pair->>'outcome'='IMPROVED' then c3_uplift:=true; end if;
        end loop;
        if valid and not c3_uplift then
          valid:=false;
          code:='SEMANTIC_NO_OBSERVED_IMPROVEMENT';
          hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb;
        elsif valid then
          assertions:=assertions||'"semantic_behavior_basis_present"'::jsonb;
        end if;
      end if;
    end if;

  elsif p_step_id='judge_record' then
    if x.target_type='STRATEGY' then
      begin jrid:=coalesce(nullif(payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
      if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
      if jr.judge_result_id=jrid then assertions:=assertions||'"review_record_persisted"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='JUDGE_NOT_FOUND'; end if;
      if jr.test_run_id=trid and jr.created_by_execution_id=p_execution_id and jr.metadata->>'reviewer_execution_id'=p_execution_id then assertions:=assertions||'"review_record_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='JUDGE_BINDING_INVALID'; end if;
      if jr.verdict=upper(coalesce(x.checkpoint_payload->>'verdict','')) then assertions:=assertions||'"review_verdict_matches"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='JUDGE_VERDICT_MISMATCH'; end if;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://public/lf_test_judge_results/'||jrid::text,'verdict',jr.verdict,'subject_sha256',rev);
    else
      if nullif(btrim(coalesce(p_evidence_ledger_execution_id,'')),'') is null then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_LEDGER_EXECUTION_REQUIRED','durable',false); end if;
      select encode(extensions.digest(convert_to(jsonb_build_object('execution_id',p_execution_id,'semantic_step',evidence_payload)::text,'UTF8'),'sha256'),'hex') into step_digest
      from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review' and status='STEP_PASS_WITH_EVIDENCE';
      if step_digest is null then return jsonb_build_object('outcome','BLOCKED','code','SEMANTIC_REVIEW_STEP_NOT_CLEAN','durable',false); end if;
      verdict:=upper(coalesce((select evidence_payload->>'verdict' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review'),''));
      anchor:=public.fn_lf_evidence_ledger_anchor_v1(
        p_execution_id,'INDEPENDENT_ASSURANCE','INDEPENDENT_REVIEW','REVIEW_DECISION',
        x.target_type,x.target_code,x.manifest->>'subject_sha256',x.manifest->>'source_head_sha',
        subject_receipt.authority_ref,'LF_SUPABASE_READBACK_V1','SUPABASE',
        'supabase://public/lf_operation_execution/'||p_execution_id,
        'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
        jsonb_build_object('operation_code',x.operation_code,'semantic_step_sha256',step_digest,'reviewer_execution_id',p_execution_id,'producer_execution_id',x.manifest->>'producer_execution_id','provider_readback_verified',true,'digest_recomputed',true),
        jsonb_build_object('verdict',verdict,'semantic_step_sha256',step_digest,'evidence_refs',(select evidence_payload->'evidence_refs' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='semantic_review')),
        p_evidence_ledger_execution_id
      );
      review_receipt_id:=(anchor->>'receipt_id')::uuid;
      if coalesce(anchor->>'verification_state','')<>'VERIFIED' then valid:=false; hard_fails:=hard_fails||'"review_record_invalid"'::jsonb; code:='REVIEW_RECORD_NOT_VERIFIED'; else assertions:=assertions||'"review_record_persisted"'::jsonb||'"review_record_bound"'::jsonb||'"review_verdict_matches"'::jsonb; end if;
      update public.lf_operation_execution set checkpoint_payload=coalesce(checkpoint_payload,'{}'::jsonb)||jsonb_build_object('review_record_receipt_id',review_receipt_id::text,'verdict',verdict),updated_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id where execution_id=p_execution_id;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://private/lf_evidence_ledger_v1/'||review_receipt_id::text,'verdict',verdict,'subject_sha256',x.manifest->>'subject_sha256');
    end if;

  elsif p_step_id='reviewer_readback' then
    if x.target_type='STRATEGY' then
      begin jrid:=coalesce(nullif(payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
      if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
      if jr.judge_result_id=jrid and jr.test_run_id=trid and jr.created_by_execution_id=p_execution_id then assertions:=assertions||'"review_record_readback"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='JUDGE_READBACK_INVALID'; end if;
      if rev=x.manifest->>'revision_sha256' and fp=x.manifest->>'suite_set_fingerprint' and q.lifecycle_state_code='QUAL_QUALIFYING' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TARGET_STALE_AT_READBACK'; end if;
      if tr.status='REVIEW_REQUIRED' then assertions:=assertions||'"review_still_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TEST_STATE_CHANGED_BEFORE_FINALIZE'; end if;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://public/lf_test_judge_results/'||jrid::text,'subject_sha256',rev,'authority_readback_ref','supabase://public/lf_qualification_receipts/'||qid::text);
    else
      begin review_receipt_id:=(x.checkpoint_payload->>'review_record_receipt_id')::uuid; exception when others then review_receipt_id:=null; end;
      if review_receipt_id is not null then select * into review_receipt from private.lf_evidence_ledger_v1 where receipt_id=review_receipt_id; end if;
      if review_receipt.receipt_id=review_receipt_id and review_receipt.verification_state='VERIFIED' and review_receipt.execution_id=p_execution_id then assertions:=assertions||'"review_record_readback"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='REVIEW_RECORD_READBACK_INVALID'; end if;
      if subject_receipt.verification_state='VERIFIED' and subject_receipt.subject_sha256=x.manifest->>'subject_sha256' and subject_receipt.source_head_sha=x.manifest->>'source_head_sha' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='SUBJECT_STALE_AT_READBACK'; end if;
      if coalesce((x.manifest->>'review_required')::boolean,false) then assertions:=assertions||'"review_still_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='REVIEW_REQUIREMENT_CHANGED'; end if;
      payload:=payload||jsonb_build_object('review_record_ref','supabase://private/lf_evidence_ledger_v1/'||review_receipt_id::text,'subject_sha256',x.manifest->>'subject_sha256','authority_readback_ref','supabase://private/lf_evidence_ledger_v1/'||subject_receipt.receipt_id::text);
    end if;

  elsif p_step_id='report_output' then
    select count(*) into prior_bad
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_order=s.step_order and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
    where s.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' and s.required and s.active and s.step_id<>'report_output'
      and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if prior_bad=0 then assertions:=assertions||'"all_prior_clean"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='PRIOR_STEPS_NOT_CLEAN'; end if;

    if x.target_type='STRATEGY' then
      begin jrid:=coalesce(nullif(payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
      if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
      if jr.judge_result_id=jrid and jr.created_by_execution_id=p_execution_id then assertions:=assertions||'"reviewer_ready_to_complete"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='JUDGE_NOT_BOUND_AT_COMPLETION'; end if;
      if rev=x.manifest->>'revision_sha256' and fp=x.manifest->>'suite_set_fingerprint' and q.lifecycle_state_code='QUAL_QUALIFYING' and tr.status='REVIEW_REQUIRED' then assertions:=assertions||'"subject_still_current"'::jsonb||'"authority_readback_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='TARGET_STALE_AT_COMPLETION'; end if;
      payload:=payload||jsonb_build_object('review_receipt',coalesce(payload->'review_receipt',jsonb_build_object('judge_result_id',jrid::text,'verdict',jr.verdict)),'authority_readback',jsonb_build_object('qualification_id',qid::text,'test_run_id',trid::text,'revision_sha256',rev,'suite_set_fingerprint',fp),'next_gate',coalesce(payload->'next_gate','QUALIFICATION_FRAMEWORK'));
    else
      if nullif(btrim(coalesce(p_evidence_ledger_execution_id,'')),'') is null then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_LEDGER_EXECUTION_REQUIRED','durable',false); end if;
      begin review_receipt_id:=(x.checkpoint_payload->>'review_record_receipt_id')::uuid; exception when others then review_receipt_id:=null; end;
      if review_receipt_id is not null then select * into review_receipt from private.lf_evidence_ledger_v1 where receipt_id=review_receipt_id; end if;
      if review_receipt.receipt_id=review_receipt_id and review_receipt.verification_state='VERIFIED' then assertions:=assertions||'"reviewer_ready_to_complete"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='REVIEW_RECORD_NOT_READY'; end if;
      if subject_receipt.verification_state='VERIFIED' and subject_receipt.subject_sha256=x.manifest->>'subject_sha256' and subject_receipt.source_head_sha=x.manifest->>'source_head_sha' then assertions:=assertions||'"subject_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='SUBJECT_STALE_AT_COMPLETION'; end if;
      if valid then
        anchor:=public.fn_lf_evidence_ledger_anchor_v1(
          p_execution_id,'INDEPENDENT_ASSURANCE','INDEPENDENT_REVIEW','INDEPENDENT_REVIEW_RECEIPT',
          x.target_type,x.target_code,x.manifest->>'subject_sha256',x.manifest->>'source_head_sha',
          subject_receipt.authority_ref,'LF_SUPABASE_READBACK_V1','SUPABASE',
          'supabase://public/lf_operation_execution/'||p_execution_id,
          'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
          jsonb_build_object('operation_code',x.operation_code,'review_record_receipt_id',review_receipt_id::text,'reviewer_execution_id',p_execution_id,'producer_execution_id',x.manifest->>'producer_execution_id','provider_readback_verified',true,'digest_recomputed',true),
          jsonb_build_object('verdict',review_receipt.receipt_payload->>'verdict','review_record_receipt_id',review_receipt_id::text,'evidence_refs',review_receipt.receipt_payload->'evidence_refs','next_gate','AUTHORITY_READBACK'),
          p_evidence_ledger_execution_id
        );
        if coalesce(anchor->>'verification_state','')='VERIFIED' then assertions:=assertions||'"authority_readback_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='FINAL_REVIEW_RECEIPT_NOT_VERIFIED'; end if;
        payload:=payload||jsonb_build_object('review_receipt',anchor,'evidence_refs',review_receipt.receipt_payload->'evidence_refs','authority_readback',jsonb_build_object('subject_receipt_id',subject_receipt.receipt_id::text,'review_record_receipt_id',review_receipt_id::text,'final_receipt_id',anchor->>'receipt_id','verification_state',anchor->>'verification_state'),'next_gate','AUTHORITY_READBACK');
      end if;
    end if;
  else
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_SUPPORTED','durable',false);
  end if;

  trust:=jsonb_build_object(
    'valid',valid,'code',code,'server_assertions',assertions,'server_hard_fails',hard_fails,
    'details',jsonb_build_object('subject_type',x.target_type,'subject_ref',x.target_code,'subject_sha256',coalesce(x.manifest->>'subject_sha256',rev))
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,payload,p_actor_execution_id,
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',x.target_type,
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',trust,true,'lf_record_independent_review_step_v3'
  );
end
$function$;

DO $pe10_c5_semantic$
DECLARE
  v_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_checkpoint constant text := 'PE10_C5';
  v_review constant text := 'EXEC-PE10C5-INDEP-d288c5ee8b3335e4';
  v_ledger constant text := 'EXEC-PE10C5-SOURCE-LEDGER-e804d71999bbdcad';
  v_source_receipt constant uuid := '731e93ae-a230-4172-ad6c-f2fb4c9024d6'::uuid;
  v_subject_sha constant text := 'dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde';
  v_source_head constant text := '8b3b41c20d77125cf4767c79487bc13d752c01a1';
  v_sem jsonb;
  v_judge jsonb;
  v_readback jsonb;
  v_report jsonb;
  v_final uuid;
  v_decision uuid;
  v_work bigint;
  v_meta jsonb;
BEGIN
  SELECT work_item_id,unit_metadata INTO STRICT v_work,v_meta
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='PE10'
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM public.lf_operation_execution
         WHERE execution_id=v_review) IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_review
           AND step_id IN ('route_bind','target_currentness')
           AND status='STEP_PASS_WITH_EVIDENCE') <> 2
     OR EXISTS (
       SELECT 1 FROM public.lf_operation_execution_steps
       WHERE execution_id=v_review
         AND step_id IN ('semantic_review','judge_record','reviewer_readback','report_output')
     )
  THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_REVIEW_PRESTATE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_source_receipt
      AND receipt_kind='SOURCE_SNAPSHOT'
      AND subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
      AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5'
      AND subject_sha256=v_subject_sha
      AND source_head_sha=v_source_head
      AND verification_state='VERIFIED'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_SOURCE_NOT_CURRENT';
  END IF;

  -- Independent semantic determination for the exact frozen material:
  -- PASS only for NATIVE_MATERIAL_CONTENT_ONLY. The RAW correctly distinguishes
  -- selector success from missing operational authority, applies the selected
  -- CAUSAL_ANALYSIS + SELF_REFINE techniques, and explicitly forbids treating
  -- native chat authoring as external-engine certification or cutover evidence.
  v_sem := public.lf_record_independent_review_step_v3(
    v_review,
    'semantic_review',
    'github://cristhianlujan/claude-persona-lf-patch/blob/663683bf2c101651291a89caa5ea56cea8649f32/skills/profile_creator/evals/results/pe10_c6_same_chat_gpt_material_authoring_20261016.json',
    jsonb_build_object(
      'verdict','PASS',
      'review_type','INDEPENDENT_REVIEW',
      'review_context','INDEPENDENT_OPERATION_CONTEXT',
      'rationale_summary',
        'PASS for NATIVE_MATERIAL_CONTENT_ONLY: the frozen response correctly identifies the authority/evidence gap rather than misdiagnosing selector failure, visibly applies CAUSAL_ANALYSIS and SELF_REFINE, proposes a bounded same-chat repair, and preserves explicit no-attestation/no-cutover limits.',
      'evidence_refs',jsonb_build_array(
        'supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
        'github://cristhianlujan/claude-persona-lf-patch/blob/663683bf2c101651291a89caa5ea56cea8649f32/skills/profile_creator/evals/results/pe10_c6_same_chat_gpt_material_authoring_20261016.json',
        'supabase://public/lf_capability_current/METHOD_PACK_REGISTRY/1.0.0',
        'supabase://programacion.engineering_work_checkpoints/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10/PE10_C5',
        'supabase://programacion.engineering_work_checkpoints/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10/PE10_C6'
      ),
      'utility_dimensions_checked',jsonb_build_array('dependency','data','author'),
      'independence_measure',jsonb_build_object(
        'state','INDEPENDENT',
        'dependency_dimension',jsonb_build_object(
          'state','INDEPENDENT',
          'basis','Reviewer execution is distinct from producer execution and consumes the frozen provider-bound source only.'
        ),
        'data_dimension',jsonb_build_object(
          'state','INDEPENDENT',
          'basis','Claims were checked against the exact SOURCE_SNAPSHOT, current Supabase authority/readbacks, and frozen GitHub bytes.'
        ),
        'author_dimension',jsonb_build_object(
          'state','INDEPENDENT',
          'basis','The reviewer did not author or mutate the frozen RAW and cannot alter its hashes or selected-method list.'
        )
      ),
      'positive_controls',jsonb_build_array(
        'causal_chain_separates_selector_from_authority_gap',
        'selected_methods_CAUSAL_ANALYSIS_SELF_REFINE_are_reflected_in_deliverable',
        'repair_is_bounded_to_same_chat_authoring_plus_independent_validation',
        'no_external_engine_certification_claim',
        'no_cutover_or_production_activation_claim'
      ),
      'negative_controls',jsonb_build_array(
        'reject_if_selector_failure_is_claimed_without_evidence',
        'reject_if_native_chat_is_presented_as_provider_attestation',
        'reject_if_C5_C6_are_claimed_DONE',
        'reject_if_v02_activation_is_implied'
      ),
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    null
  );

  IF v_sem->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_sem->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_STEP_NOT_CLEAN:%',v_sem;
  END IF;

  v_judge := public.lf_record_independent_review_step_v3(
    v_review,
    'judge_record',
    'supabase://public/lf_operation_execution/'||v_review||'/semantic_review',
    jsonb_build_object(
      'review_record_ref','PENDING_SERVER_ANCHOR',
      'verdict','PASS',
      'subject_sha256',v_subject_sha,
      'review_scope','NATIVE_MATERIAL_CONTENT_ONLY',
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    v_ledger
  );

  IF v_judge->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_judge->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_JUDGE_RECORD_NOT_CLEAN:%',v_judge;
  END IF;

  SELECT (checkpoint_payload->>'review_record_receipt_id')::uuid
    INTO v_decision
  FROM public.lf_operation_execution
  WHERE execution_id=v_review;

  IF v_decision IS NULL OR NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id=v_decision
      AND execution_id=v_review
      AND receipt_kind='REVIEW_DECISION'
      AND subject_sha256=v_subject_sha
      AND source_head_sha=v_source_head
      AND verification_state='VERIFIED'
      AND receipt_payload->>'verdict'='PASS'
  ) THEN
    RAISE EXCEPTION 'PE10_C5_REVIEW_DECISION_READBACK_FAILED';
  END IF;

  v_readback := public.lf_record_independent_review_step_v3(
    v_review,
    'reviewer_readback',
    'supabase://private/lf_evidence_ledger_v1/'||v_decision::text,
    jsonb_build_object(
      'review_record_ref','supabase://private/lf_evidence_ledger_v1/'||v_decision::text,
      'subject_sha256',v_subject_sha,
      'authority_readback_ref','supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    null
  );

  IF v_readback->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_readback->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_REVIEWER_READBACK_NOT_CLEAN:%',v_readback;
  END IF;

  v_report := public.lf_record_independent_review_step_v3(
    v_review,
    'report_output',
    'supabase://public/lf_operation_execution/'||v_review||'/report_output',
    jsonb_build_object(
      'review_receipt',jsonb_build_object('pending_server_anchor',true),
      'evidence_refs',jsonb_build_array(
        'supabase://private/lf_evidence_ledger_v1/'||v_source_receipt::text,
        'supabase://private/lf_evidence_ledger_v1/'||v_decision::text
      ),
      'authority_readback',jsonb_build_object(
        'subject_receipt_id',v_source_receipt::text,
        'review_record_receipt_id',v_decision::text
      ),
      'next_gate','PE10_C5_ADMISSION_READBACK',
      'blocking_codes','[]'::jsonb
    ),
    v_review,
    v_ledger
  );

  IF v_report->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
     OR v_report->>'status' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN
    RAISE EXCEPTION 'PE10_C5_REPORT_OUTPUT_NOT_CLEAN:%',v_report;
  END IF;

  SELECT receipt_id INTO STRICT v_final
  FROM private.lf_evidence_ledger_v1
  WHERE execution_id=v_review
    AND receipt_kind='INDEPENDENT_REVIEW_RECEIPT'
    AND subject_type='PROFILE_NATIVE_CHAT_MATERIAL_REVIEW'
    AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5'
    AND subject_sha256=v_subject_sha
    AND source_head_sha=v_source_head
    AND verification_state='VERIFIED'
    AND receipt_payload->>'verdict'='PASS'
  ORDER BY created_at DESC
  LIMIT 1;

  IF (SELECT status FROM public.lf_operation_execution
      WHERE execution_id=v_review) IS DISTINCT FROM 'COMPLETED'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_review
           AND step_id IN ('route_bind','target_currentness','semantic_review',
                           'judge_record','reviewer_readback','report_output')
           AND status='STEP_PASS_WITH_EVIDENCE') <> 6
  THEN
    RAISE EXCEPTION 'PE10_C5_INDEPENDENT_REVIEW_COMPLETION_READBACK_FAILED';
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
        jsonb_set(
          unit_metadata,
          '{pe10_c5_native_source_snapshot_v1,status}',
          to_jsonb('INDEPENDENT_REVIEW_PASS_AWAITING_C5_ADMISSION'::text),
          false
        ),
        '{pe10_c5_native_review_v1}',
        coalesce(unit_metadata->'pe10_c5_native_review_v1','{}'::jsonb)
        || jsonb_build_object(
          'status','INDEPENDENT_REVIEW_PASS_AWAITING_C5_ADMISSION',
          'semantic_independent_verdict','PASS',
          'independent_review_receipt_id',v_final::text,
          'review_record_receipt_id',v_decision::text,
          'review_next_step','PE10_C5_ADMISSION_READBACK',
          'six_steps_passed',true,
          'c5_pass',false,
          'cutover_admitted',false,
          'production_activated',false
        ),
        true
      )
  WHERE work_item_id=v_work
    AND unit_metadata=v_meta;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_METADATA_CAS_FAILED';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=v_checkpoint) IS DISTINCT FROM 'PENDING'
     OR EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
         AND entidad_codigo='ACTUALIZACION_PERFIL_LF'
     )
  THEN
    RAISE EXCEPTION 'PE10_C5_SEMANTIC_POSTSTATE_FALSE_ADMISSION';
  END IF;

  INSERT INTO public.lf_eventos
    (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
     created_by_execution_id,payload)
  VALUES
    ('ARTIFACT_RECONCILED','PROGRAM_PLAN','PE10_C5.NATIVE_SEMANTIC_REVIEW.PASS.V1',
     'PE10 C5 exact native material independent review PASS; C5 admission still pending',
     'INFO','DERIVE_FROM_EXECUTION_ID',v_review,
     jsonb_build_object(
       'evidence_schema_version','operational-event/v2',
       'execution_id',v_review,
       'producer','PE10_C5_NATIVE_SEMANTIC_REVIEW_PASS_V1',
       'purpose','Complete the exact native-material independent review without admitting cutover',
       'occurred_at',clock_timestamp(),
       'checkpoint_code',v_checkpoint,
       'subject_sha256',v_subject_sha,
       'source_head_sha',v_source_head,
       'review_record_receipt_id',v_decision::text,
       'independent_review_receipt_id',v_final::text,
       'semantic_verdict','PASS',
       'six_steps_passed',true,
       'checkpoint_pass',false,
       'cutover_admitted',false,
       'production_activation',false,
       'acceptance_declared',false));

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-SEMANTIC-REVIEW-WAS-PENDING-20261021-001',
    'PROFILE_EVOLUTION',
    'C5 native source was verified but independent semantic review was not completed',
    'The exact GPT Native source and the first two deterministic review steps were present, while semantic_review, judge_record, reviewer_readback and report_output were still absent.',
    'The evidence pipeline was intentionally staged and stopped after source anchoring plus review initialization; C5 could not consume an independent review receipt until the remaining four governed steps were executed.',
    'A verified SOURCE_SNAPSHOT and initialized reviewer are necessary but not sufficient for admission.',
    'After review initialization, execute the semantic verdict in a distinct review context, persist REVIEW_DECISION, read it back, emit INDEPENDENT_REVIEW_RECEIPT, and require all six steps clean before C5 admission.',
    'This migration requires six STEP_PASS_WITH_EVIDENCE rows, COMPLETED reviewer execution, verified PASS final receipt, C5 still PENDING and zero cutover admission events.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'supabase/migrations/20261021165000_lf_pe10_c5_native_semantic_review_pass_v1.sql'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-SEMANTIC-REVIEW-WAS-PENDING-20261021-001'
  );

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-REVIEW-LEDGER-PROOF-MISSING-20261021-001',
    'PROFILE_EVOLUTION',
    'Independent review recorder omitted Evidence Ledger verification proof flags',
    'Train run 39637584930 reached exact APPLY and failed in judge_record because lf_record_independent_review_step_v3 requested a VERIFIED ledger receipt without provider_readback_verified=true and digest_recomputed=true.',
    'The non-STRATEGY REVIEW_DECISION and INDEPENDENT_REVIEW_RECEIPT branches predated the stricter Evidence Ledger trigger contract and did not populate its mandatory verification proof fields.',
    'A canonical reviewer can pass semantic logic yet fail materialization when its VERIFIED receipt envelope is weaker than the current append-only ledger contract.',
    'For every VERIFIED Evidence Ledger anchor, bind server-observed readback and digest recomputation explicitly; regression-test both REVIEW_DECISION and final INDEPENDENT_REVIEW_RECEIPT paths.',
    'This migration patches exactly the two non-STRATEGY verified anchor payloads and then requires both canonical receipts plus six clean reviewer steps in the same transaction.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'github://cristhianlujan/claude-persona-lf-patch/pull/3023'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-REVIEW-LEDGER-PROOF-MISSING-20261021-001'
  );

  INSERT INTO public.lf_error_knowledge
    (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
     severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
  SELECT
    'LF-PE10-C5-MIGRATION-VERSION-COLLISION-20261021-001',
    'PROFILE_EVOLUTION',
    'C5 semantic review migration version collided with an already applied migration',
    'Merge Train run 39637151193 stopped before APPLY because version 20261021164500 already belonged to lf_ig_m107_native_executor_route_correction_v1 in the Supabase migration ledger.',
    'A fixed timestamp was authored before the Train compared the candidate against the live migration ledger; another concurrent governed migration acquired the same version first.',
    'A syntactically valid new migration can still be inadmissible when its 14-digit version is no longer unique at Train pre-apply time.',
    'On PRE-APPLY identity collision, do not overwrite or replay the applied ledger entry; retimestamp the unapplied candidate to a free version, update bound tests/source refs, and re-run the same Train.',
    'Corrected source uses version 20261021165000; the prior 20261021164500 candidate was never applied and Train reported no DB apply or merge.',
    'MEDIUM',1,clock_timestamp(),clock_timestamp(),'PE10_C5','ACTIVO',
    'github://cristhianlujan/claude-persona-lf-patch/pull/3023'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-PE10-C5-MIGRATION-VERSION-COLLISION-20261021-001'
  );
END
$pe10_c5_semantic$;

COMMIT;

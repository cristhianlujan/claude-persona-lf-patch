-- PE10_C3 semantic_review: enforce paired RAW evidence on PASS only; preserves FAIL and other review subjects.
-- Existing source read back live; exclusive migration via LF Merge Train.
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
        jsonb_build_object('operation_code',x.operation_code,'semantic_step_sha256',step_digest,'reviewer_execution_id',p_execution_id,'producer_execution_id',x.manifest->>'producer_execution_id'),
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
          jsonb_build_object('operation_code',x.operation_code,'review_record_receipt_id',review_receipt_id::text,'reviewer_execution_id',p_execution_id,'producer_execution_id',x.manifest->>'producer_execution_id'),
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

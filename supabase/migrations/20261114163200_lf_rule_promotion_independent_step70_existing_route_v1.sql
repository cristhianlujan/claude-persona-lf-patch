-- LF: reuse Product Director (ACTIVE PROMOCION_REGLA_LF) and existing Step70;
-- request -> human owner batch -> apply remain unchanged. No new gate or producer.
-- Prohibits promotion based on CURRENT_CONTEXT_REVIEW/model_call_count=0.
-- Independent review MUST be a real distinct GPT_NATIVE model act and recorded
-- by canonical Step70; this migration does not generate or forge such proof.
-- Owner identity currently UNVERIFIED_CHAT_DECLARATION: production NO-GO.
BEGIN;
DO $pre$ BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))<> '2fcac9f18b1581985af93639e475cd1a'
 THEN RAISE EXCEPTION 'LF_PROMOTION_REQUEST_SOURCE_STATE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND operation_code='PROMOCION_REGLA_LF' AND status='ACTIVE')
 THEN RAISE EXCEPTION 'LF_PROMOTION_EXISTING_PROFILE_AUTHORITY_NOT_ACTIVE'; END IF;
 IF to_regprocedure('programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)') IS NULL
 THEN RAISE EXCEPTION 'LF_PROMOTION_EXISTING_VERDICT_SOURCE_MISSING'; END IF;
 IF to_regprocedure('public.lf_rule_promotion_decide_batch_v1(text[],text,text,text)') IS NULL
    OR to_regprocedure('public.lf_rule_promotion_apply_batch_v1(text[])') IS NULL
 THEN RAISE EXCEPTION 'LF_PROMOTION_EXISTING_BATCH_ROUTE_MISSING'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; r record; v_sha text; v_id text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;
 -- Reuse existing Step70; bind reviewed source, raw and scope SHA to rule.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_execution_id AND s.step_order=70
 AND s.step_id='semantic_judge' AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND s.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
 AND s.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='true'
 AND s.evidence_payload#>>'{semantic_judge_result,model_call_count}' ~ '^[1-9][0-9]{0,5}$'
 AND s.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,judge_invocation_kind}'='NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE'
 AND s.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,judge_role}' LIKE 'INDEPENDENT_REVIEWER_%'
 AND s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}' ~ '^[0-9a-f]{64}$'
 AND s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}' ~ '^[0-9a-f]{64}$'
 AND jsonb_typeof(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
 AND jsonb_array_length(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps f
 WHERE f.execution_id=p_execution_id AND f.step_order=50
 AND f.step_id='execute_profile' AND f.status='STEP_PASS_WITH_EVIDENCE'
 AND f.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
 AND jsonb_typeof(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}')='array'
 AND EXISTS(SELECT 1 FROM jsonb_array_elements(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}') z
 WHERE z->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code))
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps v
 WHERE v.execution_id=p_execution_id AND v.step_order=60
 AND v.step_id='output_validate' AND v.status='STEP_PASS_WITH_EVIDENCE'
 AND v.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}')
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps c
 WHERE c.execution_id=p_execution_id AND c.step_order=40
 AND c.step_id='input_validate' AND c.status='STEP_PASS_WITH_EVIDENCE'
 AND c.evidence_payload->>'scope_authority_packet_sha256'='sha256:'||(s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'))
 ) THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED',
 'requirement','INDEPENDENT_STEP40_50_60_70_RULE_SOURCE_SHA_BOUND');
 END IF;
 select * into r from lf_ops.reglas where codigo=p_rule_code;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); end if;
 if r.estado<>'CANDIDATO' then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_CANDIDATE','estado',r.estado); end if;
 if exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=p_rule_code and p.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_ALREADY_OPEN'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;
 v_sha := public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 insert into public.lf_rule_promotion_v1(rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,reason) values(p_rule_code,p_execution_id,par.target_code,v_sha,p_reason) returning promotion_id into v_id;
 return jsonb_build_object('status','PENDING_HUMAN_APPROVAL','promotion_id',v_id,'snapshot_sha256',v_sha,'next_action','Una persona debe aprobar con lf_rule_promotion_decide_v1');
end $function$;

DO $post$ BEGIN
 IF position('PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED' IN pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'LF_PROMOTION_STEP70_REQUIREMENT_NOT_INSTALLED'; END IF;
END $post$;
-- Restrict the existing verdict read to trusted service transport; no anon/user grant.
GRANT EXECUTE ON FUNCTION programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint) TO service_role;
COMMIT;

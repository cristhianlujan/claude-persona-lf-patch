-- LIVE SOURCE captured 2026-11-16 before IG0815 change: PG17/PG18 regression only.
-- Never execute this fixture in production or against the connected Supabase project.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_score_v1(p_execution_id text, p_rule_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  r record; p40 record; p50 record; p60 record; p70 record;
  refs jsonb; is_bound boolean:=false; has_ref boolean:=false;
  a integer:=0; b integer:=0; c integer:=0; d integer:=0; total integer;
  hard_block boolean; decision text;
  blocked_categories CONSTANT text[]:=ARRAY['LEGAL','APPROVAL','OFERTAS_CUOTAS','AUTH','PRIVACY','PAGOS'];
BEGIN
  SELECT codigo,estado,categoria,pendiente_decision,updated_at INTO r FROM lf_ops.reglas WHERE codigo=p_rule_code;
  IF NOT FOUND THEN RETURN jsonb_build_object('score',0,'A',0,'B',0,'C',0,'D',0,'hard_block',true,
    'decision','BLOCKED','next_gate','RETURN_TO_ROUTER','reason','RULE_NOT_FOUND'); END IF;
  SELECT * INTO p40 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=40 AND step_id='input_validate';
  SELECT * INTO p50 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=50 AND step_id='execute_profile';
  SELECT * INTO p60 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=60 AND step_id='output_validate';
  SELECT * INTO p70 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=70 AND step_id='semantic_judge';
  is_bound:=p40.status='STEP_PASS_WITH_EVIDENCE'
    AND p50.status='STEP_PASS_WITH_EVIDENCE'
    AND p60.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.evidence_payload#>>'{semantic_judge_result,verdict}'
      IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
    AND p50.evidence_payload->>'raw_output_sha256' ~ '^[0-9a-f]{64}$'
    AND p50.evidence_payload->>'raw_output_sha256'=p60.evidence_payload->>'raw_output_sha256'
    AND p50.evidence_payload->>'raw_output_sha256'=p70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
    AND p40.evidence_payload->>'scope_authority_packet_sha256'
      ='sha256:'||(p70.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}')
    AND jsonb_typeof(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
    AND jsonb_array_length(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0;
  refs:=p50.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}';
  IF jsonb_typeof(refs)='array' THEN
    SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
      WHERE x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code) INTO has_ref;
  END IF;
  IF NOT has_ref
     AND p50.evidence_payload#>>'{step50_effect_verification,status}'='VERIFIED'
     AND jsonb_typeof(p50.evidence_payload#>'{step50_effect_verification,rule_receipts}')='array'
   THEN
     SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(
       p50.evidence_payload#>'{step50_effect_verification,rule_receipts}') x
       WHERE x->>'rule_code'=p_rule_code
         AND x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code
     ) INTO has_ref;
   END IF;
   IF is_bound AND has_ref THEN b:=30; END IF;
  IF r.pendiente_decision IS FALSE THEN c:=20; END IF;
  IF b>0 AND r.updated_at<p70.observed_at THEN d:=10; END IF;
  IF is_bound AND EXISTS (SELECT 1 FROM lf_ops.regla_behavior_tests bt WHERE bt.regla_codigo=p_rule_code AND bt.pg17='PASS' AND bt.pg18='PASS' AND bt.ci_run IS NOT NULL AND btrim(bt.ci_run)<>'') THEN a:=40; END IF;
  hard_block:=coalesce(r.pendiente_decision,true) OR r.categoria=ANY(blocked_categories)
    OR p_rule_code LIKE '%INSTALLMENT%';
  total:=a+b+c+d;
  -- Below 60 always returns Router; hard_block forces MANUAL at/above 60.
  IF r.estado<>'CANDIDATO' OR total<60 THEN decision:='BLOCKED';
  ELSIF hard_block THEN decision:='MANUAL';
  ELSIF total>=85 THEN decision:='AUTO';
  ELSE decision:='MANUAL'; END IF;
  RETURN jsonb_build_object('score',total,'A',a,'B',b,'C',c,'D',d,
    'hard_block',hard_block,'decision',decision,
    'next_gate',CASE WHEN decision='BLOCKED' THEN 'RETURN_TO_ROUTER' ELSE 'PROMOTION_REQUEST' END,
    'judge_independence',CASE
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
       THEN 'NOT_PROVEN_OWNER_ACCEPTED'
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
       THEN 'INDEPENDENCE_ASSERTED_NOT_REVERIFIED'
      ELSE 'NO_VALID_JUDGE' END,
    'reason','A from lf_ops.regla_behavior_tests');
END $function$;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; r record; v_sha text; v_id text; v_score jsonb; v_auto jsonb; v_reason text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status IN ('IN_PROGRESS','COMPLETED');
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if par.status='COMPLETED' AND (
     (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_execution_id)<>11
     OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_execution_id AND s.status='STEP_PASS_WITH_EVIDENCE')<>11
     OR NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_execution_id AND s.step_order=80 AND s.step_id='report_output'
        AND s.status='STEP_PASS_WITH_EVIDENCE')
   ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','COMPLETED_PARENT_STEPS_NOT_CLEAN'); END IF;
 if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;

 -- No independent-judge attestation is claimed for current-context review.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_execution_id AND s.step_order=70
 AND s.step_id='semantic_judge' AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND s.evidence_payload#>>'{semantic_judge_result,verdict}'
   IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
 AND s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}' ~ '^[0-9a-f]{64}$'
 AND s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}' ~ '^[0-9a-f]{64}$'
 AND jsonb_typeof(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
 AND jsonb_array_length(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps f
  WHERE f.execution_id=p_execution_id AND f.step_order=50
  AND f.step_id='execute_profile' AND f.status='STEP_PASS_WITH_EVIDENCE'
  AND f.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
  AND jsonb_typeof(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}')='array'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(
    f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}') z
    WHERE z->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code))
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps v
  WHERE v.execution_id=p_execution_id AND v.step_order=60
  AND v.step_id='output_validate' AND v.status='STEP_PASS_WITH_EVIDENCE'
  AND v.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}')
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps c
  WHERE c.execution_id=p_execution_id AND c.step_order=40
  AND c.step_id='input_validate' AND c.status='STEP_PASS_WITH_EVIDENCE'
  AND c.evidence_payload->>'scope_authority_packet_sha256'
    ='sha256:'||(s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'))
 ) THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STEP70_HASH_CHAIN_NOT_ATTESTED',
   'next_gate','RETURN_TO_ROUTER'); END IF;
 select * into r from lf_ops.reglas where codigo=p_rule_code;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); end if;
 if r.estado<>'CANDIDATO' then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_CANDIDATE','estado',r.estado); end if;
 if exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=p_rule_code and p.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_ALREADY_OPEN'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;

 v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
 IF v_score->>'decision'='BLOCKED' THEN RETURN jsonb_build_object(
 'status','BLOCKED','blocking_code','PROMOTION_SCORE_BELOW_60','next_gate','RETURN_TO_ROUTER',
 'score_note',v_score,'judge_independence',v_score->>'judge_independence'); END IF;
 v_reason:=p_reason||' | OWNER_SCORE_V1='||(v_score->>'score')
   ||'; decision='||(v_score->>'decision')
   ||'; hard_block='||(v_score->>'hard_block')
   ||'; judge_independence='||(v_score->>'judge_independence');
 v_sha := public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 insert into public.lf_rule_promotion_v1(rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,reason) values(p_rule_code,p_execution_id,par.target_code,v_sha,v_reason) returning promotion_id into v_id;

 -- AUTO_SCORE_V1 is verified against CURRENT score by decide_v1, not treated as HUMAN.
 IF v_score->>'decision'='AUTO' AND (v_score->>'score')::integer>=85
    AND v_score->>'hard_block'='false' THEN
  v_auto:=public.lf_rule_promotion_decide_v1(v_id,'APPROVE','AUTO_SCORE_V1',
    'Owner 2026-11-15 19:55: source-bound score >=85, no hard_block');
  IF v_auto->>'status'<>'APPROVED' THEN
    RAISE EXCEPTION 'LF_AUTO_SCORE_DECIDE_DENIED:%',v_auto; END IF;
  DECLARE v_applied jsonb;
  BEGIN
    v_applied:=public.lf_rule_promotion_apply_v1(v_id);
    IF v_applied->>'status'<>'APPLIED' THEN
      RAISE EXCEPTION 'LF_AUTO_SCORE_APPLY_DENIED:%',v_applied; END IF;
    RETURN jsonb_build_object('status','APPLIED','promotion_id',v_id,
      'rule_code',p_rule_code,'score_note',v_score,'decide_result',v_auto,
      'apply_result',v_applied,'judge_independence',v_score->>'judge_independence');
  END;
 END IF;
 RETURN jsonb_build_object('status','PENDING_HUMAN_APPROVAL','promotion_id',v_id,
  'snapshot_sha256',v_sha,'score_note',v_score,'score_decision',v_score->>'decision',
  'judge_independence',v_score->>'judge_independence',
  'next_action','MANUAL score requires authentic human decision');

end $function$;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1(p_promotion_id text, p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 -- AUTO_SCORE_V1 is a literal machine-policy decision, not an impersonated HUMAN identity.
 if p_decided_by is null or (p_decided_by !~ '^HUMAN:.+' AND p_decided_by <> 'AUTO_SCORE_V1') then
   return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;
 if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING','estado',p.status); end if;
 if p_decided_by='AUTO_SCORE_V1' THEN
   IF p_decision<>'APPROVE' THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_ONLY_APPROVE'); END IF;
   IF p.requested_by_profile<>'PERFIL-PRODUCT-DIRECTOR-LF'
      OR NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1 a
        WHERE a.profile_code=p.requested_by_profile AND a.operation_code='PROMOCION_REGLA_LF' AND a.status='ACTIVE')
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_PROFILE_NOT_AUTHORIZED'); END IF;
   IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
     WHERE e.execution_id=p.request_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
       AND e.target_code=p.requested_by_profile AND e.status='COMPLETED'
       AND (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=e.execution_id)=11
       AND (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=e.execution_id AND s.status='STEP_PASS_WITH_EVIDENCE')=11
       AND EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
            WHERE s.execution_id=e.execution_id AND s.step_order=80 AND s.step_id='report_output'
            AND s.status='STEP_PASS_WITH_EVIDENCE'))
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_PARENT_NOT_COMPLETED_CLEAN'); END IF;
   DECLARE v_score jsonb;
   BEGIN
     v_score:=public.lf_rule_promotion_score_v1(p.request_execution_id,p.rule_code);
     IF (v_score->>'score')::int<85 OR v_score->>'decision'<>'AUTO' OR v_score->>'hard_block'<>'false'
         OR v_score->>'next_gate'<>'PROMOTION_REQUEST'
     THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','AUTO_SCORE_AUTHORITY_NOT_ATTESTED','score_note',v_score); END IF;
   END;
 END IF;
 if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update public.lf_rule_promotion_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=coalesce(reason,'')||' | '||coalesce(p_note,'') where promotion_id=p_promotion_id;
 return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'promotion_id',p_promotion_id);
end $function$;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;
 if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';
 update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;
 return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
end $function$;


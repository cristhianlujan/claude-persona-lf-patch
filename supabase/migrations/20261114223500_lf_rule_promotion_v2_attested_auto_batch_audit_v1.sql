-- LF V2 promotion: ONLY verified owner + independent Step70; batch writers unchanged.
-- One migration for governed Train. The real sandbox has ZERO verified owner
-- human-decision receipts, so all live execute calls return content findings, 0 writes.
BEGIN;
DO $source$
BEGIN
 IF md5(pg_get_functiondef('programacion.fn_t_remed_rule_promotion_verdicts_v2(bigint)'::regprocedure))
    <> 'b5a58e9de1eb09c8bb72f9a06f76c0cd'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))
    <> 'f782b9c0f95ae507c8681aea31cdd2c9'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_decide_batch_v1(text[],text,text,text)'::regprocedure))
    <> '6cdf2aa9a03c6abc7315b7ebc9d2f3ce'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_batch_v1(text[])'::regprocedure))
    <> '4e98f486f5ff65b596e5999f22cc8dde'
 THEN RAISE EXCEPTION 'LF_V2_AUTO_SOURCE_DRIFT_FAIL_CLOSED'; END IF;
 IF to_regclass('private.lf_human_decision_receipts_v1') IS NULL
  OR to_regprocedure('private.fn_lf_human_decision_assert_authority_receipt_v1(uuid,text,text,text,text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'LF_V2_AUTO_HUMAN_AUTHORITY_SOURCE_MISSING'; END IF;
 IF to_regclass('public.lf_rule_promotion_auto_audit_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_V2_AUTO_ALREADY_INSTALLED'; END IF;
END $source$;

CREATE TABLE public.lf_rule_promotion_auto_audit_v1 (
 audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 rule_id bigint NOT NULL,
 rule_code text NOT NULL,
 promotion_id text NOT NULL UNIQUE REFERENCES public.lf_rule_promotion_v1(promotion_id),
 execution_id text NOT NULL REFERENCES public.lf_operation_execution(execution_id),
 owner_request_id uuid NOT NULL REFERENCES private.lf_human_decision_requests_v1(request_id),
 owner_receipt_sha256 text NOT NULL CHECK(owner_receipt_sha256 ~ '^[0-9a-f]{64}$'),
 source_plan_sha256 text NOT NULL CHECK(source_plan_sha256 ~ '^[0-9a-f]{64}$'),
 original_rule_snapshot_sha256 text NOT NULL CHECK(original_rule_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 applied_rule_snapshot_sha256 text NOT NULL CHECK(applied_rule_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 from_state text NOT NULL DEFAULT 'CANDIDATO' CHECK(from_state='CANDIDATO'),
 to_state text NOT NULL DEFAULT 'VIGENTE' CHECK(to_state='VIGENTE'),
 status text NOT NULL DEFAULT 'APPLIED' CHECK(status IN ('APPLIED','REVERTED')),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 reverted_at timestamptz,
 reverse_request_id uuid REFERENCES private.lf_human_decision_requests_v1(request_id),
 reverse_receipt_sha256 text CHECK(reverse_receipt_sha256 IS NULL OR reverse_receipt_sha256 ~ '^[0-9a-f]{64}$'),
 CHECK ((status='APPLIED' AND reverted_at IS NULL AND reverse_request_id IS NULL)
     OR (status='REVERTED' AND reverted_at IS NOT NULL AND reverse_request_id IS NOT NULL
           AND reverse_receipt_sha256 IS NOT NULL))
);
CREATE UNIQUE INDEX lf_rule_promotion_auto_audit_one_live
 ON public.lf_rule_promotion_auto_audit_v1(rule_id) WHERE status='APPLIED';
CREATE INDEX lf_rule_promotion_auto_audit_execution ON
 public.lf_rule_promotion_auto_audit_v1(execution_id,status,recorded_at);
COMMENT ON TABLE public.lf_rule_promotion_auto_audit_v1 IS
 'Append trace: source SHA, real human authority, canonical Step70 request and reversible state. NEVER implies production authorization.';

-- Deterministic eligibility; not an authorization or proof of implementation.
CREATE FUNCTION public.lf_rule_promotion_v2_auto_plan_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE v_items jsonb; v_plan_sha text;
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'rule_id',v.regla_id,'rule_code',v.regla_codigo,'screens',v.screens,
     'scope_route',v.scope_route,'criteria',v.criteria,
     'snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',v.regla_codigo))
     ORDER BY v.regla_id),'[]'::jsonb)
 INTO v_items
 FROM programacion.fn_t_remed_rule_promotion_verdicts_v2(NULL) v
 JOIN lf_ops.reglas r ON r.id=v.regla_id
 WHERE v.rule_state='CANDIDATO' AND v.vigente_verdict='PASS'
  AND v.scope_review_required=false
  AND r.estado='CANDIDATO' AND r.pendiente_decision IS NOT TRUE
  AND (r.valor_config->>'owner_decision_identity_verified' IS DISTINCT FROM 'false')
  AND r.id NOT IN (235,438,439,440,577,532)
  AND NOT EXISTS (SELECT 1 FROM public.lf_rule_promotion_v1 x
         WHERE x.rule_code=r.codigo AND x.status IN ('PENDING','APPROVED'));
 v_plan_sha:=encode(sha256(convert_to(jsonb_build_object(
    'schema_version','LF_RULE_V2_AUTO_PLAN_V1','items',v_items)::text,'UTF8')),'hex');
 RETURN jsonb_build_object('schema_version','LF_RULE_V2_AUTO_PLAN_V1',
    'eligible_count',jsonb_array_length(v_items),'rules',v_items,
    'plan_sha256',v_plan_sha,'continuation_allowed',true,
    'automatic_apply_authorized',false,'independent_step70_required',true,
    'verified_owner_receipt_required',true,'writes',0);
END $fn$;

-- This validates the *existing* canonical HUMAN decision authority chain.
-- A chat declaration / fake HUMAN: string / self-asserted JSON is never sufficient.
CREATE FUNCTION private.fn_lf_rule_promotion_v2_owner_receipt_check_v1(
 p_request_id uuid,p_subject_key text,p_source_sha256 text,
 p_decision_code text,p_rule_ids jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','private','public','programacion'
AS $fn$
DECLARE q record; d record; v_recomputed text;
BEGIN
 IF p_request_id IS NULL THEN RETURN jsonb_build_object(
   'status','FINDING','code','OWNER_VERIFIED_RECEIPT_MISSING'); END IF;
 SELECT * INTO q FROM private.lf_human_decision_requests_v1
 WHERE request_id=p_request_id;
 SELECT * INTO d FROM private.lf_human_decision_receipts_v1
 WHERE request_id=p_request_id;
 IF q.request_id IS NULL OR d.receipt_id IS NULL OR q.status<>'DECIDED'
   OR q.producer_code<>'RULE_PROMOTION' OR
   q.subject_type<>'LF_RULE_PROMOTION_BATCH_V2'
   OR q.subject_key IS DISTINCT FROM p_subject_key
   OR q.currentness_sha256 IS DISTINCT FROM p_source_sha256
   OR q.required_reviewer_role<>'LF_OWNER'
   OR d.reviewer_role<>'LF_OWNER'
   OR d.reviewer_identity<>'github:cristhianlujan'
   OR d.decision_code IS DISTINCT FROM p_decision_code
   OR d.observed_currentness_sha256 IS DISTINCT FROM p_source_sha256
   OR d.decision_payload->'rule_ids' IS DISTINCT FROM p_rule_ids
   OR d.authority_ref IS DISTINCT FROM q.required_authority_ref
   OR d.authority_receipt_sha256 !~ '^[0-9a-f]{64}$'
 THEN RETURN jsonb_build_object('status','FINDING',
    'code','OWNER_RECEIPT_NOT_BOUND_OR_NOT_VERIFIED'); END IF;
 IF d.receipt_sha256 IS DISTINCT FROM
   private.fn_lf_human_decision_receipt_sha_v1(
    q.request_id,q.request_sha256,d.decision_code,d.decision_payload,
    d.reviewer_identity,d.reviewer_role,d.authority_ref,
    d.authority_receipt_ref,d.authority_receipt_sha256,
    d.observed_currentness_sha256,d.metadata)
 THEN RETURN jsonb_build_object('status','FINDING',
   'code','OWNER_RECEIPT_DIGEST_MISMATCH'); END IF;
 BEGIN
   PERFORM private.fn_lf_human_decision_assert_authority_receipt_v1(
     q.request_id,d.decision_code,d.reviewer_role,
     d.authority_ref,d.authority_receipt_ref,
     d.authority_receipt_sha256,d.observed_currentness_sha256);
 EXCEPTION WHEN OTHERS THEN
   RETURN jsonb_build_object('status','FINDING','code','OWNER_AUTHORITY_CHAIN_NOT_ATTESTED');
 END;
 RETURN jsonb_build_object('status','VERIFIED','receipt_sha256',d.receipt_sha256,
   'reviewer_identity',d.reviewer_identity,'request_id',p_request_id,
   'authority_ref',d.authority_ref);
END $fn$;

-- One real Product Director run must bind Step40 -> 50 -> 60 -> INDEPENDENT 70
-- with a source_ref for EACH rule. Reusing completed/old model receipts forbidden.
CREATE FUNCTION public.lf_rule_promotion_v2_auto_execute_v1(
 p_execution_id text,p_owner_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE v_plan jsonb; v_owner jsonb; v_rule_ids jsonb; v_count int;
 v_item jsonb; v_issued jsonb; v_decided jsonb; v_applied jsonb;
 v_prom text; v_ids text[]:='{}'::text[]; v_result jsonb; v_rule record;
 v_arr jsonb:='[]'::jsonb; v_codes text[];
BEGIN
 v_plan:=public.lf_rule_promotion_v2_auto_plan_v1();
 v_count:=(v_plan->>'eligible_count')::int;
 IF v_count=0 THEN RETURN jsonb_build_object('status','NO_ELIGIBLE',
   'eligible_count',0,'applied',0,'continuation_allowed',true); END IF;
 SELECT coalesce(jsonb_agg((j.value->>'rule_id')::bigint ORDER BY
     (j.value->>'rule_id')::bigint),'[]'::jsonb)
 INTO v_rule_ids FROM jsonb_array_elements(v_plan->'rules') j(value);
 v_owner:=private.fn_lf_rule_promotion_v2_owner_receipt_check_v1(
   p_owner_request_id,p_execution_id,v_plan->>'plan_sha256','APPROVE',v_rule_ids);
 IF v_owner->>'status'<>'VERIFIED' THEN RETURN jsonb_build_object(
   'status','FINDING_NO_WRITE','code',v_owner->>'code',
   'eligible_count',v_count,'applied',0,'plan_sha256',v_plan->>'plan_sha256',
   'continuation_allowed',true,'next_action','VERIFIED_OWNER_APPROVAL_OF_EXACT_RULE_SET');
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
   WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS')
 THEN RETURN jsonb_build_object('status','FINDING_NO_WRITE',
  'code','ACTIVE_PRODUCT_DIRECTOR_PROFILE_REQUIRED','applied',0,
  'continuation_allowed',true); END IF;
 -- Pre-check binding for EVERY rule before any canonical writer request.
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_execution_id AND s.step_order=70
  AND s.status='STEP_PASS_WITH_EVIDENCE'
  AND s.step_id='semantic_judge'
  AND s.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
  AND s.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='true'
  AND s.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,judge_invocation_kind}'='NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE'
  AND (SELECT count(*) FROM jsonb_array_elements(v_plan->'rules') i
    WHERE EXISTS(SELECT 1 FROM public.lf_operation_execution_steps f
      WHERE f.execution_id=p_execution_id AND f.step_order=50
      AND f.status='STEP_PASS_WITH_EVIDENCE'
      AND f.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
      AND EXISTS(SELECT 1 FROM jsonb_array_elements(
         coalesce(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}','[]'::jsonb)) z
        WHERE z->>'source_ref'='supabase://lf_ops.reglas/'||(i->>'rule_code'))))=v_count)
 THEN RETURN jsonb_build_object('status','FINDING_NO_WRITE',
    'code','PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED_FOR_ALL_RULES',
    'eligible_count',v_count,'applied',0,'continuation_allowed',true);
 END IF;
 -- Request/decide/apply are still the only canonical writers.
 BEGIN
   FOR v_item IN SELECT value FROM jsonb_array_elements(v_plan->'rules') ORDER BY
          (value->>'rule_id')::bigint LOOP
     v_issued:=public.lf_rule_promotion_request_v1(
       p_execution_id,v_item->>'rule_code',
       'AUTO_V2: verified owner source set '||(v_plan->>'plan_sha256'));
     IF v_issued->>'status'<>'PENDING_HUMAN_APPROVAL' THEN
       RAISE EXCEPTION 'CANONICAL_REQUEST_REJECTED:%',v_issued->>'blocking_code';
     END IF;
     v_ids:=array_append(v_ids,v_issued->>'promotion_id');
     v_arr:=v_arr||jsonb_build_array(jsonb_build_object('rule_id',(v_item->>'rule_id')::bigint,
       'rule_code',v_item->>'rule_code','promotion_id',v_issued->>'promotion_id',
       'preimage_sha256',v_item->>'snapshot_sha256'));
   END LOOP;
   v_decided:=public.lf_rule_promotion_decide_batch_v1(
    v_ids,'APPROVE','HUMAN:'||(v_owner->>'reviewer_identity'),
    'VERIFIED_AUTHORITY_RECEIPT:'||(v_owner->>'receipt_sha256'));
   IF coalesce((v_decided->>'ok')::int,0)<>v_count OR coalesce((v_decided->>'blocked')::int,0)<>0
   THEN RAISE EXCEPTION 'CANONICAL_DECIDE_BATCH_NOT_ALL_APPROVED'; END IF;
   v_applied:=public.lf_rule_promotion_apply_batch_v1(v_ids);
   IF coalesce((v_applied->>'applied')::int,0)<>v_count OR coalesce((v_applied->>'blocked')::int,0)<>0
   THEN RAISE EXCEPTION 'CANONICAL_APPLY_BATCH_NOT_ALL_APPLIED'; END IF;
   FOR v_item IN SELECT value FROM jsonb_array_elements(v_arr) LOOP
     SELECT id,codigo,estado INTO v_rule FROM lf_ops.reglas
       WHERE id=(v_item->>'rule_id')::bigint;
     IF v_rule.estado<>'VIGENTE' THEN RAISE EXCEPTION 'AFTER_STATE_INCONSISTENT'; END IF;
     INSERT INTO public.lf_rule_promotion_auto_audit_v1(
       rule_id,rule_code,promotion_id,execution_id,owner_request_id,
       owner_receipt_sha256,source_plan_sha256,
       original_rule_snapshot_sha256,applied_rule_snapshot_sha256)
     VALUES(v_rule.id,v_rule.codigo,v_item->>'promotion_id',p_execution_id,
       p_owner_request_id,v_owner->>'receipt_sha256',v_plan->>'plan_sha256',
       v_item->>'preimage_sha256',
       public.lf_asset_snapshot_sha_v1('REGLA',v_rule.codigo));
   END LOOP;
   v_result:=jsonb_build_object('status','APPLIED_VERIFIED',
     'applied',v_count,'before_candidates',v_count,'applied_detail',v_arr,
     'plan_sha256',v_plan->>'plan_sha256','owner_receipt_id',p_owner_request_id,
     'continuation_allowed',true);
 EXCEPTION WHEN OTHERS THEN
   -- PLpgSQL subtransaction: undo ALL pending requests, batch approvals,
   -- candidate status changes and audit inserts from this block.
   v_result:=jsonb_build_object('status','FINDING_ATOMIC_ROLLBACK',
       'code','CANONICAL_BATCH_WRITER_OR_SOURCE_REJECTED',
       'applied',0,'eligible_count',v_count,
       'continuation_allowed',true,'next_action','SOURCE_AND_JUDGE_READBACK');
 END;
 RETURN v_result;
END $fn$;

CREATE FUNCTION public.lf_rule_promotion_v2_auto_reverse_v1(
 p_audit_id bigint,p_owner_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE a record;v_owner jsonb;v_current_sha text;v_sha text;
BEGIN
 SELECT * INTO a FROM public.lf_rule_promotion_auto_audit_v1
 WHERE audit_id=p_audit_id AND status='APPLIED' FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','FINDING_NO_WRITE',
    'code','REVERSIBLE_APPLIED_RECEIPT_NOT_FOUND','reverted',0); END IF;
 SELECT public.lf_asset_snapshot_sha_v1('REGLA',a.rule_code) INTO v_current_sha;
 IF v_current_sha IS DISTINCT FROM a.applied_rule_snapshot_sha256 THEN
   RETURN jsonb_build_object('status','FINDING_NO_WRITE',
     'code','RULE_CHANGED_AFTER_PROMOTION','reverted',0); END IF;
 v_sha:=encode(sha256(convert_to(jsonb_build_object(
  'schema_version','LF_RULE_V2_AUTO_REVERSAL_V1','audit_id',p_audit_id,
  'rule_id',a.rule_id,'after_sha256',a.applied_rule_snapshot_sha256)::text,'UTF8')),'hex');
 v_owner:=private.fn_lf_rule_promotion_v2_owner_receipt_check_v1(
  p_owner_request_id,'ROLLBACK:'||p_audit_id::text,v_sha,'APPROVE_ROLLBACK',
  jsonb_build_array(a.rule_id));
 IF v_owner->>'status'<>'VERIFIED' THEN RETURN jsonb_build_object(
  'status','FINDING_NO_WRITE','code',v_owner->>'code','reverted',0); END IF;
 UPDATE lf_ops.reglas SET estado='CANDIDATO'
 WHERE id=a.rule_id AND codigo=a.rule_code AND estado='VIGENTE';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','FINDING_NO_WRITE',
   'code','CURRENT_RULE_STATE_DRIFT','reverted',0); END IF;
 UPDATE public.lf_rule_promotion_auto_audit_v1
 SET status='REVERTED',reverted_at=now(),
 reverse_request_id=p_owner_request_id,
 reverse_receipt_sha256=v_owner->>'receipt_sha256'
 WHERE audit_id=p_audit_id;
 RETURN jsonb_build_object('status','REVERTED_VERIFIED','audit_id',p_audit_id,
   'rule_id',a.rule_id,'before','VIGENTE','after','CANDIDATO');
END $fn$;

REVOKE ALL ON TABLE public.lf_rule_promotion_auto_audit_v1 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_v2_auto_plan_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.fn_lf_rule_promotion_v2_owner_receipt_check_v1(uuid,text,text,text,jsonb)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_v2_auto_execute_v1(text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_v2_auto_reverse_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lf_rule_promotion_auto_audit_v1 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_v2_auto_plan_v1() TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_v2_auto_execute_v1(text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_v2_auto_reverse_v1(bigint,uuid) TO service_role;
COMMIT;

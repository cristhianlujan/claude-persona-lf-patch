-- LF sandbox: owner definition same LLM, NEW model call, own schema+prompt+eval.
-- No provider model-call attestation exists yet; NEVER infer independence
-- from a model-authored JSON or from a different GitHub workflow run.
-- Nonblocking finding preserves content-only Step70 and historical immutability.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_step70_separate_call_preflight_v1(
  p_execution_id text, p_call_receipt jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 s40 public.lf_operation_execution_steps%ROWTYPE;
 s50 public.lf_operation_execution_steps%ROWTYPE;
 s60 public.lf_operation_execution_steps%ROWTYPE;
 v_candidate text;
 v_scope text;
 v_schema text;
 v_eval text;
 v_fields text[];
 v_field text;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF e.execution_id IS NULL OR e.operation_code<>'EJECUCION_PERFIL_LF'
 OR e.target_type<>'PERFIL' OR e.status<>'IN_PROGRESS' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','STEP70_RUN_NOT_OPEN'); END IF;
 SELECT * INTO s40 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate';
 SELECT * INTO s50 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile';
 SELECT * INTO s60 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate';
 IF s40.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  OR s50.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  OR s60.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  OR s60.evidence_payload->>'output_contract_result' IS DISTINCT FROM 'PASS'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','STEP70_SOURCE_CHAIN_NOT_CLEAN');END IF;
 v_candidate:=s50.evidence_payload->>'raw_output_sha256';
 v_scope:=regexp_replace(coalesce(s40.evidence_payload->>'scope_authority_packet_sha256',''),
     '^sha256:','');
 v_schema:=s60.evidence_payload#>>'{deterministic_validation,source_bound_validation,source_refs,schema}';
 v_eval:=s60.evidence_payload#>>'{deterministic_validation,source_bound_validation,schema}';
 IF coalesce(v_candidate,'') !~ '^[0-9a-f]{64}$'
 OR coalesce(v_scope,'') !~ '^[0-9a-f]{64}$' THEN
  RETURN jsonb_build_object('status','BLOCKED','code','STEP70_SOURCE_HASHES_NOT_BOUND');END IF;
 IF jsonb_typeof(p_call_receipt)<>'object' THEN
  RETURN jsonb_build_object('status','JUDGE_INDEPENDENCE_NOT_PROVEN',
    'content_continuation_allowed',true,'independence_proven',false);END IF;
 v_fields:=ARRAY[
 'schema_version','receipt_ref','execution_id','model_id','model_call_id',
 'producer_call_ref','reviewer_call_ref','prompt_sha256',
 'producer_prompt_sha256','schema_id','producer_schema_id',
 'eval_id','producer_eval_id','eval_status','model_call_count',
 'candidate_sha256','scope_packet_sha256','decision_body','provider_attestation'];
 FOREACH v_field IN ARRAY v_fields LOOP
  IF NOT p_call_receipt ? v_field THEN RETURN jsonb_build_object(
    'status','JUDGE_INDEPENDENCE_NOT_PROVEN','code','STEP70_RECEIPT_FIELD_MISSING',
    'missing_field',v_field,'content_continuation_allowed',true,
    'independence_proven',false);END IF;
 END LOOP;
 IF p_call_receipt->>'schema_version' IS DISTINCT FROM
     'LF_STEP70_SAME_LLM_SEPARATE_CALL_RECEIPT_V1'
 OR p_call_receipt->>'execution_id' IS DISTINCT FROM p_execution_id
 OR p_call_receipt->>'candidate_sha256' IS DISTINCT FROM v_candidate
 OR p_call_receipt->>'scope_packet_sha256' IS DISTINCT FROM v_scope
 OR coalesce(p_call_receipt->>'model_call_id','') !~ '^[A-Za-z0-9_-]{16,128}$'
 OR coalesce(p_call_receipt->>'prompt_sha256','') !~ '^[0-9a-f]{64}$'
 OR coalesce(p_call_receipt->>'producer_prompt_sha256','') !~ '^[0-9a-f]{64}$'
 OR p_call_receipt->>'prompt_sha256'=p_call_receipt->>'producer_prompt_sha256'
 OR p_call_receipt->>'schema_id' IS DISTINCT FROM
   'LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1'
 OR p_call_receipt->>'eval_id' IS DISTINCT FROM
   'LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1'
 OR p_call_receipt->>'schema_id'=coalesce(v_schema,p_call_receipt->>'producer_schema_id')
 OR p_call_receipt->>'eval_id'=coalesce(v_eval,p_call_receipt->>'producer_eval_id')
 OR coalesce(p_call_receipt->>'producer_call_ref','')=''
 OR coalesce(p_call_receipt->>'reviewer_call_ref','')=''
 OR p_call_receipt->>'producer_call_ref'=p_call_receipt->>'reviewer_call_ref'
 OR coalesce(p_call_receipt->>'receipt_ref','')=''
 OR p_call_receipt->>'receipt_ref'=p_call_receipt->>'producer_call_ref'
 OR p_call_receipt->>'eval_status' IS DISTINCT FROM 'PASS'
 OR coalesce(p_call_receipt->>'model_call_count','') !~ '^[1-9][0-9]*$'
 OR p_call_receipt#>>'{decision_body,verdict}' IS DISTINCT FROM
   'PASS_INDEPENDENT_SEMANTIC'
 THEN RETURN jsonb_build_object('status','JUDGE_INDEPENDENCE_NOT_PROVEN',
  'code','STEP70_RECEIPT_SOURCE_OR_SCHEMA_EVAL_MISMATCH',
  'content_continuation_allowed',true,'independence_proven',false);END IF;
 -- A different workflow run or a valid JSON is NOT an independent LLM call.
 -- Provider attestation must be verified by a trusted upstream model host.
 -- No such authenticated verification endpoint is currently authorized.
 RETURN jsonb_build_object(
  'status','RECEIPT_FORMAT_VALID_MODEL_CALL_NOT_ATTESTED',
  'execution_id',p_execution_id,
  'candidate_sha256',v_candidate,
  'scope_packet_sha256',v_scope,
  'schema_id',p_call_receipt->>'schema_id',
  'eval_id',p_call_receipt->>'eval_id',
  'model_call_count_asserted',p_call_receipt->>'model_call_count',
  'receipt_ref_unverified',p_call_receipt->>'receipt_ref',
  'independence_proven',false,
  'reviewer_is_producer_unknown',true,
  'finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN',
  'content_continuation_allowed',true);
END $fn$;

-- A readback surface joins historical immutable source steps to their
-- append-only findings; DOES NOT backfill or alter original evidence_payload.
CREATE OR REPLACE VIEW public.v_lf_profile_step70_independence_readback_v1 AS
SELECT s.execution_id,s.step_order,s.step_id,s.status,
       s.evidence_ref,
       s.evidence_payload AS original_evidence_payload,
       f.finding_code AS separate_finding_code,
       CASE WHEN f.execution_id IS NOT NULL THEN true ELSE false END AS
         finding_stored_outside_original_step,
       coalesce(s.evidence_payload->'content_findings',
         CASE WHEN f.execution_id IS NOT NULL THEN jsonb_build_array(
           jsonb_build_object('finding_code',f.finding_code,
             'source','APPEND_ONLY_HISTORICAL_READBACK',
             'independence_proven',false,'content_continuation_allowed',true))
         ELSE '[]'::jsonb END) AS combined_findings,
       s.evidence_payload->>'independent_semantic_receipt_ref'
         AS independent_semantic_receipt_ref
FROM public.lf_operation_execution_steps s
LEFT JOIN public.lf_profile_semantic_independence_finding_v1 f
 ON f.execution_id=s.execution_id
 AND ((s.step_id='semantic_judge' AND f.step70_sha256=
    encode(extensions.digest(convert_to(s.evidence_payload::text,'UTF8'),'sha256'),'hex'))
 OR (s.step_id='report_output' AND f.step80_sha256=
    encode(extensions.digest(convert_to(s.evidence_payload::text,'UTF8'),'sha256'),'hex')))
WHERE s.step_id IN ('semantic_judge','report_output');

REVOKE ALL ON FUNCTION public.lf_profile_step70_separate_call_preflight_v1(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_step70_separate_call_preflight_v1(text,jsonb) TO service_role;
REVOKE ALL ON public.v_lf_profile_step70_independence_readback_v1 FROM PUBLIC;
GRANT SELECT ON public.v_lf_profile_step70_independence_readback_v1 TO service_role;
-- No broad read access: model review evidence may contain private source refs.

COMMIT;

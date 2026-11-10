-- LF #3774 | Durable per-rule authority marks and governed Product promotion handoff.
-- DEPENDS on 20261110170000_lf_rule_promotion_governed_authority_v1.sql.
-- No new profile, skill, Router path, policy, owner approval or issuer.
-- Internal post-70/ pre-80 operations; NOT a new official profile step.
BEGIN;
DO $preflight$
BEGIN
 IF to_regprocedure('public.lf_rule_promotion_authority_assess_v1(text)') IS NULL
 OR to_regprocedure('public.lf_rule_promotion_auto_ratify_v1(text,bigint)') IS NULL
 OR to_regprocedure('public.lf_rule_promotion_request_v1(text,text,text)') IS NULL
 THEN RAISE EXCEPTION 'BLOCK_AUTHORITY_MARK_DEPENDENCY_MISSING'; END IF;
 IF to_regclass('public.lf_rule_authority_tracking_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'BLOCK_AUTHORITY_MARK_TRACKER_ALREADY_INSTALLED'; END IF;
END $preflight$;

CREATE TABLE public.lf_rule_authority_tracking_v1 (
 screen_code text NOT NULL,
 rule_code text NOT NULL,
 marca text NOT NULL,
 motivo_codigo text NOT NULL,
 estado_flujo text NOT NULL CHECK(estado_flujo IN
   ('REMEDIACION_INTERNA','ESPERA_RECIBO_ACCION','PROMOCION_SOLICITADA',
    'VIGENTE_VERIFICADA')),
 rule_snapshot_sha256 text NOT NULL CHECK(rule_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
 source_decision_id text,
 source_decision_sha256 text,
 promotion_id text,
 execution_id text NOT NULL,
 evidence_ref text NOT NULL,
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[0-9a-f]{64}$'),
 first_recorded_at timestamptz NOT NULL DEFAULT now(),
 last_checked_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(screen_code,rule_code),
 CONSTRAINT lf_rule_authority_mark_known CHECK(marca IN
 ('SOURCE_LOOKUP_REQUIRED','SOURCE_AMBIGUOUS','SOURCE_NOT_OWNER_APPROVED',
  'SOURCE_SUPERSEDED_RECONCILE','MATERIAL_PARITY_UNPROVEN',
  'PENDING_DECISION_UNRESOLVED','PRODUCTION_ACTIVATION_NOT_AUTHORIZED',
  'ACTION_AUTHORIZATION_RECEIPT_REQUIRED','PROMOTION_REQUESTED',
  'PROMOTED_VERIFIED'))
);
CREATE INDEX lf_rule_authority_tracking_marca_idx
 ON public.lf_rule_authority_tracking_v1(marca,screen_code);
CREATE INDEX lf_rule_authority_tracking_execution_idx
 ON public.lf_rule_authority_tracking_v1(execution_id,last_checked_at DESC);

-- A consumer can filter *all* linked rules, even before any worker run.
-- An old marker with a changed rule SHA NEVER claims current eligibility.
-- VIGENTE is tied to the official APPLIED promotion ledger, not a boolean flag.
CREATE VIEW public.v_lf_rule_authority_filter_v1
WITH (security_invoker=true) AS
SELECT p.codigo AS pantalla_codigo,r.codigo AS regla_codigo,
 r.estado AS estado_regla,
 CASE
   WHEN r.estado='VIGENTE'
     AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 promo
       WHERE promo.rule_code=r.codigo AND promo.status='APPLIED')
     THEN 'PROMOVIDA_VERIFICADA'
   WHEN r.estado='VIGENTE' THEN 'VIGENTE_SIN_PROMOCION_EN_LEDGER'
   WHEN r.estado<>'CANDIDATO' THEN 'NO_CANDIDATO'
   WHEN t.rule_code IS NULL THEN 'SIN_EVALUACION_REGISTRADA'
   WHEN t.rule_snapshot_sha256 IS DISTINCT FROM
     public.lf_asset_snapshot_sha_v1('REGLA',r.codigo) THEN 'REVALIDAR_SNAPSHOT'
   ELSE t.marca
 END AS marca,
 CASE WHEN t.rule_code IS NULL THEN 'NO_INICIADO'
   WHEN t.rule_snapshot_sha256 IS DISTINCT FROM
     public.lf_asset_snapshot_sha_v1('REGLA',r.codigo) THEN 'REVALIDAR'
   ELSE t.estado_flujo END AS estado_flujo,
 t.motivo_codigo,t.source_decision_id,t.promotion_id,t.execution_id,
 t.evidence_ref,t.evidence_sha256,t.last_checked_at
FROM lf_ops.reglas r
JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
LEFT JOIN public.lf_rule_authority_tracking_v1 t
 ON t.rule_code=r.codigo AND t.screen_code=p.codigo;

-- Checks canonical parent, original Router receipt, stage 70 independent
-- judge, and output-validator SHA before permitting ONLY ledger marks.
CREATE FUNCTION public.lf_rule_authority_parent_guard_v1(
 p_execution_id text,p_screen_code text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops'
AS $guard$
DECLARE par public.lf_operation_execution%ROWTYPE;
 val jsonb;jud jsonb;
BEGIN
 SELECT * INTO par FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id
 AND operation_code='EJECUCION_PERFIL_LF'
 AND target_type='PERFIL'
 AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND status='IN_PROGRESS';
 IF NOT FOUND OR par.manifest->>'read_only' IS DISTINCT FROM 'true'
 OR par.manifest->>'no_write' IS DISTINCT FROM 'true'
 OR par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
 OR par.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'
    IS DISTINCT FROM 'true'
 OR par.manifest#>>'{screen_selection_result,selected_screen_code}'
    IS DISTINCT FROM p_screen_code THEN
  RETURN jsonb_build_object('status','BLOCKED','code','PRODUCT_RUN_SCOPE_OR_ROUTER_INVALID');
 END IF;
 SELECT evidence_payload INTO val
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='output_validate'
 AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO jud
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='semantic_judge'
 AND status='STEP_PASS_WITH_EVIDENCE';
 IF val IS NULL OR jud IS NULL
 OR val->>'output_contract_result' IS DISTINCT FROM 'PASS'
 OR coalesce(val->>'raw_output_sha256','') !~ '^[0-9a-f]{64}$'
 OR jud#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
 OR coalesce(jud#>>'{semantic_judge_result,verdict}','') NOT IN
    ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
 OR jud#>>'{semantic_judge_result,candidate_sha256}'
    IS DISTINCT FROM val->>'raw_output_sha256'
 OR jud->'unsupported_claims' IS DISTINCT FROM '[]'::jsonb
 OR jud->'blocking_codes' IS DISTINCT FROM '[]'::jsonb
 OR jud#>'{semantic_judge_result,result,unsupported_claims}'
    IS DISTINCT FROM '[]'::jsonb
 OR jud#>'{semantic_judge_result,result,blocking_codes}'
    IS DISTINCT FROM '[]'::jsonb THEN
  RETURN jsonb_build_object('status','BLOCKED','code','PRODUCT_JUDGE_OR_VALIDATOR_NOT_CLEAN');
 END IF;
 RETURN jsonb_build_object('status','PASS','profile_code',par.target_code,
  'parent_execution_id',p_execution_id,'screen_code',p_screen_code,
  'judge_sha256',jud#>>'{semantic_judge_result,candidate_sha256}');
END $guard$;

-- Persist one filterable authoritative *assessment* mark per candidate.
-- A human decision is not requested automatically by the marker.
-- Even a positive assessment has estado_flujo=ESPERA_RECIBO_ACCION.
CREATE FUNCTION public.lf_rule_authority_mark_refresh_v1(
 p_execution_id text,p_screen_code text,p_evidence_ref text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','extensions'
AS $mark$
DECLARE auth jsonb; assessment jsonb; item jsonb;
 target text; m text; sha text; flow text; checked_count int:=0;
BEGIN
 auth:=public.lf_rule_authority_parent_guard_v1(p_execution_id,p_screen_code);
 IF auth->>'status'<>'PASS' THEN RETURN auth; END IF;
 IF nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL
 OR length(p_evidence_ref)>1200
 THEN RETURN jsonb_build_object('status','BLOCKED','code','EXACT_EVIDENCE_REF_REQUIRED'); END IF;
 assessment:=public.lf_rule_promotion_authority_assess_v1(p_screen_code);
 IF assessment->>'status'<>'ASSESSED_READ_ONLY'
 OR assessment->>'action_authorized' IS DISTINCT FROM 'false'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','AUTHORITY_ASSESSMENT_NOT_TRUSTED'); END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(assessment->'details')
 LOOP
  target:=item->>'rule_code';m:=item->>'blocking_code';sha:=item->>'rule_sha256';
  IF m IS NULL OR m NOT IN
   ('SOURCE_LOOKUP_REQUIRED','SOURCE_AMBIGUOUS','SOURCE_NOT_OWNER_APPROVED',
    'SOURCE_SUPERSEDED_RECONCILE','MATERIAL_PARITY_UNPROVEN',
    'PENDING_DECISION_UNRESOLVED','PRODUCTION_ACTIVATION_NOT_AUTHORIZED',
    'ACTION_AUTHORIZATION_RECEIPT_REQUIRED')
  OR coalesce(sha,'') !~ '^[0-9a-f]{64}$'
  OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r
     JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
     JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
     WHERE p.codigo=p_screen_code AND r.codigo=target
       AND r.estado='CANDIDATO'
       AND public.lf_asset_snapshot_sha_v1('REGLA',target)=sha)
  THEN RAISE EXCEPTION 'BLOCK_AUTHORITY_MARK_STALE_OR_INVALID:%',target; END IF;
  flow:=CASE WHEN m='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
    THEN 'ESPERA_RECIBO_ACCION' ELSE 'REMEDIACION_INTERNA' END;
  INSERT INTO public.lf_rule_authority_tracking_v1(
   screen_code,rule_code,marca,motivo_codigo,estado_flujo,
   rule_snapshot_sha256,source_decision_id,source_decision_sha256,
   promotion_id,execution_id,evidence_ref,evidence_sha256,last_checked_at
  ) VALUES (
   p_screen_code,target,m,m,flow,sha,
   item->>'source_decision_id',item->>'source_decision_sha256',NULL,
   p_execution_id,p_evidence_ref,
   encode(extensions.digest(convert_to(item::text,'UTF8'),'sha256'),'hex'),now()
  )
  ON CONFLICT(screen_code,rule_code) DO UPDATE SET
   marca=EXCLUDED.marca,motivo_codigo=EXCLUDED.motivo_codigo,
   estado_flujo=EXCLUDED.estado_flujo,
   rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256,
   source_decision_id=EXCLUDED.source_decision_id,
   source_decision_sha256=EXCLUDED.source_decision_sha256,
   -- Preserve a verified existing promotion request only for identical SHA.
   promotion_id=CASE
    WHEN public.lf_rule_authority_tracking_v1.rule_snapshot_sha256
      =EXCLUDED.rule_snapshot_sha256
     AND public.lf_rule_authority_tracking_v1.marca='PROMOTION_REQUESTED'
     AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
       WHERE q.promotion_id=public.lf_rule_authority_tracking_v1.promotion_id
       AND q.status IN ('PENDING','APPROVED'))
    THEN public.lf_rule_authority_tracking_v1.promotion_id ELSE NULL END,
   execution_id=EXCLUDED.execution_id,evidence_ref=EXCLUDED.evidence_ref,
   evidence_sha256=EXCLUDED.evidence_sha256,last_checked_at=now();
  checked_count:=checked_count+1;
 END LOOP;
 IF checked_count<>(assessment->>'candidate_count')::int
 THEN RAISE EXCEPTION 'BLOCK_AUTHORITY_MARK_COUNT_DRIFT'; END IF;
 RETURN jsonb_build_object('status','MARKS_RECORDED','screen_code',p_screen_code,
  'marked',checked_count,'promoted',0,'action_authorized',false,
  'next_action','RECONCILE_SOURCE_OR_REQUEST_VERIFIED_RECEIPT');
END $mark$;

-- Optional sub-action 70.5, NOT a new numbered official profile step.
-- Parent must already have a clean judge and a current stored mark.
-- If no independent issuer exists, request is not opened speculatively.
CREATE FUNCTION public.lf_rule_promotion_request_eligible_v1(
 p_execution_id text,p_screen_code text,p_rule_code text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','programacion'
AS $request$
DECLARE auth jsonb; t public.lf_rule_authority_tracking_v1%ROWTYPE;
 item jsonb; assess jsonb; raw jsonb;
BEGIN
 auth:=public.lf_rule_authority_parent_guard_v1(p_execution_id,p_screen_code);
 IF auth->>'status'<>'PASS' THEN RETURN auth; END IF;
 SELECT * INTO t FROM public.lf_rule_authority_tracking_v1
 WHERE screen_code=p_screen_code AND rule_code=p_rule_code FOR UPDATE;
 IF NOT FOUND OR t.estado_flujo<>'ESPERA_RECIBO_ACCION'
 OR t.marca<>'ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
 OR t.rule_snapshot_sha256 IS DISTINCT FROM
   public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code)
 OR t.execution_id IS DISTINCT FROM p_execution_id THEN
  RETURN jsonb_build_object('status','BLOCKED','code','CURRENT_ELIGIBILITY_MARK_REQUIRED');
 END IF;
 assess:=public.lf_rule_promotion_authority_assess_v1(p_screen_code);
 SELECT x.value INTO item FROM jsonb_array_elements(assess->'details') AS x(value)
 WHERE x.value->>'rule_code'=p_rule_code;
 IF item IS NULL
 OR item->>'blocking_code' IS DISTINCT FROM 'ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
 OR item->>'rule_sha256' IS DISTINCT FROM t.rule_snapshot_sha256
 OR item->>'source_decision_sha256' IS DISTINCT FROM t.source_decision_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','code','SOURCE_OR_PARITY_REVALIDATION_REQUIRED'); END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.provenance_channels
   WHERE channel_code='LF_RULE_PROMOTION_ACTION_AUTHORITY_V1'
   AND 'RULE_PROMOTION_ACTION_AUTHORIZATION'=ANY(allowed_kinds)) THEN
  RETURN jsonb_build_object('status','BLOCKED',
    'code','INDEPENDENT_PROMOTION_ISSUER_NOT_CONFIGURED',
    'marca','ACTION_AUTHORIZATION_RECEIPT_REQUIRED',
    'rule_code',p_rule_code);
 END IF;
 raw:=public.lf_rule_promotion_request_v1(p_execution_id,p_rule_code,
 'GOVERNED_SOURCE_PARITY:'||coalesce(t.source_decision_id,'')||
 ' / SNAPSHOT:'||t.rule_snapshot_sha256);
 IF raw->>'promotion_id' IS NULL THEN RETURN raw; END IF;
 UPDATE public.lf_rule_authority_tracking_v1 SET
  marca='PROMOTION_REQUESTED',motivo_codigo='WAIT_GOVERNED_ACTION_RECEIPT',
  estado_flujo='PROMOCION_SOLICITADA',promotion_id=raw->>'promotion_id',
  last_checked_at=now()
 WHERE screen_code=p_screen_code AND rule_code=p_rule_code
   AND rule_snapshot_sha256=t.rule_snapshot_sha256;
 RETURN jsonb_build_object(
  'status','WAIT_GOVERNED_ACTION_RECEIPT',
  'promotion_id',raw->>'promotion_id',
  'rule_code',p_rule_code,
  'business_redecision_required',false,
  'next_action','EXTERNAL_ISSUER_DECIDE_AND_DELIVER_PROTECTED_RECEIPT');
END $request$;

-- Optional sub-action 70.6: Product requests completion with an independently
-- issued receipt; this wrapper does not produce/forge a receipt or HUMAN.
CREATE FUNCTION public.lf_rule_promotion_complete_tracked_v1(
 p_execution_id text,p_screen_code text,p_rule_code text,p_receipt_id bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','programacion'
AS $complete$
DECLARE auth jsonb; t public.lf_rule_authority_tracking_v1%ROWTYPE;
 result jsonb; after_sha text;
BEGIN
 auth:=public.lf_rule_authority_parent_guard_v1(p_execution_id,p_screen_code);
 IF auth->>'status'<>'PASS' THEN RETURN auth; END IF;
 SELECT * INTO t FROM public.lf_rule_authority_tracking_v1
 WHERE screen_code=p_screen_code AND rule_code=p_rule_code FOR UPDATE;
 IF NOT FOUND OR t.estado_flujo<>'PROMOCION_SOLICITADA'
 OR t.marca<>'PROMOTION_REQUESTED' OR t.promotion_id IS NULL
 OR t.execution_id IS DISTINCT FROM p_execution_id
 OR t.rule_snapshot_sha256 IS DISTINCT FROM
   public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code)
 OR NOT EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
   WHERE q.promotion_id=t.promotion_id AND q.rule_code=p_rule_code
   AND q.request_execution_id=p_execution_id
   AND q.status='PENDING' AND q.request_snapshot_sha256=t.rule_snapshot_sha256)
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PENDING_PROMOTION_BINDING_OR_SHA_INVALID'); END IF;
 result:=public.lf_rule_promotion_auto_ratify_v1(t.promotion_id,p_receipt_id);
 IF result->>'status'<>'APPLIED_VERIFIED' THEN RETURN result; END IF;
 IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas r WHERE r.codigo=p_rule_code
   AND r.estado='VIGENTE' AND r.pendiente_decision=false)
 THEN RAISE EXCEPTION 'BLOCK_TRACKED_PROMOTION_FINAL_READBACK'; END IF;
 after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 UPDATE public.lf_rule_authority_tracking_v1 SET
   marca='PROMOTED_VERIFIED',motivo_codigo='APPLIED_BY_GOVERNED_RECEIPT',
   estado_flujo='VIGENTE_VERIFICADA',rule_snapshot_sha256=after_sha,
   last_checked_at=now()
 WHERE screen_code=p_screen_code AND rule_code=p_rule_code
   AND promotion_id=t.promotion_id;
 RETURN result||jsonb_build_object('marca','PROMOVIDA_VERIFICADA',
   'estado_flujo','VIGENTE_VERIFICADA','rule_snapshot_sha256',after_sha);
END $complete$;

REVOKE ALL ON TABLE public.lf_rule_authority_tracking_v1
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON TABLE public.v_lf_rule_authority_filter_v1
 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.lf_rule_authority_tracking_v1 TO service_role;
GRANT SELECT ON TABLE public.v_lf_rule_authority_filter_v1 TO service_role;
REVOKE ALL ON FUNCTION public.lf_rule_authority_parent_guard_v1(text,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_authority_mark_refresh_v1(text,text,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_request_eligible_v1(text,text,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_complete_tracked_v1(text,text,text,bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_authority_parent_guard_v1(text,text)
 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_authority_mark_refresh_v1(text,text,text)
 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_request_eligible_v1(text,text,text)
 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_complete_tracked_v1(text,text,text,bigint)
 TO service_role;
COMMIT;

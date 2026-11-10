-- LF #3774 / Rule promotion semantic authority + governed ratification, candidate.
-- Existing Product Director -> IG -> governed operation remains intact.
-- No new skill/profile, Router change or implicit human queue.
-- An owner-approved SOURCE is not an action authorization. An externally
-- issued, protected, exact-target ACTION receipt is separately required.
-- No issuer/channel is activated by this migration: fail closed by default.
BEGIN;

DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
    <> '16e45f40dad5cecc215a2f978be47728' THEN
   -- Source drift must be deliberately reconciled before changing any path.
   RAISE EXCEPTION 'BLOCK_RULE_PROMOTION_HUMAN_DECIDER_SOURCE_DRIFT';
 END IF;
 IF to_regprocedure('public.lf_rule_promotion_authority_assess_v1(text)') IS NOT NULL
 OR to_regprocedure('public.lf_rule_promotion_auto_ratify_v1(text,bigint)') IS NOT NULL
 THEN RAISE EXCEPTION 'BLOCK_RULE_PROMOTION_ALREADY_INSTALLED'; END IF;
 IF md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
     <> 'd7fe763c999db6f6259b6b1e2bd69644'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_guard_v1()'::regprocedure))
     <> 'ee782e4bd0128c80ee13881899c0d74e'
 OR md5(pg_get_functiondef('programacion.fn_guard_provenance_receipt_insert()'::regprocedure))
     <> '32da02afebd3f8ff4281b52312f0aaec'
 THEN RAISE EXCEPTION 'BLOCK_RULE_PROMOTION_GUARD_SOURCE_DRIFT'; END IF;
END $preflight$;

CREATE FUNCTION public.lf_rule_promotion_authority_assess_v1(p_screen_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','extensions'
AS $assess$
DECLARE result jsonb;
BEGIN
 IF nullif(btrim(coalesce(p_screen_code,'')),'') IS NULL
 OR NOT EXISTS(SELECT 1 FROM lf_ops.pantallas p WHERE p.codigo=p_screen_code)
 THEN RETURN jsonb_build_object('status','BLOCKED','code','SCREEN_NOT_FOUND_OR_UNSCOPED'); END IF;

 WITH candidates AS (
   SELECT DISTINCT r.id,r.codigo,r.categoria,r.titulo,r.descripcion,r.razon,
     r.valor_config,r.estado,r.origen,r.pendiente_decision,r.pendiente_detalle,
     r.updated_at,public.lf_asset_snapshot_sha_v1('REGLA',r.codigo) rule_sha256
   FROM lf_ops.reglas r
   JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
   WHERE p.codigo=p_screen_code AND r.estado='CANDIDATO'
 ), selected AS (
   SELECT c.*,
    (SELECT count(*) FROM public.lf_decisiones_gov d
      WHERE d.id_decision=c.origen
         OR (nullif(c.valor_config->>'source_decision_id','') IS NOT NULL
             AND d.id_decision=c.valor_config->>'source_decision_id')
         OR (coalesce(c.valor_config->>'source_decision_number','') ~ '^[0-9]{1,12}$'
             AND d.decision_number::text=c.valor_config->>'source_decision_number')
    ) AS source_count,
    (SELECT to_jsonb(d) FROM public.lf_decisiones_gov d
      WHERE d.id_decision=c.origen
         OR (nullif(c.valor_config->>'source_decision_id','') IS NOT NULL
             AND d.id_decision=c.valor_config->>'source_decision_id')
         OR (coalesce(c.valor_config->>'source_decision_number','') ~ '^[0-9]{1,12}$'
             AND d.decision_number::text=c.valor_config->>'source_decision_number')
      ORDER BY d.updated_at DESC,d.id_decision LIMIT 1
    ) AS decision
   FROM candidates c
 ), checked AS (
   SELECT s.*,
    s.decision->>'id_decision' AS decision_id,
    s.decision->>'estado_normalizado' AS decision_state,
    s.decision->'raw_payload' AS payload,
    s.source_count=1
      AND s.decision->>'estado_normalizado' IN
          ('APROBADA','VIGENTE','CANDIDATO_APROBADO_POR_OWNER')
      AND (
        s.decision->>'estado_original'='APROBADO_POR_OWNER'
        OR s.decision->>'estado_normalizado' IN
          ('APROBADA','VIGENTE','CANDIDATO_APROBADO_POR_OWNER')
      ) AS source_owner_approved,
    s.source_count=1 AND
      s.decision->'raw_payload'->>'rule_code'=s.codigo AND
      s.decision->'raw_payload'->>'title'=s.titulo AND
      s.decision->'raw_payload'->>'description'=s.descripcion AND
      s.decision->'raw_payload'->>'reason' IS NOT DISTINCT FROM s.razon AND
      s.decision->'raw_payload'->>'category'=s.categoria AND
      s.decision->'raw_payload'->>'transversal'=s.es_transversal::text AND
      s.decision->'raw_payload'->'rule_config' IS NOT DISTINCT FROM s.valor_config
      AS exact_material_parity,
    EXISTS(SELECT 1 FROM public.lf_decisiones_gov newer
      WHERE newer.id_decision IS DISTINCT FROM s.decision->>'id_decision'
        AND (newer.raw_payload->>'supersedes_decision_id'=s.decision->>'id_decision'
          OR newer.raw_payload->>'supersedes_decision_number'
               = s.decision->>'decision_number')
    ) AS has_successor
   FROM selected s
 ), classified AS (
  SELECT x.*,
    CASE
      WHEN source_count=0 THEN 'SOURCE_LOOKUP_REQUIRED'
      WHEN source_count<>1 THEN 'SOURCE_AMBIGUOUS'
      WHEN NOT coalesce(source_owner_approved,false) THEN 'SOURCE_NOT_OWNER_APPROVED'
      WHEN has_successor THEN 'SOURCE_SUPERSEDED_RECONCILE'
      WHEN NOT coalesce(exact_material_parity,false) THEN 'MATERIAL_PARITY_UNPROVEN'
      WHEN coalesce(pendiente_decision,false) THEN 'PENDING_DECISION_UNRESOLVED'
      WHEN coalesce(valor_config->>'production_authorized','true')='false'
        THEN 'PRODUCTION_ACTIVATION_NOT_AUTHORIZED'
      ELSE 'ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
    END AS blocking_code
  FROM checked x
 )
 SELECT jsonb_build_object(
   'schema_version','lf-rule-promotion-authority/v1',
   'status','ASSESSED_READ_ONLY','screen_code',p_screen_code,
   'candidate_count',count(*),
   'action_authorized',false,'human_queue_allowed',false,
   'requires_verified_action_receipt',true,
   'source_count',count(*) FILTER(WHERE source_count=1),
   'exact_owner_approved_count',count(*) FILTER(
      WHERE blocking_code='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'),
   'internal_remediation_count',count(*) FILTER(
      WHERE blocking_code<>'ACTION_AUTHORIZATION_RECEIPT_REQUIRED'),
   'details',coalesce(jsonb_agg(jsonb_build_object(
     'rule_code',codigo,'rule_sha256',rule_sha256,'status',
       CASE WHEN blocking_code='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
            THEN 'GOVERNED_AUTHORIZATION_PENDING' ELSE 'INTERNAL_REMEDIATION' END,
     'blocking_code',blocking_code,'source_count',source_count,
     'source_decision_id',decision_id,'source_state',decision_state,
     'source_owner_approved',source_owner_approved,
     'exact_material_parity',exact_material_parity,
     'source_has_successor',has_successor,
     'source_decision_sha256',CASE WHEN decision IS NOT NULL
       THEN encode(extensions.digest(convert_to(decision::text,'UTF8'),'sha256'),'hex')
       ELSE NULL END,
     'pending_decision',pendiente_decision,
     'human_decision_required',false,'action_authorized',false
   ) ORDER BY codigo),'[]'::jsonb)
 ) INTO result
 FROM classified;
 RETURN result;
END
$assess$;

-- This does not call the human decider with a forged HUMAN identity.
-- It verifies the external issuer-token-protected receipt against the exact
-- promotion request, rule preimage, source semantics, and currentness.
CREATE FUNCTION public.lf_rule_promotion_auto_ratify_v1(
  p_promotion_id text,p_receipt_id bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path='pg_catalog','public','programacion','extensions','lf_ops'
AS $ratify$
DECLARE
 promo public.lf_rule_promotion_v1%ROWTYPE;
 rule_row lf_ops.reglas%ROWTYPE;
 proof programacion.provenance_receipts%ROWTYPE;
 screen_code text;eligible jsonb;detail jsonb;expected_source_sha text;
 report jsonb; issuer_kinds text[];
BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
     <> 'd7fe763c999db6f6259b6b1e2bd69644'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_guard_v1()'::regprocedure))
     <> 'ee782e4bd0128c80ee13881899c0d74e'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROMOTION_RUNTIME_SOURCE_DRIFT'); END IF;
 IF coalesce(p_promotion_id,'')='' OR p_receipt_id IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','code','RATIFICATION_INPUT_REQUIRED'); END IF;
 SELECT * INTO promo FROM public.lf_rule_promotion_v1
 WHERE promotion_id=p_promotion_id AND status='PENDING' FOR UPDATE;
 IF NOT FOUND THEN
 RETURN jsonb_build_object('status','BLOCKED','code','PROMOTION_REQUEST_NOT_PENDING'); END IF;
 SELECT * INTO rule_row FROM lf_ops.reglas
 WHERE codigo=promo.rule_code FOR UPDATE;
 IF NOT FOUND OR rule_row.estado<>'CANDIDATO' OR rule_row.pendiente_decision
 OR public.lf_asset_snapshot_sha_v1('REGLA',promo.rule_code)
    IS DISTINCT FROM promo.request_snapshot_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROMOTION_PREIMAGE_OR_STATE_INVALID'); END IF;
 IF promo.requested_by_profile<>'PERFIL-PRODUCT-DIRECTOR-LF'
 OR NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1 a
   WHERE a.profile_code=promo.requested_by_profile AND a.operation_code='PROMOCION_REGLA_LF'
      AND a.status='ACTIVE')
 OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
   WHERE e.execution_id=promo.request_execution_id
     AND e.operation_code='EJECUCION_PERFIL_LF'
     AND e.target_code=promo.requested_by_profile
     AND e.manifest->>'no_promotion'='true')
 THEN RETURN jsonb_build_object('status','BLOCKED','code','PROMOTION_PROFILE_BINDING_INVALID'); END IF;
 SELECT p.codigo INTO screen_code FROM lf_ops.reglas_pantallas rp
 JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
 WHERE rp.regla_id=rule_row.id
 ORDER BY p.codigo LIMIT 1;
 IF screen_code IS NULL THEN
 RETURN jsonb_build_object('status','BLOCKED','code','RULE_SCREEN_SCOPE_MISSING'); END IF;
 eligible:=public.lf_rule_promotion_authority_assess_v1(screen_code);
 SELECT elem.value INTO detail
 FROM jsonb_array_elements(eligible->'details') AS elem(value)
 WHERE elem.value->>'rule_code'=promo.rule_code;
 IF detail IS NULL OR detail->>'blocking_code'<>'ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'code','SOURCE_SEMANTIC_AUTHORITY_UNPROVEN','assessment',detail); END IF;
 expected_source_sha:=detail->>'source_decision_sha256';
 SELECT * INTO proof FROM programacion.provenance_receipts WHERE id=p_receipt_id;
 SELECT allowed_kinds INTO issuer_kinds FROM programacion.provenance_channels
 WHERE channel_code=proof.issuer_channel;
 IF NOT FOUND OR proof.issuer_channel IS DISTINCT FROM 'LF_RULE_PROMOTION_ACTION_AUTHORITY_V1'
 OR nullif(btrim(proof.issuer_identity),'') IS NULL
 OR proof.issuer_identity='product_director_lf'
 OR proof.created_at<promo.created_at
 OR proof.receipt_kind<>'RULE_PROMOTION_ACTION_AUTHORIZATION'
 OR NOT coalesce(proof.receipt_kind=ANY(issuer_kinds),false)
 OR proof.subject_type<>'LF_RULE_PROMOTION'
 OR proof.subject_ref IS DISTINCT FROM p_promotion_id
 OR proof.subject_sha256 IS DISTINCT FROM promo.request_snapshot_sha256
 OR proof.payload->>'action_code' IS DISTINCT FROM 'PROMOTE_GOVERNED_CANDIDATE'
 OR proof.payload->>'promotion_id' IS DISTINCT FROM p_promotion_id
 OR proof.payload->>'rule_code' IS DISTINCT FROM promo.rule_code
 OR proof.payload->>'source_decision_id' IS DISTINCT FROM detail->>'source_decision_id'
 OR proof.payload->>'source_decision_sha256' IS DISTINCT FROM expected_source_sha
 OR proof.payload->>'request_execution_id' IS DISTINCT FROM promo.request_execution_id
 OR proof.payload->>'source_currentness' IS DISTINCT FROM 'CURRENT'
 OR proof.payload->>'semantic_parity' IS DISTINCT FROM 'MATCH_EXACT'
 OR proof.payload->>'decision' IS DISTINCT FROM 'APPROVE'
 OR proof.payload->>'security_gate' IS DISTINCT FROM 'PASS'
 OR proof.payload->>'owner_policy' IS DISTINCT FROM 'CURRENT_AUTHORITY'
 OR proof.payload->>'rule_snapshot_sha256' IS DISTINCT FROM promo.request_snapshot_sha256
 OR proof.payload->>'head_sha' IS DISTINCT FROM proof.head_sha
 OR proof.payload->>'subject_sha256' IS DISTINCT FROM proof.subject_sha256
 OR proof.payload->>'subject_ref' IS DISTINCT FROM proof.subject_ref
 OR proof.payload->>'subject_type' IS DISTINCT FROM proof.subject_type
 OR proof.receipt_sha256 IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(
   jsonb_build_object('schema_version',1,'receipt_kind',proof.receipt_kind,
    'execution_id',proof.execution_id,'head_sha',proof.head_sha,
    'subject_type',proof.subject_type,'subject_ref',proof.subject_ref,
    'subject_sha256',proof.subject_sha256,'issuer_channel',proof.issuer_channel,
    'issuer_identity',proof.issuer_identity,'verification_ref',proof.verification_ref,
    'payload',proof.payload))
 THEN RETURN jsonb_build_object('status','BLOCKED','code','EXTERNAL_ACTION_RECEIPT_NOT_VERIFIED'); END IF;
 -- This narrowly ratifies the already-authorized action; current HUMAN route remains.
 UPDATE public.lf_rule_promotion_v1
 SET status='APPROVED',decided_by='GOVERNED:'||proof.issuer_channel||':'||proof.id::text,
    decided_at=now(),reason=coalesce(reason,'')||' | VERIFIED_RECEIPT:'||proof.id
 WHERE promotion_id=p_promotion_id AND status='PENDING';
 report:=public.lf_rule_promotion_apply_v1(p_promotion_id);
 IF report->>'status' IS DISTINCT FROM 'APPLIED'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas
   WHERE codigo=promo.rule_code AND estado='VIGENTE' AND pendiente_decision=false)
 THEN RAISE EXCEPTION 'BLOCK_AUTO_RATIFICATION_ATOMIC_APPLY'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED',
   'rule_code',promo.rule_code,'promotion_id',p_promotion_id,
   'action_receipt_id',p_receipt_id,'human_business_redecision',false,
   'source_decision_id',detail->>'source_decision_id',
   'rule_state','VIGENTE');
END
$ratify$;

REVOKE ALL ON FUNCTION public.lf_rule_promotion_authority_assess_v1(text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_auto_ratify_v1(text,bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_authority_assess_v1(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_auto_ratify_v1(text,bigint) TO service_role;
COMMIT;

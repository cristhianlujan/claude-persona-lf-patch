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
 ig_proposal_sha256 text NOT NULL CHECK(ig_proposal_sha256 ~ '^[0-9a-f]{64}$'),
 product_disposition text NOT NULL CHECK(product_disposition IN ('ACCEPT_PROPOSAL','ADJUST_PROPOSAL','REJECT_PROPOSAL')),
 product_rationale text NOT NULL,
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
  'PRODUCT_IG_ADJUSTMENT_REQUIRED','PRODUCT_IG_REJECTED',
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
 t.ig_proposal_sha256,t.product_disposition,t.product_rationale,
 t.evidence_ref,t.evidence_sha256,t.last_checked_at
FROM lf_ops.reglas r
JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
LEFT JOIN public.lf_rule_authority_tracking_v1 t
 ON t.rule_code=r.codigo AND t.screen_code=p.codigo;

-- Read-only deterministic source discovery inside the EXISTING IG dependency.
-- Technical policy links and mentions are SEARCH LEADS, never owner authority.
-- This function does not update rule origins, issue receipt, or open human queues.
CREATE FUNCTION public.lf_ig_rule_source_recovery_v1(
 p_execution_id text,p_screen_code text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','programacion','extensions'
AS $recover$
DECLARE par public.lf_operation_execution%ROWTYPE;
 result jsonb; v_n integer;
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
  RETURN jsonb_build_object('status','BLOCKED',
    'code','IG_RECOVERY_ROUTER_OR_SCOPE_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps st
   WHERE st.execution_id=p_execution_id
     AND st.step_id='input_validate' AND st.status='STEP_PASS_WITH_EVIDENCE') THEN
  RETURN jsonb_build_object('status','BLOCKED',
    'code','IG_RECOVERY_STEP40_REQUIRED'); END IF;
 WITH scope AS (
   SELECT DISTINCT r.id,r.codigo,r.origen,r.created_by,r.valor_config,r.estado,
    public.lf_asset_snapshot_sha_v1('REGLA',r.codigo) rule_sha
   FROM lf_ops.reglas r
   JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
   WHERE p.codigo=p_screen_code AND r.estado='CANDIDATO'
 ), raw_evidence AS (
   SELECT r.codigo,r.rule_sha,
     jsonb_build_object(
       'rule_code',r.codigo,'rule_snapshot_sha256',r.rule_sha,
       'origin_label',r.origen,'historical_created_by',r.created_by,
       'origin_class',CASE WHEN r.origen LIKE 'OWNER_%'
         THEN 'OWNER_CLAIM_NOT_ATTESTED'
         WHEN r.origen LIKE 'DEC-%' THEN 'DECISION_REFERENCE_NOT_YET_PARITY_PROOF'
         ELSE 'HANDOFF_OR_LOT_LABEL_NOT_APPROVAL' END,
       'source_decision_direct',coalesce((
         SELECT jsonb_agg(jsonb_build_object(
           'decision_id',d.id_decision,'state',d.estado_normalizado,
           'decision_number',d.decision_number,
           'authority_status','CHECK_EXACT_MATERIAL_PARITY_SEPARATELY'
         ) ORDER BY d.id_decision)
         FROM public.lf_decisiones_gov d WHERE
           d.id_decision=r.origen
           OR (nullif(r.valor_config->>'source_decision_id','') IS NOT NULL
             AND d.id_decision=r.valor_config->>'source_decision_id')
           OR (coalesce(r.valor_config->>'source_decision_number','')
               ~ '^[0-9]{1,12}$' AND
             d.decision_number::text=r.valor_config->>'source_decision_number')
       ),'[]'::jsonb),
       'decision_text_mentions',coalesce((
         SELECT jsonb_agg(jsonb_build_object(
           'decision_id',d.id_decision,'decision_number',d.decision_number,
           'state',d.estado_normalizado,
           'evidence_role','MENTION_ONLY_NOT_BUSINESS_APPROVAL'
         ) ORDER BY d.decision_number)
         FROM public.lf_decisiones_gov d WHERE (
           position(r.codigo in coalesce(d.documento_relacionado,''))>0
           OR position(r.codigo in coalesce(d.decision,''))>0
           OR position(r.codigo in coalesce(d.raw_payload::text,''))>0
         ) AND d.id_decision IS DISTINCT FROM r.origen
           AND d.id_decision IS DISTINCT FROM r.valor_config->>'source_decision_id'
           AND (coalesce(r.valor_config->>'source_decision_number','')=''
                OR d.decision_number::text IS DISTINCT FROM
                   r.valor_config->>'source_decision_number')
       ),'[]'::jsonb),
       'technical_links',coalesce((
         SELECT jsonb_agg(jsonb_build_object(
           'link_id',l.link_id,'reference_role',l.reference_role,
           'target_table',l.target_table,'target_id',l.target_id,
           'link_state',l.status,
           'evidence_role','TECHNICAL_REFERENCE_NOT_OWNER_APPROVAL'
         ) ORDER BY l.link_id)
         FROM programacion.t_remed_link_sources x
         JOIN programacion.t_remed_links l ON l.link_id=x.link_id
         WHERE x.rule_id=r.id
       ),'[]'::jsonb),
       'explicit_policy_references',coalesce((
         SELECT jsonb_agg(jsonb_build_object(
           'registry',pol.registry,'policy_code',pol.policy_code,
           'policy_id',pol.policy_id,'state',pol.state,
           'source_decision_id',pol.source_decision_id,
           'source_decision_state',d.estado_normalizado,
           'evidence_role','POLICY_REFERENCE_NOT_RULE_PARITY',
           'policy_sha256',pol.policy_sha256
         ) ORDER BY pol.registry,pol.policy_code)
         FROM (
           SELECT 'lf_ops.politicas_seguridad' registry,
             p.security_policy_id::text policy_id,p.policy_code,p.status state,
             p.source_decision_id,
             encode(extensions.digest(convert_to(to_jsonb(p)::text,'UTF8'),'sha256'),'hex') policy_sha256
           FROM lf_ops.politicas_seguridad p
           WHERE p.security_policy_id::text=r.valor_config->>'security_policy_id'
           UNION ALL
           SELECT 'lf_ops.politicas_sesion',p.session_policy_id::text,
             p.policy_code,p.status,p.source_decision_id,
             encode(extensions.digest(convert_to(to_jsonb(p)::text,'UTF8'),'sha256'),'hex')
           FROM lf_ops.politicas_sesion p
           WHERE p.session_policy_id::text=r.valor_config->>'session_policy_id'
           UNION ALL
           SELECT 'lf_ops.politicas_rate_limit',p.rate_limit_policy_id::text,
             p.policy_code,p.status,p.source_decision_id,
             encode(extensions.digest(convert_to(to_jsonb(p)::text,'UTF8'),'sha256'),'hex')
           FROM lf_ops.politicas_rate_limit p
           WHERE p.rate_limit_policy_id::text=r.valor_config->>'rate_limit_policy_id'
           UNION ALL
           SELECT 'lf_ops.politicas_timeout',p.timeout_policy_id::text,
             p.policy_code,p.status,p.source_decision_id,
             encode(extensions.digest(convert_to(to_jsonb(p)::text,'UTF8'),'sha256'),'hex')
           FROM lf_ops.politicas_timeout p
           WHERE p.timeout_policy_id::text=r.valor_config->>'timeout_policy_id'
           UNION ALL
           SELECT 'lf_ops.otp_politicas',p.id::text,p.codigo,
             p.estado,NULL::text,
             encode(extensions.digest(convert_to(to_jsonb(p)::text,'UTF8'),'sha256'),'hex')
           FROM lf_ops.otp_politicas p
           WHERE p.codigo=r.valor_config->>'email_otp_policy_code'
         ) pol LEFT JOIN public.lf_decisiones_gov d
           ON d.id_decision=pol.source_decision_id
       ),'[]'::jsonb),
       'unresolved_policy_keys',coalesce((
         SELECT jsonb_agg(jsonb_build_object('key',kv.key,'value',kv.value)
           ORDER BY kv.key)
         FROM jsonb_each(r.valor_config) kv
         WHERE kv.key LIKE '%policy_id' OR kv.key LIKE '%policy_code'
       ),'[]'::jsonb),
       'rule_semantics_approved',false,
       'promotion_authorized',false
     ) AS evidence
   FROM scope r
 ), classified AS (
  SELECT e.codigo,e.rule_sha,e.evidence,
   CASE
    WHEN jsonb_array_length(e.evidence->'source_decision_direct')>0
      THEN 'DIRECT_DECISION_REFERENCE_REQUIRES_PARITY'
    WHEN jsonb_array_length(e.evidence->'decision_text_mentions')>0
      THEN 'DECISION_MENTION_REQUIRES_AUTHORITY_REVIEW'
    WHEN jsonb_array_length(e.evidence->'explicit_policy_references')>0
      THEN 'POLICY_LINEAGE_REQUIRES_AUTHORITY_REVIEW'
    WHEN jsonb_array_length(e.evidence->'technical_links')>0
      THEN 'TECHNICAL_LINEAGE_REQUIRES_AUTHORITY_REVIEW'
    ELSE 'ORIGINAL_SOURCE_NOT_FOUND'
   END status
  FROM raw_evidence e
 )
 SELECT jsonb_build_object(
  'status','IG_SOURCE_DISCOVERY_READ_ONLY',
  'schema_version','LF_IG_RULE_SOURCE_RECOVERY_V1',
  'screen_code',p_screen_code,'execution_id',p_execution_id,
  'rule_count',count(*),'direct_decision_count',
   count(*) FILTER(WHERE status='DIRECT_DECISION_REFERENCE_REQUIRES_PARITY'),
  'source_lookup_count',
   count(*) FILTER(WHERE status<>'DIRECT_DECISION_REFERENCE_REQUIRES_PARITY'),
  'technical_linked_rule_count',
   count(*) FILTER(WHERE jsonb_array_length(evidence->'technical_links')>0),
  'policy_linked_rule_count',
   count(*) FILTER(WHERE jsonb_array_length(evidence->'explicit_policy_references')>0),
  'text_mentioned_rule_count',
   count(*) FILTER(WHERE jsonb_array_length(evidence->'decision_text_mentions')>0),
  'items',coalesce(jsonb_agg(jsonb_build_object(
   'rule_code',codigo,'rule_snapshot_sha256',rule_sha,
   'discovery_status',status,
   'evidence',evidence,
   'discovery_sha256',encode(extensions.digest(
     convert_to(evidence::text,'UTF8'),'sha256'),'hex'),
   'owner_approval_proven',false,
   'action_authorized',false
  ) ORDER BY codigo),'[]'::jsonb),
  'owner_authority_inferred',false,'promoted',0,'human_queue_created',false
 ) INTO result FROM classified;
 RETURN result;
END $recover$;

REVOKE ALL ON FUNCTION public.lf_ig_rule_source_recovery_v1(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ig_rule_source_recovery_v1(text,text)
 TO service_role;

-- Input Governance proposes once, BEFORE Product Director starts work.
-- This is read-only, not a second LLM and never a permit to promote.
-- Source evidence is exactly the preexisting authority assessment; when
-- authority is missing the proposal is to recover it, NOT invent rule values.
CREATE FUNCTION public.lf_ig_rule_proposal_prepare_v1(
 p_execution_id text,p_screen_code text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops','extensions'
AS $igproposal$
DECLARE par public.lf_operation_execution%ROWTYPE;
 assess jsonb; proposals jsonb; recovery jsonb; v_screen_code text;
BEGIN
 SELECT * INTO par FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id AND operation_code='EJECUCION_PERFIL_LF'
 AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND target_type='PERFIL' AND status='IN_PROGRESS';
 v_screen_code:=coalesce(nullif(btrim(coalesce(p_screen_code,'')),''),
    par.manifest#>>'{screen_selection_result,selected_screen_code}');
 IF NOT FOUND OR par.manifest->>'read_only' IS DISTINCT FROM 'true'
 OR par.manifest->>'no_write' IS DISTINCT FROM 'true'
 OR par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
 OR par.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'
   IS DISTINCT FROM 'true'
 OR par.manifest#>>'{screen_selection_result,selected_screen_code}'
   IS DISTINCT FROM v_screen_code
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'code','IG_PROPOSAL_ROUTER_OR_SCOPE_INVALID'); END IF;
 IF v_screen_code IS NULL THEN RETURN jsonb_build_object(
  'status','IG_PROPOSAL_NOT_APPLICABLE','proposal_count',0,
  'proposals','[]'::jsonb,'action_authorized',false); END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_operation_execution_steps st
    WHERE st.execution_id=p_execution_id
      AND st.step_id='input_validate'
      AND st.status='STEP_PASS_WITH_EVIDENCE'
 ) THEN RETURN jsonb_build_object('status','BLOCKED',
   'code','IG_PROPOSAL_INPUT_GOVERNANCE_STEP40_REQUIRED'); END IF;
 assess:=public.lf_rule_promotion_authority_assess_v1(v_screen_code);
 IF assess->>'status' IS DISTINCT FROM 'ASSESSED_READ_ONLY'
 OR assess->>'action_authorized' IS DISTINCT FROM 'false'
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'code','IG_PROPOSAL_SOURCE_ASSESSMENT_INVALID'); END IF;
 recovery:=public.lf_ig_rule_source_recovery_v1(p_execution_id,v_screen_code);
 IF recovery->>'status' IS DISTINCT FROM 'IG_SOURCE_DISCOVERY_READ_ONLY'
 OR recovery->>'rule_count' IS DISTINCT FROM assess->>'candidate_count'
 OR recovery->>'owner_authority_inferred' IS DISTINCT FROM 'false'
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'code','IG_PROPOSAL_SOURCE_DISCOVERY_UNTRUSTED_OR_DRIFT'); END IF;
 SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'rule_code',itm.value->>'rule_code',
      'ig_problem_code',itm.value->>'blocking_code',
      'proposed_action',
       CASE itm.value->>'blocking_code'
       WHEN 'SOURCE_LOOKUP_REQUIRED' THEN (
         SELECT CASE src.value->>'discovery_status'
         WHEN 'DECISION_MENTION_REQUIRES_AUTHORITY_REVIEW'
           THEN 'RECONCILE_RELATED_DECISION_REFERENCE'
         WHEN 'POLICY_LINEAGE_REQUIRES_AUTHORITY_REVIEW'
           THEN 'RECONCILE_POLICY_LINEAGE_AND_OWNER_DECISION'
         WHEN 'TECHNICAL_LINEAGE_REQUIRES_AUTHORITY_REVIEW'
           THEN 'RECONCILE_TECHNICAL_LINEAGE_TO_ORIGINAL_APPROVAL'
         ELSE 'SEARCH_ORIGINAL_OWNER_SOURCE' END
         FROM jsonb_array_elements(recovery->'items') src(value)
         WHERE src.value->>'rule_code'=itm.value->>'rule_code'
       )
       WHEN 'SOURCE_AMBIGUOUS' THEN 'RECONCILE_MULTIPLE_AUTHORITY_SOURCES'
       WHEN 'SOURCE_NOT_OWNER_APPROVED' THEN 'RESOLVE_EXISTING_OWNER_DECISION'
       WHEN 'SOURCE_SUPERSEDED_RECONCILE' THEN 'BIND_LATEST_APPROVED_DECISION'
       WHEN 'MATERIAL_PARITY_UNPROVEN' THEN 'RECONCILE_RULE_TO_CURRENT_APPROVED_SOURCE'
       WHEN 'PENDING_DECISION_UNRESOLVED' THEN 'RESOLVE_EXPLICIT_PENDING_DECISION'
       WHEN 'PRODUCTION_ACTIVATION_NOT_AUTHORIZED' THEN 'KEEP_PRODUCTION_BLOCKED'
       WHEN 'ACTION_AUTHORIZATION_RECEIPT_REQUIRED' THEN 'REQUEST_GOVERNED_PROMOTION'
       ELSE 'BLOCK_UNCLASSIFIED_CASE'
       END,
      'reason',CASE
        WHEN itm.value->>'blocking_code'='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
        THEN 'Current owner source and exact rule parity proved; action authorization remains separate'
        WHEN itm.value->>'blocking_code'='SOURCE_LOOKUP_REQUIRED'
        THEN 'No direct approved owner decision; use linked evidence only as search leads, verify original owner authority and rule parity before any promotion'
        ELSE 'Preserve current candidate state until exact authority, values and supersession are reconciled'
        END,
      'rule_sha256',itm.value->>'rule_sha256',
      'source_decision_id',itm.value->>'source_decision_id',
      'source_decision_sha256',itm.value->>'source_decision_sha256',
      'source_recovery',(
       SELECT src.value FROM jsonb_array_elements(recovery->'items') src(value)
       WHERE src.value->>'rule_code'=itm.value->>'rule_code'
      ),
      'ig_proposal_sha256',encode(extensions.digest(
         convert_to(jsonb_build_object(
           'authority_assessment',itm.value,
           'source_recovery',(
             SELECT src.value FROM jsonb_array_elements(recovery->'items') src(value)
             WHERE src.value->>'rule_code'=itm.value->>'rule_code'
           ))::text,'UTF8'),'sha256'),'hex'),
      'source_evidence',itm.value,
      'needs_human_decision',CASE
        WHEN itm.value->>'blocking_code'='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
        THEN 'NO_NEW_BUSINESS_DECISION'
        ELSE 'UNDETERMINED_UNTIL_RECONCILIATION' END,
      'action_authorized',false
    ) ORDER BY itm.value->>'rule_code'),'[]'::jsonb)
 INTO proposals
 FROM jsonb_array_elements(assess->'details') AS itm(value);
 RETURN jsonb_build_object(
   'schema_version','LF_IG_RULE_RESOLUTION_PROPOSAL_V1',
   'status','IG_PROPOSAL_READY',
   'execution_id',p_execution_id,'screen_code',v_screen_code,
   'proposal_count',jsonb_array_length(proposals),
   'source_discovery_summary',jsonb_build_object(
    'rule_count',recovery->'rule_count',
    'source_lookup_count',recovery->'source_lookup_count',
    'technical_linked_rule_count',recovery->'technical_linked_rule_count',
    'policy_linked_rule_count',recovery->'policy_linked_rule_count',
    'text_mentioned_rule_count',recovery->'text_mentioned_rule_count'),
   'proposals',proposals,
   'next_actor','PERFIL-PRODUCT-DIRECTOR-LF',
   'next_action','PROFILE_REVIEW_EXISTING_IG_PROPOSAL',
   'action_authorized',false,
   'promotion_allowed',false);
END $igproposal$;

-- Checks canonical parent, original Router receipt, stage 70 independent
-- judge, and output-validator SHA before permitting ONLY ledger marks.
CREATE FUNCTION public.lf_rule_authority_parent_guard_v1(
 p_execution_id text,p_screen_code text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops'
AS $guard$
DECLARE par public.lf_operation_execution%ROWTYPE;
 val jsonb;jud jsonb;outp jsonb;
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
 SELECT evidence_payload->'profile_output' INTO outp
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='execute_profile'
 AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO val
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='output_validate'
 AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO jud
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='semantic_judge'
 AND status='STEP_PASS_WITH_EVIDENCE';
 IF outp IS NULL OR outp->>'worker' IS DISTINCT FROM 'product_director_lf'
 OR outp->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
 OR val IS NULL OR jud IS NULL
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
 ig_bundle jsonb; reviews jsonb; review jsonb; proposal jsonb;
 target text; m text; sha text; flow text; checked_count int:=0;
 found_count int;
BEGIN
 auth:=public.lf_rule_authority_parent_guard_v1(p_execution_id,p_screen_code);
 IF auth->>'status'<>'PASS' THEN RETURN auth; END IF;
 IF nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL
 OR length(p_evidence_ref)>1200
 OR NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps step
    WHERE step.execution_id=p_execution_id
    AND step.step_id='semantic_judge'
    AND step.status='STEP_PASS_WITH_EVIDENCE'
    AND step.evidence_ref=p_evidence_ref)
 THEN RETURN jsonb_build_object('status','BLOCKED',
  'code','EXACT_JUDGE_EVIDENCE_REF_REQUIRED'); END IF;
 assessment:=public.lf_rule_promotion_authority_assess_v1(p_screen_code);
 IF assessment->>'status'<>'ASSESSED_READ_ONLY'
 OR assessment->>'action_authorized' IS DISTINCT FROM 'false'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','AUTHORITY_ASSESSMENT_NOT_TRUSTED'); END IF;
 -- Product Director must explicitly review every exact upstream IG proposal.
 -- Prevalidate the complete array before any tracking-table mutation.
 ig_bundle:=public.lf_ig_rule_proposal_prepare_v1(p_execution_id,p_screen_code);
 SELECT st.evidence_payload#>'{profile_output,traceability,ig_rule_proposal_decisions}'
 INTO reviews FROM public.lf_operation_execution_steps st
 WHERE st.execution_id=p_execution_id AND st.step_id='execute_profile'
 AND st.status='STEP_PASS_WITH_EVIDENCE';
 IF ig_bundle->>'status' IS DISTINCT FROM 'IG_PROPOSAL_READY'
 OR jsonb_typeof(reviews) IS DISTINCT FROM 'array'
 OR jsonb_array_length(reviews)<>(assessment->>'candidate_count')::int
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'code','PRODUCT_IG_PROPOSAL_REVIEW_MISSING_OR_DRIFT'); END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(assessment->'details') LOOP
  SELECT e.value INTO proposal FROM jsonb_array_elements(ig_bundle->'proposals') AS e(value)
   WHERE e.value->>'rule_code'=item->>'rule_code';
  SELECT count(*),max(e.value::text)::jsonb INTO found_count,review
   FROM jsonb_array_elements(reviews) AS e(value)
   WHERE e.value->>'rule_code'=item->>'rule_code'
   AND e.value->>'ig_proposal_sha256'=proposal->>'ig_proposal_sha256'
   AND e.value->>'disposition' IN
    ('ACCEPT_PROPOSAL','ADJUST_PROPOSAL','REJECT_PROPOSAL')
   AND length(btrim(coalesce(e.value->>'rationale','')))>=8;
  IF proposal IS NULL OR found_count<>1 THEN RETURN jsonb_build_object(
    'status','BLOCKED','code','PRODUCT_IG_PROPOSAL_SHA_OR_REVIEW_INVALID',
    'rule_code',item->>'rule_code'); END IF;
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(assessment->'details')
 LOOP
  target:=item->>'rule_code';m:=item->>'blocking_code';sha:=item->>'rule_sha256';
  SELECT e.value INTO proposal FROM jsonb_array_elements(ig_bundle->'proposals') e(value)
   WHERE e.value->>'rule_code'=target;
  SELECT e.value INTO review FROM jsonb_array_elements(reviews) e(value)
   WHERE e.value->>'rule_code'=target;
  IF review->>'disposition'='ADJUST_PROPOSAL' THEN
    m:='PRODUCT_IG_ADJUSTMENT_REQUIRED';
  ELSIF review->>'disposition'='REJECT_PROPOSAL' THEN
    m:='PRODUCT_IG_REJECTED'; END IF;
  IF m IS NULL OR m NOT IN
   ('SOURCE_LOOKUP_REQUIRED','SOURCE_AMBIGUOUS','SOURCE_NOT_OWNER_APPROVED',
    'SOURCE_SUPERSEDED_RECONCILE','MATERIAL_PARITY_UNPROVEN',
    'PENDING_DECISION_UNRESOLVED','PRODUCTION_ACTIVATION_NOT_AUTHORIZED',
    'ACTION_AUTHORIZATION_RECEIPT_REQUIRED',
    'PRODUCT_IG_ADJUSTMENT_REQUIRED','PRODUCT_IG_REJECTED')
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
   ig_proposal_sha256,product_disposition,product_rationale,
   promotion_id,execution_id,evidence_ref,evidence_sha256,last_checked_at
  ) VALUES (
   p_screen_code,target,m,m,flow,sha,
   item->>'source_decision_id',item->>'source_decision_sha256',
   proposal->>'ig_proposal_sha256',review->>'disposition',review->>'rationale',NULL,
   p_execution_id,p_evidence_ref,
   encode(extensions.digest(convert_to(item::text,'UTF8'),'sha256'),'hex'),now()
  )
  ON CONFLICT(screen_code,rule_code) DO UPDATE SET
   -- Preserve a genuinely pending request ONLY while rule AND decision
   -- source match the new authoritative assessment. Otherwise invalidate.
   marca=CASE
      WHEN public.lf_rule_authority_tracking_v1.marca='PROMOTION_REQUESTED'
       AND EXCLUDED.marca='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
       AND EXCLUDED.product_disposition='ACCEPT_PROPOSAL'
       AND public.lf_rule_authority_tracking_v1.rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256
       AND public.lf_rule_authority_tracking_v1.source_decision_sha256
           IS NOT DISTINCT FROM EXCLUDED.source_decision_sha256
       AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
         WHERE q.promotion_id=public.lf_rule_authority_tracking_v1.promotion_id
           AND q.status='PENDING'
           AND q.request_snapshot_sha256=EXCLUDED.rule_snapshot_sha256)
      THEN 'PROMOTION_REQUESTED' ELSE EXCLUDED.marca END,
   motivo_codigo=CASE
      WHEN public.lf_rule_authority_tracking_v1.marca='PROMOTION_REQUESTED'
       AND EXCLUDED.marca='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
       AND EXCLUDED.product_disposition='ACCEPT_PROPOSAL'
       AND public.lf_rule_authority_tracking_v1.rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256
       AND public.lf_rule_authority_tracking_v1.source_decision_sha256
           IS NOT DISTINCT FROM EXCLUDED.source_decision_sha256
       AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
         WHERE q.promotion_id=public.lf_rule_authority_tracking_v1.promotion_id
           AND q.status='PENDING')
      THEN 'WAIT_GOVERNED_ACTION_RECEIPT' ELSE EXCLUDED.motivo_codigo END,
   estado_flujo=CASE
      WHEN public.lf_rule_authority_tracking_v1.marca='PROMOTION_REQUESTED'
       AND EXCLUDED.marca='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
       AND EXCLUDED.product_disposition='ACCEPT_PROPOSAL'
       AND public.lf_rule_authority_tracking_v1.rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256
       AND public.lf_rule_authority_tracking_v1.source_decision_sha256
           IS NOT DISTINCT FROM EXCLUDED.source_decision_sha256
       AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
         WHERE q.promotion_id=public.lf_rule_authority_tracking_v1.promotion_id
           AND q.status='PENDING')
      THEN 'PROMOCION_SOLICITADA' ELSE EXCLUDED.estado_flujo END,
   rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256,
   source_decision_id=EXCLUDED.source_decision_id,
   source_decision_sha256=EXCLUDED.source_decision_sha256,
   ig_proposal_sha256=EXCLUDED.ig_proposal_sha256,
   product_disposition=EXCLUDED.product_disposition,
   product_rationale=EXCLUDED.product_rationale,
   promotion_id=CASE
    WHEN public.lf_rule_authority_tracking_v1.marca='PROMOTION_REQUESTED'
      AND EXCLUDED.marca='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
       AND EXCLUDED.product_disposition='ACCEPT_PROPOSAL'
      AND public.lf_rule_authority_tracking_v1.rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256
      AND public.lf_rule_authority_tracking_v1.source_decision_sha256
          IS NOT DISTINCT FROM EXCLUDED.source_decision_sha256
      AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
        WHERE q.promotion_id=public.lf_rule_authority_tracking_v1.promotion_id
          AND q.status='PENDING'
          AND q.request_snapshot_sha256=EXCLUDED.rule_snapshot_sha256)
    THEN public.lf_rule_authority_tracking_v1.promotion_id ELSE NULL END,
   execution_id=CASE
    WHEN public.lf_rule_authority_tracking_v1.marca='PROMOTION_REQUESTED'
      AND EXCLUDED.marca='ACTION_AUTHORIZATION_RECEIPT_REQUIRED'
       AND EXCLUDED.product_disposition='ACCEPT_PROPOSAL'
      AND public.lf_rule_authority_tracking_v1.rule_snapshot_sha256=EXCLUDED.rule_snapshot_sha256
      AND public.lf_rule_authority_tracking_v1.source_decision_sha256
          IS NOT DISTINCT FROM EXCLUDED.source_decision_sha256
      AND EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1 q
        WHERE q.promotion_id=public.lf_rule_authority_tracking_v1.promotion_id
          AND q.status='PENDING')
    THEN public.lf_rule_authority_tracking_v1.execution_id
    ELSE EXCLUDED.execution_id END,
   evidence_ref=EXCLUDED.evidence_ref,
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
 OR t.product_disposition<>'ACCEPT_PROPOSAL'
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
REVOKE ALL ON FUNCTION public.lf_ig_rule_proposal_prepare_v1(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ig_rule_proposal_prepare_v1(text,text)
 TO service_role;
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

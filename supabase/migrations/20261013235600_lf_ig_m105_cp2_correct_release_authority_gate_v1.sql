-- CP2 only: align authentic release gate; do not change any promotion authority or activate production.

CREATE OR REPLACE VIEW programacion.v_ig_m105_cp2_execution_preflight_v1
WITH (security_invoker=true) AS
WITH release AS (
 SELECT c.capability_code,c.version,c.previous_version,c.manifest_sha256,
  c.promoted_at,c.promoted_by_execution_id,
  v.release_state,v.supersedes_version
 FROM public.lf_capability_current c JOIN public.lf_capability_version_registry v
 ON v.capability_code=c.capability_code AND v.version=c.version
 WHERE c.capability_code='INPUT_GOVERNANCE'
), ready AS(
 SELECT r.id,r.receipt_sha256,r.payload#>>'{manifest,bundle_sha256}' bundle_sha
 FROM programacion.provenance_receipts r WHERE
 r.subject_type='IG_CUTOVER_READINESS'
 AND r.subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
 AND r.receipt_kind='EVIDENCE_VERIFICATION'
 AND r.issuer_channel='EVIDENCE_VERIFIER_V1'
 AND r.payload->>'verification_status'='VERIFIED'
 AND r.payload->>'readiness_status'='CUTOVER_READY'
 ORDER BY id DESC LIMIT 1
), evaluation AS(
 SELECT v.*, (v.previous_version IS NOT NULL
  AND v.version IS DISTINCT FROM v.previous_version
  AND v.release_state='RELEASED'
  AND v.supersedes_version=v.previous_version) authentic_release,
  EXISTS(SELECT 1 FROM ready WHERE bundle_sha~'^[0-9a-f]{64}$') readiness_receipt_present,
  EXISTS(
   SELECT 1 FROM programacion.human_decisions d
   JOIN programacion.provenance_receipts a ON a.id=d.authority_receipt_id
   JOIN ready rd ON true
   WHERE d.decision='APPROVE'
   AND d.metadata->>'decision_class'='CUTOVER_AUTHORIZED'
   AND d.metadata->>'capability_code'='INPUT_GOVERNANCE'
   AND d.metadata->>'release_id'=v.version
   AND d.metadata->>'release_manifest_sha256'=v.manifest_sha256
   AND d.metadata->>'cutover_readiness_receipt_sha256'=rd.receipt_sha256
   AND d.metadata->>'authority_role'='SUPER_ADMIN'
   AND d.created_at<=v.promoted_at
   AND a.receipt_kind='HUMAN_DECISION' AND a.issuer_channel='HUMAN_AUTHORITY_V1'
   AND a.subject_type='human_decision' AND a.subject_ref=d.approval_ref
   AND a.subject_sha256=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(programacion.fn_v09_canonical_jsonb_text(jsonb_build_object(
    'execution_id',d.execution_id,'head_sha',d.head_sha,
    'decision',d.decision,'actor_identity',d.actor_identity,
    'approval_ref',d.approval_ref,'metadata',d.metadata)),'UTF8'),'sha256'),'hex')
  ) signed_release_authorization_present
 FROM release v
)
SELECT *,
 authentic_release AND readiness_receipt_present
 AND signed_release_authorization_present
 AND coalesce(btrim(promoted_by_execution_id),'')<>'' AS can_attempt_real_cp2
FROM evaluation;

CREATE OR REPLACE FUNCTION public.fn_ig_m105_cp2_attest_run_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, programacion, public
AS $m105$
DECLARE
 v_run programacion.input_readiness_runs%rowtype;
 v_release record;
 v_handoff programacion.provenance_receipts%rowtype;
 v_human_decision programacion.human_decisions%rowtype;
 v_human_subject_sha text;
 v_cutover_receipt programacion.provenance_receipts%rowtype;
 v_authority_receipt programacion.provenance_receipts%rowtype;
 v_families bigint; v_valid bigint;
 v_source jsonb; v_sha text; v_ref text;
 v_token text; v_payload jsonb;
 v_id bigint; v_receipt_sha text;
 v_issuer constant text := 'SUPABASE:IG_M105_CP2_CANONICAL_EDGE_RELEASE_VERIFIER_V1';
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'IG_M105_CP2_ATTESTATION_SERVICE_ROLE_ONLY';
 END IF;
 IF p_run_id IS NULL OR p_run_id<1 THEN RAISE EXCEPTION 'IG_M105_CP2_RUN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('M105_ATTEST_RUN:'||p_run_id,0));
 SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=p_run_id;
 IF NOT EXISTS(
   SELECT 1 FROM programacion.engineering_plan_units u,
     LATERAL jsonb_array_elements_text(u.unit_metadata#>'{m105_scope_v1,screen_ids}') e
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5'
   AND e.value=v_run.pantalla_id::text
 ) THEN RAISE EXCEPTION 'IG_M105_CP2_SCREEN_OUTSIDE_FROZEN_COHORT'; END IF;
 SELECT c.version,c.previous_version,c.manifest_sha256,c.promoted_at,c.promoted_by_execution_id,r.release_state,r.supersedes_version
 INTO STRICT v_release
 FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r
   ON r.capability_code=c.capability_code AND r.version=c.version
 WHERE c.capability_code='INPUT_GOVERNANCE';
 IF v_release.previous_version IS NULL OR v_release.version=v_release.previous_version
 OR v_release.release_state<>'RELEASED'
 OR v_release.supersedes_version IS DISTINCT FROM v_release.previous_version
 OR v_release.manifest_sha256 !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'IG_M105_CP2_AUTHENTIC_VNEXT_REQUIRED'; END IF;
 IF v_run.status IS DISTINCT FROM 'COMPLETED'
 OR v_run.created_at<=v_release.promoted_at
 OR v_run.curator_completed_at IS NULL OR v_run.validator_completed_at IS NULL
 OR v_run.curator_identity NOT LIKE 'INPUT_CURATOR:EDGE:input-governance-curator-v1:%'
 OR v_run.validator_identity NOT LIKE 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:%'
 OR v_run.source_snapshot_sha256 !~ '^[0-9a-f]{64}$'
 OR NOT programacion.fn_input_run_is_source_current(v_run.id)
 OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs latest
   WHERE latest.pantalla_id=v_run.pantalla_id AND latest.id>v_run.id)
 THEN RAISE EXCEPTION 'IG_M105_CP2_NO_CURRENT_COMPLETED_EDGE_RUN:%',p_run_id; END IF;
 SELECT count(*),count(*) FILTER(
   WHERE a.validator_outcome IN ('PASS','FAIL','BLOCKED')
    AND a.validator_identity=v_run.validator_identity
    AND a.validator_sha256 ~ '^[0-9a-f]{64}$'
    AND jsonb_typeof(a.validator_evidence)='object'
    AND a.validator_assessed_at IS NOT NULL
 ) INTO v_families,v_valid FROM programacion.input_family_assessments a WHERE a.run_id=v_run.id;
 IF v_run.family_count<=0 OR v_families<>v_run.family_count OR v_valid<>v_families
 THEN RAISE EXCEPTION 'IG_M105_CP2_EDGE_EVALUATION_INCOMPLETE:%',p_run_id; END IF;
 SELECT * INTO v_handoff
 FROM programacion.provenance_receipts h
 WHERE h.subject_type='input_governance_curator_handoff'
   AND h.receipt_kind='EVIDENCE_VERIFICATION'
   AND h.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND h.subject_ref='input-readiness-run:'||v_run.id
   AND h.payload->>'verification_status'='VERIFIED'
   AND h.payload#>>'{handoff,run_id}'=v_run.id::text
   AND h.payload#>>'{handoff,curator_identity}'=v_run.curator_identity
   AND h.created_at>=v_run.created_at
 ORDER BY h.id DESC LIMIT 1;
 IF v_handoff.id IS NULL THEN
   RAISE EXCEPTION 'IG_M105_CP2_SIGNED_EDGE_HANDOFF_REQUIRED:%',p_run_id;
 END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_handoff.id,'EVIDENCE_VERIFICATION',v_handoff.execution_id,
   v_handoff.head_sha,v_handoff.subject_type,v_handoff.subject_ref,v_handoff.subject_sha256);
 -- Use actual Input Governance readiness + human-authority evidence.
 -- programacion.promotions belongs to a DIFFERENT pipeline and is not populated
 -- by public.fn_lf_capability_promote_v1. Do not invent a promotion there.
 SELECT * INTO v_cutover_receipt FROM programacion.provenance_receipts r
 WHERE r.subject_type='IG_CUTOVER_READINESS'
 AND r.subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
 AND r.receipt_kind='EVIDENCE_VERIFICATION'
 AND r.issuer_channel='EVIDENCE_VERIFIER_V1'
 AND r.payload->>'verification_status'='VERIFIED'
 AND r.payload->>'readiness_status'='CUTOVER_READY'
 AND r.payload->>'bundle_sha256'=r.payload#>>'{manifest,bundle_sha256}'
 ORDER BY r.id DESC LIMIT 1;
 IF v_cutover_receipt.id IS NULL THEN
  RAISE EXCEPTION 'IG_M105_CP2_SIGNED_READINESS_REQUIRED';
 END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_cutover_receipt.id,v_cutover_receipt.receipt_kind,v_cutover_receipt.execution_id,
   v_cutover_receipt.head_sha,v_cutover_receipt.subject_type,
   v_cutover_receipt.subject_ref,v_cutover_receipt.subject_sha256);
 -- A typed, signed human decision for THIS capability/release only.
 -- The existing human_decisions insertion trigger checks its authority receipt.
 -- It is never sufficient to insert metadata or forge a service-role approval.
 SELECT d.* INTO v_human_decision
 FROM programacion.human_decisions d
 JOIN programacion.provenance_receipts h ON h.id=d.authority_receipt_id
 WHERE d.decision='APPROVE'
 AND d.metadata->>'decision_class'='CUTOVER_AUTHORIZED'
 AND d.metadata->>'capability_code'='INPUT_GOVERNANCE'
 AND d.metadata->>'release_id'=v_release.version
 AND d.metadata->>'release_manifest_sha256'=v_release.manifest_sha256
 AND d.metadata->>'cutover_readiness_receipt_sha256'=v_cutover_receipt.receipt_sha256
 AND d.metadata->>'authority_role'='SUPER_ADMIN'
 AND d.created_at<=v_release.promoted_at
 AND h.receipt_kind='HUMAN_DECISION'
 AND h.issuer_channel='HUMAN_AUTHORITY_V1'
 AND h.subject_type='human_decision'
 AND h.subject_ref=d.approval_ref
 ORDER BY d.id DESC LIMIT 1;
 IF v_human_decision.id IS NULL THEN
  RAISE EXCEPTION 'IG_M105_CP2_SIGNED_RELEASE_SPECIFIC_HUMAN_AUTHORIZATION_REQUIRED';
 END IF;
 v_human_subject_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
  'execution_id',v_human_decision.execution_id,
  'head_sha',v_human_decision.head_sha,
  'decision',v_human_decision.decision,
  'actor_identity',v_human_decision.actor_identity,
  'approval_ref',v_human_decision.approval_ref,
  'metadata',v_human_decision.metadata));
 PERFORM programacion.fn_assert_provenance_receipt(
  v_human_decision.authority_receipt_id,'HUMAN_DECISION',
  v_human_decision.execution_id,v_human_decision.head_sha,
  'human_decision',v_human_decision.approval_ref,v_human_subject_sha);
 -- Promotion identity comes from the capability-current authority itself,
 -- not from programacion.promotions.
 IF coalesce(btrim(v_release.promoted_by_execution_id),'')='' THEN
  RAISE EXCEPTION 'IG_M105_CP2_PROMOTION_ACTOR_MISSING';
 END IF;
 v_ref:='input-readiness-run:'||v_run.id::text;
 v_source:=jsonb_build_object(
    'schema_version','IG_M105_CP2_RELEASE_RUN_BINDING_SUBJECT_V1',
    'runtime','input-governance-agent-v1',
    'run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'release_id',v_release.version,
    'release_manifest_sha256',v_release.manifest_sha256,
    'curator_identity',v_run.curator_identity,
    'validator_identity',v_run.validator_identity,
    'curator_handoff_receipt_sha256',v_handoff.receipt_sha256,
    'capability_promoted_by_execution_id',v_release.promoted_by_execution_id,
    'cutover_readiness_receipt_id',v_cutover_receipt.id,
    'family_count',v_run.family_count);
 v_sha:=programacion.fn_v09_sha256_jsonb(v_source);
 SELECT id,receipt_sha256 INTO v_id,v_receipt_sha
 FROM programacion.provenance_receipts pr
 WHERE pr.subject_type='IG_RELEASE_RUN_BINDING'
 AND pr.subject_ref=v_ref AND pr.subject_sha256=v_sha
 AND pr.head_sha=v_human_decision.head_sha
 AND pr.issuer_channel='EVIDENCE_VERIFIER_V1'
 AND pr.receipt_kind='EVIDENCE_VERIFICATION'
 AND pr.payload->>'verification_status'='VERIFIED'
 ORDER BY id DESC LIMIT 1;
 IF v_id IS NULL THEN
   SELECT decrypted_secret INTO v_token FROM vault.decrypted_secrets
   WHERE name='EVIDENCE_VERIFIER_V1_TOKEN' ORDER BY created_at DESC LIMIT 1;
   IF length(coalesce(v_token,''))<32 THEN
     RAISE EXCEPTION 'IG_M105_CP2_CANONICAL_VERIFIER_TOKEN_UNAVAILABLE'; END IF;
   v_payload:=jsonb_build_object(
     'schema_version','IG_M105_CP2_RELEASE_RUN_BINDING_RECEIPT_V1',
     'runtime','input-governance-agent-v1',
     'head_sha',v_human_decision.head_sha,
     'subject_type','IG_RELEASE_RUN_BINDING',
     'subject_ref',v_ref,'subject_sha256',v_sha,
     'run_id',v_run.id::text,'pantalla_id',v_run.pantalla_id::text,
     'release_id',v_release.version,
     'release_manifest_sha256',v_release.manifest_sha256,
     'verification_status','VERIFIED',
     'verifier_identity',v_issuer,
     'verification_method','CANONICAL_EDGE_RUN_HANDOFF_CUTOVER_READBACK_V1',
     'signed_curator_handoff_id',v_handoff.id,
     'capability_promoted_by_execution_id',v_release.promoted_by_execution_id,
     'source_snapshot_sha256',v_run.source_snapshot_sha256);
   SELECT id,receipt_sha256 INTO v_id,v_receipt_sha
   FROM programacion.issue_provenance_receipt(
     'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',
     null,v_human_decision.head_sha,'IG_RELEASE_RUN_BINDING',v_ref,v_sha,
     v_issuer,'supabase://programacion.input_readiness_runs/'||v_run.id||'#m105-cp2-release',
     v_payload);
 END IF;
 PERFORM programacion.fn_assert_provenance_receipt(
   v_id,'EVIDENCE_VERIFICATION',null,v_human_decision.head_sha,
   'IG_RELEASE_RUN_BINDING',v_ref,v_sha);
 RETURN jsonb_build_object(
   'status','PERSISTED_VERIFIED','run_id',v_run.id,
   'receipt_id',v_id,'receipt_sha256',v_receipt_sha,
   'release_id',v_release.version,'pantalla_id',v_run.pantalla_id,
   'production_activation',false);
END $m105$;

CREATE OR REPLACE FUNCTION public.fn_ig_m105_cp2_dispatch_context_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion'
AS $function$
DECLARE v_scope jsonb; v_release record; v_cohort integer; v_pass boolean;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN
   RAISE EXCEPTION 'IG_M105_CP2_SERVICE_ROLE_REQUIRED';
 END IF;
 SELECT u.unit_metadata#>'{m105_scope_v1}' INTO STRICT v_scope
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.5';
 IF v_scope->>'schema_version' IS DISTINCT FROM 'M105_SCOPE_SNAPSHOT_V1'
 OR jsonb_typeof(v_scope->'screen_ids') IS DISTINCT FROM 'array'
 OR jsonb_array_length(v_scope->'screen_ids')<>13
 OR (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_scope->'screen_ids'))<>13
 THEN RAISE EXCEPTION 'IG_M105_CP2_COHORT_DRIFT'; END IF;
 SELECT c.version,c.previous_version,c.manifest_sha256,r.release_state
 INTO STRICT v_release FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r
 ON r.capability_code=c.capability_code AND r.version=c.version
 WHERE c.capability_code='INPUT_GOVERNANCE';
 SELECT v.can_attempt_real_cp2 INTO STRICT v_pass
 FROM programacion.v_ig_m105_cp2_execution_preflight_v1 v
 WHERE v.capability_code='INPUT_GOVERNANCE';
 v_pass:=coalesce(v_pass,false)
 AND v_release.previous_version IS NOT NULL
 AND v_release.version IS DISTINCT FROM v_release.previous_version
 AND v_release.release_state='RELEASED'
 AND v_release.manifest_sha256 ~ '^[0-9a-f]{64}$';
 RETURN jsonb_build_object(
   'status','AUTHORIZED_CONTEXT','scope',v_scope,
   'release',jsonb_build_object('version',v_release.version,
      'previous_version',v_release.previous_version,
      'manifest_sha256',v_release.manifest_sha256),
   'dispatch_permitted',v_pass,
   'reason',CASE WHEN v_pass THEN 'AUTHENTIC_CURRENT_RELEASE_READBACK'
                 ELSE 'VNEXT_RELEASE_OR_SIGNED_AUTHORITY_MISSING' END,
   'no_promotion',true,'no_receipt_fabrication',true);
END $function$;

DO $align$
DECLARE m jsonb; w bigint;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT w,m
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' FOR UPDATE;
 IF m#>>'{m105_cp2_producer_v1,receipt_issuer}' IS DISTINCT FROM
  'public.fn_ig_m105_cp2_attest_run_v1'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=w AND checkpoint_code='NEW_RUNS_VNEXT')<>'PENDING'
 THEN RAISE EXCEPTION 'M105_CP2_AUTHORITY_GATE_CURRENTNESS_DRIFT'; END IF;
 m:=jsonb_set(m,'{m105_cp2_producer_v1,release_authority}',
 jsonb_build_object(
 'capability_promoter','public.fn_lf_capability_promote_v1',
 'readiness_subject_type','IG_CUTOVER_READINESS',
 'readiness_source','programacion.fn_ig_m912_cutover_ready_receipt_v1',
 'human_decision_proof','programacion.human_decisions.authority_receipt_id',
 'human_channel','HUMAN_AUTHORITY_V1',
 'human_authority_scope','INPUT_GOVERNANCE_EXACT_RELEASE',
 'preflight','programacion.v_ig_m105_cp2_execution_preflight_v1',
 'foreign_promotion_table','NOT_REQUIRED',
 'production_activation','REQUIRES_SEPARATE_EXPLICIT_AUTHORIZATION'),true);
 m:=jsonb_set(m,'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}',
 m#>'{action_specs_v1,NEW_RUNS_VNEXT,target,declared_objects}'||
 jsonb_build_array('programacion.v_ig_m105_cp2_execution_preflight_v1'),true);
 m:=jsonb_set(m,'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}',
 m#>'{source_pack_v1,checkpoint_inputs,NEW_RUNS_VNEXT,inputs,db_objects}'||
 jsonb_build_array('programacion.v_ig_m105_cp2_execution_preflight_v1'),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5' AND work_item_id=w;
 IF (SELECT unit_metadata#>>'{m105_cp2_producer_v1,release_authority,foreign_promotion_table}'
  FROM programacion.engineering_plan_units WHERE work_item_id=w)<>'NOT_REQUIRED'
 THEN RAISE EXCEPTION 'M105_CP2_AUTHORITY_GATE_READBACK'; END IF;
END $align$;
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT 'IG-M105-CP2-FOREIGN-PROMOTION-GATE-008','INPUT_GOVERNANCE',
'CP2 issuer required foreign programacion.promotions records not issued by LF capability promoter',
'M10.5 CP2 independent Edge run-to-release attestation was coupled to unrelated Programming promotion records, making genuine LF capability release unadmittable.',
'public.fn_lf_capability_promote_v1 updates lf_capability_current only; programacion.promotions is a separate authority flow and M9.12 checks that it remains empty.',
'Use the existing signed IG_CUTOVER_READINESS receipt, exact current capability release registry and a release-specific signed human authorization receipt. Fail closed if authority is missing; never require unrelated programacion.promotions.',
'Live before change: M9.12 signed CUTOVER_READY present; Input Governance only 1.0.0 and no capability-specific human receipt. Do not auto-promote or declare CP2 passed.',
'github://cristhianlujan/claude-persona-lf-patch/ig/m105-cp2-cutover-authority-alignment-20261013',
'programacion.engineering_plan_units/M10.5/NEW_RUNS_VNEXT',
'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5','ACTIVO','CONTRACT_PREFLIGHT',
ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-CP2-FOREIGN-PROMOTION-GATE-008');

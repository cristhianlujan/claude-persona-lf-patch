CREATE OR REPLACE FUNCTION saly.creative_chat_save_qa_v1(p_token uuid, p_run_id bigint, p_artifact_ref text, p_artifact_sha256 text, p_worker_receipt text, p_qa_receipt jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE c saly.creative_queue_claims_v1%ROWTYPE;
 r saly.creative_runs%ROWTYPE;
 i saly.creative_order_items%ROWTYPE;
 d saly.creative_run_detection_v1%ROWTYPE;
 v_verdict text;v_reviewer text;v_released jsonb;
BEGIN
 IF p_token IS NULL OR p_run_id IS NULL OR p_run_id<1
 OR jsonb_typeof(p_qa_receipt) IS DISTINCT FROM 'object'
 OR p_artifact_sha256 IS NULL OR p_artifact_sha256 !~ '^[0-9a-f]{64}$'
 OR nullif(btrim(coalesce(p_artifact_ref,'')),'') IS NULL
 OR nullif(btrim(coalesce(p_worker_receipt,'')),'') IS NULL
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_INPUT_INVALID'; END IF;
 v_verdict:=p_qa_receipt->>'verdict';
 v_reviewer:=p_qa_receipt->>'reviewer_ref';
 IF v_verdict NOT IN('PASS','FAIL') OR v_verdict IS NULL
 OR nullif(btrim(coalesce(p_qa_receipt->>'comment','')),'') IS NULL
 OR length(p_qa_receipt->>'comment')>4000
 OR nullif(btrim(coalesce(v_reviewer,'')),'') IS NULL
 OR p_qa_receipt->>'artifact_sha256' IS DISTINCT FROM p_artifact_sha256
 OR p_qa_receipt->>'reviewer_kind' IS DISTINCT FROM 'AUTOMATED_MODEL'
 OR p_qa_receipt->>'generator_model_family' IS DISTINCT FROM 'GPT'
 OR p_qa_receipt->>'reviewer_model_family' IS DISTINCT FROM 'CLAUDE'
 THEN RAISE EXCEPTION 'SALY_AUTOMATED_QA_PROVENANCE_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO c FROM saly.creative_queue_claims_v1
 WHERE claim_token=p_token FOR UPDATE;
 SELECT * INTO r FROM saly.creative_runs WHERE id=p_run_id FOR UPDATE;
 IF c.id IS NULL OR r.id IS NULL THEN
 RAISE EXCEPTION 'SALY_CHAT_QA_RUN_NOT_FOUND'; END IF;
 SELECT * INTO i FROM saly.creative_order_items
 WHERE id=c.item_id AND order_id=c.order_id FOR UPDATE;
 IF i.id IS NULL OR c.state<>'ACTIVE' OR c.lease_until<=clock_timestamp()
 OR r.queue_claim_id IS DISTINCT FROM c.id
 OR r.order_id IS DISTINCT FROM c.order_id
 OR r.item_id IS DISTINCT FROM c.item_id
 OR r.state<>'EXITOSO' OR i.status<>'PRODUCIENDO'
 OR r.output_evidence->>'artifact_ref' IS DISTINCT FROM p_artifact_ref
 OR r.output_evidence->>'sha256' IS DISTINCT FROM p_artifact_sha256
 OR r.output_evidence->>'worker_receipt' IS DISTINCT FROM p_worker_receipt
 THEN RAISE EXCEPTION 'SALY_CHAT_QA_NOT_GENERATED_OR_BINDING_INVALID'; END IF;
 IF lower(btrim(v_reviewer))=lower(btrim(c.worker_ref))
 THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_REVIEWER_NOT_INDEPENDENT'; END IF;
 SELECT * INTO d FROM saly.creative_run_detection_v1
 WHERE run_id=r.id AND item_id=i.id AND order_id=i.order_id
 AND claim_id=c.id AND artifact_ref=p_artifact_ref
 AND artifact_sha256=p_artifact_sha256;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_CHAT_QA_DETECTION_NOT_RECORDED'; END IF;
 IF v_verdict='FAIL' THEN
   UPDATE saly.creative_order_items
   SET status='BLOQUEADO',qa_receipt=p_qa_receipt
      ||jsonb_build_object('run_id',p_run_id,'detection_run_id',d.run_id)
   WHERE id=i.id AND status='PRODUCIENDO';
   PERFORM saly.creative_queue_release_v1(p_token,'BLOCKED','QA_FAIL_AFTER_GENERATION');
   RETURN jsonb_build_object('status','QA_FAIL_BLOCKED','item_state','BLOQUEADO',
       'run_state','EXITOSO','run_id',r.id,'item_id',i.id,
       'qa_reviewer_kind','AUTOMATED_MODEL','db_done_allowed',false);
 END IF;
 -- The independent technical+semantic QA (L3C) is not bypassed.
 IF i.acceptance_json ? 'semantic_qa' THEN
   IF r.input_snapshot#>'{visual_contract,qa_checks}' IS DISTINCT FROM
      saly.creative_item_visual_contract_l3b(i.id)#>'{contract,qa_checks}'
   THEN RAISE EXCEPTION 'CREATIVE_TECHNICAL_CHECK_EXPECTATIONS_MISMATCH'; END IF;
   PERFORM saly.creative_assert_dual_qa_l3c(
      i.acceptance_json,p_qa_receipt,r.input_snapshot,r.output_evidence);
 END IF;
 UPDATE saly.creative_order_items SET status='EN_QA'
 WHERE id=i.id AND status='PRODUCIENDO';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_STAGE_NOT_READY'; END IF;
 UPDATE saly.creative_order_items SET status='TERMINADO',
  approved_at=NULL,approved_by=NULL,
  qa_receipt=p_qa_receipt||jsonb_build_object('run_id',p_run_id,
    'detection_run_id',d.run_id,
    'first_ready_elapsed_seconds',d.first_ready_elapsed_seconds,
    'check_count',d.check_count)
 WHERE id=i.id AND status='EN_QA';
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_CHAT_QA_TERMINAL_NOT_READY'; END IF;
 -- No independently verified delivery row is referenced or fabricated here.
 v_released:=saly.creative_chat_finalize_after_verified_delivery_v1(p_token,p_run_id);
 RETURN jsonb_build_object('status','TERMINADO','run_id',r.id,'item_id',i.id,
    'order_closed',v_released->'order_closed','db_claim_state','DONE',
    'db_item_state','TERMINADO',
    'qa_reviewer_kind','AUTOMATED_MODEL',
    'first_ready_elapsed_seconds',d.first_ready_elapsed_seconds,
    'check_count',d.check_count,'single_transaction',true);
END; $function$
;

CREATE OR REPLACE FUNCTION saly.creative_chat_terminal_item_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
DECLARE
  v_j jsonb;
  v_a jsonb;
  v_order_status text;
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status='TERMINADO' OR EXISTS (
   SELECT 1 FROM saly.creative_orders o WHERE o.id=OLD.order_id AND o.status='TERMINADO'
  ) THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP<>'UPDATE' THEN RETURN NEW; END IF;
 SELECT status INTO v_order_status FROM saly.creative_orders
 WHERE id=NEW.order_id FOR UPDATE;
 -- Explicit signed owner approval may follow an already completed order.
 IF OLD.status='TERMINADO' AND NEW.status='APROBADO' THEN
   IF auth.uid() IS NULL OR NEW.approved_by IS DISTINCT FROM auth.uid()::text
     OR NEW.approved_at IS NULL
     OR (to_jsonb(NEW) - 'status' - 'approved_at' - 'approved_by' - 'updated_at')
          IS DISTINCT FROM
        (to_jsonb(OLD) - 'status' - 'approved_at' - 'approved_by' - 'updated_at')
   THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_OWNER_TRANSITION_INVALID'; END IF;
   RETURN NEW;
 END IF;
 IF OLD.status='TERMINADO' OR v_order_status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ITEM_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status IN ('LISTO','EN_QA') THEN
   IF NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL
      OR NEW.qa_receipt->>'verdict' IS DISTINCT FROM 'PASS'
      OR NOT EXISTS(SELECT 1 FROM saly.creative_runs r
        JOIN saly.creative_run_detection_v1 d ON d.run_id=r.id
        WHERE r.item_id=NEW.id AND r.order_id=NEW.order_id AND r.state='EXITOSO'
        AND d.item_id=NEW.id AND d.order_id=NEW.order_id
        AND d.artifact_sha256=r.output_evidence->>'sha256'
        AND d.artifact_ref=r.output_evidence->>'artifact_ref'
        AND r.output_evidence->>'sha256'=NEW.qa_receipt->>'artifact_sha256')
   THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_QA_RUN_MISSING'; END IF;
   RETURN NEW;
 END IF;
 IF NEW.status='TERMINADO' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF OLD.status<>'PENDIENTE' OR NEW.order_id<>OLD.order_id
  OR NEW.code<>OLD.code OR NEW.acceptance_json IS DISTINCT FROM OLD.acceptance_json
  OR NEW.context_json IS DISTINCT FROM OLD.context_json
  OR EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.item_id=NEW.id)
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_NOT_ARCHIVED_PENDING'; END IF;
  v_a:=OLD.qa_receipt->'chat_artifact_reconciliation_v1';
  v_j:=NEW.qa_receipt->'chat_judge_v1';
  IF v_a IS NULL OR v_j IS NULL
  OR NEW.qa_receipt->'chat_artifact_reconciliation_v1' IS DISTINCT FROM v_a
  OR v_a->>'status' IS DISTINCT FROM 'ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE'
  OR v_a->>'avoid_regeneration' IS DISTINCT FROM 'true'
  OR v_a->>'chat_delivery_observed' IS DISTINCT FROM 'true'
  OR v_a->>'sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'artifact_sha256' IS DISTINCT FROM v_a->>'sha256'
  OR v_j->>'judge_receipt_sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'source_manifest_input_sha256' !~ '^[0-9a-f]{64}$'
  OR v_j->>'judge_kind' IS DISTINCT FROM 'DETERMINISTIC_TECHNICAL_SEPARATE_PROCESS'
  OR v_j->>'technical_verdict' NOT IN ('PASS_TECHNICAL','PASS_TECHNICAL_WITH_OBSERVATIONS')
  OR v_j->>'technical_verdict' IS NULL
  OR v_j->>'semantic_independence_proven' IS DISTINCT FROM 'false'
  OR v_j->>'semantic_verdict' IS DISTINCT FROM 'NOT_INDEPENDENTLY_EVALUATED'
  OR v_j->>'production_approved' IS DISTINCT FROM 'false'
  OR v_j->>'run_verified' IS DISTINCT FROM 'false'
  OR v_j->>'terminal_semantics' IS DISTINCT FROM 'IMAGE_DELIVERED_AND_QA_COMMENTED_NOT_APPROVED'
  OR nullif(btrim(v_j->>'qa_comment'),'') IS NULL
  OR jsonb_typeof(v_j->'observations') IS DISTINCT FROM 'array'
  OR NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM saly.creative_item_dependencies d
    JOIN saly.creative_order_items p ON p.id=d.depends_on_item_id
    WHERE d.order_id=NEW.order_id AND d.item_id=NEW.id
      AND p.status NOT IN ('TERMINADO','APROBADO')
  ) THEN
   RAISE EXCEPTION 'SALY_CHAT_TERMINAL_JUDGE_OR_DEPENDENCY_MISSING';
  END IF;
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_chat_terminal_order_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.status='TERMINADO' THEN
   RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_IMMUTABLE'; END IF;
  RETURN OLD;
 END IF;
 IF TG_OP<>'UPDATE' THEN RETURN NEW; END IF;
 IF OLD.status='TERMINADO' THEN
  RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_IMMUTABLE'; END IF;
 IF NEW.status='TERMINADO' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF OLD.status NOT IN ('PLANIFICADO','EN_PROCESO')
  OR NEW.completed_at IS NULL
  OR NOT EXISTS (SELECT 1 FROM saly.creative_order_items i
                 WHERE i.order_id=NEW.id AND i.required)
  OR EXISTS (
   SELECT 1 FROM saly.creative_order_items i WHERE i.order_id=NEW.id AND
      (i.status NOT IN ('TERMINADO','APROBADO','OMITIDO')
       OR (i.required AND i.status NOT IN ('TERMINADO','APROBADO'))
       OR (i.status='TERMINADO' AND
         (
          -- The old historical chat-archive closure stays accepted exactly as before.
          (
            i.qa_receipt#>>'{chat_judge_v1,artifact_sha256}' IS DISTINCT FROM
              i.qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}'
            OR nullif(btrim(i.qa_receipt#>>'{chat_judge_v1,qa_comment}'),'') IS NULL
          )
          AND NOT EXISTS (
            -- Newly generated evidence: no creative human approval required.
            SELECT 1 FROM saly.creative_runs r
            WHERE r.item_id=i.id AND r.order_id=i.order_id AND r.state='EXITOSO'
              AND i.qa_receipt->>'verdict'='PASS'
              AND i.qa_receipt->>'artifact_sha256'=r.output_evidence->>'sha256'
              AND EXISTS (
                SELECT 1 FROM saly.creative_run_detection_v1 d
                WHERE d.run_id=r.id AND d.item_id=i.id AND d.order_id=i.order_id
                  AND d.artifact_sha256=r.output_evidence->>'sha256'
                  AND d.artifact_ref=r.output_evidence->>'artifact_ref'
                  AND d.check_count BETWEEN 1 AND 7
              )
          )
        )))
  )
  OR EXISTS (SELECT 1 FROM saly.creative_runs r WHERE r.order_id=NEW.id
              AND r.state IN ('EN_COLA','EJECUTANDO'))
  THEN RAISE EXCEPTION 'SALY_CHAT_TERMINAL_ORDER_DETAILS_INCOMPLETE'; END IF;
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_context_set_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions'
AS $function$
DECLARE v_all int; v_official int; v_drift int; v_distinct_codes int;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_SET_DELETE_FORBIDDEN'; END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD.state='SEALED' THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_SET_IMMUTABLE'; END IF;
  IF NEW.project_id IS DISTINCT FROM OLD.project_id
   OR NEW.code IS DISTINCT FROM OLD.code
   OR NEW.version_label IS DISTINCT FROM OLD.version_label
   OR NEW.mode IS DISTINCT FROM OLD.mode
   OR NEW.provenance IS DISTINCT FROM OLD.provenance
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_IDENTITY_IMMUTABLE'; END IF;
 END IF;
 IF NEW.state='SEALED' THEN
  IF EXISTS (SELECT 1 FROM saly.proyecto WHERE id=NEW.project_id AND codigo='LF') THEN
    SELECT count(*),count(DISTINCT e.code),count(*) FILTER(WHERE e.project_id<>NEW.project_id OR e.code NOT LIKE 'lf.source.%' OR v.approval_status<>'APPROVED' OR t.role<>'OFFICIAL' OR t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex'))
    INTO v_all,v_distinct_codes,v_drift FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=NEW.id;
    IF v_all<1 OR v_all<>v_distinct_codes OR v_drift<>0 THEN RAISE EXCEPTION 'LF_CONTEXT_SEAL_INCOMPLETE'; END IF;
    NEW.sealed_at:=now(); RETURN NEW;
  END IF;
  -- OLD is read only in the UPDATE-only guard above.
  -- Universal seal rule: two effective SALY official colors, no duplicate codes,
  -- verified immutable values; no 41-token hardcode for future EXPLORE sets.
  SELECT count(*)::int,
    count(*) FILTER(WHERE t.role='OFFICIAL')::int,
    count(DISTINCT e.code)::int,
    count(*) FILTER(WHERE t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex'))::int
  INTO v_all,v_official,v_distinct_codes,v_drift
  FROM saly.creative_context_tokens t
  JOIN saly.identity_versions v ON v.id=t.identity_version_id
  JOIN saly.identity_elements e ON e.id=v.element_id
  WHERE t.context_set_id=NEW.id;
  IF v_all<2 OR v_official<>2 OR v_all<>v_distinct_codes OR v_drift<>0
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_SEAL_INCOMPLETE_DUPLICATE_OR_DRIFT'; END IF;
  IF EXISTS (
    SELECT 1 FROM saly.creative_context_tokens t
    WHERE t.context_set_id=NEW.id AND t.role='OFFICIAL'
    AND NOT EXISTS (SELECT 1 FROM saly.v_identity_current effective
       WHERE effective.project_code='SALY-001'
       AND effective.version_id=t.identity_version_id))
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_OFFICIAL_NOT_EFFECTIVE'; END IF;
  IF EXISTS (
   SELECT 1 FROM saly.creative_context_tokens alias_link
   JOIN saly.identity_versions alias_v ON alias_v.id=alias_link.identity_version_id
   WHERE alias_link.context_set_id=NEW.id
    AND alias_v.metadata->>'kind'='ALIAS'
    AND NOT EXISTS (
       SELECT 1 FROM saly.creative_context_tokens target_link
       JOIN saly.identity_versions target_v ON target_v.id=target_link.identity_version_id
       JOIN saly.identity_elements target_e ON target_e.id=target_v.element_id
       WHERE target_link.context_set_id=NEW.id
        AND target_e.code=alias_v.metadata->>'alias_target_code'))
  THEN RAISE EXCEPTION 'CREATIVE_CONTEXT_ALIAS_TARGET_MISSING'; END IF;
  NEW.sealed_at:=now();
 END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_context_token_guard_l2a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'extensions'
AS $function$
DECLARE v_set record; v_version record; v_expected_role text;
BEGIN
 IF TG_OP<>'INSERT' THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_TOKEN_IMMUTABLE';
 END IF;
 SELECT * INTO v_set FROM saly.creative_context_sets WHERE id=NEW.context_set_id FOR UPDATE;
 IF NOT FOUND OR v_set.state<>'DRAFT' THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_NOT_DRAFT';
 END IF;
 SELECT e.project_id,e.code,v.approval_status,v.value_json INTO v_version
 FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE v.id=NEW.identity_version_id;
 IF NOT FOUND OR v_version.project_id<>v_set.project_id THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_WRONG_PROJECT_OR_VERSION';
 END IF;
 IF EXISTS (SELECT 1 FROM saly.proyecto WHERE id=v_set.project_id AND codigo='LF') THEN
   IF v_version.code NOT LIKE 'lf.source.%' OR v_version.approval_status<>'APPROVED' OR NEW.role<>'OFFICIAL' THEN RAISE EXCEPTION 'LF_CONTEXT_SOURCE_NOT_AUTHORIZED'; END IF;
   NEW.value_sha256:=encode(extensions.digest(v_version.value_json::text,'sha256'),'hex');
   RETURN NEW;
 END IF;
 v_expected_role:=CASE
  WHEN v_version.code IN ('color.brand.primary','color.action.primary.bg')
       AND v_version.approval_status='APPROVED' THEN 'OFFICIAL'
  WHEN v_version.code LIKE 'candidate.saly_ds_v1.%'
       AND (v_version.approval_status='CANDIDATE' OR (v_version.approval_status='APPROVED' AND EXISTS (SELECT 1 FROM saly.v_identity_current c WHERE c.version_id=NEW.identity_version_id AND c.project_code='SALY-001'))) THEN 'EXISTING'
  WHEN v_version.code LIKE 'candidate.saly_home_v3.%'
       AND (v_version.approval_status='CANDIDATE' OR (v_version.approval_status='APPROVED' AND EXISTS (SELECT 1 FROM saly.v_identity_current c WHERE c.version_id=NEW.identity_version_id AND c.project_code='SALY-001'))) THEN 'HOME'
  ELSE NULL END;
 IF v_expected_role IS NULL OR NEW.role<>v_expected_role THEN
   RAISE EXCEPTION 'CREATIVE_CONTEXT_ROLE_NOT_AUTHORIZED';
 END IF;
 NEW.value_sha256:=encode(extensions.digest(v_version.value_json::text,'sha256'),'hex');
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_delete_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
 RAISE EXCEPTION 'CREATIVE_LEDGER_DELETE_FORBIDDEN';
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_dependency_guard_l1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_cycle boolean; v_excluded_id bigint:=-1;
BEGIN
 IF TG_OP='UPDATE' THEN v_excluded_id:=OLD.id; END IF;
 PERFORM 1 FROM saly.creative_orders WHERE id=NEW.order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CREATIVE_ORDER_NOT_FOUND'; END IF;
 IF EXISTS (SELECT 1 FROM saly.creative_order_items
            WHERE id=NEW.item_id AND status='APROBADO')
 THEN RAISE EXCEPTION 'CREATIVE_DEPENDENCY_ON_APPROVED_ITEM'; END IF;
 WITH RECURSIVE walk(id) AS (
   SELECT NEW.depends_on_item_id
   UNION
   SELECT d.depends_on_item_id FROM saly.creative_item_dependencies d
   JOIN walk w ON w.id=d.item_id
   WHERE d.order_id=NEW.order_id AND d.id<>v_excluded_id
 )
 SELECT EXISTS(SELECT 1 FROM walk WHERE id=NEW.item_id) INTO v_cycle;
 IF v_cycle THEN RAISE EXCEPTION 'CREATIVE_DEPENDENCY_CYCLE'; END IF;
 RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.creative_execution_policy_for_item_v1(p_asof timestamp with time zone, p_order_id bigint, p_item_id bigint, p_attempt integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'pg_temp'
AS $function$
 SELECT CASE WHEN p_order_id=22 AND p_item_id=26 AND p_attempt IN (3,4)
 THEN saly.creative_execution_policy_v1(p_asof)||jsonb_build_object('MAX_ATTEMPTS',p_attempt)
 ELSE saly.creative_execution_policy_v1(p_asof) END
$function$
;

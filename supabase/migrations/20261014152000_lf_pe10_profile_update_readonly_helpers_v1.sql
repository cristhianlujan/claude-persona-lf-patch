-- LF Profile Updater / PE10 — read-only helpers, NO ROUTE ACTIVATION.
-- Exact source = three reviewed candidate helpers in this PR.
-- Submit ONLY through LF Migration Train; do not run manual DDL on Supabase.
-- This migration does not modify ACT-0001, operation registry, policy versions,
-- method qualification, executable steps, existing executions or profile files.
-- Follow-up activation must be separate and only after credentialed end-to-end
-- positive/negative tests for both caller and recorder against one shared route.
BEGIN;
DO $preflight$
BEGIN
 IF (SELECT version FROM public.lf_operation_registry
     WHERE operation_code='ACTUALIZACION_PERFIL_LF') <> 'v0.1'
 THEN RAISE EXCEPTION 'PE10_READONLY_HELPERS_OPERATION_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_steps
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active) <> 15
 THEN RAISE EXCEPTION 'PE10_READONLY_HELPERS_STEP_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_policy_versions
     WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE'
       AND policy_version='v1.1') <> 1
 THEN RAISE EXCEPTION 'PE10_READONLY_HELPERS_POLICY_DRIFT'; END IF;
 IF to_regprocedure('public.lf_profile_update_verified_receipt_v1(text,text,text,text,text)') IS NOT NULL
    OR to_regprocedure('public.lf_profile_update_effective_route_v1(text)') IS NOT NULL
    OR to_regprocedure('public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'PE10_READONLY_HELPERS_ALREADY_PRESENT'; END IF;
 IF NOT has_table_privilege(current_user,'private.lf_evidence_ledger_v1','SELECT')
    OR NOT has_table_privilege(current_user,'private.lf_evidence_resolver_registry_v1','SELECT')
 THEN RAISE EXCEPTION 'PE10_TRAIN_PRINCIPAL_PRIVATE_READ_UNAVAILABLE'; END IF;
 IF has_table_privilege('service_role','private.lf_evidence_ledger_v1','SELECT')
    OR has_table_privilege('service_role','private.lf_evidence_resolver_registry_v1','SELECT')
 THEN RAISE EXCEPTION 'PE10_BROAD_PRIVATE_LEDGER_GRANT_UNEXPECTED'; END IF;
END
$preflight$;
-- SOURCE skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql BLOB 1920b513aec0404a22455d99f7871496172fa920
-- Candidate-only: NOT a deployed migration or a grant of Profile Updater write authority.
-- Owner: existing ACTUALIZACION_PERFIL_LF, no parallel registry or model engine.
-- Preflight shows service_role has USAGE(private) but NO SELECT on
-- private.lf_evidence_ledger_v1. Do not grant broad SELECT to service_role.
--
-- Rollback-only trial through Train required before any adoption:
-- BEGIN; create the function; revoke/grant only EXECUTE; assert positives/negatives;
-- verify permissions (no ledger SELECT); ROLLBACK.
--
-- This reader returns only a boolean. No private ledger data leaves the function.
CREATE OR REPLACE FUNCTION public.lf_profile_update_verified_receipt_v1(
    p_subject_type text,
    p_subject_ref text,
    p_receipt_id text,
    p_subject_sha256 text,
    p_source_head_sha text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $lf$
DECLARE
    v_id uuid;
BEGIN
    IF p_subject_type NOT IN ('PROFILE_ASSESSMENT', 'METHOD_QUALIFICATION')
       OR NULLIF(btrim(p_subject_ref), '') IS NULL
       OR p_receipt_id IS NULL
       OR p_receipt_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR p_subject_sha256 IS NULL
       OR p_subject_sha256 !~ '^[0-9a-f]{64}$'
       OR p_source_head_sha IS NULL
       OR p_source_head_sha !~ '^[0-9a-f]{40}$'
    THEN RETURN false; END IF;
    v_id := p_receipt_id::uuid;

    RETURN EXISTS (
        SELECT 1
          FROM private.lf_evidence_ledger_v1 l
          JOIN private.lf_evidence_resolver_registry_v1 rr
            ON rr.resolver_id=l.resolver_id
           AND rr.active IS TRUE
           AND rr.trust_level='TRUSTED_PROVIDER_BOUND'
           AND rr.provider=l.provider
           AND rr.verification_method=l.verification_method
         WHERE l.receipt_id = v_id
           AND l.subject_type = p_subject_type
           AND l.subject_ref = p_subject_ref
           AND l.subject_sha256 = p_subject_sha256
           AND l.source_head_sha = p_source_head_sha
           AND l.verification_state = 'VERIFIED'
           AND l.resolver_id IN ('LF_GITHUB_SOURCE_READBACK_V1','LF_SUPABASE_READBACK_V1')
           AND NULLIF(btrim(l.provider_ref),'') IS NOT NULL
           AND l.receipt_sha256 ~ '^[0-9a-f]{64}$'
           AND l.verified_at IS NOT NULL
    );
END;
$lf$;

-- Restrict access to a boolean-verification RPC only. No schema/table grants.
REVOKE ALL ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_verified_receipt_v1(text,text,text,text,text) TO service_role;

-- Do NOT apply this source by itself. Admission requires:
-- (1) check the deployment principal may read the private ledger AND resolver registry;
-- (2) prove positive/negative exact-receipt resolution under ROLLBACK;
-- (3) cross-bind receipt to actual profile target/source and method version;
-- (4) preserve 22 frozen historic execution requirements;
-- (5) activate only with the two step contracts, judge bindings, conditional
--     policy and both consumer/recorder effective-required-step logic;
-- (6) retain NO_CHANGE without write, no autonomous GPT Native claims.

-- SOURCE skills/profile_creator/contracts/profile_update_effective_route_reader_candidate_v1.sql BLOB 50ac250b11ffb61c7af91a50ab1271281402278a
-- Profile Updater v0.2 route resolver, CANDIDATE SOURCE ONLY (not deployed).
-- This is a read-only derivation; no editing execution manifest or policies.
-- MUST be wired into BOTH the existing Profile step recorder and the Edge
-- operationSnapshot before registering route-enabled step contracts.
--
-- The legacy path deliberately returns the immutable v0.1 required-step list.
CREATE OR REPLACE FUNCTION public.lf_profile_update_effective_route_v1(
    p_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog,public
AS $route$
DECLARE
    e public.lf_operation_execution%rowtype;
    frozen jsonb;
    routes jsonb;
    prefix jsonb;
    update_steps jsonb;
    no_change_steps jsonb;
    decision_row public.lf_operation_execution_steps%rowtype;
    selected jsonb;
    outcome text;
    x text;
BEGIN
    SELECT * INTO e
      FROM public.lf_operation_execution
     WHERE execution_id = p_execution_id;
    IF NOT FOUND OR e.operation_code <> 'ACTUALIZACION_PERFIL_LF' THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_EXECUTION_UNRESOLVED');
    END IF;
    frozen := e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
    IF frozen IS NULL THEN
        RETURN jsonb_build_object('outcome','LEGACY_NO_SNAPSHOT','effective_steps',null);
    END IF;
    IF jsonb_typeof(frozen) <> 'array' OR jsonb_array_length(frozen)=0
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(frozen) a
          WHERE jsonb_typeof(a.value) <> 'string'
       )
       OR (SELECT count(*) FROM jsonb_array_elements_text(frozen))
           <> (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(frozen) a(value))
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements_text(frozen) a(value)
          WHERE NULLIF(btrim(a.value),'') IS NULL
             OR NOT EXISTS (
                SELECT 1 FROM public.lf_operation_steps s
                 WHERE s.operation_code=e.operation_code AND s.step_id=a.value
                   AND s.required AND s.active
             )
       )
    THEN RETURN jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID'); END IF;

    routes := e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}';
    IF routes IS NULL THEN
        RETURN jsonb_build_object('outcome','LEGACY_FROZEN','effective_steps',frozen);
    END IF;
    prefix := e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_before_decision}';
    update_steps := routes->'UPDATE';
    no_change_steps := routes->'NO_CHANGE';
    -- Type-check before array operations: malformed JSON must fail closed,
    -- never yield a successful or ambiguous NULL boolean.
    IF coalesce(jsonb_typeof(routes),'') <> 'object'
       OR coalesce(jsonb_typeof(prefix),'') <> 'array'
       OR coalesce(jsonb_typeof(update_steps),'') <> 'array'
       OR coalesce(jsonb_typeof(no_change_steps),'') <> 'array'
    THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID');
    END IF;
    IF update_steps <> frozen
       OR jsonb_array_length(prefix) <> 6
       OR jsonb_array_length(no_change_steps) < 6
       OR prefix <> (
            SELECT jsonb_agg(value ORDER BY ordinality)
              FROM jsonb_array_elements(update_steps) WITH ORDINALITY a(value,ordinality)
             WHERE ordinality <= 6
       )
       OR prefix <> (
            SELECT jsonb_agg(value ORDER BY ordinality)
              FROM jsonb_array_elements(no_change_steps) WITH ORDINALITY a(value,ordinality)
             WHERE ordinality <= 6
       )
       OR prefix->>4 <> 'method_selection'
       OR prefix->>5 <> 'evolution_decision'
       OR (SELECT count(*) FROM jsonb_array_elements_text(no_change_steps))
          <> (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(no_change_steps) a(x))
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements(no_change_steps) a(value)
         WHERE jsonb_typeof(a.value) <> 'string'
       )
       OR no_change_steps ? 'github_write'
       OR no_change_steps ? 'pre_write_execution_binding_gate'
       OR no_change_steps ? 'post_merge_reconcile'
       OR EXISTS (
         SELECT 1 FROM jsonb_array_elements_text(no_change_steps) b(value)
          WHERE NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements_text(frozen) f(value)
             WHERE f.value=b.value
          )
       )
    THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID');
    END IF;

    SELECT * INTO decision_row
      FROM public.lf_operation_execution_steps
     WHERE execution_id=p_execution_id AND step_id='evolution_decision';
    IF NOT FOUND OR decision_row.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
        RETURN jsonb_build_object('outcome','AWAITING_EVOLUTION_DECISION','effective_steps',prefix);
    END IF;
    IF decision_row.evidence_payload->>'recorded_by_rpc' IS DISTINCT FROM 'lf_record_profile_operation_step_v1'
       OR decision_row.evidence_payload->>'mini_judge_result' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','EVOLUTION_DECISION_UNVERIFIED_RECORDER');
    END IF;
    outcome := decision_row.evidence_payload->>'decision';
    IF outcome NOT IN ('UPDATE','NO_CHANGE') OR outcome IS NULL THEN
        RETURN jsonb_build_object('outcome','BLOCKED','code','EVOLUTION_DECISION_NOT_ADMITTED');
    END IF;
    IF (outcome='NO_CHANGE' AND decision_row.evidence_payload->>'evolution_mode' IS DISTINCT FROM 'NO_CHANGE')
       OR (outcome='UPDATE' AND (
         decision_row.evidence_payload->>'evolution_mode' IS NULL
         OR decision_row.evidence_payload->>'evolution_mode' NOT IN
              ('PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE')
       ))
    THEN RETURN jsonb_build_object('outcome','BLOCKED','code','EVOLUTION_DECISION_MODE_MISMATCH'); END IF;
    selected := routes->outcome;
    RETURN jsonb_build_object('outcome',outcome,'effective_steps',selected);
END;
$route$;

-- NOTE: no GRANT here. Do not apply while caller and recorder use different
-- route functions, since that would violate invariant:
--    cursor.next_step == recorder.authorized_next_step.
-- Test under a Train ROLLBACK with cases:
-- legacy 15/15; UPDATE 17/17; NO_CHANGE 10/10 and zero write; pending 6/17;
-- malformed; stale/forged decision; historical 22 unmodified;
-- missing method qualification/assessment fail-closed.

-- SOURCE skills/profile_creator/contracts/profile_update_evolution_step_guard_candidate_v1.sql BLOB 6565ce15ea00297dc54c80014bbcc3723d7dc646
-- Candidate-only; designed for invocation INSIDE the existing
-- public.lf_record_profile_operation_step_v1 substantive validation path.
-- Never directly install/GRANT as a standalone UPDATE/NO_CHANGE authority.
--
-- Prerequisite: verified_receipt reader with narrow SECURITY DEFINER scope.
CREATE OR REPLACE FUNCTION public.lf_profile_update_evolution_step_guard_v1(
  p_execution_id text,
  p_step_id text,
  p_payload jsonb
) RETURNS text
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog,public
AS $guard$
DECLARE
  e public.lf_operation_execution%rowtype;
  recorded public.lf_operation_execution_steps%rowtype;
  portfolio jsonb;
  r record;
  m record;
  method_data jsonb;
  slug text;
  decision text;
  mode text;
BEGIN
  IF p_step_id NOT IN ('method_selection','evolution_decision') THEN RETURN NULL; END IF;
  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR e.operation_code<>'ACTUALIZACION_PERFIL_LF'
     OR e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}' IS NULL
  THEN RETURN 'EVOLUTION_OPERATION_CONTEXT_INVALID'; END IF;
  IF jsonb_typeof(p_payload) <> 'object' THEN RETURN 'EVOLUTION_EVIDENCE_NOT_OBJECT'; END IF;
  slug:=split_part(e.target_path,'/',2);
  IF NULLIF(slug,'') IS NULL OR p_payload->>'profile_slug' IS DISTINCT FROM slug THEN
    RETURN 'EVOLUTION_PROFILE_IDENTITY_MISMATCH';
  END IF;
  IF p_payload->>'source_head_sha' IS DISTINCT FROM coalesce(e.manifest->>'initial_main_revision','')
     OR p_payload->>'source_head_sha' !~ '^[0-9a-f]{40}$'
  THEN RETURN 'EVOLUTION_SOURCE_REVISION_MISMATCH'; END IF;
  IF NOT public.lf_profile_update_verified_receipt_v1(
       'PROFILE_ASSESSMENT',slug,
       p_payload->>'profile_assessment_receipt_id',
       p_payload->>'profile_assessment_sha256',
       p_payload->>'source_head_sha'
  ) THEN RETURN 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'; END IF;

  IF p_step_id='method_selection' THEN
    IF p_payload->>'selector_version' IS DISTINCT FROM (
      SELECT version FROM public.lf_capability_current
       WHERE capability_code='CAPABILITY_SELECTOR'
    ) THEN RETURN 'EVOLUTION_SELECTOR_VERSION_STALE'; END IF;
    SELECT v.manifest#>'{contract,qualified_method_portfolio}' INTO portfolio
      FROM public.lf_capability_current c
      JOIN public.lf_capability_version_registry v
        ON v.capability_code=c.capability_code AND v.version=c.version
     WHERE c.capability_code='METHOD_PACK_REGISTRY'
       AND v.release_state='RELEASED';
    IF coalesce(jsonb_typeof(portfolio),'')<>'array'
       OR coalesce(jsonb_typeof(p_payload->'selected_methods'),'')<>'array'
    THEN RETURN 'EVOLUTION_METHOD_PORTFOLIO_INVALID'; END IF;

    IF jsonb_array_length(p_payload->'selected_methods')=0 THEN
      IF p_payload->'no_additional_method_needed' IS DISTINCT FROM 'true'::jsonb
         OR nullif(btrim(p_payload->>'empty_selection_reason'),'') IS NULL
      THEN RETURN 'EVOLUTION_EMPTY_METHOD_UNJUSTIFIED'; END IF;
    ELSE
      IF p_payload->'no_additional_method_needed'='true'::jsonb THEN
        RETURN 'EVOLUTION_METHOD_SELECTION_CONTRADICTORY';
      END IF;
    END IF;
    FOR r IN SELECT value AS item FROM jsonb_array_elements(p_payload->'selected_methods')
    LOOP
      IF jsonb_typeof(r.item)<>'object' OR
         nullif(btrim(r.item->>'method_id'),'') IS NULL OR
         nullif(btrim(r.item->>'exact_version'),'') IS NULL OR
         nullif(btrim(r.item->>'receipt_id'),'') IS NULL
      THEN RETURN 'EVOLUTION_METHOD_RECORD_INVALID'; END IF;
      SELECT elem.value INTO method_data
        FROM jsonb_array_elements(portfolio) AS elem(value)
       WHERE elem.value->>'method_id'=r.item->>'method_id'
         AND elem.value->>'exact_version'=r.item->>'exact_version'
         AND elem.value->>'qualification_state'='QUALIFIED'
       LIMIT 1;
      IF method_data IS NULL THEN RETURN 'EVOLUTION_METHOD_NOT_QUALIFIED'; END IF;
      IF NOT public.lf_profile_update_verified_receipt_v1(
        'METHOD_QUALIFICATION',
        (r.item->>'method_id')||'@'||(r.item->>'exact_version'),
        r.item->>'receipt_id',
        r.item->>'subject_sha256',
        r.item->>'source_head_sha'
      ) THEN RETURN 'EVOLUTION_METHOD_QUALIFICATION_UNVERIFIED'; END IF;
    END LOOP;
    IF p_payload->'method_execution_permitted' IS DISTINCT FROM 'false'::jsonb
    THEN RETURN 'EVOLUTION_SELECTION_ILLEGAL_EXECUTION_PERMISSION'; END IF;
    RETURN NULL;
  END IF;

  SELECT * INTO recorded FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id AND step_id='method_selection';
  IF NOT FOUND OR recorded.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
     OR recorded.evidence_payload->>'recorded_by_rpc' IS DISTINCT FROM 'lf_record_profile_operation_step_v1'
     OR recorded.evidence_payload->>'mini_judge_result' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN RETURN 'EVOLUTION_SELECTION_STEP_NOT_CLEAN'; END IF;
  IF recorded.evidence_payload->>'profile_assessment_receipt_id'
     IS DISTINCT FROM p_payload->>'profile_assessment_receipt_id'
  THEN RETURN 'EVOLUTION_DECISION_ASSESSMENT_RECEIPT_MISMATCH'; END IF;
  decision:=p_payload->>'decision';
  mode:=p_payload->>'evolution_mode';
  IF decision='NO_CHANGE' AND mode IS DISTINCT FROM 'NO_CHANGE' THEN
    RETURN 'EVOLUTION_NO_CHANGE_MODE_INVALID';
  ELSIF decision='UPDATE' AND (mode IS NULL OR mode NOT IN ('PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE'))
  THEN RETURN 'EVOLUTION_UPDATE_MODE_INVALID';
  ELSIF decision IS NULL OR decision NOT IN ('NO_CHANGE','UPDATE')
  THEN RETURN 'EVOLUTION_DECISION_NOT_ADMITTED';
  END IF;
  IF nullif(btrim(p_payload->>'decision_evidence_ref'),'') IS NULL THEN
    RETURN 'EVOLUTION_DECISION_EVIDENCE_MISSING';
  END IF;
  IF p_payload->'github_write_permitted' IS DISTINCT FROM 'false'::jsonb THEN
    RETURN 'EVOLUTION_DECISION_CANNOT_AUTHORIZE_WRITE';
  END IF;
  RETURN NULL;
END;
$guard$;

-- Keep this check as one component of the existing substantive recorder.
-- The registered judge must additionally verify typed assertions and
-- no outstanding blockers. No direct PASS is returned or declared here.

REVOKE ALL ON FUNCTION public.lf_profile_update_effective_route_v1(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_effective_route_v1(text) TO service_role;
REVOKE ALL ON FUNCTION public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_update_evolution_step_guard_v1(text,text,jsonb) TO service_role;

-- Test negative paths without writing an operation execution.
DO $smoke$
DECLARE
  v jsonb;
BEGIN
 IF public.lf_profile_update_verified_receipt_v1(
      'PROFILE_ASSESSMENT','nonexistent','not-a-uuid',
      repeat('a',64),repeat('b',40)) IS TRUE
 THEN RAISE EXCEPTION 'PE10_VERIFIED_RECEIPT_FALSE_POSITIVE'; END IF;

 v := public.lf_profile_update_effective_route_v1(
      'EXEC-PE10-NONEXISTENT-SOURCE-ONLY');
 IF v->>'outcome' IS DISTINCT FROM 'BLOCKED'
 THEN RAISE EXCEPTION 'PE10_ROUTE_UNKNOWN_EXECUTION_ACCEPTED'; END IF;

 IF public.lf_profile_update_evolution_step_guard_v1(
       'EXEC-PE10-NONEXISTENT-SOURCE-ONLY','method_selection','{}'::jsonb)
    IS DISTINCT FROM 'EVOLUTION_OPERATION_CONTEXT_INVALID'
 THEN RAISE EXCEPTION 'PE10_GUARD_UNKNOWN_EXECUTION_ACCEPTED'; END IF;

 IF has_table_privilege('service_role','private.lf_evidence_ledger_v1','SELECT')
    OR has_table_privilege('service_role','private.lf_evidence_resolver_registry_v1','SELECT')
 THEN RAISE EXCEPTION 'PE10_TEST_BROAD_GRANT'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_steps
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active) <> 15
 THEN RAISE EXCEPTION 'PE10_TEST_STEPS_CHANGED'; END IF;
END
$smoke$;
COMMIT;

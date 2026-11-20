-- PR-H: replaces only the unconditional FUNCTIONAL ban with source-bound Train evidence.
-- No alter of owner_decide, child guard, candidate promotion, rules or security policies.
-- This migration does not seed any evidence and cannot apply AUTH-020.
DO $pre$
BEGIN
  IF md5(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure))
       IS DISTINCT FROM '9d1a771fe5dd8b466b76071b582f19fa'
  THEN RAISE EXCEPTION 'PR_H_FINALIZER_PREIMAGE_DRIFT'; END IF;
  IF (SELECT count(*) FROM public.lf_ig_rule_change_v2) <> 0
     OR (SELECT count(*) FROM public.lf_ig_owner_decision_v2) <> 0
  THEN RAISE EXCEPTION 'PR_H_EXISTING_V2_RECEIPTS_REQUIRE_REVIEW'; END IF;
  IF to_regclass('public.lf_ig_functional_train_evidence_v1') IS NOT NULL
  THEN RAISE EXCEPTION 'PR_H_TRAIN_EVIDENCE_TABLE_PREEXISTS'; END IF;
  IF has_function_privilege('anon','public.lf_ig_rule_finalize_v2(text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_ig_rule_finalize_v2(text)','EXECUTE')
  THEN RAISE EXCEPTION 'PR_H_FINALIZER_CLIENT_EXECUTE_EXPOSED'; END IF;
END
$pre$;

-- Evidence must be produced in a separate, real, exact-patch Train run before
-- the owner decides: owner_decide -> staged -> finalize is ONE transaction.
-- FAIL-CLOSED: no row for the exact rule/source/patch => no FUNCTIONAL write.
CREATE TABLE public.lf_ig_functional_train_evidence_v1 (
  rule_code text NOT NULL CHECK (rule_code ~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'),
  source_snapshot_sha256 text NOT NULL
    CHECK (source_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  proposal_sha256 text NOT NULL CHECK (proposal_sha256 ~ '^[0-9a-f]{64}$'),
  candidate_snapshot_sha256 text NOT NULL
    CHECK (candidate_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  train_execution_id text NOT NULL
    CHECK (train_execution_id ~ '^EXEC-DB-TRAIN-PR[0-9]+-[0-9]{14}-R[0-9]+$'),
  train_run_id text NOT NULL CHECK (train_run_id ~ '^[0-9]+$'),
  train_event_id bigint NOT NULL REFERENCES public.lf_eventos(id),
  train_head_sha text NOT NULL CHECK (train_head_sha ~ '^[0-9a-f]{40}$'),
  pg_rollback_status text NOT NULL CHECK (pg_rollback_status='PASS'),
  independent_readback_status text NOT NULL
    CHECK (independent_readback_status='PASS'),
  functional_checks_status text NOT NULL CHECK (functional_checks_status='PASS'),
  negative_checks_status text NOT NULL CHECK (negative_checks_status='PASS'),
  pg_report_sha256 text NOT NULL CHECK (pg_report_sha256 ~ '^[0-9a-f]{64}$'),
  readback_sha256 text NOT NULL CHECK (readback_sha256 ~ '^[0-9a-f]{64}$'),
  check_manifest_sha256 text NOT NULL
    CHECK (check_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  report_ref text NOT NULL CHECK (length(btrim(report_ref))>=8),
  captured_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (rule_code,source_snapshot_sha256,proposal_sha256)
);
ALTER TABLE public.lf_ig_functional_train_evidence_v1
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_ig_functional_train_evidence_v1
  FORCE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.lf_ig_functional_train_evidence_v1
  FROM PUBLIC, anon, authenticated, service_role;

DO $replace$
DECLARE
  v_fn text;
  v_original_length integer;
BEGIN
  SELECT pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure)
   INTO v_fn;
  IF md5(v_fn)<>'9d1a771fe5dd8b466b76071b582f19fa'
  THEN RAISE EXCEPTION 'PR_H_FINALIZER_PREIMAGE_CHANGE_DURING_TRANSACTION'; END IF;

  v_original_length:=length(v_fn);
  v_fn:=replace(v_fn,$ph_old_0$ c jsonb;before_sha text;after_sha text;v_promotion text;$ph_old_0$,$ph_new_0$ c jsonb;before_sha text;after_sha text;v_promotion text;v_impact record;$ph_new_0$);
  IF v_original_length-length(v_fn) <> -16 THEN
    RAISE EXCEPTION 'PR_H_FINALIZER_REPLACEMENT_COUNT_0';
  END IF;

  v_original_length:=length(v_fn);
  v_fn:=replace(v_fn,$ph_old_1$   -- A functional change can weaken security/business controls. A declared
   -- human decision plus profile semantic PASS is insufficient for post-write
   -- impact; no signed independent impact receipt is installed in this version.
   IF ch.approved_patch->>'change_kind' IS DISTINCT FROM 'DOCUMENTARY_ONLY'
   THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING'; END IF;$ph_old_1$,$ph_new_1$   -- Owner-delegated automatic functional gate: only a source-bound technical
   -- Train receipt with PostgreSQL rollback, independent readback and tests.
   IF ch.approved_patch->>'change_kind'='FUNCTIONAL' THEN
     SELECT * INTO v_impact FROM public.lf_ig_functional_train_evidence_v1 i
     WHERE i.rule_code=ch.rule_code
       AND i.source_snapshot_sha256=before_sha
       AND i.proposal_sha256=d.proposal_sha256
       AND i.pg_rollback_status='PASS'
       AND i.independent_readback_status='PASS'
       AND i.functional_checks_status='PASS'
       AND i.negative_checks_status='PASS'
     LIMIT 1;
     IF NOT FOUND THEN
       RAISE EXCEPTION 'LF_IG_VIGENTE_FUNCTIONAL_TRAIN_EVIDENCE_MISSING'; END IF;
     IF ch.approved_patch IS DISTINCT FROM d.approved_patch OR
        encode(extensions.digest(convert_to(ch.approved_patch::text,'UTF8'),'sha256'),'hex')
          IS DISTINCT FROM d.proposal_sha256
     THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FUNCTIONAL_PATCH_SHA_DRIFT'; END IF;
     IF NOT EXISTS (
       SELECT 1 FROM public.lf_operation_execution te
       JOIN public.lf_eventos evt
         ON evt.id=v_impact.train_event_id
        AND evt.entidad_codigo=te.execution_id
        AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
        AND evt.origen='lf-migration-merge-train'
       WHERE te.execution_id=v_impact.train_execution_id
         AND te.operation_code='ACTUALIZACION_DB_LF'
         AND te.status='COMPLETED'
         AND te.manifest->>'train_run_id'=v_impact.train_run_id
         AND te.manifest->>'head_sha'=v_impact.train_head_sha
         AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||v_impact.train_run_id
         AND evt.payload#>>'{receipt,train_run_id}'=v_impact.train_run_id
         AND evt.payload#>>'{receipt,heads,final_head}'=v_impact.train_head_sha
         AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
         AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
         AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
         AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
         AND evt.payload->>'receipt_sha256' ~ '^[0-9a-f]{64}$'
         AND encode(extensions.digest(
               convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
             =evt.payload->>'receipt_sha256'
     ) THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FUNCTIONAL_TRAIN_RUN_UNVERIFIED'; END IF;
   ELSIF ch.approved_patch->>'change_kind' IS DISTINCT FROM 'DOCUMENTARY_ONLY'
   THEN RAISE EXCEPTION 'LF_IG_VIGENTE_CHANGE_KIND_INVALID'; END IF;$ph_new_1$);
  IF v_original_length-length(v_fn) <> -2190 THEN
    RAISE EXCEPTION 'PR_H_FINALIZER_REPLACEMENT_COUNT_1';
  END IF;

  v_original_length:=length(v_fn);
  v_fn:=replace(v_fn,$ph_old_2$ after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',ch.rule_code);
 IF after_sha IS NULL OR after_sha=before_sha OR NOT EXISTS($ph_old_2$,$ph_new_2$ after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',ch.rule_code);
 IF ch.kind='CORRECT_VIGENTE' AND
    ch.approved_patch->>'change_kind'='FUNCTIONAL' AND
    after_sha IS DISTINCT FROM v_impact.candidate_snapshot_sha256
 THEN RAISE EXCEPTION 'LF_IG_VIGENTE_FUNCTIONAL_CANDIDATE_HASH_DRIFT'; END IF;
 IF after_sha IS NULL OR after_sha=before_sha OR NOT EXISTS($ph_new_2$);
  IF v_original_length-length(v_fn) <> -234 THEN
    RAISE EXCEPTION 'PR_H_FINALIZER_REPLACEMENT_COUNT_2';
  END IF;
  IF md5(v_fn)<>'df1acd69a46b8bc4a6c257d95cc9a47a'
  THEN RAISE EXCEPTION 'PR_H_FINALIZER_PROJECTION_MD5_DRIFT'; END IF;
  EXECUTE v_fn;
  IF md5(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure))
    <>'df1acd69a46b8bc4a6c257d95cc9a47a'
  THEN RAISE EXCEPTION 'PR_H_FINALIZER_POSTIMAGE_MD5_DRIFT'; END IF;
  IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1)<>0
  THEN RAISE EXCEPTION 'PR_H_NO_EVIDENCE_SHOULD_BE_SEEDED'; END IF;
  IF NOT (
    SELECT relrowsecurity AND relforcerowsecurity
      FROM pg_class WHERE oid='public.lf_ig_functional_train_evidence_v1'::regclass
  ) OR EXISTS(SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='lf_ig_functional_train_evidence_v1')
  THEN RAISE EXCEPTION 'PR_H_RLS_INVALID'; END IF;
  IF has_function_privilege('anon','public.lf_ig_rule_finalize_v2(text)','EXECUTE')
      OR has_function_privilege('authenticated','public.lf_ig_rule_finalize_v2(text)','EXECUTE')
  THEN RAISE EXCEPTION 'PR_H_FINALIZER_EXECUTE_ACL_DRIFT'; END IF;
END
$replace$;

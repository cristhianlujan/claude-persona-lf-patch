BEGIN;
DO $pre$
BEGIN
  IF to_regclass('private.lf_programming_context_handoff_receipts_v1') IS NULL
     OR to_regclass('public.lf_operation_execution') IS NULL
     OR to_regclass('public.lf_operation_execution_steps') IS NULL
     OR to_regprocedure('private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'PROGRAMACION_V2_PREREQUISITE_MISSING';
  END IF;
END $pre$;

CREATE TABLE IF NOT EXISTS private.lf_programming_admission_revocations_v1 (
  revocation_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  binding_key_sha256 text,
  context_id uuid,
  reason_code text NOT NULL,
  revoked_by_execution_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_programming_revocation_target CHECK
    ((binding_key_sha256 IS NOT NULL) <> (context_id IS NOT NULL)),
  CONSTRAINT ck_programming_revocation_sha CHECK
    (binding_key_sha256 IS NULL OR binding_key_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT ck_programming_revocation_reason CHECK (btrim(reason_code) <> ''),
  CONSTRAINT ck_programming_revocation_execution CHECK (btrim(revoked_by_execution_id) <> '')
);
CREATE INDEX IF NOT EXISTS idx_programming_revocation_binding ON private.lf_programming_admission_revocations_v1(binding_key_sha256);
CREATE INDEX IF NOT EXISTS idx_programming_revocation_context ON private.lf_programming_admission_revocations_v1(context_id);

CREATE OR REPLACE FUNCTION private.fn_lf_programming_admission_revocation_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog','private' AS $fn$
BEGIN
  RAISE EXCEPTION 'PROGRAMACION_V2_REVOCATION_APPEND_ONLY:%',TG_OP;
END $fn$;
DROP TRIGGER IF EXISTS trg_00_programming_admission_revocation_immutable ON private.lf_programming_admission_revocations_v1;
CREATE TRIGGER trg_00_programming_admission_revocation_immutable BEFORE UPDATE OR DELETE
ON private.lf_programming_admission_revocations_v1 FOR EACH ROW
EXECUTE FUNCTION private.fn_lf_programming_admission_revocation_immutable_v1();

-- Canonical definition fingerprint: exclude only volatile metadata.generated_at.
-- SECURITY INVOKER, callable only by owner via V2 resolver.
CREATE OR REPLACE FUNCTION private.fn_lf_programming_definition_ref_sha256_v1(p_definition_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','private','lf_ops','extensions' AS $ref$
DECLARE
  parts text[]; v_count bigint; v_status text; v_version text; v_contract jsonb;
BEGIN
  IF p_definition_ref IS NULL OR p_definition_ref !~ '^lf-screen-contract://[^/]+/[^/]+/[^/]+$' THEN
    RETURN jsonb_build_object('ok',false,'reason','DEFINITION_REF_SCHEME_UNSUPPORTED');
  END IF;
  parts := string_to_array(substring(p_definition_ref from length('lf-screen-contract://')+1),'/');
  -- One call only: each call builds the full screen contract (~300 KB for B2B-AUTH-001).
  SELECT count(*), min(f.screen_status), min(f.contract_version), (array_agg(f.contract))[1]
    INTO v_count,v_status,v_version,v_contract
    FROM lf_ops.fn_screen_contract_v1(parts[1],parts[2],parts[3]) f;
  IF v_count IS DISTINCT FROM 1 THEN
    RETURN jsonb_build_object('ok',false,'reason',CASE WHEN v_count=0 THEN 'DEFINITION_NOT_FOUND' ELSE 'DEFINITION_AMBIGUOUS' END);
  END IF;
  RETURN jsonb_build_object('ok',true,'definition_ref',p_definition_ref,
    'definition_sha256',encode(extensions.digest(convert_to((v_contract #- '{metadata,generated_at}')::text,'UTF8'),'sha256'),'hex'),
    'screen_status',v_status,'contract_version',v_version);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok',false,'reason','DEFINITION_CURRENTNESS_UNDETERMINED');
END $ref$;

CREATE OR REPLACE FUNCTION private.fn_lf_programming_definition_currentness_v1(p_definition_refs jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','private' AS $cur$
DECLARE
  ref jsonb; one jsonb; items jsonb := '[]'::jsonb;
  failure text; item_reason text;
BEGIN
  IF jsonb_typeof(p_definition_refs) IS DISTINCT FROM 'array'
     OR jsonb_array_length(CASE WHEN jsonb_typeof(p_definition_refs)='array' THEN p_definition_refs ELSE '[]'::jsonb END)=0 THEN
    RETURN jsonb_build_object('verified',false,'reason','DEFINITION_REFS_INVALID','results',items);
  END IF;
  FOR ref IN SELECT value FROM jsonb_array_elements(p_definition_refs) LOOP
    IF jsonb_typeof(ref) IS DISTINCT FROM 'object'
       OR (SELECT count(*) FROM jsonb_object_keys(ref)) IS DISTINCT FROM 2
       OR jsonb_typeof(ref->'definition_ref') IS DISTINCT FROM 'string'
       OR btrim(ref->>'definition_ref') = ''
       OR jsonb_typeof(ref->'definition_sha256') IS DISTINCT FROM 'string'
       OR (ref->>'definition_sha256') !~ '^[0-9a-f]{64}$' THEN
      RETURN jsonb_build_object('verified',false,'reason','DEFINITION_REFS_INVALID','results',items);
    END IF;
    one:=private.fn_lf_programming_definition_ref_sha256_v1(ref->>'definition_ref');
    item_reason:=NULL;
    IF (one->>'ok')::boolean IS DISTINCT FROM true THEN
      item_reason:=coalesce(one->>'reason','DEFINITION_CURRENTNESS_UNDETERMINED');
    ELSIF one->>'screen_status' IS DISTINCT FROM 'VIGENTE' THEN
      item_reason:='DEFINITION_NOT_CURRENT';
    ELSIF one->>'definition_sha256' IS DISTINCT FROM ref->>'definition_sha256' THEN
      item_reason:='DEFINITION_CHANGED';
    END IF;
    IF failure IS NULL THEN failure:=item_reason; END IF;
    items:=items || jsonb_build_array(jsonb_build_object(
      'definition_ref',ref->>'definition_ref','ok',item_reason IS NULL,
      'reason',coalesce(item_reason,'DEFINITION_CURRENT'),
      'screen_status',one->>'screen_status'));
  END LOOP;
  RETURN jsonb_build_object('verified',failure IS NULL,
    'reason',coalesce(failure,'DEFINITION_CURRENT'),'results',items);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('verified',false,'reason','DEFINITION_CURRENTNESS_UNDETERMINED','results',items);
END $cur$;

CREATE OR REPLACE FUNCTION private.fn_lf_programming_admission_revocation_train_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','private','public' AS $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
     WHERE e.execution_id=NEW.revoked_by_execution_id
       AND e.operation_code='ACTUALIZACION_DB_LF'
       AND e.status='IN_PROGRESS'
       AND e.manifest->>'producer'='lf-migration-merge-train') THEN
    RAISE EXCEPTION 'PROGRAMACION_V2_REVOCATION_NOT_TRAIN';
  END IF;
  RETURN NEW;
END $guard$;
CREATE TRIGGER trg_01_programming_admission_revocation_train_guard
BEFORE INSERT ON private.lf_programming_admission_revocations_v1
FOR EACH ROW EXECUTE FUNCTION private.fn_lf_programming_admission_revocation_train_guard_v1();

CREATE OR REPLACE FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v2(p_binding jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','private','public','extensions' AS $fn$
DECLARE
  v1 jsonb; r jsonb; env jsonb; j jsonb; cur jsonb;
  scopes jsonb; refs jsonb; v_revoked boolean;
  judge_count bigint; review_count bigint; record_count bigint;
  dt_from timestamptz; dt_until timestamptz;
  keysha text; context_uuid uuid;
  result jsonb;
  checks jsonb := '[]'::jsonb;
  reason text;
  digest CONSTANT text := 'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';
BEGIN
  -- Reuse the exact existing D7 normalizer and binding hash, without fallback.
  -- A D7 v1 match returns record even though v1 admission is always closed.
  v1 := private.fn_lf_programming_context_handoff_receipt_resolve_v1(p_binding);
  IF (v1->>'found')::boolean IS DISTINCT FROM true THEN
    reason := 'PG01_V2_RECEIPT_NOT_FOUND';
  ELSE
    r := v1->'record';
    keysha := r->>'binding_key_sha256';
    IF (v1->>'hashes_verified')::boolean IS DISTINCT FROM true THEN
      reason := 'PG01_V2_HASH_MISMATCH';
    ELSIF r->>'verdict' IS DISTINCT FROM 'ACCEPT' THEN
      reason := 'PG01_V2_RECEIPT_NOT_ACCEPT';
    END IF;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','RECEIPT','pass',reason IS NULL));
  -- Stop at the receipt: never overwrite its reason and never report a row that was not found.
  IF reason IS NOT NULL THEN
    RETURN jsonb_build_object('found',coalesce((v1->>'found')::boolean,false),
      'hashes_verified',coalesce((v1->>'hashes_verified')::boolean,false),
      'admissible',false,'reason',reason,
      'envelope_contract','PROGRAMMING_ADMISSION_ENVELOPE_V2','checks',checks,'record',r);
  END IF;
  env := r->'envelope';
  IF jsonb_typeof(env) IS DISTINCT FROM 'object'
     OR env->>'schema_version' IS DISTINCT FROM 'PROGRAMMING_ADMISSION_ENVELOPE_V2'
     OR (SELECT count(*) FROM jsonb_object_keys(env)) IS DISTINCT FROM 10
     OR NOT (env ?& ARRAY['schema_version','entry_contract_digest_sha256','context_id','context_sha256','judge','admitted_scope_ids','valid_from','valid_until','definition_refs','issued_by_execution_id']) THEN
    reason := 'PG01_V2_ENVELOPE_INVALID';
  END IF;
  IF reason IS NULL THEN
    j := env->'judge'; scopes := env->'admitted_scope_ids'; refs := env->'definition_refs';
    IF jsonb_typeof(j) IS DISTINCT FROM 'object'
       OR (SELECT count(*) FROM jsonb_object_keys(j)) IS DISTINCT FROM 4
       OR j->>'capability_code' IS DISTINCT FROM 'INDEPENDENT_ASSURANCE'
       OR j->>'capability_version' IS DISTINCT FROM '2.0.1'
       OR jsonb_typeof(j->'execution_id') IS DISTINCT FROM 'string'
       OR btrim(j->>'execution_id') = ''
       OR (j->>'subject_sha256') !~ '^[0-9a-f]{64}$'
       OR jsonb_typeof(scopes) IS DISTINCT FROM 'array'
       OR jsonb_typeof(refs) IS DISTINCT FROM 'array'
       OR jsonb_typeof(env->'issued_by_execution_id') IS DISTINCT FROM 'string'
       OR btrim(env->>'issued_by_execution_id') = ''
       OR (env->>'context_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR (env->>'context_sha256') !~ '^[0-9a-f]{64}$'
       OR (env->>'entry_contract_digest_sha256') !~ '^[0-9a-f]{64}$'
       OR jsonb_typeof(env->'valid_from') IS DISTINCT FROM 'string'
       OR jsonb_typeof(env->'valid_until') IS DISTINCT FROM 'string' THEN
      reason := 'PG01_V2_ENVELOPE_INVALID';
    END IF;
  END IF;
  IF reason IS NULL THEN
    IF jsonb_array_length(scopes)=0 OR jsonb_array_length(refs)=0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(scopes) AS a(val)
                  WHERE jsonb_typeof(a.val) IS DISTINCT FROM 'string' OR btrim(a.val#>>'{}')='')
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(refs) AS a(val)
                  WHERE jsonb_typeof(a.val) IS DISTINCT FROM 'object'
                     OR (SELECT count(*) FROM jsonb_object_keys(a.val)) IS DISTINCT FROM 2
                     OR jsonb_typeof(a.val->'definition_ref') IS DISTINCT FROM 'string'
                     OR btrim(a.val->>'definition_ref')=''
                     OR (a.val->>'definition_sha256') !~ '^[0-9a-f]{64}$') THEN
      reason := 'PG01_V2_ENVELOPE_INVALID';
    END IF;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','ENVELOPE','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  IF reason IS NULL AND (env->>'context_id' IS DISTINCT FROM r->>'context_id'
       OR env->>'context_sha256' IS DISTINCT FROM r->>'context_sha256'
       OR env->>'entry_contract_digest_sha256' IS DISTINCT FROM p_binding->>'entry_contract_digest_sha256'
       OR env->>'entry_contract_digest_sha256' IS DISTINCT FROM digest) THEN
    reason := 'PG01_V2_CONTEXT_OR_CONTRACT_MISMATCH';
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','CONTEXT','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  IF reason IS NULL THEN
    SELECT count(*) INTO judge_count FROM public.lf_operation_execution e
      WHERE e.execution_id=j->>'execution_id'
        AND e.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
        AND e.status='COMPLETED'
        AND e.manifest->>'capability_code'='INDEPENDENT_ASSURANCE'
        AND e.manifest->>'subject_sha256'=r->>'context_sha256'
        AND e.manifest->>'subject_ref'='PROGRAMMING_ANALYSIS_PACKAGE/'||(r->>'context_id');
    IF j->>'subject_sha256' IS DISTINCT FROM r->>'context_sha256' OR judge_count IS DISTINCT FROM 1 THEN
      reason := 'PG01_V2_JUDGE_INVALID';
    END IF;
  END IF;
  IF reason IS NULL THEN
    SELECT count(*) INTO review_count FROM public.lf_operation_execution_steps s
     WHERE s.execution_id=j->>'execution_id' AND s.step_id='semantic_review'
       AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'verdict'='PASS';
    SELECT count(*) INTO record_count FROM public.lf_operation_execution_steps s
     WHERE s.execution_id=j->>'execution_id' AND s.step_id='judge_record'
       AND s.status='STEP_PASS_WITH_EVIDENCE';
    IF review_count IS DISTINCT FROM 1 OR record_count IS DISTINCT FROM 1 THEN
      reason := 'PG01_V2_JUDGE_STEPS_INVALID';
    END IF;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','JUDGE','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  IF reason IS NULL THEN
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_binding->'requested_scope_ids') AS q(val)
               WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(scopes) AS a(val) WHERE a.val=q.val)) THEN
      reason := 'PG01_V2_SCOPE_NOT_ADMITTED';
    END IF;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','SCOPES','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  IF reason IS NULL THEN
    BEGIN
      IF env->>'valid_from' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'
         OR env->>'valid_until' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$' THEN
        reason := 'PG01_V2_VALIDITY_INVALID';
      ELSE
        dt_from := (env->>'valid_from')::timestamptz;
        dt_until := (env->>'valid_until')::timestamptz;
        IF dt_from >= dt_until OR dt_until > dt_from + interval '24 hours' THEN
          reason := 'PG01_V2_VALIDITY_INVALID';
        ELSIF now() < dt_from THEN
          reason := 'PG01_V2_NOT_YET_VALID';
        ELSIF now() >= dt_until THEN
          reason := 'PG01_V2_EXPIRED';
        END IF;
      END IF;
    EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
      reason := 'PG01_V2_VALIDITY_INVALID';
    END;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','VALIDITY','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  IF reason IS NULL THEN
    SELECT EXISTS(SELECT 1 FROM private.lf_programming_admission_revocations_v1 rev
                  WHERE rev.binding_key_sha256=keysha OR rev.context_id=(r->>'context_id')::uuid) INTO v_revoked;
    IF v_revoked THEN reason := 'PG01_V2_REVOKED'; END IF;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','REVOCATION','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  IF reason IS NULL THEN
    cur := private.fn_lf_programming_definition_currentness_v1(refs);
    IF (cur->>'verified')::boolean IS DISTINCT FROM true THEN
      reason := 'PG01_V2_DEFINITION_CURRENTNESS_NOT_VERIFIED';
    END IF;
  END IF;
  checks := checks || jsonb_build_array(jsonb_build_object('check','DEFINITION_CURRENTNESS','pass',reason IS NULL,'evaluated',reason IS NULL OR NOT (checks @> '[{"pass":false}]'::jsonb)));
  RETURN jsonb_build_object('found',true,'hashes_verified',(v1->>'hashes_verified')::boolean,
    'admissible',reason IS NULL,'reason',coalesce(reason,'PG01_V2_ADMITTED'),
    'envelope_contract','PROGRAMMING_ADMISSION_ENVELOPE_V2', 'checks',checks,'record',r);
END $fn$;

ALTER TABLE private.lf_programming_admission_revocations_v1 OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_admission_revocation_immutable_v1() OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_definition_ref_sha256_v1(text) OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_admission_revocation_train_guard_v1() OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_definition_currentness_v1(jsonb) OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb) OWNER TO postgres;
REVOKE ALL ON TABLE private.lf_programming_admission_revocations_v1 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_programming_admission_revocation_immutable_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_programming_definition_ref_sha256_v1(text) FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
REVOKE ALL ON FUNCTION private.fn_lf_programming_admission_revocation_train_guard_v1() FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
REVOKE ALL ON FUNCTION private.fn_lf_programming_definition_currentness_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
REVOKE ALL ON FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE private.lf_programming_admission_revocations_v1 IS 'Append-only D7 phase-2 revocation facts; inserts restricted to ACTUALIZACION_DB_LF Merge Train.';
COMMENT ON FUNCTION private.fn_lf_programming_definition_currentness_v1(jsonb) IS 'Product definition currentness from lf_ops screen contract; VIGENTE and canonical SHA256 excluding metadata.generated_at only.';
COMMENT ON FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb) IS 'V2 exact-binding admission; 24-hour maximum envelope validity, verified Product definition and Train-only revocations. V1 unchanged.';
DO $after$
BEGIN
  IF (SELECT prosecdef FROM pg_proc WHERE oid='private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)'::regprocedure) IS DISTINCT FROM true
     OR has_function_privilege('service_role','private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)','EXECUTE')
     OR has_function_privilege('anon','private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'PROGRAMACION_V2_PRIVILEGE_POSTCHECK_FAILED';
  END IF;
  IF (private.fn_lf_programming_definition_currentness_v1('[]'::jsonb)->>'verified') IS DISTINCT FROM 'false'
     OR (private.fn_lf_programming_definition_currentness_v1('[]'::jsonb)->>'reason') IS DISTINCT FROM 'DEFINITION_REFS_INVALID'
     OR (private.fn_lf_programming_definition_currentness_v1(
           jsonb_build_array(jsonb_build_object('definition_ref','product://unsupported','definition_sha256',repeat('a',64)))
         )->>'verified') IS DISTINCT FROM 'false'
     OR has_function_privilege('service_role','private.fn_lf_programming_definition_ref_sha256_v1(text)','EXECUTE')
     OR has_function_privilege('anon','private.fn_lf_programming_definition_ref_sha256_v1(text)','EXECUTE')
     OR has_function_privilege('authenticated','private.fn_lf_programming_definition_ref_sha256_v1(text)','EXECUTE')
     OR has_function_privilege('service_role','private.fn_lf_programming_definition_currentness_v1(jsonb)','EXECUTE')
     OR has_function_privilege('anon','private.fn_lf_programming_definition_currentness_v1(jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.fn_lf_programming_definition_currentness_v1(jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'PROGRAMACION_V2_CURRENTNESS_POSTCHECK_FAILED';
  END IF;
END $after$;
COMMIT;

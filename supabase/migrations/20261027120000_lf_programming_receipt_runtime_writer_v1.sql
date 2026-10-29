BEGIN;
-- LF / PG-01 runtime receipt writer.
-- D7 source is pinned by md5 before any change; the core below is an explicit copy.
DO $pre$
BEGIN
 IF to_regprocedure('private.fn_lf_programming_context_handoff_receipt_record_v1(jsonb,jsonb,jsonb,text)') IS NULL
    OR md5(pg_get_functiondef('private.fn_lf_programming_context_handoff_receipt_record_v1(jsonb,jsonb,jsonb,text)'::regprocedure)) IS DISTINCT FROM '6d100a1213fa9dd60cf86f066f0cb015' THEN
   RAISE EXCEPTION 'PG01_RUNTIME_WRITER_D7_SOURCE_DRIFT';
 END IF;
 IF to_regprocedure('private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)') IS NULL
    OR to_regprocedure('private.fn_lf_programming_definition_ref_sha256_v1(text)') IS NULL THEN
   RAISE EXCEPTION 'PG01_RUNTIME_WRITER_V2_NOT_INSTALLED';
 END IF;
END $pre$;

-- D7 core: steps 2-8 of fn_lf_programming_context_handoff_receipt_record_v1, copied
-- verbatim from 20261026173901 (same codes, binding hash and idempotency). Only the
-- caller-authority step 1 moves to the wrappers. p_execution_id -> p_actor_execution_id.


CREATE FUNCTION
private.fn_lf_programming_context_handoff_receipt_record_core_v1(
    p_receipt jsonb,
    p_envelope jsonb,
    p_binding jsonb,
    p_actor_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'private', 'public', 'extensions'
AS $function$
DECLARE

    v_receiver_digest CONSTANT text :=
        'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';


    v_receipt_key_count integer;
    v_context_id uuid;

    v_requested_scope_ids jsonb;
    v_binding_canonical jsonb;

    v_binding_key_sha256 text;
    v_receipt_sha256 text;
    v_envelope_sha256 text;

    v_inserted_record_id uuid;
    v_inserted_created_at timestamptz;

    v_existing private.lf_programming_context_handoff_receipts_v1%ROWTYPE;
BEGIN
    /*
     * 1. Caller authority is checked by the wrapper
     *    (Train: record_v1, runtime: record_runtime_v1).
     */

    /*
     * 2. Exact PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 shape.
     */
    IF p_receipt IS NULL
       OR pg_catalog.jsonb_typeof(p_receipt) <> 'object'
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_SHAPE_INVALID';
    END IF;

    SELECT count(*)
      INTO v_receipt_key_count
      FROM pg_catalog.jsonb_object_keys(p_receipt);

    IF v_receipt_key_count <> 8
       OR NOT (
           p_receipt ?& ARRAY[
               'schema_version',
               'context_id',
               'context_sha256',
               'snapshot_schema_digest_sha256',
               'receiver_schema_digest_sha256',
               'material_projection_sha256',
               'validated_material_paths',
               'verdict'
           ]
       )
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_SHAPE_INVALID';
    END IF;

    IF pg_catalog.jsonb_typeof(p_receipt->'schema_version') <> 'string'
       OR p_receipt->>'schema_version'
          <> 'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1'

       OR pg_catalog.jsonb_typeof(p_receipt->'context_id') <> 'string'
       OR NOT (
           p_receipt->>'context_id'
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )

       OR pg_catalog.jsonb_typeof(p_receipt->'context_sha256') <> 'string'
       OR NOT (
           p_receipt->>'context_sha256' ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'snapshot_schema_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_receipt->>'snapshot_schema_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'receiver_schema_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_receipt->>'receiver_schema_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'material_projection_sha256'
          ) <> 'string'
       OR NOT (
           p_receipt->>'material_projection_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'validated_material_paths'
          ) <> 'array'
       OR pg_catalog.jsonb_array_length(
              p_receipt->'validated_material_paths'
          ) = 0

       OR EXISTS (
           SELECT 1
             FROM pg_catalog.jsonb_array_elements(
                      p_receipt->'validated_material_paths'
                  ) AS item(value)
            WHERE pg_catalog.jsonb_typeof(item.value) <> 'string'
       )

       OR pg_catalog.jsonb_typeof(p_receipt->'verdict') <> 'string'
       OR p_receipt->>'verdict' NOT IN ('ACCEPT', 'BLOCK')
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_SHAPE_INVALID';
    END IF;


    /*
     * 3. Current receiver contract.
     */
    IF p_receipt->>'receiver_schema_digest_sha256'
       <> v_receiver_digest
    THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_RECEIVER_DIGEST_MISMATCH';
    END IF;


    /*
     * 4. Context pair must exist exactly in the persisted as-of snapshot.
     */
    v_context_id := (p_receipt->>'context_id')::uuid;

    PERFORM 1
      FROM private.lf_decision_context_asof_v1 c
     WHERE c.context_id = v_context_id
       AND c.context_sha256 = p_receipt->>'context_sha256';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_CONTEXT_NOT_FOUND_OR_HASH_MISMATCH';
    END IF;


    /*
     * 5. Binding contract.
     *
     * Extra JSON keys are ignored by the identity function. Only these six
     * fields define binding_key_sha256.
     */
    IF p_binding IS NULL
       OR pg_catalog.jsonb_typeof(p_binding) <> 'object'
       OR NOT (
           p_binding ?& ARRAY[
               'context_id',
               'context_sha256',
               'target_ref',
               'requested_scope_ids',
               'producer_execution_ref',
               'entry_contract_digest_sha256'
           ]
       )

       OR pg_catalog.jsonb_typeof(p_binding->'context_id') <> 'string'
       OR NOT (
           p_binding->>'context_id'
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )

       OR pg_catalog.jsonb_typeof(p_binding->'context_sha256') <> 'string'
       OR NOT (
           p_binding->>'context_sha256' ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(p_binding->'target_ref') <> 'string'
       OR pg_catalog.btrim(p_binding->>'target_ref') = ''

       OR pg_catalog.jsonb_typeof(
              p_binding->'requested_scope_ids'
          ) <> 'array'

       OR EXISTS (
           SELECT 1
             FROM pg_catalog.jsonb_array_elements(
                      p_binding->'requested_scope_ids'
                  ) AS item(value)
            WHERE pg_catalog.jsonb_typeof(item.value) <> 'string'
       )

       OR pg_catalog.jsonb_typeof(
              p_binding->'producer_execution_ref'
          ) <> 'string'
       OR pg_catalog.btrim(
              p_binding->>'producer_execution_ref'
          ) = ''

       OR pg_catalog.jsonb_typeof(
              p_binding->'entry_contract_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_binding->>'entry_contract_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR p_binding->>'context_id' <> v_context_id::text
       OR p_binding->>'context_sha256'
          <> p_receipt->>'context_sha256'
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_BINDING_INVALID';
    END IF;


    /*
     * Normalize requested_scope_ids as a sorted unique JSON string array.
     */
    SELECT COALESCE(
               pg_catalog.jsonb_agg(scope_id ORDER BY scope_id),
               '[]'::jsonb
           )
      INTO v_requested_scope_ids
      FROM (
          SELECT DISTINCT value AS scope_id
            FROM pg_catalog.jsonb_array_elements_text(
                     p_binding->'requested_scope_ids'
                 )
      ) AS normalized_scopes;


    v_binding_canonical :=
        pg_catalog.jsonb_build_object(
            'context_id',
                v_context_id::text,
            'context_sha256',
                p_binding->>'context_sha256',
            'target_ref',
                p_binding->>'target_ref',
            'requested_scope_ids',
                v_requested_scope_ids,
            'producer_execution_ref',
                p_binding->>'producer_execution_ref',
            'entry_contract_digest_sha256',
                p_binding->>'entry_contract_digest_sha256'
        );

    v_binding_key_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    v_binding_canonical::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );


    /*
     * 6. Envelope: phase 1 stores it, but does not release its admission
     * semantics. Only a non-empty schema_version is required.
     */
    IF p_envelope IS NULL
       OR pg_catalog.jsonb_typeof(p_envelope) <> 'object'
       OR NOT (p_envelope ? 'schema_version')
       OR pg_catalog.jsonb_typeof(
              p_envelope->'schema_version'
          ) <> 'string'
       OR pg_catalog.btrim(
              p_envelope->>'schema_version'
          ) = ''
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_ENVELOPE_INVALID';
    END IF;


    v_receipt_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    p_receipt::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );

    v_envelope_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    p_envelope::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );


    /*
     * 7. Atomic record-or-replay.
     *
     * The unique binding key is the concurrency arbiter.
     */
    INSERT INTO private.lf_programming_context_handoff_receipts_v1
    (
        binding_key_sha256,
        context_id,
        context_sha256,
        receipt,
        receipt_sha256,
        envelope,
        envelope_sha256,
        verdict,
        created_by_execution_id
    )
    VALUES
    (
        v_binding_key_sha256,
        v_context_id,
        p_receipt->>'context_sha256',
        p_receipt,
        v_receipt_sha256,
        p_envelope,
        v_envelope_sha256,
        p_receipt->>'verdict',
        p_actor_execution_id
    )
    ON CONFLICT (binding_key_sha256) DO NOTHING
    RETURNING
        receipt_record_id,
        created_at
    INTO
        v_inserted_record_id,
        v_inserted_created_at;


    IF v_inserted_record_id IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object(
            'schema_version',
                'PG01_RECEIPT_LEDGER_RECORD_RESULT_V1',
            'status',
                'RECORDED',
            'receipt_record_id',
                v_inserted_record_id,
            'binding_key_sha256',
                v_binding_key_sha256,
            'receipt_sha256',
                v_receipt_sha256,
            'envelope_sha256',
                v_envelope_sha256,
            'created_by_execution_id',
                p_actor_execution_id
        );
    END IF;


    SELECT *
      INTO STRICT v_existing
      FROM private.lf_programming_context_handoff_receipts_v1
     WHERE binding_key_sha256 = v_binding_key_sha256;


    IF v_existing.receipt_sha256 = v_receipt_sha256
       AND v_existing.envelope_sha256 = v_envelope_sha256
    THEN
        RETURN pg_catalog.jsonb_build_object(
            'schema_version',
                'PG01_RECEIPT_LEDGER_RECORD_RESULT_V1',
            'status',
                'IDEMPOTENT_REPLAY',
            'receipt_record_id',
                v_existing.receipt_record_id,
            'binding_key_sha256',
                v_existing.binding_key_sha256,
            'receipt_sha256',
                v_existing.receipt_sha256,
            'envelope_sha256',
                v_existing.envelope_sha256,
            'created_by_execution_id',
                v_existing.created_by_execution_id
        );
    END IF;


    RAISE EXCEPTION
        'PG01_RECEIPT_BINDING_REPLAY_CONFLICT';
END
$function$;

CREATE OR REPLACE FUNCTION private.fn_lf_programming_context_handoff_receipt_record_v1(
 p_receipt jsonb,p_envelope jsonb,p_binding jsonb,p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','private','public','extensions' AS $fn$
DECLARE n bigint;
BEGIN
 SELECT count(*) INTO n FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='ACTUALIZACION_DB_LF'
   AND e.status='IN_PROGRESS' AND e.manifest->>'producer'='lf-migration-merge-train';
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'PG01_RECEIPT_WRITER_EXECUTION_NOT_AUTHORIZED'; END IF;
 RETURN private.fn_lf_programming_context_handoff_receipt_record_core_v1(p_receipt,p_envelope,p_binding,p_execution_id);
END $fn$;

CREATE FUNCTION private.fn_lf_programming_context_handoff_receive_v1(p_context_id uuid,p_context_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path TO 'pg_catalog','private','public','extensions' AS $fn$
DECLARE c record; snap jsonb; projection jsonb:='{}'::jsonb; reasons jsonb:='[]'::jsonb;
 fields text[]:=ARRAY['objective','target_granularity','target','authority_state','implementation_state',
 'requirements','authority_bindings','implementability_schema','applicable_rules','applicable_invariants',
 'preserve','material_front_coverage','decision_context','analysis_stop_rule','scope_readiness',
 'scope_front_matrix','package_readiness','unresolved_material_items','source_refs','currentness_refs',
 'snapshot_schema_digest_sha256','authority_fingerprint_sha256','source_snapshot_sha256'];
 k text; paths jsonb:='[]'::jsonb; schema_sha text;
 constant_digest CONSTANT text:='d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';
BEGIN
 SELECT * INTO c FROM private.lf_decision_context_asof_v1 WHERE context_id=p_context_id;
 IF NOT FOUND OR c.context_sha256 IS DISTINCT FROM p_context_sha256 THEN
   RAISE EXCEPTION 'PG01_RECEIVER_CONTEXT_NOT_FOUND_OR_HASH_MISMATCH'; END IF;
 IF c.context_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(c.context_payload::text,'UTF8'),'sha256'),'hex') THEN
   RAISE EXCEPTION 'PG01_RECEIVER_CONTEXT_DIGEST_MISMATCH'; END IF;
 snap:=c.context_payload#>'{extensions,programming_context_snapshot}';
 IF jsonb_typeof(snap) IS DISTINCT FROM 'object' THEN snap:='{}'::jsonb; reasons:=reasons||'"SNAPSHOT_SCHEMA_INVALID"'::jsonb;
 ELSIF snap->>'schema_version' IS DISTINCT FROM 'PROGRAMMING_CONTEXT_SNAPSHOT_V1' THEN
   reasons:=reasons||'"SNAPSHOT_SCHEMA_INVALID"'::jsonb;
 END IF;
 FOR k IN SELECT unnest(fields) LOOP
  paths:=paths||to_jsonb('extensions.programming_context_snapshot.'||k);
  IF NOT (snap ? k) OR snap->k='null'::jsonb THEN
    reasons:=reasons||to_jsonb('MATERIAL_FIELD_MISSING:'||k);
  ELSE projection:=projection||jsonb_build_object(k,snap->k); END IF;
 END LOOP;
 FOR k IN SELECT jsonb_object_keys(snap) LOOP
  IF k IS DISTINCT FROM 'schema_version' AND NOT k=ANY(fields) THEN
    reasons:=reasons||to_jsonb('MATERIAL_FIELD_UNKNOWN:'||k); END IF;
 END LOOP;
 schema_sha:=snap->>'snapshot_schema_digest_sha256';
 IF schema_sha IS NULL OR schema_sha !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'PG01_RECEIVER_SNAPSHOT_UNREADABLE'; END IF;
 IF schema_sha IS DISTINCT FROM constant_digest THEN
   reasons:=reasons||'"SNAPSHOT_SCHEMA_DIGEST_MISMATCH"'::jsonb; END IF;
 RETURN jsonb_build_object('receipt',jsonb_build_object(
   'schema_version','PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
   'context_id',p_context_id::text,'context_sha256',p_context_sha256,
   'snapshot_schema_digest_sha256',schema_sha,'receiver_schema_digest_sha256',constant_digest,
   'material_projection_sha256',encode(extensions.digest(convert_to(projection::text,'UTF8'),'sha256'),'hex'),
   'validated_material_paths',paths,
   'verdict',CASE WHEN jsonb_array_length(reasons)=0 THEN 'ACCEPT' ELSE 'BLOCK' END),
   'block_reasons',reasons);
END $fn$;

CREATE FUNCTION private.fn_lf_programming_receipt_record_runtime_v1(
 p_source_execution_id text,p_router_action_binding jsonb,p_programming_handoff jsonb,p_judge_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','private','public','lf_ops','extensions' AS $fn$
DECLARE e record; c record; j record; b jsonb; sel text; selsha text; dref text; d jsonb;
 h jsonb:=p_programming_handoff; ctx uuid; r jsonb; receipt jsonb; reasons jsonb;
 snapshot jsonb; ready jsonb; scopes jsonb; env jsonb; result jsonb; oldrow record;
 warnings jsonb:='[]'::jsonb; stamp timestamptz; valid_from text; valid_until text;
 keysha text; screen_count bigint; norm_scopes jsonb; canonical jsonb; sid text;
 constant_digest CONSTANT text:='d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_source_execution_id;
 IF NOT FOUND OR e.operation_code IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
 OR e.target_type IS DISTINCT FROM 'PERFIL' OR e.status IS DISTINCT FROM 'COMPLETED'
 OR e.manifest#>>'{router_profile_handoff,channel}' IS DISTINCT FROM 'PROGRAMACION'
 OR jsonb_typeof(p_router_action_binding) IS DISTINCT FROM 'object'
 OR e.manifest#>'{router_profile_handoff,semantic_request,router_action_binding}' IS DISTINCT FROM p_router_action_binding THEN
  RAISE EXCEPTION 'PG01_RUNTIME_SOURCE_EXECUTION_INVALID'; END IF;
 IF jsonb_typeof(h) IS DISTINCT FROM 'object'
 OR (SELECT count(*) FROM jsonb_object_keys(h)) IS DISTINCT FROM 6
 OR NOT (h ?& ARRAY['context_id','context_sha256','target_ref','requested_scope_ids','producer_execution_ref','entry_contract_digest_sha256'])
 OR jsonb_typeof(h->'context_id') IS DISTINCT FROM 'string' OR h->>'context_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 OR h->>'context_sha256' !~ '^[0-9a-f]{64}$' OR jsonb_typeof(h->'context_sha256') IS DISTINCT FROM 'string'
 OR jsonb_typeof(h->'target_ref') IS DISTINCT FROM 'string' OR btrim(h->>'target_ref')=''
 OR jsonb_typeof(h->'requested_scope_ids') IS DISTINCT FROM 'array'
 OR jsonb_array_length(CASE WHEN jsonb_typeof(h->'requested_scope_ids')='array' THEN h->'requested_scope_ids' ELSE '[]'::jsonb END)=0
 OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(h->'requested_scope_ids')='array' THEN h->'requested_scope_ids' ELSE '[]'::jsonb END) x(v)
    WHERE jsonb_typeof(x.v) IS DISTINCT FROM 'string' OR btrim(x.v#>>'{}')='')
 OR h->>'producer_execution_ref' IS DISTINCT FROM p_source_execution_id
 OR h->>'entry_contract_digest_sha256' IS DISTINCT FROM constant_digest THEN
  RAISE EXCEPTION 'PG01_RUNTIME_HANDOFF_INVALID'; END IF;
 ctx:=(h->>'context_id')::uuid;
 SELECT * INTO c FROM private.lf_decision_context_asof_v1 WHERE context_id=ctx;
 IF NOT FOUND OR c.context_sha256 IS DISTINCT FROM h->>'context_sha256'
 OR c.created_by_execution_id IS DISTINCT FROM p_source_execution_id THEN
  RAISE EXCEPTION 'PG01_RUNTIME_SNAPSHOT_NOT_FROM_SOURCE'; END IF;
 sel:=e.manifest#>>'{screen_selection_result,selected_screen_code}';
 selsha:=e.manifest#>>'{screen_selection_result,semantic_receipt_sha256}';
 IF nullif(btrim(coalesce(sel,'')),'') IS NULL OR coalesce(selsha,'') !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'PG01_RUNTIME_SCREEN_SELECTION_MISSING'; END IF;
 -- Integrity of the selector binding (#3183): same schema, VALID/SELECTED, and the
 -- receipt recomputed with the selector's own formula. Proves the stored result is
 -- internally consistent; provenance still rests on who may write the manifest.
 IF e.manifest->>'screen_selection_schema_version' IS DISTINCT FROM 'LF_PROFILE_SCREEN_SELECTOR_BINDING_V1'
 OR e.manifest#>>'{screen_selection_validation,status}' IS DISTINCT FROM 'VALID'
 OR e.manifest#>>'{screen_selection_result,decision}' IS DISTINCT FROM 'SELECTED'
 OR e.manifest#>>'{screen_selection_validation,selected_screen_code}' IS DISTINCT FROM sel
 OR selsha IS DISTINCT FROM encode(extensions.digest(convert_to(
      ((e.manifest->'screen_selection_result')-'semantic_receipt_sha256')::text,'UTF8'),'sha256'),'hex') THEN
  RAISE EXCEPTION 'PG01_RUNTIME_SCREEN_SELECTION_INVALID'; END IF;
 SELECT count(*),min('lf-screen-contract://'||sh.app_shell_code||'/'||m.module_code||'/'||p.codigo)
 INTO screen_count,dref FROM lf_ops.pantallas p JOIN lf_ops.modulos m ON p.module_id=m.module_id
 JOIN lf_ops.app_shells sh ON m.app_shell_id=sh.app_shell_id
 WHERE p.codigo=sel AND p.activa=true;
 IF screen_count IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'PG01_RUNTIME_SCREEN_UNRESOLVED'; END IF;
 d:=private.fn_lf_programming_definition_ref_sha256_v1(dref);
 IF (d->>'ok')::boolean IS DISTINCT FROM true OR d->>'definition_sha256' !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION 'PG01_RUNTIME_DEFINITION_UNRESOLVED'; END IF;
 IF h->>'target_ref' IS DISTINCT FROM dref THEN RAISE EXCEPTION 'PG01_RUNTIME_TARGET_SCREEN_MISMATCH'; END IF;
 -- H-A3: an issue on a non-current definition is rejected before any ledger read or
 -- write (no new row, no replay of an older row). Earlier rows are left untouched.
 IF d->>'screen_status' IS DISTINCT FROM 'VIGENTE' THEN RAISE EXCEPTION 'PG01_RUNTIME_DEFINITION_NOT_CURRENT'; END IF;
 -- H-A2 candidate: fail closed before reading judge steps and before ledger INSERT.
 IF p_judge_execution_id IS NULL OR btrim(p_judge_execution_id) = ''
    OR p_judge_execution_id IS NOT DISTINCT FROM p_source_execution_id THEN
   RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_NOT_INDEPENDENT';
 END IF;
 SELECT * INTO j FROM public.lf_operation_execution WHERE execution_id=p_judge_execution_id;
 IF NOT FOUND OR j.operation_code IS DISTINCT FROM 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  OR j.status IS DISTINCT FROM 'COMPLETED'
  OR j.manifest->>'capability_code' IS DISTINCT FROM 'INDEPENDENT_ASSURANCE'
  OR j.manifest->>'subject_sha256' IS DISTINCT FROM c.context_sha256
  OR j.manifest->>'subject_ref' IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE/'||ctx::text
  OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_judge_execution_id
       AND s.step_id='semantic_review' AND s.status='STEP_PASS_WITH_EVIDENCE' AND s.evidence_payload->>'verdict'='PASS') IS DISTINCT FROM 1
  OR (SELECT count(*) FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_judge_execution_id
       AND s.step_id='judge_record' AND s.status='STEP_PASS_WITH_EVIDENCE') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_INVALID'; END IF;
 -- H-A2 v2 (Claude, 29-oct): governed provenance of the judge, checked before any
 -- ledger read or write. JSON fields are only accepted when they match rows in tables
 -- that service_role cannot write (evidence ledger, orchestrator dispatch receipts).
 IF j.manifest->>'producer_execution_id' IS DISTINCT FROM p_source_execution_id
    OR j.manifest->>'subject_type' IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE'
    OR j.manifest->>'subject_ref' IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE/'||ctx::text
    OR j.manifest->>'subject_sha256' IS DISTINCT FROM c.context_sha256
    OR j.target_type IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE'
    OR j.target_code IS DISTINCT FROM 'PROGRAMMING_ANALYSIS_PACKAGE/'||ctx::text
    OR coalesce(j.manifest->>'source_head_sha','') !~ '^[0-9a-f]{40}$'
    OR coalesce(j.manifest->>'subject_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR coalesce(j.manifest->>'capability_manifest_sha256','') !~ '^[0-9a-f]{64}$'
    OR coalesce(j.manifest->>'plan_digest','') !~ '^[0-9a-f]{64}$'
    OR nullif(btrim(coalesce(j.manifest->>'orchestrator_execution_id','')),'') IS NULL
    OR j.manifest->'review_required' IS DISTINCT FROM 'true'::jsonb
    OR j.manifest->'runtime_activation' IS DISTINCT FROM 'false'::jsonb
    OR j.manifest#>'{capability_binding_receipt,ready}' IS DISTINCT FROM 'true'::jsonb
    OR coalesce(j.manifest#>>'{capability_binding_receipt,entry_guard,receipt_id}','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR nullif(btrim(coalesce(j.created_by_execution_id,'')),'') IS NULL
    OR j.created_by_execution_id IN (p_source_execution_id, p_judge_execution_id)
    OR j.manifest->>'orchestrator_execution_id' IN (p_source_execution_id, p_judge_execution_id)
    OR j.created_by_execution_id IS DISTINCT FROM j.manifest->>'orchestrator_execution_id' THEN
   RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_PROVENANCE_INVALID'; END IF;
 -- Subject receipt: VERIFIED, exact PG-01 subject, not anchored by the producer.
 PERFORM 1 FROM private.lf_evidence_ledger_v1 v
  WHERE v.receipt_id=(j.manifest->>'subject_receipt_id')::uuid
    AND v.verification_state='VERIFIED'
    AND v.subject_type='PROGRAMMING_ANALYSIS_PACKAGE'
    AND v.subject_ref='PROGRAMMING_ANALYSIS_PACKAGE/'||ctx::text
    AND v.subject_sha256=c.context_sha256
    AND v.source_head_sha=j.manifest->>'source_head_sha'
    AND v.created_by_execution_id IS DISTINCT FROM p_source_execution_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_SUBJECT_RECEIPT_NOT_VERIFIED'; END IF;
 -- Orchestrator dispatch receipt (not writable by service_role): exact consumer, plan
 -- and capability, digest recomputed with the issuer's formula, not issued by producer.
 PERFORM 1 FROM private.lf_orchestrator_dispatch_receipts_v1 dr
  WHERE dr.receipt_id=(j.manifest#>>'{capability_binding_receipt,entry_guard,receipt_id}')::uuid
    AND dr.consumer_execution_id=p_judge_execution_id
    AND dr.capability_code='INDEPENDENT_ASSURANCE'
    AND dr.plan_digest=j.manifest->>'plan_digest'
    AND dr.orchestrator_execution_id=j.manifest->>'orchestrator_execution_id'
    AND dr.issued_by_execution_id IS DISTINCT FROM p_source_execution_id
    AND dr.receipt_sha256=encode(extensions.digest(convert_to(jsonb_build_object(
      'schema_version','LF_ORCHESTRATOR_DISPATCH_RECEIPT_V1',
      'orchestrator_execution_id',dr.orchestrator_execution_id,
      'orchestrator_operation_code',dr.orchestrator_operation_code,
      'orchestrator_operation_version',dr.orchestrator_operation_version,
      'consumer_execution_id',dr.consumer_execution_id,'capability_code',dr.capability_code,
      'plan_digest',dr.plan_digest,'dispatch_scope',dr.dispatch_scope,'guard_code',dr.guard_code)::text,'UTF8'),'sha256'),'hex');
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_DISPATCH_RECEIPT_INVALID'; END IF;
 -- Capability binding row for the judge, matching the manifest it was reserved with.
 PERFORM 1 FROM public.lf_capability_binding cb
  WHERE cb.execution_id=p_judge_execution_id AND cb.capability_code='INDEPENDENT_ASSURANCE'
    AND cb.binding_state IN ('BOUND','PINNED')
    AND cb.bound_manifest_sha256=j.manifest->>'capability_manifest_sha256'
    AND cb.bound_by_execution_id=j.manifest->>'orchestrator_execution_id';
 IF NOT FOUND THEN RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_CAPABILITY_BINDING_INVALID'; END IF;
 -- Review result steps must be authored by the judge itself (shape of begin_v3 judges). KNOWN GAP: no governed
 -- review-result receipt exists yet; steps remain writable by service_role.
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=p_judge_execution_id
     AND s.step_id IN ('semantic_review','judge_record')
     AND (nullif(btrim(coalesce(s.created_by_execution_id,'')),'') IS NULL
          OR s.created_by_execution_id IS DISTINCT FROM p_judge_execution_id)) THEN
   RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_REVIEW_RESULT_UNPROVEN'; END IF;
 -- H-A2 authority gate (fail-closed). Every check above binds the judge to rows that
 -- service_role cannot write, but the root of that chain is not authenticated: service_role
 -- may INSERT public.lf_operation_execution rows (ORQUESTACION_PIPELINE_LF is not a
 -- ROUTER_DOWNSTREAM_AUTHORITY consumer) and the evidence anchor takes VERIFIED from its
 -- caller. Until an authenticated reviewer/orchestrator identity exists (owner decision D-B),
 -- no runtime PG-01 receipt is issued. Lifting this gate is the only change D-B requires here.
 RAISE EXCEPTION 'PG01_RUNTIME_JUDGE_AUTHORITY_UNVERIFIED';
 r:=private.fn_lf_programming_context_handoff_receive_v1(ctx,c.context_sha256);
 receipt:=r->'receipt'; reasons:=r->'block_reasons';
 snapshot:=c.context_payload#>'{extensions,programming_context_snapshot}';
 SELECT coalesce(jsonb_agg(scope_id ORDER BY scope_id),'[]'::jsonb) INTO ready FROM
 (SELECT DISTINCT value->>'scope_id' AS scope_id FROM jsonb_array_elements(CASE
 WHEN jsonb_typeof(snapshot->'scope_readiness')='array' THEN snapshot->'scope_readiness' ELSE '[]'::jsonb END) x(value)
 WHERE value->>'status'='READY' AND nullif(btrim(value->>'scope_id'),'') IS NOT NULL) q;
 IF receipt->>'verdict'='ACCEPT' AND jsonb_array_length(ready)=0 THEN RAISE EXCEPTION 'PG01_RUNTIME_NO_READY_SCOPE'; END IF;
 IF receipt->>'verdict'='ACCEPT' AND EXISTS (
 SELECT 1 FROM jsonb_array_elements_text(h->'requested_scope_ids') q(scope_id)
 WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(ready) a(scope_id) WHERE a.scope_id=q.scope_id)) THEN
 RAISE EXCEPTION 'PG01_RUNTIME_SCOPE_NOT_READY'; END IF;
 IF receipt->>'verdict'='BLOCK' THEN
  SELECT jsonb_agg(scope_id ORDER BY scope_id) INTO scopes FROM
  (SELECT DISTINCT value AS scope_id FROM jsonb_array_elements_text(h->'requested_scope_ids')) s;
 ELSE scopes:=ready; END IF;
 stamp:=now(); -- same clock as resolve_v2, so a same-transaction gate is not NOT_YET_VALID
 valid_from:=to_char(stamp AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 valid_until:=to_char((stamp+interval '24 hours') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
 env:=jsonb_build_object('schema_version','PROGRAMMING_ADMISSION_ENVELOPE_V2',
 'entry_contract_digest_sha256',constant_digest,'context_id',ctx::text,'context_sha256',c.context_sha256,
 'judge',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','capability_version','2.0.1',
 'execution_id',p_judge_execution_id,'subject_sha256',c.context_sha256),
 'admitted_scope_ids',scopes,'valid_from',valid_from,'valid_until',valid_until,
 'definition_refs',jsonb_build_array(jsonb_build_object('definition_ref',dref,'definition_sha256',d->>'definition_sha256')),
 'issued_by_execution_id',p_source_execution_id);
 -- The canonical D7 key, byte-for-byte identical to its resolver and writer.
 SELECT coalesce(jsonb_agg(scope_id ORDER BY scope_id),'[]'::jsonb) INTO norm_scopes FROM
 (SELECT DISTINCT value AS scope_id FROM jsonb_array_elements_text(h->'requested_scope_ids')) q;
 canonical:=jsonb_build_object('context_id',ctx::text,'context_sha256',h->>'context_sha256',
 'target_ref',h->>'target_ref','requested_scope_ids',norm_scopes,'producer_execution_ref',
 h->>'producer_execution_ref','entry_contract_digest_sha256',h->>'entry_contract_digest_sha256');
 keysha:=encode(extensions.digest(convert_to(canonical::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO oldrow FROM private.lf_programming_context_handoff_receipts_v1 WHERE binding_key_sha256=keysha;
 IF FOUND THEN
  IF oldrow.receipt IS DISTINCT FROM receipt OR
     (oldrow.envelope-'valid_from'-'valid_until') IS DISTINCT FROM (env-'valid_from'-'valid_until') THEN
    RAISE EXCEPTION 'PG01_RECEIPT_BINDING_REPLAY_CONFLICT'; END IF;
  result:=jsonb_build_object('status','IDEMPOTENT_REPLAY','receipt_record_id',oldrow.receipt_record_id,
  'binding_key_sha256',oldrow.binding_key_sha256);
  valid_until:=oldrow.envelope->>'valid_until';
 ELSE
  result:=private.fn_lf_programming_context_handoff_receipt_record_core_v1(receipt,env,h,p_source_execution_id);
 END IF;
 RETURN jsonb_build_object('schema_version','PG01_RUNTIME_RECEIPT_RESULT_V1',
 'status',result->>'status','receipt_record_id',result->'receipt_record_id',
 'binding_key_sha256',result->>'binding_key_sha256','verdict',receipt->>'verdict',
 'block_reasons',reasons,'warnings',warnings,'definition_ref',dref,
 'screen_selection_receipt_sha256',selsha,'valid_until',valid_until);
END $fn$;

ALTER FUNCTION private.fn_lf_programming_context_handoff_receipt_record_core_v1(jsonb,jsonb,jsonb,text) OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_context_handoff_receive_v1(uuid,text) OWNER TO postgres;
ALTER FUNCTION private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.fn_lf_programming_context_handoff_receipt_record_core_v1(jsonb,jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_programming_context_handoff_receive_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text) TO service_role;
COMMENT ON FUNCTION private.fn_lf_programming_context_handoff_receipt_record_core_v1(jsonb,jsonb,jsonb,text) IS 'D7 validation, canonical binding hash and append-only idempotent ledger insert. Owner only.';
COMMENT ON FUNCTION private.fn_lf_programming_context_handoff_receive_v1(uuid,text) IS 'Read-only PG-01 material snapshot projection and V1 receipt builder. Owner only.';
COMMENT ON FUNCTION private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text) IS 'Runtime governed context/screen/judge verification and PG-01 receipt/V2 envelope recording. No development execution authority.';
DO $after$
BEGIN
 IF (SELECT prosecdef FROM pg_proc WHERE oid='private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)'::regprocedure) IS DISTINCT FROM true
 OR has_function_privilege('anon','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 OR has_function_privilege('authenticated','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE')
 OR NOT has_function_privilege('service_role','private.fn_lf_programming_receipt_record_runtime_v1(text,jsonb,jsonb,text)','EXECUTE') THEN
 RAISE EXCEPTION 'PG01_RUNTIME_WRITER_PERMISSIONS_INVALID'; END IF;
END $after$;
COMMIT;

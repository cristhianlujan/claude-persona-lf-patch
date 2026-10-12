-- LF source-binding admission: enforce genuine existing Human Decision
-- / provenance authority receipts, not JSON self-assertion.
-- No new ledger, no enterprise row read, no bypass RLS on B2B tables.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_source_binding_authority_gate_v1(
 p_source_ref text, p_binding_metadata jsonb
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $body$
DECLARE
 v_request private.lf_human_decision_requests_v1%ROWTYPE;
 v_receipt private.lf_human_decision_receipts_v1%ROWTYPE;
 v_request_id uuid;
 v_receipt_id uuid;
 v_body jsonb;
 v_binding_sha text;
 v_request_digest text;
 v_receipt_digest text;
 v_reason text:='BLOCK_SOURCE_BINDING_AUTHORITY_INVALID';
BEGIN
 IF p_source_ref IS NULL OR
    p_source_ref !~ '^db://[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$' OR
    pg_catalog.jsonb_typeof(p_binding_metadata) IS DISTINCT FROM 'object' OR
    p_binding_metadata->>'admission_status' IS DISTINCT FROM 'VIGENTE' THEN
   v_reason:='BLOCK_SOURCE_BINDING_AUTHORITY_INPUT_INVALID';
 ELSIF coalesce(p_binding_metadata->>'human_decision_request_id','') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR coalesce(p_binding_metadata->>'human_decision_receipt_id','') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   v_reason:='BLOCK_SOURCE_BINDING_AUTHORITY_RECEIPT_MISSING';
 ELSE
   v_request_id:=(p_binding_metadata->>'human_decision_request_id')::uuid;
   v_receipt_id:=(p_binding_metadata->>'human_decision_receipt_id')::uuid;
   -- Metadata fields for linking a decision are excluded from the frozen
   -- binding payload; all access-affecting fields are included and hashed.
   v_body:=p_binding_metadata-'admission_status'
                             -'human_decision_request_id'
                             -'human_decision_receipt_id';
   v_binding_sha:=encode(extensions.digest(
       convert_to(v_body::text,'UTF8'),'sha256'),'hex');
   SELECT * INTO v_request
   FROM private.lf_human_decision_requests_v1
   WHERE request_id=v_request_id
     AND producer_code='LF_SOURCE_BINDING_ADMISSION'
     AND subject_type='LF_SOURCE_BINDING'
     AND subject_key=p_source_ref
     AND source_ref=p_source_ref
     AND status='DECIDED'
     AND (expires_at IS NULL OR expires_at>now())
     AND subject_ref->>'source_ref'=p_source_ref
     AND subject_ref->>'binding_sha256'=v_binding_sha
     AND currentness_sha256=v_binding_sha
     AND allowed_actions ? 'APPROVE';
   IF NOT FOUND THEN
     v_reason:='BLOCK_SOURCE_BINDING_AUTHORITY_REQUEST_NOT_CURRENT';
   ELSE
     v_request_digest:=private.fn_lf_human_decision_request_sha_v1(
       v_request.producer_code,v_request.subject_type,v_request.subject_key,
       v_request.subject_ref,v_request.required_authority_ref,
       v_request.required_reviewer_role,v_request.allowed_actions,
       v_request.evidence_refs,v_request.currentness_sha256,
       v_request.impact,v_request.source_ref,v_request.source_revision,
       v_request.metadata);
     SELECT * INTO v_receipt FROM private.lf_human_decision_receipts_v1
     WHERE receipt_id=v_receipt_id AND request_id=v_request_id
       AND decision_code='APPROVE'
       AND decision_payload->>'source_ref'=p_source_ref
       AND decision_payload->>'binding_sha256'=v_binding_sha
       AND observed_currentness_sha256=v_binding_sha
       AND reviewer_role=v_request.required_reviewer_role
       AND authority_ref=v_request.required_authority_ref;
     IF v_request.request_sha256 IS DISTINCT FROM v_request_digest
          OR NOT FOUND THEN
       v_reason:='BLOCK_SOURCE_BINDING_AUTHORITY_DECISION_NOT_MATCHED';
     ELSE
       v_receipt_digest:=private.fn_lf_human_decision_receipt_sha_v1(
         v_receipt.request_id,v_request.request_sha256,
         v_receipt.decision_code,v_receipt.decision_payload,
         v_receipt.reviewer_identity,v_receipt.reviewer_role,
         v_receipt.authority_ref,v_receipt.authority_receipt_ref,
         v_receipt.authority_receipt_sha256,
         v_receipt.observed_currentness_sha256,v_receipt.metadata);
       IF v_receipt.receipt_sha256 IS DISTINCT FROM v_receipt_digest THEN
         v_reason:='BLOCK_SOURCE_BINDING_AUTHORITY_DECISION_DIGEST';
       ELSIF NOT private.fn_lf_human_decision_assert_authority_receipt_v1(
           v_receipt.request_id,v_receipt.decision_code,v_receipt.reviewer_role,
           v_receipt.authority_ref,v_receipt.authority_receipt_ref,
           v_receipt.authority_receipt_sha256,
           v_receipt.observed_currentness_sha256) THEN
         v_reason:='BLOCK_SOURCE_BINDING_AUTHORITY_PROVENANCE_INVALID';
       ELSE
         v_reason:='SOURCE_BINDING_HUMAN_AUTHORITY_VERIFIED';
       END IF;
     END IF;
   END IF;
 END IF;
 RETURN pg_catalog.jsonb_build_object(
   'schema_version','LF_D2_SOURCE_BINDING_AUTHORITY_GATE_V1',
   'decision',v_reason,'source_ref',p_source_ref,
   'binding_digest_sha256',v_binding_sha,
   'authority_receipt_reverified',
       v_reason='SOURCE_BINDING_HUMAN_AUTHORITY_VERIFIED',
   'business_data_read_authorized',false,'business_rows_accessed',false,
   'runtime_dispatched',false,'effects_executed',false);
EXCEPTION WHEN OTHERS THEN
 RETURN pg_catalog.jsonb_build_object(
  'schema_version','LF_D2_SOURCE_BINDING_AUTHORITY_GATE_V1',
  'decision','BLOCK_SOURCE_BINDING_AUTHORITY_PROOF_UNAVAILABLE',
  'source_ref',p_source_ref,'authority_receipt_reverified',false,
  'business_data_read_authorized',false,'business_rows_accessed',false,
  'runtime_dispatched',false,'effects_executed',false);
END $body$;
REVOKE ALL ON FUNCTION private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)
  TO service_role;
COMMENT ON FUNCTION private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)
 IS 'Narrow verifier of existing human decision and provenance receipts for frozen source binding. No ledger duplication, no business reads.';

-- Existing D2 preflight remains SECURITY INVOKER; this new proof is an
-- additional AND gate after its existing inventory/policy/facade checks.
-- LF D2: canonical binding readback, metadata only. Not a data reader.
-- Reuses inventory.objects, public.lf_activos, policy and operation contracts.
-- Source reference is EXACT D1 db://schema.object; NEVER an invented catalog:// URI.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_binding_readback_v1(p_source_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE
 v_result text := 'BLOCK_UNCLASSIFIED';
 v_policy_count integer;
 v_policy_sha text;
 v_inventory_count integer;
 v_asset_count integer;
 v_metadata jsonb;
 v_catalog_count integer;
 v_catalog_fp text;
 v_facade_signature text;
 v_facade_count integer;
 v_step_count integer;
 v_missing_column_count integer;
 v_max_rows integer;
 v_schema text;
 v_table text;
BEGIN
 IF p_source_ref IS NULL OR length(p_source_ref)>250
    OR p_source_ref !~ '^db://[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$' THEN
   v_result:='BLOCK_CANONICAL_REF_INVALID';
 ELSE
   v_schema:=split_part(substring(p_source_ref from 6),'.',1);
   v_table:=split_part(substring(p_source_ref from 6),'.',2);
   SELECT count(*)::integer INTO v_inventory_count
   FROM inventory.fn_lookup_v3(
      p_source_ref,ARRAY['DB_TABLE','DB_VIEW']::text[],5,
      ARRAY['CURRENT']::text[]) i
   WHERE i.object_ref=p_source_ref
     AND i.match_reason='EXACT_REF'
     AND i.currentness IN ('CATALOG_MANAGED','CURRENT');
   IF v_inventory_count<>1 THEN
     v_result:='BLOCK_INVENTORY_SOURCE_NOT_UNIQUE_CURRENT';
   ELSE
     SELECT count(*)::integer,max(policy_sha)
       INTO v_policy_count,v_policy_sha
     FROM public.lf_policy_versions
     WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE';
     IF v_policy_count<>1 OR v_policy_sha !~ '^[0-9a-f]{64}$' THEN
       v_result:='BLOCK_SOURCE_POLICY_NOT_CURRENT';
     ELSE
       SELECT count(*)::integer,max(a.metadata::text)::jsonb
         INTO v_asset_count,v_metadata
       FROM public.lf_activos a
       WHERE a.archived_at IS NULL AND a.metadata->>'canonical_source_ref'=p_source_ref;
       IF v_asset_count<>1 THEN
         v_result:='BLOCK_BINDING_ABSENT_OR_AMBIGUOUS';
       ELSIF private.fn_lf_d1_managed_inventory_qualification_v1()->>'technical_readiness'<>'PASS' THEN
         v_result:='BLOCK_MANAGED_INVENTORY_NOT_CURRENT';
       ELSIF v_metadata->>'admission_status' IS DISTINCT FROM 'VIGENTE' THEN
         v_result:='BLOCK_BINDING_NOT_VIGENTE';
       ELSIF v_metadata->>'policy_sha' IS DISTINCT FROM v_policy_sha THEN
         v_result:='BLOCK_BINDING_POLICY_DRIFT';
       ELSE
         SELECT count(*)::integer,
           max(encode(extensions.digest(convert_to(
              n.nspname||'.'||c.relname||'|'||coalesce(cols.structure,''),'UTF8'
           ),'sha256'),'hex'))
         INTO v_catalog_count,v_catalog_fp
         FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
         LEFT JOIN LATERAL (
            SELECT string_agg(att.attname||':'||att.atttypid::regtype::text||':'||
              att.attnotnull::text,'|' ORDER BY att.attnum) AS structure
            FROM pg_catalog.pg_attribute att
            WHERE att.attrelid=c.oid AND att.attnum>0 AND NOT att.attisdropped
         ) cols ON TRUE
         WHERE n.nspname=v_schema AND c.relname=v_table
           AND c.relkind IN ('r','p','v') AND NOT c.relispartition;
         IF v_catalog_count<>1 OR v_metadata->>'source_schema_fingerprint' IS DISTINCT FROM v_catalog_fp THEN
            v_result:='BLOCK_BINDING_SCHEMA_FINGERPRINT_DRIFT';
         ELSIF EXISTS(
            SELECT 1 FROM (VALUES ('binding_version'),('read_facade_ref'),
             ('tenant_scope_rule_ref'),('required_permission_code'),('operation_code'),
             ('step_id'),('resolver_ref'),('receipt_ref'),('evidence_ref'),
             ('approved_by_ref')) fields(k)
            WHERE nullif(btrim(v_metadata->>k),'') IS NULL
         ) THEN
            v_result:='BLOCK_BINDING_REQUIRED_FIELDS_MISSING';
         ELSIF jsonb_typeof(v_metadata->'permitted_columns') IS DISTINCT FROM 'array'
            OR jsonb_typeof(v_metadata->'allowed_filter_fields') IS DISTINCT FROM 'array'
            OR jsonb_array_length(v_metadata->'permitted_columns')=0
            OR jsonb_array_length(v_metadata->'allowed_filter_fields')=0 THEN
            v_result:='BLOCK_BINDING_COLUMN_FILTER_ALLOWLIST_MISSING';
         ELSE
            SELECT count(*)::integer INTO v_missing_column_count
            FROM (
              SELECT jsonb_array_elements_text(v_metadata->'permitted_columns') AS name
              UNION ALL
              SELECT jsonb_array_elements_text(v_metadata->'allowed_filter_fields')
            ) requested
            WHERE NOT EXISTS(
               SELECT 1 FROM pg_catalog.pg_attribute att
               JOIN pg_catalog.pg_class c ON c.oid=att.attrelid
               JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname=v_schema AND c.relname=v_table
                 AND att.attname=requested.name AND att.attnum>0 AND NOT att.attisdropped
            );
            IF v_missing_column_count>0 THEN
               v_result:='BLOCK_BINDING_COLUMN_FILTER_SCHEMA_MISMATCH';
            ELSIF v_metadata->>'max_rows' IS NULL
              OR (v_metadata->>'max_rows') !~ '^[0-9]{1,4}$'
              OR (v_metadata->>'max_rows')::integer NOT BETWEEN 1 AND 1000 THEN
               v_result:='BLOCK_BINDING_READ_LIMIT_INVALID';
            ELSE
               v_facade_signature:=v_metadata->>'read_facade_ref';
               SELECT count(*)::integer INTO v_facade_count
               FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure(v_facade_signature)
               AND p.prokind='f' AND NOT p.prosecdef;
               SELECT count(*)::integer INTO v_step_count
               FROM public.lf_operation_step_contracts s
               WHERE s.operation_code=v_metadata->>'operation_code'
                 AND s.step_id=v_metadata->>'step_id'
                 AND s.resolver_ref=v_metadata->>'resolver_ref'
                 AND s.status IN ('VIGENTE','ACTIVE');
               IF v_facade_count<>1 THEN
                 v_result:='BLOCK_GOVERNED_INVOKER_FACADE_ABSENT';
               ELSIF v_step_count<>1 THEN
                 v_result:='BLOCK_OPERATION_STEP_NOT_CURRENT';
               ELSE
                 IF private.fn_lf_d2_source_binding_authority_gate_v1(p_source_ref,v_metadata)->>'decision'
                   = 'SOURCE_BINDING_HUMAN_AUTHORITY_VERIFIED' THEN
                    v_result:='STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION';
                  ELSE
                    v_result:='BLOCK_SOURCE_BINDING_HUMAN_AUTHORITY_NOT_VERIFIED';
                  END IF;
               END IF;
            END IF;
         END IF;
       END IF;
     END IF;
   END IF;
 END IF;
 RETURN jsonb_build_object(
   'schema_version','LF_D2_CANONICAL_SOURCE_BINDING_READBACK_V1',
   'source_ref',p_source_ref,
   'decision',v_result,
   'business_data_read_authorized',false,
   'rows_accessed',false,
   'global_discovery_exhausted',false,
   'effects_executed',false,
   'next_required_gate','FACADE_REAL_IDENTITY_TENANT_PERMISSION_RLS_READBACK');
EXCEPTION WHEN insufficient_privilege THEN
 RETURN jsonb_build_object(
   'schema_version','LF_D2_CANONICAL_SOURCE_BINDING_READBACK_V1',
   'decision','BLOCK_BINDING_CATALOG_ACL_DENIED',
   'source_ref',p_source_ref,
   'business_data_read_authorized',false,
   'rows_accessed',false,
   'global_discovery_exhausted',false,
   'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_d2_binding_readback_v1(text) IS
'Canonical read-only binding preflight; never authorizes business reads or bypasses RLS.';
REVOKE ALL ON FUNCTION private.fn_lf_d2_binding_readback_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d2_binding_readback_v1(text) TO service_role;

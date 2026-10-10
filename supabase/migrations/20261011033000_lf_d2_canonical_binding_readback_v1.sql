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
   FROM inventory.objects i
   WHERE i.object_ref=p_source_ref
     AND i.object_type IN ('DB_TABLE','DB_VIEW')
     AND i.active AND i.currentness IN ('CATALOG_MANAGED','CURRENT');
   IF v_inventory_count<>1 THEN
     v_result:='BLOCK_INVENTORY_SOURCE_NOT_UNIQUE_CURRENT';
   ELSIF private.fn_lf_d1_managed_inventory_qualification_v1()->>'technical_readiness'<>'PASS' THEN
     v_result:='BLOCK_MANAGED_INVENTORY_NOT_CURRENT';
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
       ELSIF v_metadata->>'admission_status'<>'VIGENTE' THEN
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
            ELSIF (v_metadata->>'max_rows') !~ '^[0-9]{1,4}$'
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
                 v_result:='STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION';
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

-- LF D2 generic source-binding candidate preparation. No writes or authorization.
-- Inventory and catalog are sources of metadata only; no column is auto-admitted.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_source_binding_candidate_v1(p_source_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE
 v_gate jsonb;
 v_status text:='BLOCK_INVALID_SOURCE_REF';
 v_schema text;
 v_object text;
 v_count integer:=0;
 v_policy_count integer:=0;
 v_policy_sha text;
 v_fingerprint text;
 v_observed jsonb:='[]'::jsonb;
BEGIN
 IF p_source_ref IS NOT NULL
   AND pg_catalog.length(p_source_ref)<=250
   AND p_source_ref ~ '^db://[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$' THEN
  v_gate:=private.fn_lf_d2_binding_readback_v1(p_source_ref);
  IF v_gate->>'decision'='BLOCK_INVENTORY_SOURCE_NOT_UNIQUE_CURRENT' THEN
    v_status:='BLOCK_NOT_IN_CANONICAL_INVENTORY';
  ELSIF v_gate->>'decision'='BLOCK_MANAGED_INVENTORY_NOT_CURRENT' THEN
    v_status:='BLOCK_MANAGED_INVENTORY_NOT_CURRENT';
  ELSIF v_gate->>'decision'='STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION' THEN
    v_status:='BLOCK_ALREADY_STRUCTURALLY_GOVERNED';
  ELSE
    v_schema:=pg_catalog.split_part(pg_catalog.substr(p_source_ref,6),'.',1);
    v_object:=pg_catalog.split_part(pg_catalog.substr(p_source_ref,6),'.',2);
    SELECT count(*)::int INTO v_count
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname=v_schema AND c.relname=v_object
      AND c.relkind IN ('r','p','v') AND NOT c.relispartition;
    SELECT count(*)::int,max(policy_sha) INTO v_policy_count,v_policy_sha
    FROM public.lf_policy_versions
    WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE';
    IF v_count<>1 THEN
      v_status:='BLOCK_PHYSICAL_SOURCE_NOT_UNIQUE';
    ELSIF v_policy_count<>1 OR v_policy_sha !~ '^[0-9a-f]{64}$' THEN
      v_status:='BLOCK_SOURCE_POLICY_NOT_CURRENT';
    ELSE
      SELECT encode(extensions.digest(convert_to(
          n.nspname||'.'||c.relname||'|'||coalesce(
            pg_catalog.string_agg(a.attname||':'||a.atttypid::regtype::text||':'||
               a.attnotnull::text,'|' ORDER BY a.attnum),''
          ),'UTF8'),'sha256'),'hex'),
        coalesce(pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object('column',a.attname,'postgres_type',a.atttypid::regtype::text,
            'nullable',NOT a.attnotnull) ORDER BY a.attnum),'[]'::jsonb)
      INTO v_fingerprint,v_observed
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
      WHERE n.nspname=v_schema AND c.relname=v_object
      GROUP BY n.nspname,c.relname;
      IF v_fingerprint IS NULL THEN
        v_status:='BLOCK_PHYSICAL_SOURCE_COLUMNS_UNAVAILABLE';
      ELSE
        v_status:='CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE';
      END IF;
    END IF;
  END IF;
 END IF;
 RETURN pg_catalog.jsonb_build_object(
 'schema_version','LF_D2_SOURCE_BINDING_CANDIDATE_V1',
 'decision',v_status,'source_ref',p_source_ref,
 'source_schema_fingerprint',CASE WHEN v_status='CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE'
                                    THEN v_fingerprint ELSE NULL END,
 'observed_columns_for_governance_review',CASE WHEN v_status='CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE'
                                                THEN v_observed ELSE '[]'::jsonb END,
 'policy_code','POL-LF-SOURCE-RESOLUTION',
 'policy_sha',CASE WHEN v_status='CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE' THEN v_policy_sha ELSE NULL END,
 'proposed_binding',CASE WHEN v_status='CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE'
  THEN pg_catalog.jsonb_build_object(
    'canonical_source_ref',p_source_ref,
    'source_schema_fingerprint',v_fingerprint,'policy_sha',v_policy_sha,
    'admission_status','CANDIDATO',
    'permitted_columns','[]'::jsonb,
    'allowed_filter_fields','[]'::jsonb,
    'read_facade_ref',NULL,'tenant_scope_rule_ref',NULL,
    'required_permission_code',NULL,'max_rows',NULL,
    'governance_approval_required',true)
  ELSE NULL END,
 'binding_written',false,'business_rows_accessed',false,
 'business_read_authorized',false,'runtime_dispatched',false,
 'effects_executed',false);
EXCEPTION WHEN insufficient_privilege THEN
 RETURN pg_catalog.jsonb_build_object(
 'schema_version','LF_D2_SOURCE_BINDING_CANDIDATE_V1',
 'decision','BLOCK_CANONICAL_METADATA_ACL_DENIED',
 'binding_written',false,'business_rows_accessed',false,
 'business_read_authorized',false,'runtime_dispatched',false,
 'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_d2_source_binding_candidate_v1(text)
IS 'Generic metadata-only binding proposal: never automatically allow columns, filters, permissions or reads.';
REVOKE ALL ON FUNCTION private.fn_lf_d2_source_binding_candidate_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d2_source_binding_candidate_v1(text) TO service_role;

-- LF D2: metadata-only request plan for a governed read facade.
-- Never issues SELECT against the business relation, never executes an RPC.
-- It is NOT an authorization token. Supabase is source of all binding policy.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_facade_request_plan_v1(
  p_source_ref text,p_projection jsonb,p_filters jsonb,p_row_limit integer
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $f$
DECLARE
  v_gate jsonb;
  v_md jsonb;
  v_missing integer:=0;
  v_limit integer;
  v_rpc text;
  v_status text;
BEGIN
  -- First check types, then call JSON cardinality functions.
  IF p_source_ref IS NULL OR p_projection IS NULL OR p_filters IS NULL OR
     p_row_limit IS NULL OR p_row_limit NOT BETWEEN 1 AND 1000 OR
     pg_catalog.jsonb_typeof(p_projection) IS DISTINCT FROM 'array' OR
     pg_catalog.jsonb_typeof(p_filters) IS DISTINCT FROM 'object' THEN
    v_status:='BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST';
  ELSIF pg_catalog.jsonb_array_length(p_projection) NOT BETWEEN 1 AND 30 OR
        (SELECT count(*) FROM pg_catalog.jsonb_object_keys(p_filters))>20 THEN
    v_status:='BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST';
  ELSE
    v_gate:=private.fn_lf_d2_binding_readback_v1(p_source_ref);
    IF v_gate->>'decision' IS DISTINCT FROM
       'STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION' THEN
       v_status:='BLOCK_SOURCE_NOT_STRUCTURALLY_ADMITTED';
    ELSE
       SELECT a.metadata INTO v_md FROM public.lf_activos a
       WHERE a.archived_at IS NULL
         AND a.metadata->>'canonical_source_ref'=p_source_ref
         AND a.metadata->>'admission_status'='VIGENTE';
       IF v_md IS NULL THEN
         v_status:='BLOCK_BINDING_NOT_CURRENT';
       ELSE
         SELECT count(*)::integer INTO v_missing
         FROM (SELECT pg_catalog.jsonb_array_elements(p_projection) AS val) s
         WHERE pg_catalog.jsonb_typeof(val) IS DISTINCT FROM 'string'
            OR NOT EXISTS(SELECT 1
              FROM pg_catalog.jsonb_array_elements_text(v_md->'permitted_columns') c
              WHERE c=s.val #>> '{}');
         IF v_missing>0 OR
            (SELECT count(*)<>count(DISTINCT c)
             FROM pg_catalog.jsonb_array_elements_text(p_projection) c) THEN
            v_status:='BLOCK_PROJECTION_NOT_GOVERNED';
         ELSE
           SELECT count(*)::integer INTO v_missing
           FROM pg_catalog.jsonb_object_keys(p_filters) k
           WHERE NOT EXISTS(SELECT 1
             FROM pg_catalog.jsonb_array_elements_text(v_md->'allowed_filter_fields') x
             WHERE x=k);
           IF v_missing>0 OR EXISTS (
             SELECT 1 FROM pg_catalog.jsonb_each(p_filters) fl
             WHERE fl.value='null'::jsonb OR
                   pg_catalog.jsonb_typeof(fl.value) NOT IN ('string','number','boolean')) THEN
             v_status:='BLOCK_FILTER_NOT_GOVERNED';
           ELSE
             v_limit:=(v_md->>'max_rows')::integer;
             v_rpc:=v_md->>'read_facade_ref';
             IF p_row_limit>v_limit THEN
               v_status:='BLOCK_ROW_LIMIT_EXCEEDS_BINDING';
             ELSIF NOT EXISTS(
                 SELECT 1 FROM pg_catalog.pg_proc p
                 WHERE p.oid=pg_catalog.to_regprocedure(v_rpc)
                   AND p.prokind='f' AND NOT p.prosecdef
                   AND p.provolatile IN ('s','i')
                ) THEN
               v_status:='BLOCK_FACADE_NOT_READONLY_INVOKER';
             ELSE
               v_status:='PLAN_ONLY_REQUIRES_AUTHENTICATED_USER_RLS_AND_READBACK';
             END IF;
           END IF;
         END IF;
       END IF;
    END IF;
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'schema_version','LF_D2_FACADE_REQUEST_PLAN_V1',
    'decision',v_status,'source_ref',p_source_ref,
    'facade_ref',CASE WHEN v_status='PLAN_ONLY_REQUIRES_AUTHENTICATED_USER_RLS_AND_READBACK'
                        THEN v_rpc ELSE NULL END,
    'normalized_projection',CASE WHEN v_status='PLAN_ONLY_REQUIRES_AUTHENTICATED_USER_RLS_AND_READBACK'
                                  THEN p_projection ELSE '[]'::jsonb END,
    'normalized_filters',CASE WHEN v_status='PLAN_ONLY_REQUIRES_AUTHENTICATED_USER_RLS_AND_READBACK'
                               THEN p_filters ELSE '{}'::jsonb END,
    'row_limit',CASE WHEN v_status='PLAN_ONLY_REQUIRES_AUTHENTICATED_USER_RLS_AND_READBACK'
                      THEN p_row_limit ELSE NULL END,
    'execution_authorized',false,
    'authenticated_actor_verified',false,
    'tenant_scope_verified',false,
    'business_rows_accessed',false,
    'receipt_verified',false,
    'runtime_dispatch_authorized',false,
    'effects_executed',false,
    'next_gate','USER_SCOPED_RLS_FACADE_EXECUTION_AND_PERSISTED_RECEIPT');
EXCEPTION WHEN insufficient_privilege THEN
  RETURN pg_catalog.jsonb_build_object(
    'schema_version','LF_D2_FACADE_REQUEST_PLAN_V1',
    'decision','BLOCK_CANONICAL_METADATA_ACL_DENIED',
    'execution_authorized',false,'business_rows_accessed',false,
    'receipt_verified',false,'runtime_dispatch_authorized',false,
    'effects_executed',false);
END $f$;
COMMENT ON FUNCTION private.fn_lf_d2_facade_request_plan_v1(text,jsonb,jsonb,integer)
IS 'Metadata-only facade invocation descriptor from VIGENTE binding; caller must separately execute as authenticated RLS-scoped user and read back ledger receipt.';
REVOKE ALL ON FUNCTION private.fn_lf_d2_facade_request_plan_v1(text,jsonb,jsonb,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d2_facade_request_plan_v1(text,jsonb,jsonb,integer) TO service_role;

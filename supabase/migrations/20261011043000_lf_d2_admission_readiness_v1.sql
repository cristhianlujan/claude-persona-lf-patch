-- LF D2 admission diagnostic: one read-only composition of existing D1/D2
-- and pg_catalog, not a second authorization engine.
-- No SELECT on business rows, role grants, RLS changes, binding writes, or user fixtures.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_admission_readiness_v1(p_source_ref text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO ''
AS $fn$
DECLARE
  v_binding jsonb;
  v_candidate jsonb;
  v_source text;
  v_schema text;
  v_object text;
  v_object_oid oid;
  v_object_count integer:=0;
  v_rls boolean;
  v_force_rls boolean;
  v_client_grant boolean;
  v_client_policy integer:=0;
  v_client_deny integer:=0;
  v_client_static_false integer:=0;
  v_actor boolean:=false;
  v_ledger_grant boolean:=false;
  v_decision text;
  v_gaps jsonb:='[]'::jsonb;
  v_policy_state text;
BEGIN
  v_source:=p_source_ref;
  IF v_source IS NULL OR pg_catalog.length(v_source)>250 OR
     v_source !~ '^db://[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*$' THEN
    v_decision:='BLOCK_INVALID_CANONICAL_SOURCE_REF';
    v_gaps:=v_gaps||pg_catalog.jsonb_build_array('CANONICAL_REF_REQUIRED');
  ELSE
    v_binding:=private.fn_lf_d2_binding_readback_v1(v_source);
    v_candidate:=private.fn_lf_d2_source_binding_candidate_v1(v_source);
    v_schema:=pg_catalog.split_part(pg_catalog.substr(v_source,6),'.',1);
    v_object:=pg_catalog.split_part(pg_catalog.substr(v_source,6),'.',2);
    SELECT count(*)::int,max(c.oid)::oid,bool_or(c.relrowsecurity),bool_or(c.relforcerowsecurity)
    INTO v_object_count,v_object_oid,v_rls,v_force_rls
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname=v_schema AND c.relname=v_object
      AND c.relkind IN ('r','p','v') AND NOT c.relispartition;
    IF v_object_count=1 THEN
      v_client_grant:=pg_catalog.has_table_privilege('authenticated',v_object_oid,'SELECT');
      SELECT count(*) FILTER (WHERE pol.polpermissive AND
                                  pol.polcmd IN ('r','*') AND
                                  ('authenticated'::regrole=ANY(pol.polroles) OR
                                   '0'::oid=ANY(pol.polroles)))::integer,
             count(*) FILTER (WHERE NOT pol.polpermissive AND
                                  pol.polcmd IN ('r','*') AND
                                  ('authenticated'::regrole=ANY(pol.polroles) OR
                                   '0'::oid=ANY(pol.polroles)))::integer,
             count(*) FILTER (WHERE pol.polcmd IN ('r','*') AND
                                  ('authenticated'::regrole=ANY(pol.polroles) OR
                                   '0'::oid=ANY(pol.polroles)) AND
                                  pg_catalog.lower(pg_catalog.btrim(
                                    pg_catalog.pg_get_expr(pol.polqual,pol.polrelid)))
                                     IN ('false','(false)'))::integer
      INTO v_client_policy,v_client_deny,v_client_static_false
      FROM pg_catalog.pg_policy pol WHERE pol.polrelid=v_object_oid;
    ELSE
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('EXACT_PHYSICAL_SOURCE_NOT_UNIQUE');
    END IF;
    v_actor:=auth.uid() IS NOT NULL AND current_user='authenticated';
    v_ledger_grant:=pg_catalog.has_table_privilege(
      'service_role','private.lf_evidence_ledger_v1','SELECT');

    IF v_binding->>'decision' IS DISTINCT FROM
      'STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION' THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('BINDING_NOT_STRUCTURALLY_ADMITTED');
    END IF;
    IF v_candidate->>'decision'='BLOCK_MANAGED_INVENTORY_NOT_CURRENT' OR
       v_binding->>'decision'='BLOCK_MANAGED_INVENTORY_NOT_CURRENT' THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('MANAGED_INVENTORY_REFRESH_REQUIRED');
    ELSIF v_candidate->>'decision'='BLOCK_NOT_IN_CANONICAL_INVENTORY' THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('CANONICAL_INDEX_CURRENTNESS_REQUIRED');
    END IF;
    IF NOT v_actor THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('REAL_AUTHENTICATED_ACTOR_SESSION_REQUIRED');
    END IF;
    IF v_object_count=1 AND v_client_grant IS NOT TRUE THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('DIRECT_CLIENT_TABLE_READ_UNAVAILABLE_USE_GOVERNED_FACADE');
    END IF;
    IF v_object_count=1 AND v_rls IS TRUE AND (v_client_policy=0 OR v_client_policy=v_client_static_false) THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('NO_PERMISSIVE_CLIENT_SELECT_RLS_POLICY');
    END IF;
    IF NOT v_ledger_grant THEN
      v_gaps:=v_gaps||pg_catalog.jsonb_build_array('SCOPED_LEDGER_RECEIPT_READBACK_REQUIRED');
    END IF;
    -- Never inspect business rows or infer company permission from JWT claims.
    v_gaps:=v_gaps||pg_catalog.jsonb_build_array(
      'ACTOR_COMPANY_PERMISSION_RLS_PROOF_NOT_EXECUTED');
    v_decision:='REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'schema_version','LF_D2_ADMISSION_READINESS_V1',
    'source_ref',v_source,
    'decision',v_decision,
    'binding_decision',v_binding->>'decision',
    'candidate_decision',v_candidate->>'decision',
    'blocking_requirements',v_gaps,
    'physical_source_count',v_object_count,
    'rls_enabled',v_rls,
    'force_rls',v_force_rls,
    'authenticated_direct_select_granted',v_client_grant,
    'authenticated_permissive_select_policies',v_client_policy,
    'authenticated_restrictive_select_policies',v_client_deny,
    'authenticated_static_false_select_policies',v_client_static_false,
    'rls_effective_authorization_not_inferred',true,
    'canonical_actor_present',v_actor,
    'ledger_global_service_select_granted',v_ledger_grant,
    'business_data_access_authorized',false,
    'business_rows_accessed',false,
    'runtime_enabled',false,'effects_executed',false);
EXCEPTION WHEN insufficient_privilege THEN
  RETURN pg_catalog.jsonb_build_object(
    'schema_version','LF_D2_ADMISSION_READINESS_V1',
    'decision','BLOCK_READINESS_CATALOG_ACL_DENIED',
    'blocking_requirements',pg_catalog.jsonb_build_array('CANONICAL_METADATA_ACL_REQUIRED'),
    'business_data_access_authorized',false,'business_rows_accessed',false,
    'runtime_enabled',false,'effects_executed',false);
END $fn$;
COMMENT ON FUNCTION private.fn_lf_d2_admission_readiness_v1(text)
IS 'Consolidated D2 diagnostic only. Client SELECT, RLS and ledger ACL inspection never constitutes actor/tenant authorization.';
REVOKE ALL ON FUNCTION private.fn_lf_d2_admission_readiness_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_d2_admission_readiness_v1(text)
 TO service_role;
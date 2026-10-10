-- LF D1: least-privilege repair for the EXISTING inventory.fn_lookup_v3.
-- Metadata/currentness only. Does NOT GRANT any B2B business table, RLS
-- permission, or broad inventory schema access. Existing v3 is reused.
DO $pre$
BEGIN
 IF NOT has_function_privilege('service_role',
    'inventory.fn_lookup_v3(text,text[],integer,text[])','EXECUTE')
 THEN RAISE EXCEPTION 'D1_INVENTORY_V3_SERVICE_EXECUTE_MISSING'; END IF;
 IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid='inventory.v_managed_currentness_v1'::regclass
    AND c.reloptions @> ARRAY['security_invoker=true']
 ) THEN RAISE EXCEPTION 'D1_CURRENTNESS_VIEW_MUST_BE_SECURITY_INVOKER'; END IF;
 IF has_table_privilege('anon','inventory.v_managed_currentness_v1','SELECT')
 OR has_table_privilege('authenticated','inventory.v_managed_currentness_v1','SELECT')
 THEN RAISE EXCEPTION 'D1_CURRENTNESS_VIEW_CLIENT_SELECT_PREEXISTS'; END IF;
 IF NOT has_table_privilege('service_role','inventory.snapshots','SELECT')
 THEN RAISE EXCEPTION 'D1_CURRENTNESS_BASE_TABLE_GRANT_MISSING'; END IF;
END $pre$;

GRANT SELECT ON inventory.v_managed_currentness_v1 TO service_role;

DO $post$
BEGIN
 IF NOT has_table_privilege('service_role','inventory.v_managed_currentness_v1','SELECT')
 OR has_table_privilege('anon','inventory.v_managed_currentness_v1','SELECT')
 OR has_table_privilege('authenticated','inventory.v_managed_currentness_v1','SELECT')
 THEN RAISE EXCEPTION 'D1_CURRENTNESS_VIEW_GRANT_SCOPE_INVALID'; END IF;
END $post$;

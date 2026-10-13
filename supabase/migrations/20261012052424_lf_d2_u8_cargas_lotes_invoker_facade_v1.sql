-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261012052424
-- source_name=lf_d2_u8_cargas_lotes_invoker_facade_v1
-- LF D2 U8. Candidate technical construction; does not admit business binding or actor.
-- Reuses current catalog, policy and RLS. No grant, no runtime enable.
CREATE OR REPLACE FUNCTION private.fn_lf_d2_cargas_lotes_read_v1(
  p_source_ref text, p_projection jsonb, p_filters jsonb, p_row_limit integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO ''
AS $lf$
DECLARE
  v_plan jsonb;
  v_company uuid;
  v_rows jsonb := '[]'::jsonb;
  v_allowed text[] := ARRAY['load_id','company_id','load_code','load_name','load_type','status','created_at','total_records','valid_count'];
BEGIN
  IF p_source_ref IS DISTINCT FROM 'db://lf_ops.cargas_lotes'
     OR p_projection IS NULL OR jsonb_typeof(p_projection) IS DISTINCT FROM 'array'
     OR p_filters IS NULL OR jsonb_typeof(p_filters) IS DISTINCT FROM 'object'
     OR p_row_limit IS NULL OR p_row_limit NOT BETWEEN 1 AND 100 THEN
    RETURN jsonb_build_object('decision','BLOCK_FACADE_REQUEST_INVALID','rows','[]'::jsonb,'business_answer_admitted',false);
  END IF;
  IF EXISTS (
     SELECT 1 FROM jsonb_array_elements(p_projection) AS a(v)
     WHERE jsonb_typeof(a.v) <> 'string' OR NOT (a.v #>> '{}') = ANY(v_allowed)
  ) OR EXISTS (
     SELECT 1 FROM jsonb_object_keys(p_filters) AS f(key)
     WHERE f.key NOT IN ('load_code','status')
  ) OR EXISTS (
     SELECT 1 FROM jsonb_each(p_filters) AS f(key,val)
     WHERE jsonb_typeof(f.val) <> 'string'
  ) THEN
    RETURN jsonb_build_object('decision','BLOCK_UNGOVERNED_PROJECTION_OR_FILTER','rows','[]'::jsonb,'business_answer_admitted',false);
  END IF;
  -- The service/database owner must never stand in for a real B2B actor.
  IF current_user IS DISTINCT FROM 'authenticated' OR auth.uid() IS NULL THEN
    RETURN jsonb_build_object('decision','BLOCK_REAL_AUTHENTICATED_ACTOR_REQUIRED','rows','[]'::jsonb,'business_answer_admitted',false);
  END IF;
  v_plan := private.fn_lf_d2_facade_request_plan_v1(p_source_ref,p_projection,p_filters,p_row_limit);
  IF v_plan->>'decision' IS DISTINCT FROM 'PLAN_ONLY_REQUIRES_AUTHENTICATED_USER_RLS_AND_READBACK'
     OR v_plan->>'facade_ref' IS DISTINCT FROM 'private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)' THEN
    RETURN jsonb_build_object('decision','BLOCK_GOVERNED_BINDING_NOT_ADMITTED','rows','[]'::jsonb,
       'business_answer_admitted',false,'plan_decision',v_plan->>'decision');
  END IF;
  v_company := lf_ops.b2b_current_company_id();
  IF v_company IS NULL OR NOT lf_ops.fn_b2b_can_read_load_company_v1(v_company) THEN
    RETURN jsonb_build_object('decision','BLOCK_COMPANY_PERMISSION','rows','[]'::jsonb,'business_answer_admitted',false);
  END IF;
  -- Row-level security applies to the invoker's exact source read.
  SELECT coalesce(jsonb_agg(q.projection ORDER BY q.created_at DESC,q.load_id),'[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT l.load_id,l.created_at,
      (SELECT coalesce(jsonb_object_agg(k.key,k.value),'{}'::jsonb)
       FROM jsonb_each(jsonb_build_object(
         'load_id',l.load_id,'company_id',l.company_id,'load_code',l.load_code,
         'load_name',l.load_name,'load_type',l.load_type,'status',l.status,
         'created_at',l.created_at,'total_records',l.total_records,'valid_count',l.valid_count
       )) AS k WHERE p_projection ? k.key) AS projection
    FROM lf_ops.cargas_lotes l
    WHERE l.company_id=v_company
      AND (NOT (p_filters ? 'load_code') OR l.load_code=p_filters->>'load_code')
      AND (NOT (p_filters ? 'status') OR l.status=p_filters->>'status')
    ORDER BY l.created_at DESC,l.load_id
    LIMIT p_row_limit
  ) q;
  -- Data-plane receipt and recheck remain prerequisites before profile admission.
  RETURN jsonb_build_object('decision','READ_EXECUTED_RECEIPT_AND_ACTOR_READBACK_PENDING',
       'source_ref',p_source_ref,'rows',v_rows,'row_count',jsonb_array_length(v_rows),
       'business_answer_admitted',false,'receipt_verified',false);
EXCEPTION WHEN insufficient_privilege THEN
  RETURN jsonb_build_object('decision','BLOCK_INVOKER_PRIVILEGES','rows','[]'::jsonb,'business_answer_admitted',false);
END
$lf$;
-- No new client, service or public permission during technical construction.
REVOKE ALL ON FUNCTION private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)
  FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)
IS 'LF D2 candidate B2B metadata facade: SECURITY INVOKER, actor/tenant/RLS and admitted binding; no execution grant or business admission pending real-actor proof.';

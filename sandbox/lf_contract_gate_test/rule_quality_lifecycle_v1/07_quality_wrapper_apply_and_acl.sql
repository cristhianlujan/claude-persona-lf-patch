-- LOTE 14 SANDBOX: generic envelope. Real LF gate is called unchanged.
SET search_path=rule_quality_l13,public;

CREATE FUNCTION saly_fixture_apply(p_rule text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_n int;
BEGIN
 UPDATE saly_source_synthetic SET vigente=true WHERE codigo=p_rule AND vigente=false;
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION USING ERRCODE='23514',
      MESSAGE='BLOCK_SALY_SYNTHETIC_APPLY_NOT_ONE_ROW'; END IF;
 RETURN jsonb_build_object('status','APPLIED','fixture_only',true,'rule_code',p_rule);
END $fn$;

-- Envelope: quality BEFORE; existing LF apply UNMODIFIED; quality AFTER.
-- The same function works for both project adapters without changing source SQL.
CREATE FUNCTION quality_apply_envelope(p_project text,p_rule text,p_promotion_id text DEFAULT NULL,
 p_owner_run text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_actor text;v_adapter project_source_adapters%ROWTYPE;
        v_rule rules%ROWTYPE;v_result jsonb;v_return jsonb;v_source_state text;
BEGIN
 v_actor:=trusted_actor_role(p_project);
 SELECT * INTO v_adapter FROM project_source_adapters WHERE project_code=p_project;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',
   MESSAGE='BLOCK_QUALITY_PROJECT_ADAPTER_MISSING'; END IF;
 SELECT * INTO v_rule FROM rules WHERE project_code=p_project AND rule_code=p_rule FOR UPDATE;
 IF NOT FOUND OR v_rule.state<>'EN_REVISION'
    OR v_rule.family_code IS NULL OR v_rule.reviewed_at IS NULL
    OR v_rule.next_review_at IS NULL OR v_rule.next_review_at<=clock_timestamp() THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_PREFLIGHT_INCOMPLETE';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM category_family_map
    WHERE project_code=p_project AND category_raw=v_rule.category_raw
      AND family_code=v_rule.family_code AND mapping_status='APPROVED') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_FAMILY_MAPPING_NOT_APPROVED';
 END IF;
 INSERT INTO activation_tickets(project_code,rule_code,actor_role,status)
 VALUES(p_project,p_rule,v_actor,'ARMED')
 ON CONFLICT(project_code,rule_code) DO UPDATE SET
    actor_role=EXCLUDED.actor_role,status='ARMED',created_at=clock_timestamp();
 IF v_adapter.engine='LF_FROZEN_APPLY' THEN
   IF p_promotion_id IS NULL OR p_owner_run IS NULL THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_GATE_IDENTIFIERS_REQUIRED';
   END IF;
   v_result:=public.lf_rule_promotion_apply_v1(p_promotion_id);
   IF v_result->>'status'<>'APPLIED' THEN
     RAISE EXCEPTION USING ERRCODE='23514',
       MESSAGE='BLOCK_QUALITY_FROZEN_GATE_NOT_APPLIED';
   END IF;
   v_return:=public.lf_rule_promotion_profile_return_readback_v1(p_promotion_id,p_owner_run);
   IF v_return->>'status'<>'READY'
      OR (v_return->>'readback_verified')::boolean IS DISTINCT FROM true THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_GATE_RETURN_NOT_READY';
   END IF;
 ELSIF v_adapter.engine='SALY_SYNTHETIC_APPLY' THEN
   v_result:=saly_fixture_apply(p_rule);
   v_return:=jsonb_build_object('status','READY','sandbox_fixture',true,'readback_verified',true);
 ELSE
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_UNKNOWN_ENGINE';
 END IF;
 EXECUTE format('SELECT %I::text FROM %s WHERE %I=$1',
   v_adapter.state_col,v_adapter.source_table,v_adapter.code_col)
 INTO v_source_state USING p_rule;
 IF v_source_state IS DISTINCT FROM v_adapter.active_value THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_SOURCE_READBACK_NOT_ACTIVE';
 END IF;
 UPDATE rules SET state='VIGENTE' WHERE project_code=p_project AND rule_code=p_rule;
 UPDATE activation_tickets SET status='CONSUMED'
 WHERE project_code=p_project AND rule_code=p_rule AND actor_role=v_actor;
 RETURN jsonb_build_object('status','READY','project_code',p_project,
   'rule_code',p_rule,'family_code',v_rule.family_code,
   'owner_role',v_actor,'reviewed_at',v_rule.reviewed_at,
   'next_review_at',v_rule.next_review_at,
   'quality_readback','VIGENTE','gate',v_result,'profile_return',v_return);
END $fn$;

-- Database permissions: no direct DML for tenant roles, even owner.
REVOKE ALL ON SCHEMA rule_quality_l13 FROM PUBLIC;
GRANT USAGE ON SCHEMA rule_quality_l13 TO lf_owner_role,lf_super_role,
 lf_reader_role,lf_no_grant_role,saly_owner_role,saly_super_role;
REVOKE ALL ON ALL TABLES IN SCHEMA rule_quality_l13 FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA rule_quality_l13 FROM PUBLIC;
ALTER TABLE rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE rules FORCE ROW LEVEL SECURITY;
-- No RLS INSERT/UPDATE policy for tenant roles; only SECURITY DEFINER owner writes.
GRANT EXECUTE ON FUNCTION trusted_actor_role(text) TO
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
GRANT EXECUTE ON FUNCTION quality_prepare_new(text,text,text,timestamptz) TO
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
GRANT EXECUTE ON FUNCTION quality_propose_correction(text,text,text,text,jsonb) TO
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
GRANT EXECUTE ON FUNCTION quality_apply_envelope(text,text,text,text) TO
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;

-- Explicit schema search_path for L13 STABLE selectors when invoked outside L13.
-- These are quality read-only functions, NOT frozen promotion gates.
ALTER FUNCTION list_review_due(text,timestamptz)
 SET search_path=rule_quality_l13,pg_temp;
ALTER FUNCTION find_noncurrent_references(text)
 SET search_path=rule_quality_l13,pg_temp;
ALTER FUNCTION find_parameter_differences(text)
 SET search_path=rule_quality_l13,pg_temp;

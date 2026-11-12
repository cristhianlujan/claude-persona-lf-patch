-- LOTE 14: POSTGRESQL SANDBOX ONLY. DO NOT APPLY TO SUPABASE.
SET search_path=rule_quality_l13,public;
CREATE ROLE lf_owner_role LOGIN PASSWORD 'sandbox_lf_owner_only';
CREATE ROLE lf_super_role LOGIN PASSWORD 'sandbox_lf_super_only';
CREATE ROLE lf_reader_role LOGIN PASSWORD 'sandbox_lf_reader_only';
CREATE ROLE lf_no_grant_role LOGIN PASSWORD 'sandbox_no_grant_only';
CREATE ROLE saly_owner_role LOGIN PASSWORD 'sandbox_saly_owner_only';
CREATE ROLE saly_super_role LOGIN PASSWORD 'sandbox_saly_super_only';
INSERT INTO actors(project_code,actor_code,profile_code,can_approve) VALUES
 ('lf','lf_owner_role','LF_GOVERNANCE',true),
 ('lf','lf_super_role','SUPER_ADMIN',true),
 ('lf','lf_reader_role','READER',false),
 ('saly','saly_owner_role','SALY_OWNER',true),
 ('saly','saly_super_role','SUPER_ADMIN',true);
-- These are SYNTHETIC approvals of two mappings, not owner approval of live LF/SALY.
UPDATE category_family_map SET mapping_status='APPROVED'
 WHERE (project_code='lf' AND category_raw='SECURITY')
    OR (project_code='saly' AND category_raw='MOTOR_DISPONIBLE');
CREATE TABLE project_source_adapters (
 project_code text PRIMARY KEY REFERENCES projects(project_code),
 source_table regclass NOT NULL,
 code_col text NOT NULL, category_col text NOT NULL,
 description_col text NOT NULL, state_col text NOT NULL,
 active_value text NOT NULL,
 engine text NOT NULL CHECK (engine IN ('LF_FROZEN_APPLY','SALY_SYNTHETIC_APPLY')),
 CHECK (code_col ~ '^[a-z_]+$' AND category_col ~ '^[a-z_]+$'
    AND description_col ~ '^[a-z_]+$' AND state_col ~ '^[a-z_]+$')
);
INSERT INTO project_source_adapters VALUES
 ('lf','lf_ops.reglas'::regclass,'codigo','categoria','descripcion','estado','VIGENTE','LF_FROZEN_APPLY'),
 ('saly','rule_quality_l13.saly_source_synthetic'::regclass,
  'codigo','categoria','regla','vigente','true','SALY_SYNTHETIC_APPLY');
CREATE TABLE activation_tickets(
 project_code text NOT NULL,rule_code text NOT NULL,actor_role text NOT NULL,
 status text NOT NULL CHECK(status IN ('ARMED','CONSUMED')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(project_code,rule_code),
 FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code)
);
CREATE TABLE correction_requests (
 project_code text NOT NULL,original_rule_code text NOT NULL,
 successor_rule_code text NOT NULL,owner_role text NOT NULL,
 evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
 status text NOT NULL DEFAULT 'EN_REVISION' CHECK(status='EN_REVISION'),
 PRIMARY KEY(project_code,successor_rule_code),
 FOREIGN KEY(project_code,original_rule_code) REFERENCES rules(project_code,rule_code),
 FOREIGN KEY(project_code,successor_rule_code) REFERENCES rules(project_code,rule_code),
 CHECK(original_rule_code<>successor_rule_code)
);

-- session_user is the PG-authenticated role. A user-set GUC cannot substitute it.
-- SECURITY DEFINER changes current_user, NOT session_user.
CREATE FUNCTION trusted_actor_role(p_project text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_role text:=session_user;
        v_claim text:=nullif(current_setting('app.l14_actor_claim',true),'');
        v_actor actors%ROWTYPE;v_owner text;
BEGIN
 IF v_claim IS NOT NULL AND v_claim<>v_role THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_QUALITY_GUC_IDENTITY_MISMATCH';
 END IF;
 SELECT * INTO v_actor FROM actors WHERE project_code=p_project AND actor_code=v_role;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_QUALITY_ROLE_UNMAPPED';
 END IF;
 IF upper(v_actor.profile_code)='SUPER_ADMIN' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_SUPER_ADMIN_APPROVAL';
 END IF;
 SELECT owner_profile_code INTO v_owner FROM projects WHERE project_code=p_project;
 IF NOT v_actor.can_approve OR v_owner IS NULL OR v_owner<>v_actor.profile_code THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_QUALITY_NOT_OWNER';
 END IF;
 RETURN v_role;
END $fn$;

-- The same generic function uses the adapter columns in LF and SALY.
CREATE FUNCTION quality_prepare_new(p_project text,p_rule text,p_family text,
 p_review_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_actor text;v_adapter project_source_adapters%ROWTYPE;
        v_category text;v_description text;v_state text;v_days integer;v_mapping text;v_now timestamptz;
BEGIN
 v_actor:=trusted_actor_role(p_project);
 IF p_family IS NULL OR btrim(p_family)='' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_FAMILY_REQUIRED';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM families WHERE project_code=p_project AND family_code=p_family) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_FAMILY_PROJECT_MISMATCH';
 END IF;
 SELECT * INTO v_adapter FROM project_source_adapters WHERE project_code=p_project;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_PROJECT_ADAPTER_MISSING';
 END IF;
 EXECUTE format('SELECT %I::text,%I::text,%I::text FROM %s WHERE %I=$1',
      v_adapter.category_col,v_adapter.description_col,v_adapter.state_col,
      v_adapter.source_table,v_adapter.code_col)
 INTO v_category,v_description,v_state USING p_rule;
 IF v_category IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_QUALITY_SOURCE_MISSING';
 END IF;
 IF v_state=v_adapter.active_value THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_NEW_ALREADY_ACTIVE';
 END IF;
 SELECT mapping_status INTO v_mapping FROM category_family_map
 WHERE project_code=p_project AND category_raw=v_category AND family_code=p_family;
 IF v_mapping IS DISTINCT FROM 'APPROVED' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_FAMILY_MAPPING_NOT_APPROVED';
 END IF;
 IF EXISTS (SELECT 1 FROM rules WHERE project_code=p_project AND rule_code=p_rule) THEN
   RAISE EXCEPTION USING ERRCODE='23505',MESSAGE='BLOCK_QUALITY_EXISTS_USE_SUCCESSOR';
 END IF;
 IF p_review_at IS NOT NULL THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_QUALITY_CALLER_REVIEW_TIME_FORBIDDEN';
 END IF;
 v_now:=clock_timestamp();
 SELECT review_interval_days INTO v_days FROM projects WHERE project_code=p_project;
 INSERT INTO rules(project_code,rule_code,family_code,category_raw,entity_code,
                   definition_text,config,state,reviewed_at,next_review_at,effective_from)
 VALUES (p_project,p_rule,p_family,v_category,'GENERAL',v_description,
         '{}'::jsonb,'EN_REVISION',v_now,
         v_now+make_interval(days=>v_days),v_now);
 RETURN jsonb_build_object('status','QUALITY_PREPARED','project_code',p_project,
    'rule_code',p_rule,'family_code',p_family,'owner_role',v_actor,
    'reviewed_at',v_now,
    'next_review_at',v_now+make_interval(days=>v_days));
END $fn$;

-- L23: CURATOR DETERMINISTICO EN PG18 AISLADO. PROHIBIDO DESPLEGAR EN SUPABASE.
-- No cambia L7/L8/L11B ni L14/L17 wrappers; gate via trigger BEFORE ARM activation ticket.
SET search_path=rule_quality_l13,pg_temp;

CREATE TABLE l23_curator_verdicts (
  project_code text NOT NULL,
  rule_code text NOT NULL,
  verdict text NOT NULL CHECK (verdict IN ('ACEPTAR','DEVOLVER_CON_MOTIVO','ESCALAR_A_HUMANO')),
  reason_code text NOT NULL,
  reason_text text NOT NULL,
  evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  candidate_fingerprint_sha256 text NOT NULL CHECK(candidate_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
  actor_code text NOT NULL,
  owner_profile_code text,
  seal_hmac_sha256 text NOT NULL CHECK(seal_hmac_sha256 ~ '^[0-9a-f]{64}$'),
  evaluated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(project_code,rule_code),
  FOREIGN KEY(project_code) REFERENCES projects(project_code)
);

-- Fingerprint binds source candidate, quality registry row, owner, category map,
-- correction lineage and FULL active source+quality sets (TOCTOU guard).
CREATE FUNCTION l23_curator_fingerprint_v1(p_project text,p_rule text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_ad project_source_adapters%ROWTYPE;
 v_source jsonb;v_active jsonb;v_q jsonb;v_family jsonb;v_map jsonb;v_correction jsonb;
 v_qactive jsonb;v_project jsonb;v_intents jsonb;v_snapshot jsonb;
BEGIN
 SELECT * INTO v_ad FROM project_source_adapters WHERE project_code=p_project;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L23_ADAPTER_MISSING'; END IF;
 EXECUTE format('SELECT to_jsonb(s) FROM %s s WHERE %I=$1',v_ad.source_table,v_ad.code_col)
 INTO v_source USING p_rule;
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY to_jsonb(s)::text),''[]''::jsonb) FROM %s s WHERE to_jsonb(s)->>%L=%L',
   v_ad.source_table,v_ad.state_col,v_ad.active_value) INTO v_active;
 SELECT to_jsonb(r) INTO v_q FROM rules r WHERE project_code=p_project AND rule_code=p_rule;
 SELECT to_jsonb(f) INTO v_family FROM families f WHERE project_code=p_project
   AND family_code=v_q->>'family_code';
 SELECT to_jsonb(m) INTO v_map FROM category_family_map m WHERE project_code=p_project
   AND category_raw=v_q->>'category_raw';
 SELECT to_jsonb(c) INTO v_correction FROM correction_requests c
   WHERE project_code=p_project AND successor_rule_code=p_rule;
 SELECT to_jsonb(p) INTO v_project FROM projects p WHERE project_code=p_project;
 SELECT coalesce(jsonb_agg(to_jsonb(i) ORDER BY to_jsonb(i)::text),'[]'::jsonb)
 INTO v_intents FROM l18_owner_intents i WHERE project_code=p_project AND rule_code=p_rule;
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]'::jsonb)
 INTO v_qactive FROM rules r WHERE project_code=p_project AND state='VIGENTE';
 v_snapshot:=jsonb_build_object('project',v_project,'rule',v_q,'source',v_source,
    'family',v_family,'mapping',v_map,'correction',v_correction,
    'active_source',v_active,'active_quality',v_qactive,'signed_owner_intents',v_intents);
 RETURN jsonb_build_object('sha256',encode(extensions.digest(
    convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex'),
   'snapshot',v_snapshot);
END $fn$;

CREATE FUNCTION l23_curator_seal_v1(p_record jsonb)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_secret text;
BEGIN
 SELECT key_hex INTO v_secret FROM l17_hmac_private WHERE key_id='sandbox-only';
 IF v_secret IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L23_SEAL_KEY_MISSING'; END IF;
 RETURN encode(extensions.hmac(convert_to(p_record::text,'UTF8'),
   decode(v_secret,'hex'),'sha256'),'hex');
END $fn$;

-- Internal evaluator has no caller-selectable verdict or actor.
CREATE FUNCTION l23_curator_evaluate_internal_v1(p_project text,p_rule text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_ident jsonb;v_actor text;v_q rules%ROWTYPE;v_owner text;v_fowner text;
 v_fp jsonb;v_src jsonb;v_active jsonb;v_registry jsonb;v_row jsonb;v_conf jsonb;
 v_cur jsonb;v_same boolean;v_differ boolean;v_dup text;v_conflict text;
 v_verdict text:='ACEPTAR';v_reason text:='NO_BLOCKING_DUPLICATE_OR_CONFLICT';
 v_text text:='No se encontro duplicado exacto ni conflicto de claves en las fuentes activas inspeccionadas';
 v_evidence jsonb;v_signed jsonb;v_seal text;v_updated integer;v_prior text;
BEGIN
 v_ident:=l17_verify_signed_claim_v2(p_project);
 v_actor:=v_ident->>'actor_code';
 SELECT * INTO v_q FROM rules WHERE project_code=p_project AND rule_code=p_rule;
 IF NOT FOUND OR v_q.state<>'EN_REVISION' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L23_NOT_IN_REVIEW';
 END IF;
 v_fp:=l23_curator_fingerprint_v1(p_project,p_rule);
 v_src:=v_fp->'snapshot'->'source';
 v_active:=v_fp->'snapshot'->'active_source';
 v_registry:=v_fp->'snapshot'->'active_quality';
 SELECT owner_profile_code INTO v_owner FROM projects WHERE project_code=p_project;
 SELECT owner_profile_code INTO v_fowner FROM families
   WHERE project_code=p_project AND family_code=v_q.family_code;
 IF v_fowner IS NULL THEN
  v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='FAMILY_NOT_FOUND';
  v_text:='La familia no existe en el proyecto';
 ELSIF v_fowner IS DISTINCT FROM v_owner THEN
  v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='FAMILY_OWNER_PROFILE_MISMATCH';
  v_text:='El perfil owner de familia no coincide con el owner de proyecto';
 ELSIF NOT EXISTS (SELECT 1 FROM actors a WHERE a.project_code=p_project
     AND a.actor_code=v_actor AND a.can_approve
     AND a.profile_code=v_fowner AND upper(a.profile_code)<>'SUPER_ADMIN') THEN
  v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='ACTOR_NOT_FAMILY_OWNER';
  v_text:='El actor autenticado no es el perfil owner correcto de la familia';
 ELSIF NOT EXISTS (SELECT 1 FROM category_family_map m
     WHERE m.project_code=p_project AND m.category_raw=v_q.category_raw
     AND m.family_code=v_q.family_code AND m.mapping_status='APPROVED') THEN
  v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='CATEGORY_FAMILY_NOT_APPROVED';
  v_text:='La categoria no esta aprobada para la familia';
 ELSIF v_src IS NULL OR v_src->>'categoria' IS DISTINCT FROM v_q.category_raw
     OR coalesce(v_src->>'descripcion',v_src->>'regla') IS DISTINCT FROM v_q.definition_text THEN
  v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='SOURCE_CANDIDATE_MISMATCH';
  v_text:='Candidato no existe o sus datos no coinciden con el registro de calidad';
 ELSE
  v_conf:=coalesce(v_src->'valor_config','{}'::jsonb);
  IF jsonb_typeof(v_conf) IS DISTINCT FROM 'object' THEN
   v_verdict:='ESCALAR_A_HUMANO';v_reason:='CONFIG_NOT_OBJECT';
   v_text:='valor_config no es un objeto comparable';
  ELSE
   FOR v_row IN SELECT value FROM jsonb_array_elements(coalesce(v_active,'[]'::jsonb)) LOOP
    IF v_row->>'codigo'=p_rule THEN
     v_dup:=p_rule;EXIT;
    END IF;
    IF v_row->>'categoria'=v_q.category_raw THEN
     v_cur:=coalesce(v_row->'valor_config','{}'::jsonb);
     IF coalesce(v_row->>'descripcion',v_row->>'regla')=v_q.definition_text AND v_cur=v_conf THEN
       v_dup:=v_row->>'codigo';EXIT;
     END IF;
     IF jsonb_typeof(v_cur)='object' THEN
      SELECT EXISTS(SELECT 1 FROM jsonb_object_keys(v_conf) k
          WHERE v_cur ? k AND (v_cur->k) IS DISTINCT FROM (v_conf->k))
      INTO v_differ;
      IF v_differ THEN v_conflict:=v_row->>'codigo';EXIT; END IF;
     END IF;
    END IF;
   END LOOP;
   IF v_dup IS NULL AND v_conflict IS NULL THEN
    FOR v_row IN SELECT value FROM jsonb_array_elements(coalesce(v_registry,'[]'::jsonb)) LOOP
     IF v_row->>'rule_code'=p_rule THEN v_dup:=p_rule;EXIT; END IF;
     IF v_row->>'family_code'=v_q.family_code AND v_row->>'category_raw'=v_q.category_raw THEN
      v_cur:=coalesce(v_row->'config','{}'::jsonb);
      IF v_row->>'definition_text'=v_q.definition_text AND v_cur=v_conf THEN
       v_dup:=v_row->>'rule_code';EXIT;
      END IF;
      IF jsonb_typeof(v_cur)='object' THEN
       SELECT EXISTS(SELECT 1 FROM jsonb_object_keys(v_conf) k
          WHERE v_cur ? k AND v_cur->k IS DISTINCT FROM v_conf->k)
       INTO v_differ;
       IF v_differ THEN v_conflict:=v_row->>'rule_code';EXIT; END IF;
      END IF;
     END IF;
    END LOOP;
   END IF;
   IF v_dup IS NOT NULL THEN
    v_verdict:='DEVOLVER_CON_MOTIVO';v_reason:='EXACT_DUPLICATE_VIGENTE';
    v_text:='Existe codigo o contenido identico en una regla VIGENTE: '||v_dup;
   ELSIF v_conflict IS NOT NULL THEN
    -- Explicit correction can be ACCEPTED only if old VIGENTE is named in
    -- a formal correction_request AND signed-owner intent already exists.
    -- This is sandbox HMAC owner, NOT a real Step70 approval.
    IF EXISTS(SELECT 1 FROM correction_requests c
        JOIN l18_owner_intents i ON i.project_code=c.project_code
          AND i.rule_code=c.successor_rule_code AND i.owner_actor=c.owner_role
        WHERE c.project_code=p_project AND c.successor_rule_code=p_rule
          AND c.original_rule_code=v_conflict AND c.owner_role=v_actor
          AND i.decision='APPROVE_SANDBOX_PROPOSAL') THEN
      v_verdict:='ACEPTAR';v_reason:='SIGNED_EXPLICIT_CORRECTION_LINEAGE';
      v_text:='Cambio explicito de valor_config ligado a regla anterior y owner HMAC del ensayo; NO firma de produccion';
    ELSE
      v_verdict:='ESCALAR_A_HUMANO';v_reason:='CONFIG_VALUE_CONFLICT';
      v_text:='valor_config difiere para la misma clave y categoria/familia: '||v_conflict;
    END IF;
   END IF;
  END IF;
 END IF;
 v_evidence:=jsonb_build_object('candidate_rule',p_rule,'project',p_project,
   'family',v_q.family_code,'category',v_q.category_raw,
   'active_source_count',jsonb_array_length(coalesce(v_active,'[]'::jsonb)),
   'active_quality_count',jsonb_array_length(coalesce(v_registry,'[]'::jsonb)),
   'duplicate_rule',v_dup,'conflict_rule',v_conflict,
   'candidate_fingerprint_sha256',v_fp->>'sha256',
   'identity_mode','L17_HMAC_SIGNED_PG18_SANDBOX_NOT_SUPABASE',
   'curator_mode','DETERMINISTIC_SQL_SAME_GPT_AUTHOR_NOT_INDEPENDENT');
 v_signed:=jsonb_build_object('project',p_project,'rule',p_rule,'verdict',v_verdict,
   'reason',v_reason,'reason_text',v_text,'evidence',v_evidence,
   'fingerprint',v_fp->>'sha256','actor',v_actor,'owner_profile',v_fowner);
 v_seal:=l23_curator_seal_v1(v_signed);
 INSERT INTO l23_curator_verdicts(project_code,rule_code,verdict,reason_code,reason_text,
   evidence,candidate_fingerprint_sha256,actor_code,owner_profile_code,seal_hmac_sha256)
 VALUES(p_project,p_rule,v_verdict,v_reason,v_text,v_evidence,v_fp->>'sha256',
   v_actor,v_fowner,v_seal)
 ON CONFLICT(project_code,rule_code) DO UPDATE
 SET verdict=EXCLUDED.verdict,reason_code=EXCLUDED.reason_code,
 reason_text=EXCLUDED.reason_text,evidence=EXCLUDED.evidence,
 candidate_fingerprint_sha256=EXCLUDED.candidate_fingerprint_sha256,
 actor_code=EXCLUDED.actor_code,owner_profile_code=EXCLUDED.owner_profile_code,
 seal_hmac_sha256=EXCLUDED.seal_hmac_sha256,evaluated_at=clock_timestamp();
 RETURN jsonb_build_object('verdict',v_verdict,'reason_code',v_reason,'reason_text',v_text,
  'evidence',v_evidence,'actor_code',v_actor,'fingerprint_sha256',v_fp->>'sha256',
  'seal_hmac_sha256',v_seal,'gate_precondition',(v_verdict='ACEPTAR'),
  'production_attested',false,'independent_curator_attested',false);
END $fn$;

CREATE FUNCTION l23_curator_evaluate_v1(p_project text,p_rule text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=rule_quality_l13,pg_temp AS $fn$
BEGIN
 PERFORM l17_assert_request_current_user_v2(p_project);
 RETURN l23_curator_evaluate_internal_v1(p_project,p_rule);
END $fn$;

-- Security-critical precondition: HMAC receipt, actor, fingerprint, family owner,
-- independent recompute of canonical candidate+VIGENTE sets.
CREATE FUNCTION l23_curator_require_v1(p_project text,p_rule text,p_actor text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_row l23_curator_verdicts%ROWTYPE;v_fp text;v_seal text;
 v_signed jsonb;v_identity jsonb;v_owner text;
BEGIN
 SELECT * INTO v_row FROM l23_curator_verdicts
 WHERE project_code=p_project AND rule_code=p_rule FOR UPDATE;
 IF NOT FOUND OR v_row.verdict IS DISTINCT FROM 'ACEPTAR' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L23_CURATOR_NOT_ACCEPTED';
 END IF;
 v_identity:=l17_verify_signed_claim_v2(p_project);
 IF v_row.actor_code IS DISTINCT FROM p_actor OR
   v_row.actor_code IS DISTINCT FROM v_identity->>'actor_code' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L23_CURATOR_ACTOR_MISMATCH';
 END IF;
 SELECT owner_profile_code INTO v_owner FROM families
 WHERE project_code=p_project AND family_code=(SELECT family_code FROM rules
 WHERE project_code=p_project AND rule_code=p_rule);
 IF v_owner IS DISTINCT FROM v_row.owner_profile_code OR NOT EXISTS (
  SELECT 1 FROM actors a WHERE a.project_code=p_project AND a.actor_code=p_actor
  AND a.profile_code=v_owner AND a.can_approve AND upper(a.profile_code)<>'SUPER_ADMIN') THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L23_CURATOR_OWNER_STALE';
 END IF;
 v_signed:=jsonb_build_object('project',v_row.project_code,'rule',v_row.rule_code,
   'verdict',v_row.verdict,'reason',v_row.reason_code,'reason_text',v_row.reason_text,
   'evidence',v_row.evidence,'fingerprint',v_row.candidate_fingerprint_sha256,
   'actor',v_row.actor_code,'owner_profile',v_row.owner_profile_code);
 v_seal:=l23_curator_seal_v1(v_signed);
 IF v_row.seal_hmac_sha256 IS DISTINCT FROM v_seal THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L23_CURATOR_SEAL_INVALID';
 END IF;
 v_fp:=l23_curator_fingerprint_v1(p_project,p_rule)->>'sha256';
 IF v_row.candidate_fingerprint_sha256 IS DISTINCT FROM v_fp THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L23_CURATOR_SNAPSHOT_STALE';
 END IF;
END $fn$;

-- L14 wrapper unmodified: it must INSERT/UPSERT ARMED activation_ticket BEFORE the
-- frozen LF apply or SALY fixture. This trigger vetoes that INSERT on missing/bad Curator.
CREATE FUNCTION l23_curator_activation_ticket_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=rule_quality_l13,pg_temp AS $fn$
BEGIN
 IF NEW.status='ARMED' THEN
  PERFORM l23_curator_require_v1(NEW.project_code,NEW.rule_code,NEW.actor_role);
 END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER trg_l23_curator_before_activation
 BEFORE INSERT OR UPDATE OF status,actor_role ON activation_tickets
 FOR EACH ROW EXECUTE FUNCTION l23_curator_activation_ticket_guard_v1();

-- Defense in depth: no direct DML, no unauthenticated interface, no signing oracle.
REVOKE ALL ON l23_curator_verdicts FROM PUBLIC,l17_authenticator,
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
REVOKE ALL ON FUNCTION l23_curator_fingerprint_v1(text,text),
 l23_curator_seal_v1(jsonb),l23_curator_evaluate_internal_v1(text,text),
 l23_curator_evaluate_v1(text,text),l23_curator_require_v1(text,text,text)
 FROM PUBLIC,l17_authenticator,lf_owner_role,lf_super_role,lf_reader_role,
 saly_owner_role,saly_super_role;
GRANT EXECUTE ON FUNCTION l23_curator_evaluate_v1(text,text),
 l23_curator_evaluate_internal_v1(text,text)
 TO lf_owner_role,saly_owner_role;
-- Only security-definer internal code invokes seal/fingerprint/require.

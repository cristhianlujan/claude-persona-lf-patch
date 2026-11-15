-- IG: Curator-owned deterministic B2B policy source binder, generic by channel + screen operation.
-- CANDIDATO policy and links remain CANDIDATO. Never promotes rules or simulates QA.
-- Existing B2B authentication (including screen 51) is explicitly excluded.
BEGIN;

CREATE TABLE IF NOT EXISTS programacion.input_policy_autobind_receipts_v1 (
  receipt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pantalla_id integer NOT NULL REFERENCES lf_ops.pantallas(id),
  family_code text NOT NULL CHECK (family_code IN
    ('SESSION','RATE_LIMIT','TIMEOUT_RETRY','IDEMPOTENCY_CONCURRENCY')),
  reference_role text NOT NULL,
  policy_kind text NOT NULL,
  policy_code text NOT NULL,
  policy_numeric_id bigint NOT NULL,
  pantalla_politica_id bigint NOT NULL REFERENCES lf_ops.pantallas_politicas(pantalla_politica_id),
  source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
  source_status text NOT NULL,
  evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
  curator_identity text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(pantalla_id,family_code,reference_role,source_sha256)
);

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_policy_autobind_v1(
  p_pantalla_id integer,p_consumer text,p_curator_identity text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops','public'
AS $binder$
DECLARE
  v_screen lf_ops.pantallas%rowtype;
  v_upload boolean:=false;
  d record;
  v_policy jsonb;
  v_policy_id bigint;
  v_status text;
  v_source_count integer;
  v_valid_rules integer;
  v_link lf_ops.pantallas_politicas%rowtype;
  v_rows integer;
  v_inserted boolean;
  v_sha text;
  v_write_count integer:=0;
  v_bindings jsonb:='[]'::jsonb;
  v_findings jsonb:='[]'::jsonb;
BEGIN
  SELECT * INTO v_screen FROM lf_ops.pantallas WHERE id=p_pantalla_id AND activa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_SCREEN_NOT_FOUND:%',p_pantalla_id;
  END IF;
  IF v_screen.module_code NOT LIKE 'B2B_%' OR v_screen.module_code='B2B_AUTENTICACION' THEN
    RETURN jsonb_build_object('status','NOT_APPLICABLE','write_count',0,
      'channel',coalesce(v_screen.module_code,'UNKNOWN'),
      'bindings','[]'::jsonb,'findings','[]'::jsonb);
  END IF;

  SELECT EXISTS(SELECT 1 FROM lf_ops.pantalla_elementos pe
    WHERE pe.pantalla_id=p_pantalla_id AND pe.element_role='UPLOAD_DROPZONE'
      AND pe.required_for_implementation AND pe.status<>'DEPRECATED')
    INTO v_upload;

  FOR d IN SELECT * FROM (
    VALUES
    ('SESSION','SESSION','b2b_session_policy_id',
      'SESSION-B2B-DEFAULT','B2B_APP_SHELL','[399,400]'::jsonb,true),
    ('RATE_LIMIT','RATE_LIMIT','upload_rate_limit_policy_id',
      'RATE-B2B-UPLOAD','FILE_UPLOAD','[418]'::jsonb,v_upload),
    ('TIMEOUT_RETRY','TIMEOUT','upload_timeout_policy_id',
      'TIMEOUT-B2B-UPLOAD','FILE_UPLOAD','[417]'::jsonb,v_upload),
    ('TIMEOUT_RETRY','TIMEOUT','validation_timeout_policy_id',
      'TIMEOUT-B2B-VALIDATION','FILE_VALIDATION','[417]'::jsonb,v_upload),
    ('TIMEOUT_RETRY','TIMEOUT','processing_timeout_policy_id',
      'TIMEOUT-B2B-PROCESSING','LOAD_PROCESSING','[417]'::jsonb,v_upload),
    ('IDEMPOTENCY_CONCURRENCY','SECURITY','idempotency_security_policy_id',
      'SEC-B2B-IDEMPOTENCY','upload','[403]'::jsonb,v_upload)
  ) AS desired(family_code,policy_kind,reference_role,policy_code,operation_code,rule_ids,applicable)
  WHERE desired.applicable
  LOOP
    v_policy:=NULL; v_policy_id:=NULL; v_status:=NULL; v_source_count:=0;
    CASE d.policy_kind
    WHEN 'SESSION' THEN
      SELECT count(*),min(session_policy_id) INTO v_source_count,v_policy_id
      FROM lf_ops.politicas_sesion
      WHERE policy_code=d.policy_code AND scope_code=d.operation_code AND status='VIGENTE';
      IF v_source_count=1 THEN
        SELECT to_jsonb(p),p.status INTO v_policy,v_status
        FROM lf_ops.politicas_sesion p WHERE p.session_policy_id=v_policy_id;
      END IF;
    WHEN 'RATE_LIMIT' THEN
      SELECT count(*),min(rate_limit_policy_id) INTO v_source_count,v_policy_id
      FROM lf_ops.politicas_rate_limit
      WHERE policy_code=d.policy_code AND resource_code=d.operation_code
        AND scope_key='TENANT_USER' AND window_seconds>0 AND max_requests>0
        AND status IN ('CANDIDATO','VIGENTE');
      IF v_source_count=1 THEN
        SELECT to_jsonb(p),p.status INTO v_policy,v_status
        FROM lf_ops.politicas_rate_limit p WHERE p.rate_limit_policy_id=v_policy_id;
      END IF;
    WHEN 'TIMEOUT' THEN
      SELECT count(*),min(timeout_policy_id) INTO v_source_count,v_policy_id
      FROM lf_ops.politicas_timeout
      WHERE policy_code=d.policy_code AND operation_code=d.operation_code
        AND timeout_seconds>0 AND retry_limit>=0 AND status IN ('CANDIDATO','VIGENTE');
      IF v_source_count=1 THEN
        SELECT to_jsonb(p),p.status INTO v_policy,v_status
        FROM lf_ops.politicas_timeout p WHERE p.timeout_policy_id=v_policy_id;
      END IF;
    WHEN 'SECURITY' THEN
      SELECT count(*),min(security_policy_id) INTO v_source_count,v_policy_id
      FROM lf_ops.politicas_seguridad
      WHERE policy_code=d.policy_code AND category='INTEGRITY'
        AND policy_config->'actions' ? d.operation_code
        AND status IN ('CANDIDATO','VIGENTE');
      IF v_source_count=1 THEN
        SELECT to_jsonb(p),p.status INTO v_policy,v_status
        FROM lf_ops.politicas_seguridad p WHERE p.security_policy_id=v_policy_id;
      END IF;
    END CASE;
    IF v_source_count<>1 OR v_policy IS NULL THEN
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'family_code',d.family_code,'reference_role',d.reference_role,
        'code','POLICY_SOURCE_MISSING_OR_AMBIGUOUS','source_count',v_source_count));
      CONTINUE;
    END IF;

    SELECT count(*) INTO v_valid_rules
    FROM jsonb_array_elements_text(d.rule_ids) refs(id_text)
    JOIN lf_ops.reglas r ON r.id=refs.id_text::integer
    JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id AND rp.pantalla_id=p_pantalla_id
    WHERE (d.family_code='IDEMPOTENCY_CONCURRENCY' AND r.estado='CANDIDATO')
       OR (d.family_code<>'IDEMPOTENCY_CONCURRENCY' AND r.estado='VIGENTE');
    IF v_valid_rules<>jsonb_array_length(d.rule_ids) THEN
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'family_code',d.family_code,'reference_role',d.reference_role,
        'code','POLICY_RULE_SOURCE_MISSING','matched',v_valid_rules));
      CONTINUE;
    END IF;

    v_inserted:=false;
    INSERT INTO lf_ops.pantallas_politicas(
      pantalla_id,policy_kind,reference_role,
      rate_limit_policy_id,timeout_policy_id,session_policy_id,security_policy_id,status
    ) VALUES (
      p_pantalla_id,d.policy_kind,d.reference_role,
      CASE WHEN d.policy_kind='RATE_LIMIT' THEN v_policy_id ELSE NULL END,
      CASE WHEN d.policy_kind='TIMEOUT' THEN v_policy_id ELSE NULL END,
      CASE WHEN d.policy_kind='SESSION' THEN v_policy_id ELSE NULL END,
      CASE WHEN d.policy_kind='SECURITY' THEN v_policy_id ELSE NULL END,
      'CANDIDATO'
    ) ON CONFLICT (pantalla_id,reference_role) DO NOTHING;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    v_inserted:=v_rows=1;
    v_write_count:=v_write_count+v_rows;

    SELECT * INTO v_link FROM lf_ops.pantallas_politicas pp
    WHERE pp.pantalla_id=p_pantalla_id AND pp.reference_role=d.reference_role;
    IF NOT FOUND OR v_link.policy_kind<>d.policy_kind
      OR (CASE d.policy_kind
          WHEN 'RATE_LIMIT' THEN v_link.rate_limit_policy_id
          WHEN 'TIMEOUT' THEN v_link.timeout_policy_id
          WHEN 'SESSION' THEN v_link.session_policy_id
          ELSE v_link.security_policy_id END) IS DISTINCT FROM v_policy_id
      OR v_link.status NOT IN ('CANDIDATO','VIGENTE') THEN
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
        'family_code',d.family_code,'reference_role',d.reference_role,
        'code','POLICY_SCREEN_LINK_CONFLICT_NO_OVERWRITE'));
      CONTINUE;
    END IF;

    INSERT INTO lf_ops.pantallas_politicas_reglas(pantalla_politica_id,regla_id)
    SELECT v_link.pantalla_politica_id,x.value::integer
    FROM jsonb_array_elements_text(d.rule_ids) x(value)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    v_write_count:=v_write_count+v_rows;

    v_sha:=programacion.fn_v09_sha256_jsonb(v_policy);
    IF v_inserted THEN
      INSERT INTO programacion.input_policy_autobind_receipts_v1(
        pantalla_id,family_code,reference_role,policy_kind,policy_code,
        policy_numeric_id,pantalla_politica_id,source_sha256,source_status,evidence,curator_identity
      ) VALUES (
        p_pantalla_id,d.family_code,d.reference_role,d.policy_kind,d.policy_code,
        v_policy_id,v_link.pantalla_politica_id,v_sha,v_status,
        jsonb_build_object('channel',v_screen.module_code,'operation',d.operation_code,
          'rule_ids',d.rule_ids,'source_kind','EXISTING_POLICY_CATALOG',
          'policy_link_status',v_link.status,'source_sha256',v_sha,
          'production_authorized',false,'promotion_authorized',false),
        p_curator_identity
      ) ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_rows=ROW_COUNT;
      v_write_count:=v_write_count+v_rows;
    END IF;
    v_bindings:=v_bindings||jsonb_build_array(jsonb_build_object(
      'family_code',d.family_code,'reference_role',d.reference_role,
      'policy_code',d.policy_code,'policy_id',v_policy_id,
      'policy_status',v_status,'screen_link_id',v_link.pantalla_politica_id,
      'screen_link_status',v_link.status,'policy_sha256',v_sha,
      'new_screen_link',v_inserted));
  END LOOP;

  RETURN jsonb_build_object('status','EVIDENCE_FIRST_POLICY_AUTOBIND',
    'screen_id',p_pantalla_id,'channel',v_screen.module_code,
    'consumer',p_consumer,'write_count',v_write_count,
    'bindings',v_bindings,'findings',v_findings,
    'continuation_allowed',true,'production_authorized',false,
    'promotion_authorized',false);
END
$binder$;

CREATE OR REPLACE FUNCTION programacion.fn_input_policy_autobind_coverage_v1(
 p_pantalla_id integer,p_family_code text,p_version_id bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','programacion','lf_ops','public'
AS $cover$
DECLARE
  v_module text;
  v_upload boolean;
  v_expected integer;
  v_count integer:=0;
  v_evidence jsonb:='[]'::jsonb;
  v_rule_count integer;
  v_source_sha text;
BEGIN
  IF p_family_code NOT IN ('SESSION','RATE_LIMIT','TIMEOUT_RETRY','IDEMPOTENCY_CONCURRENCY') THEN
    RETURN jsonb_build_object('handled',false);
  END IF;
  SELECT module_code INTO v_module FROM lf_ops.pantallas
  WHERE id=p_pantalla_id AND activa;
  IF v_module IS NULL OR v_module NOT LIKE 'B2B_%'
     OR v_module='B2B_AUTENTICACION' THEN
    RETURN jsonb_build_object('handled',false,'reason','CHANNEL_OR_AUTH_SCREEN_EXCLUDED');
  END IF;
  SELECT EXISTS(SELECT 1 FROM lf_ops.pantalla_elementos
    WHERE pantalla_id=p_pantalla_id AND element_role='UPLOAD_DROPZONE'
      AND required_for_implementation AND status<>'DEPRECATED') INTO v_upload;
  IF p_family_code<>'SESSION' AND NOT v_upload THEN
    RETURN jsonb_build_object('handled',false,'reason','UPLOAD_OPERATION_NOT_PRESENT');
  END IF;

  v_expected:=CASE p_family_code WHEN 'TIMEOUT_RETRY' THEN 3 ELSE 1 END;
  SELECT count(*),coalesce(jsonb_agg(jsonb_build_object(
      'reference_role',pp.reference_role,'policy_kind',pp.policy_kind,
      'policy_code',r.policy_code,'policy_status',r.source_status,
      'source_sha256',r.source_sha256,'link_status',pp.status)
      ORDER BY pp.reference_role),'[]'::jsonb)
  INTO v_count,v_evidence
  FROM programacion.input_policy_autobind_receipts_v1 r
  JOIN lf_ops.pantallas_politicas pp
    ON pp.pantalla_politica_id=r.pantalla_politica_id
   AND pp.pantalla_id=r.pantalla_id AND pp.reference_role=r.reference_role
   AND pp.status IN ('CANDIDATO','VIGENTE')
  WHERE r.pantalla_id=p_pantalla_id AND r.family_code=p_family_code
    AND (
      (p_family_code='SESSION' AND r.reference_role='b2b_session_policy_id'
       AND pp.policy_kind='SESSION' AND pp.session_policy_id=r.policy_numeric_id
       AND EXISTS(SELECT 1 FROM lf_ops.politicas_sesion p
         WHERE p.session_policy_id=r.policy_numeric_id
           AND p.policy_code='SESSION-B2B-DEFAULT' AND p.status='VIGENTE'
           AND p.scope_code='B2B_APP_SHELL'
           AND programacion.fn_v09_sha256_jsonb(to_jsonb(p))=r.source_sha256)
       AND (SELECT count(*) FROM lf_ops.pantallas_politicas_reglas x
         WHERE x.pantalla_politica_id=pp.pantalla_politica_id AND x.regla_id IN(399,400))=2)
      OR
      (p_family_code='RATE_LIMIT' AND r.reference_role='upload_rate_limit_policy_id'
       AND pp.policy_kind='RATE_LIMIT' AND pp.rate_limit_policy_id=r.policy_numeric_id
       AND EXISTS(SELECT 1 FROM lf_ops.politicas_rate_limit p
         WHERE p.rate_limit_policy_id=r.policy_numeric_id
           AND p.policy_code='RATE-B2B-UPLOAD' AND p.resource_code='FILE_UPLOAD'
           AND p.status IN ('CANDIDATO','VIGENTE')
           AND programacion.fn_v09_sha256_jsonb(to_jsonb(p))=r.source_sha256)
       AND EXISTS(SELECT 1 FROM lf_ops.pantallas_politicas_reglas x
         WHERE x.pantalla_politica_id=pp.pantalla_politica_id AND x.regla_id=418))
      OR
      (p_family_code='TIMEOUT_RETRY' AND pp.policy_kind='TIMEOUT'
       AND pp.timeout_policy_id=r.policy_numeric_id
       AND ((r.reference_role='upload_timeout_policy_id' AND r.policy_code='TIMEOUT-B2B-UPLOAD')
         OR (r.reference_role='validation_timeout_policy_id' AND r.policy_code='TIMEOUT-B2B-VALIDATION')
         OR (r.reference_role='processing_timeout_policy_id' AND r.policy_code='TIMEOUT-B2B-PROCESSING'))
       AND EXISTS(SELECT 1 FROM lf_ops.politicas_timeout p
         WHERE p.timeout_policy_id=r.policy_numeric_id
           AND p.policy_code=r.policy_code AND p.status IN ('CANDIDATO','VIGENTE')
           AND programacion.fn_v09_sha256_jsonb(to_jsonb(p))=r.source_sha256)
       AND EXISTS(SELECT 1 FROM lf_ops.pantallas_politicas_reglas x
         WHERE x.pantalla_politica_id=pp.pantalla_politica_id AND x.regla_id=417))
      OR
      (p_family_code='IDEMPOTENCY_CONCURRENCY'
       AND r.reference_role='idempotency_security_policy_id'
       AND pp.policy_kind='SECURITY' AND pp.security_policy_id=r.policy_numeric_id
       AND EXISTS(SELECT 1 FROM lf_ops.politicas_seguridad p
         WHERE p.security_policy_id=r.policy_numeric_id
           AND p.policy_code='SEC-B2B-IDEMPOTENCY'
           AND p.status IN ('CANDIDATO','VIGENTE')
           AND programacion.fn_v09_sha256_jsonb(to_jsonb(p))=r.source_sha256)
       AND EXISTS(SELECT 1 FROM lf_ops.pantallas_politicas_reglas x
         WHERE x.pantalla_politica_id=pp.pantalla_politica_id AND x.regla_id=403))
    );

  IF v_count<>v_expected THEN
    RETURN jsonb_build_object('handled',false,'reason','POLICY_AUTOBIND_EVIDENCE_INCOMPLETE',
      'family_code',p_family_code,'verified_count',v_count,'required_count',v_expected);
  END IF;
  v_source_sha:=programacion.fn_v09_sha256_jsonb(v_evidence);
  RETURN jsonb_build_object(
    'handled',true,'family_code',p_family_code,'level','COMPLETE',
    'severity','P1','blocker_code','POLICY_AUTOBIND_IMPLEMENTATION_QA_PENDING',
    'stage_statuses',jsonb_build_object('story','READY','implementation','NOT_READY',
       'qa','BLOCKED','production','BLOCKED'),
    'stage_blockers',jsonb_build_array(jsonb_build_object(
       'code','POLICY_AUTOBIND_IMPLEMENTATION_QA_PENDING',
       'earliest_blocking_stage','IMPLEMENTATION',
       'dependency_ref','IG_POLICY_AUTOBIND_QA',
       'state','READY_WITH_DEPENDENCY','uncertainty_type','IMPLEMENTATION_DEPENDENCY')),
    'probe',jsonb_build_object('resolution_contract','IG_POLICY_AUTOBIND_COVERAGE_V1',
       'channel',v_module,'operation_qualified',v_upload,
       'policy_binding_count',v_count,'source_links',v_evidence,
       'evidence_sha256',v_source_sha,'implementation_tested',false,
       'policy_promotion_authorized',false,'production_authorized',false,
       'session_context_contract_still_required',p_family_code='SESSION')
  );
END
$cover$;

DO $patch$
DECLARE
  v_def text;
  v_old text;
  v_new text;
  v_sig regprocedure;
BEGIN
  -- Source guard: preserve exact current Curator and all existing branches.
  v_sig:='programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure;
  v_def:=pg_get_functiondef(v_sig);
  IF md5(v_def)<>'071fdce8c6ac9851e8106afd511fd3fb' THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_CURATOR_SOURCE_DRIFT';
  END IF;
  v_old:=$old$  v_plan jsonb;$old$;
  v_new:=$new$  v_plan jsonb;
  v_policy_autobind jsonb;$new$;
  IF (length(v_def)-length(replace(v_def,v_old,'')))<>length(v_old) THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_CURATOR_DECL_ANCHOR';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=$old$  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);$old$;
  v_new:=$new$  v_policy_autobind:=programacion.fn_input_governance_policy_autobind_v1(
    p_pantalla_id,p_consumer,p_curator_identity);
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);$new$;
  IF (length(v_def)-length(replace(v_def,v_old,'')))<>length(v_old) THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_CURATOR_GRAPH_ANCHOR';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=$old$  v_strategy:=v_plan->>'strategy';$old$;
  v_new:=$new$  v_strategy:=v_plan->>'strategy';
  IF coalesce((v_policy_autobind->>'write_count')::integer,0)>0
     AND v_strategy NOT IN ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_WRITE_WITHOUT_MATERIALIZATION:%',v_strategy;
  END IF;$new$;
  IF (length(v_def)-length(replace(v_def,v_old,'')))<>length(v_old) THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_CURATOR_STRATEGY_ANCHOR';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=$old$    'graph_sha256',programacion.fn_v09_sha256_jsonb(v_graph),$old$;
  v_new:=$new$    'graph_sha256',programacion.fn_v09_sha256_jsonb(v_graph),
    'policy_autobind',v_policy_autobind,$new$;
  IF (length(v_def)-length(replace(v_def,v_old,'')))<>length(v_old) THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_CURATOR_CONTEXT_ANCHOR';
  END IF;
  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;

  v_sig:='programacion.fn_input_governance_family_complete_probe_v1(integer,text,bigint,jsonb)'::regprocedure;
  v_def:=pg_get_functiondef(v_sig);
  IF md5(v_def)<>'8b811c9cf20ff4903ced50b7b4b70ba3' THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_COMPLETENESS_SOURCE_DRIFT';
  END IF;
  -- IMPORTANT: RATE_LIMIT, SESSION, TIMEOUT_RETRY have no complete_criteria_v1
  -- in registry v19. Check the governed autobind receipt BEFORE the legacy
  -- missing-criteria guard; missing receipt falls back unchanged.
  v_old:=$old$  if jsonb_typeof(v_criteria)<>'object'$old$;
  v_new:=$new$  IF p_family_code IN ('SESSION','RATE_LIMIT','TIMEOUT_RETRY','IDEMPOTENCY_CONCURRENCY') THEN
    v_sem:=programacion.fn_input_policy_autobind_coverage_v1(
      p_pantalla_id,p_family_code,p_version_id);
    IF coalesce((v_sem->>'handled')::boolean,false) THEN RETURN v_sem; END IF;
  END IF;
  if jsonb_typeof(v_criteria)<>'object'$new$;
  IF (length(v_def)-length(replace(v_def,v_old,'')))<>length(v_old) THEN
    RAISE EXCEPTION 'IG_POLICY_AUTOBIND_COMPLETENESS_ANCHOR';
  END IF;
  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;
END
$patch$;

REVOKE ALL ON TABLE programacion.input_policy_autobind_receipts_v1 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION programacion.fn_input_governance_policy_autobind_v1(integer,text,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION programacion.fn_input_policy_autobind_coverage_v1(integer,text,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON programacion.input_policy_autobind_receipts_v1 TO service_role;
GRANT EXECUTE ON FUNCTION programacion.fn_input_policy_autobind_coverage_v1(integer,text,bigint)
  TO service_role;

-- Readback of structure; no live Curator execution in this migration.
DO $post$
BEGIN
 IF to_regclass('programacion.input_policy_autobind_receipts_v1') IS NULL
   OR position('fn_input_governance_policy_autobind_v1' IN pg_get_functiondef(
     'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure))=0
   OR position('fn_input_policy_autobind_coverage_v1' IN pg_get_functiondef(
     'programacion.fn_input_governance_family_complete_probe_v1(integer,text,bigint,jsonb)'::regprocedure))=0
 THEN RAISE EXCEPTION 'IG_POLICY_AUTOBIND_POST_SOURCE_READBACK_FAILED'; END IF;
END
$post$;
COMMIT;

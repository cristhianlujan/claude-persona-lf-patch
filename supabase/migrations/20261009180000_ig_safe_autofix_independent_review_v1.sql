CREATE OR REPLACE FUNCTION public.lf_input_safe_autofix_independent_review_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $fn$
DECLARE
  c_marker constant text := 'derive:DERIVE_FROM_VIGENTE_RULE_EXPLICIT_VALUE:COMPONENT_TOKEN_CODE_TO_ID:v1';
  v_pant        integer;
  v_found       boolean := false;
  v_mod_id      bigint;
  v_mod_code    text;
  v_shell_id    bigint;
  v_shell_code  text;
  v_ds_id       bigint;
  v_ds_code     text;
  v_ds          bigint[] := array[]::bigint[];
  v_checked     integer := 0;
  v_findings    jsonb := '[]'::jsonb;
  e             record;
  v_codes       text[];
  v_rules       text[];
  v_bad_rules   text[];
  v_has_cand    boolean;
  v_exp_status  text;
  v_tok_code    text;
  v_tok_status  text;
  v_tok_ds      bigint;
  v_tok_found   boolean;
  v_vig_count   integer;
BEGIN
  SELECT r.pantalla_id INTO v_pant
  FROM programacion.input_readiness_runs r
  WHERE r.id = p_run_id;
  v_found := FOUND;

  IF NOT v_found OR v_pant IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version', 'LF_SAFE_AUTOFIX_INDEPENDENT_REVIEW_V1',
      'run_id', p_run_id,
      'pantalla_id', NULL,
      'checked_count', 0,
      'failed_count', 1,
      'verdict', 'BLOCKED',
      'findings', jsonb_build_array(jsonb_build_object(
        'element_id', NULL, 'code', 'RUN_NOT_FOUND',
        'detail', 'run id not found or without pantalla_id'))
    );
  END IF;

  -- Raw design-system resolution: pantalla -> modulo -> app_shell -> design_system
  SELECT p.module_id, p.module_code INTO v_mod_id, v_mod_code
  FROM lf_ops.pantallas p WHERE p.id = v_pant;

  SELECT m.app_shell_id, m.app_shell_code INTO v_shell_id, v_shell_code
  FROM lf_ops.modulos m
  WHERE (v_mod_id IS NOT NULL AND m.module_id = v_mod_id)
     OR (v_mod_id IS NULL AND m.module_code = v_mod_code)
  ORDER BY m.module_id
  LIMIT 1;

  SELECT s.design_system_id, s.design_system_code INTO v_ds_id, v_ds_code
  FROM lf_ops.app_shells s
  WHERE (v_shell_id IS NOT NULL AND s.app_shell_id = v_shell_id)
     OR (v_shell_id IS NULL AND s.app_shell_code = v_shell_code)
  ORDER BY s.app_shell_id
  LIMIT 1;

  SELECT coalesce(array_agg(d.design_system_id), array[]::bigint[]) INTO v_ds
  FROM lf_design.design_systems d
  WHERE (v_ds_id IS NOT NULL AND d.design_system_id = v_ds_id)
     OR (v_ds_id IS NULL AND d.design_system_code = v_ds_code);

  FOR e IN
    SELECT pe.element_id, pe.component_token_id, pe.semantic_binding_status,
           pe.status, pe.source_refs
    FROM lf_ops.pantalla_elementos pe
    WHERE pe.pantalla_id = v_pant
      AND jsonb_typeof(pe.source_refs) = 'array'
      AND pe.source_refs @> to_jsonb(c_marker)
    ORDER BY pe.element_id
  LOOP
    v_checked := v_checked + 1;

    SELECT array_agg(DISTINCT substr(x, 22)) INTO v_codes
    FROM jsonb_array_elements_text(e.source_refs) AS t(x)
    WHERE x LIKE 'component_token_code:%';

    SELECT array_agg(DISTINCT substr(x, 6)) INTO v_rules
    FROM jsonb_array_elements_text(e.source_refs) AS t(x)
    WHERE x LIKE 'rule:%';

    -- (a)
    IF v_codes IS NULL OR array_length(v_codes, 1) <> 1 OR v_codes[1] = '' THEN
      v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
        'code', 'SOURCE_CONFLICT_OR_MISSING_CODE',
        'detail', 'distinct component_token_code refs: ' || coalesce(array_to_string(v_codes, ','), '<none>'));
    END IF;

    -- (b)
    IF v_rules IS NULL THEN
      v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
        'code', 'RULE_NOT_ACTIVE_OR_PENDING', 'detail', 'no rule: source_ref');
      v_has_cand := false;
    ELSE
      SELECT array_agg(q.rc) INTO v_bad_rules
      FROM unnest(v_rules) AS q(rc)
      WHERE NOT EXISTS (
        SELECT 1 FROM lf_ops.reglas rg
        WHERE rg.codigo = q.rc
          AND rg.estado IN ('VIGENTE', 'CANDIDATO')
          AND coalesce(rg.pendiente_decision, false) = false);
      IF v_bad_rules IS NOT NULL THEN
        v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
          'code', 'RULE_NOT_ACTIVE_OR_PENDING',
          'detail', 'rules not active/exist/pending: ' || array_to_string(v_bad_rules, ','));
      END IF;
      SELECT EXISTS (
        SELECT 1 FROM lf_ops.reglas rg
        WHERE rg.codigo = ANY (v_rules) AND rg.estado = 'CANDIDATO') INTO v_has_cand;
    END IF;

    -- (c)
    SELECT t.component_token_code, t.status, t.design_system_id, true
      INTO v_tok_code, v_tok_status, v_tok_ds, v_tok_found
    FROM lf_design.component_tokens t
    WHERE e.component_token_id IS NOT NULL
      AND t.component_token_id = e.component_token_id;
    IF NOT coalesce(v_tok_found, false) THEN
      v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
        'code', 'TOKEN_MISMATCH',
        'detail', 'component_token_id ' || coalesce(e.component_token_id::text, 'NULL') || ' not found');
    ELSE
      IF v_codes IS NOT NULL AND array_length(v_codes, 1) = 1
         AND v_tok_code IS DISTINCT FROM v_codes[1] THEN
        v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
          'code', 'TOKEN_MISMATCH',
          'detail', 'token code ' || coalesce(v_tok_code, 'NULL') || ' <> source code ' || v_codes[1]);
      END IF;
      IF v_tok_status IS DISTINCT FROM 'VIGENTE' THEN
        v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
          'code', 'TOKEN_MISMATCH',
          'detail', 'token status ' || coalesce(v_tok_status, 'NULL') || ' is not VIGENTE');
      END IF;
      IF v_tok_ds IS NULL OR NOT (v_tok_ds = ANY (v_ds)) THEN
        v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
          'code', 'DESIGN_SYSTEM_MISMATCH',
          'detail', 'token design_system_id ' || coalesce(v_tok_ds::text, 'NULL')
                    || ' not in screen design systems ' || array_to_string(v_ds, ','));
      END IF;
    END IF;

    IF v_codes IS NOT NULL AND array_length(v_codes, 1) = 1 THEN
      SELECT count(*) INTO v_vig_count
      FROM lf_design.component_tokens t
      WHERE t.component_token_code = v_codes[1]
        AND t.status = 'VIGENTE'
        AND t.design_system_id = ANY (v_ds);
      IF v_vig_count <> 1 THEN
        v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
          'code', 'TOKEN_NOT_UNIQUE_VIGENTE',
          'detail', v_vig_count::text || ' VIGENTE tokens with code ' || v_codes[1] || ' in screen design system');
      END IF;
    END IF;

    -- (d)
    IF e.semantic_binding_status IS DISTINCT FROM 'RESOLVED_ID' THEN
      v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
        'code', 'BINDING_STATUS_NOT_RESOLVED',
        'detail', 'semantic_binding_status=' || coalesce(e.semantic_binding_status, 'NULL'));
    END IF;

    -- (e)
    IF e.status IS DISTINCT FROM 'INACTIVO' THEN
      v_exp_status := CASE WHEN coalesce(v_has_cand, false) THEN 'CANDIDATO' ELSE 'VIGENTE' END;
      IF e.status IS DISTINCT FROM v_exp_status THEN
        v_findings := v_findings || jsonb_build_object('element_id', e.element_id,
          'code', 'STATUS_MISMATCH',
          'detail', 'status=' || coalesce(e.status, 'NULL') || ' expected ' || v_exp_status);
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'schema_version', 'LF_SAFE_AUTOFIX_INDEPENDENT_REVIEW_V1',
    'run_id', p_run_id,
    'pantalla_id', v_pant,
    'checked_count', v_checked,
    'failed_count', jsonb_array_length(v_findings),
    'verdict', CASE WHEN v_checked = 0 THEN 'NOT_APPLICABLE'
                    WHEN jsonb_array_length(v_findings) = 0 THEN 'PASS'
                    ELSE 'FAIL' END,
    'findings', v_findings
  );
END;
$fn$;

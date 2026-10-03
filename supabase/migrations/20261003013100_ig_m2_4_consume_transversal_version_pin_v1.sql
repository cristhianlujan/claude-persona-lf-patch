-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M2.4 / PAULO-020
-- Consumer cutover: remove private version pins from reachable IG runtime functions.
-- Depends on: 20261003013000_ig_m2_4_transversal_version_pin_v1.sql.
-- Owner: SUPER_ADMIN.
-- EKB: IG-M2-4-PRIVATE-VERSION-PIN-DRIFT-001.

DO $pre$
DECLARE
  v_pin jsonb;
BEGIN
  IF to_regprocedure('public.fn_lf_version_compatibility_resolve_source_v1(text,text,text)') IS NULL
     OR to_regprocedure('public.fn_lf_version_compatibility_current_version_id_v1(text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_M2_4_TRANSVERSAL_VERSION_PIN_SURFACE_MISSING';
  END IF;

  v_pin := public.fn_lf_version_compatibility_resolve_source_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );
  IF coalesce((v_pin->>'resolved')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_M2_4_TRANSVERSAL_VERSION_PIN_NOT_RESOLVED:%',v_pin;
  END IF;
END $pre$;

DO $patch$
DECLARE
  r record;
  rep jsonb;
  v_def text;
  v_old text;
  v_new text;
  v_expr text := $$public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT')$$;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      (
        'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure,
        'ae66ae3cb58ef0c7629cb5c425179a10',
        jsonb_build_array(
          jsonb_build_array('version_id=19','version_id='||v_expr)
        )
      ),
      (
        'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure,
        '33fce181eacb0f820fcfc88e5d367692',
        jsonb_build_array(
          jsonb_build_array('v_version bigint:=19;','v_version bigint:='||v_expr||';'),
          jsonb_build_array('version_id=19','version_id=v_version'),
          jsonb_build_array('if v_contract_revision=''5.13'' then','if v_contract_revision is not null then')
        )
      ),
      (
        'programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'::regprocedure,
        'eca1d3eeced974fd4633d0f8907e228d',
        jsonb_build_array(
          jsonb_build_array('v_version bigint:=19;','v_version bigint:='||v_expr||';'),
          jsonb_build_array('v_contract_revision not in (''5.12'',''5.13'')','v_contract_revision is null')
        )
      ),
      (
        'programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure,
        'cad01f182c1aae36e00a355c3b3782a4',
        jsonb_build_array(
          jsonb_build_array(E'declare\n  v_parent record;',E'declare\n  v_version bigint:='||v_expr||E';\n  v_parent record;'),
          jsonb_build_array('version_id=19','version_id=v_version'),
          jsonb_build_array('v_contract_revision not in (''5.12'',''5.13'')','v_contract_revision is null'),
          jsonb_build_array('fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,19)','fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version)')
        )
      ),
      (
        'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure,
        '257e0258e63e39656ccb095476fb51a8',
        jsonb_build_array(
          jsonb_build_array(E'declare\n  v_parent programacion.input_readiness_runs%rowtype;',E'declare\n  v_version bigint:='||v_expr||E';\n  v_parent programacion.input_readiness_runs%rowtype;'),
          jsonb_build_array('version_id=19','version_id=v_version'),
          jsonb_build_array('v_contract_revision not in (''5.12'',''5.13'')','v_contract_revision is null'),
          jsonb_build_array('fn_input_screen_canonical_graph(p_pantalla_id,19)','fn_input_screen_canonical_graph(p_pantalla_id,v_version)'),
          jsonb_build_array('fn_input_governance_bootstrap_classify_v2_cached_v1(p_pantalla_id,v_family,19,v_graph)','fn_input_governance_bootstrap_classify_v2_cached_v1(p_pantalla_id,v_family,v_version,v_graph)')
        )
      ),
      (
        'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure,
        'c8e89ac1776e217eda12c8b6a11f7317',
        jsonb_build_array(
          jsonb_build_array('version_id=19','version_id='||v_expr)
        )
      ),
      (
        'programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure,
        '5f8bdaf0c6fc732b8fb9008d911c82e8',
        jsonb_build_array(
          jsonb_build_array('version_id=19','version_id='||v_expr)
        )
      ),
      (
        'programacion.fn_input_governance_bootstrap_validate_v1(bigint,text)'::regprocedure,
        'ccecf306a3d6ee6ac576260f82d7d64e',
        jsonb_build_array(
          jsonb_build_array(E'declare\n  v_status text;',E'declare\n  v_version bigint:='||v_expr||E';\n  v_status text;'),
          jsonb_build_array('version_id=19','version_id=v_version'),
          jsonb_build_array('fn_input_governance_bootstrap_classify_v1(v_pantalla_id,a.family_code,19)','fn_input_governance_bootstrap_classify_v1(v_pantalla_id,a.family_code,v_version)')
        )
      ),
      (
        'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure,
        'c982bf5eb6bfa4dc4fbb3efd0c7a29dd',
        jsonb_build_array(
          jsonb_build_array(E'declare\n  v_status text;',E'declare\n  v_version bigint:='||v_expr||E';\n  v_status text;'),
          jsonb_build_array('version_id=19','version_id=v_version'),
          jsonb_build_array('fn_input_governance_bootstrap_classify_v2(v_pantalla_id,a.family_code,19)','fn_input_governance_bootstrap_classify_v2(v_pantalla_id,a.family_code,v_version)')
        )
      ),
      (
        'programacion.fn_input_governance_safe_autofix_v1(bigint)'::regprocedure,
        '4a179a221611c0e35a63c1568c172a25',
        jsonb_build_array(
          jsonb_build_array('version_id=19','version_id='||v_expr)
        )
      ),
      (
        'programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint)'::regprocedure,
        '5f2c6f4384c11375b5f35e4c8c298595',
        jsonb_build_array(
          jsonb_build_array('version_id=19','version_id='||v_expr)
        )
      ),
      (
        'programacion.fn_input_governance_record_ekb_occurrence(text,text,text,integer,bigint,text,jsonb)'::regprocedure,
        '460218ef39c8a30226ace9c2091225b7',
        jsonb_build_array(
          jsonb_build_array('version_id=19','version_id='||v_expr)
        )
      )
    ) q(sig,expected_md5,replacements)
  LOOP
    v_def := pg_get_functiondef(r.sig);
    IF md5(v_def) <> r.expected_md5 THEN
      RAISE EXCEPTION 'M2_4_SOURCE_DRIFT:% expected=% actual=%',r.sig,r.expected_md5,md5(v_def);
    END IF;

    v_new := v_def;
    FOR rep IN SELECT value FROM jsonb_array_elements(r.replacements)
    LOOP
      v_old := rep->>0;
      IF position(v_old IN v_new)=0 THEN
        RAISE EXCEPTION 'M2_4_PATCH_ANCHOR_MISSING:% anchor=%',r.sig,v_old;
      END IF;
      v_new := replace(v_new,v_old,rep->>1);
    END LOOP;

    EXECUTE v_new;
  END LOOP;
END $patch$;

DO $relations$
DECLARE
  v_batch uuid := gen_random_uuid();
  v_exec text := 'CHATGPT-IG-CV-M2-4-T-SOURCE-20261003';
  v_asset text;
BEGIN
  FOREACH v_asset IN ARRAY ARRAY[
    'PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET',
    'PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET',
    'PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET',
    'PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_activo_relaciones
      WHERE codigo_activo=v_asset
        AND relacionado_codigo='CAPABILITY_VERSION_COMPATIBILITY'
        AND relacion_tipo='DEPENDE_DE'
    ) THEN
      INSERT INTO public.lf_activo_relaciones(
        codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
        migration_batch_id,created_by_execution_id
      ) VALUES (
        v_asset,'CAPABILITY_VERSION_COMPATIBILITY','DEPENDE_DE','TRANSVERSAL_VERSION_PIN',
        'IG_CURATOR_VALIDATOR_REFACTOR_V2:M2.4',v_batch,v_exec
      );
    END IF;
  END LOOP;
END $relations$;

DO $post$
DECLARE
  v_bad integer;
  v_pin jsonb;
  v_spec jsonb;
BEGIN
  SELECT count(*) INTO v_bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion'
    AND p.oid IN (
      'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure,
      'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure,
      'programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'::regprocedure,
      'programacion.fn_input_governance_recurate_v2(integer,text,text)'::regprocedure,
      'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure,
      'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure,
      'programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure,
      'programacion.fn_input_governance_bootstrap_validate_v1(bigint,text)'::regprocedure,
      'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure,
      'programacion.fn_input_governance_safe_autofix_v1(bigint)'::regprocedure,
      'programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint)'::regprocedure,
      'programacion.fn_input_governance_record_ekb_occurrence(text,text,text,integer,bigint,text,jsonb)'::regprocedure
    )
    AND (
      p.prosrc ~ 'version_id\s*=\s*19'
      OR p.prosrc ~ 'v_version\s*[:=]+\s*19'
    );

  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'M2_4_PRIVATE_VERSION_PIN_REMAINS:%',v_bad;
  END IF;

  v_pin := public.fn_lf_version_compatibility_resolve_source_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );
  IF coalesce((v_pin->>'resolved')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'M2_4_SHARED_VERSION_PIN_POSTCONDITION_FAILED:%',v_pin;
  END IF;

  v_spec := programacion.fn_input_governance_worker_spec(1,'STORY_CREATOR');
  IF (v_spec->>'version_id')::bigint <> (v_pin->'version'->>'version_id')::bigint
     OR v_spec->>'readiness_contract_revision' <> v_pin->'version'->>'revision' THEN
    RAISE EXCEPTION 'M2_4_WORKER_SPEC_VERSION_PIN_DRIFT:%',v_spec;
  END IF;

  IF (SELECT count(*) FROM public.lf_activo_relaciones
      WHERE relacionado_codigo='CAPABILITY_VERSION_COMPATIBILITY'
        AND relacion_tipo='DEPENDE_DE'
        AND codigo_activo IN (
          'PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET',
          'PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET',
          'PROGRAMACION_FN_INPUT_GOVERNANCE_EKB_SET',
          'PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET'
        )) <> 4 THEN
    RAISE EXCEPTION 'M2_4_MATERIAL_RELATIONS_INCOMPLETE';
  END IF;
END $post$;

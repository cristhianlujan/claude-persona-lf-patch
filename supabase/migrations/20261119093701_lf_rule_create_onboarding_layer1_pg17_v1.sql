-- IG onboarding: CREATE-only Layer 1; existing rules and UPDATE behavior preserved.
-- Scope keys live inside valor_config, without a new table/column/process.
-- Uses the existing authorized parent profile and existing IG V2 child invocation.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_regla_candidate_write_v1(
  p_execution_id text, p_action_code text, p_codigo text, p_categoria text,
  p_titulo text, p_descripcion text, p_razon text DEFAULT NULL::text,
  p_valor_config jsonb DEFAULT NULL::jsonb, p_es_transversal boolean DEFAULT false,
  p_origen text DEFAULT NULL::text
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public','lf_ops'
AS $lf_rule_writer$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_expected text;
  v_before lf_ops.reglas%rowtype;
  v_after lf_ops.reglas%rowtype;
  v_cfg jsonb;
  v_ids jsonb;
  v_scope text;
  v_applicability text;
  v_text text;
  v_config_scope text;
  v_config_key text;
  v_review text := 'GOVERNED_CANDIDATE_REQUIRES_REVIEW';
BEGIN
  IF upper(coalesce(p_action_code,'')) NOT IN ('REGLA_CREATE','REGLA_UPDATE') THEN
    RAISE EXCEPTION 'LF_REGLA_ACTION_INVALID:%',p_action_code;
  END IF;
  IF btrim(coalesce(p_execution_id,''))='' OR btrim(coalesce(p_codigo,''))=''
    OR btrim(coalesce(p_categoria,''))='' OR btrim(coalesce(p_titulo,''))=''
    OR btrim(coalesce(p_descripcion,''))='' THEN
    RAISE EXCEPTION 'LF_REGLA_REQUIRED_INPUT_MISSING: completa codigo, categoria, titulo y descripcion';
  END IF;
  v_expected:=CASE upper(p_action_code) WHEN 'REGLA_CREATE' THEN 'CREACION_REGLA_LF'
               ELSE 'ACTUALIZACION_REGLA_LF' END;
  PERFORM 1 FROM public.lf_operation_mode_bindings b
   WHERE b.operation_code=v_expected
     AND b.task_mode=CASE WHEN upper(p_action_code)='REGLA_CREATE' THEN 'CREATE_NEW' ELSE 'REMEDIATE_EXISTING' END
     AND b.execution_mode='GOVERNED' AND b.status='ACTIVE' AND b.allowed
     AND b.write_allowed AND b.destination_kind='CANONICAL_CANDIDATE'
     AND b.input_completeness='COMPLETE_REQUIRED';
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_REGLA_GOVERNED_MODE_BINDING_MISSING:%',v_expected; END IF;
  SELECT * INTO v_exec FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_REGLA_EXECUTION_NOT_FOUND:%',p_execution_id; END IF;
  IF v_exec.operation_code<>v_expected OR v_exec.status<>'IN_PROGRESS'
     OR v_exec.target_type<>'REGLA' OR v_exec.target_code<>p_codigo THEN
    RAISE EXCEPTION 'LF_REGLA_EXECUTION_BINDING_MISMATCH';
  END IF;
  SELECT * INTO v_before FROM lf_ops.reglas WHERE codigo=p_codigo;

  IF upper(p_action_code)='REGLA_CREATE' THEN
    IF FOUND THEN RAISE EXCEPTION 'LF_REGLA_CREATE_DUPLICATE: codigo ya existe; revisa la regla %',p_codigo; END IF;
    IF btrim(coalesce(p_razon,''))='' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_REASON_REQUIRED: explica por que existe la regla en razon';
    END IF;
    IF btrim(coalesce(p_origen,''))='' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_ORIGIN_REQUIRED: identifica la fuente verificable en origen';
    END IF;
    IF p_descripcion !~* 'condici[oó]n[[:space:]]*:'
       OR p_descripcion !~* 'alcance[[:space:]]*:'
       OR p_descripcion !~* 'resultado[[:space:]]*:' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_DESCRIPTION_SECTIONS_REQUIRED: escribe Condicion:, Alcance: y Resultado: en descripcion';
    END IF;
    v_text:=concat_ws(' ',p_titulo,p_descripcion,p_razon);
    IF v_text ~* '(^|[^[:alnum:]])[0-9]+([.,][0-9]+)?[[:space:]]*(%|segundos?|minutos?|horas?|d[ií]as?|meses?|intentos?|reenv[ií]os?|soles?)'
       OR v_text ~* '(S/|US[$])[[:space:]]*[0-9]+'
       OR coalesce(p_valor_config,'{}'::jsonb)::text ~* '"[^"]*(limit|max|min|threshold|attempt|timeout|ttl|duration|window|seconds|minutes|hours|days|percent|count|retries)[^"]*"[[:space:]]*:[[:space:]]*[0-9]+' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_HARDCODED_VALUE: elimina cifras en duro; cita variable y ubicacion scope/config_key en public.lf_global_config';
    END IF;
    IF p_valor_config IS NULL OR jsonb_typeof(p_valor_config)<>'object' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_SCOPE_REQUIRED: declara lf_rule_scope en valor_config';
    END IF;
    v_cfg:=p_valor_config;
    v_scope:=upper(btrim(coalesce(v_cfg->>'lf_rule_scope','')));
    IF v_scope NOT IN ('PANTALLA','BACKEND','TRANSVERSAL') OR v_scope='' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_SCOPE_REQUIRED: declara lf_rule_scope PANTALLA, BACKEND o TRANSVERSAL en valor_config';
    END IF;
    v_ids:=coalesce(v_cfg->'lf_screen_ids','[]'::jsonb);
    IF jsonb_typeof(v_ids)<>'array' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_SCREEN_IDS_INVALID: lf_screen_ids debe ser una lista de IDs existentes';
    END IF;
    IF EXISTS(
      SELECT 1 FROM jsonb_array_elements_text(v_ids) AS ids(id)
      WHERE ids.id !~ '^[0-9]+$'
        OR NOT EXISTS(SELECT 1 FROM lf_ops.pantallas p WHERE p.id::text=ids.id)
    ) THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_SCREEN_IDS_INVALID: usa IDs existentes en lf_ops.pantallas para lf_screen_ids';
    END IF;
    v_applicability:=btrim(coalesce(v_cfg->>'lf_applicability',''));
    IF v_scope='BACKEND' THEN
      IF coalesce(p_es_transversal,false) OR jsonb_array_length(v_ids)>0 THEN
        RAISE EXCEPTION 'LF_RULE_CREATE_BACKEND_SCOPE_INCOHERENT: BACKEND no exige ni admite pantallas; usa es_transversal=false y lf_screen_ids=[]';
      END IF;
      IF btrim(coalesce(v_exec.manifest#>>'{profile_handoff,source_execution_id}',''))=''
        OR v_exec.manifest#>>'{profile_handoff,skill_run_id}' IS NOT NULL THEN
        RAISE EXCEPTION 'LF_RULE_CREATE_BACKEND_DIRECT_ONLY: crea BACKEND desde el RUN del perfil autorizado, sin IG ni skill_run_id';
      END IF;
    ELSIF v_scope='PANTALLA' THEN
      IF coalesce(p_es_transversal,false) OR jsonb_array_length(v_ids)=0 THEN
        RAISE EXCEPTION 'LF_RULE_CREATE_SCREEN_REQUIRED: PANTALLA exige lf_screen_ids no vacio y es_transversal=false';
      END IF;
    ELSE
      IF NOT coalesce(p_es_transversal,false)
         OR (jsonb_array_length(v_ids)<2 AND v_applicability='') THEN
        RAISE EXCEPTION 'LF_RULE_CREATE_TRANSVERSAL_SCOPE_REQUIRED: TRANSVERSAL exige es_transversal=true y lf_applicability o varias pantallas';
      END IF;
    END IF;
    IF v_scope IN ('PANTALLA','TRANSVERSAL') THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.lf_skill_invocation_v1 inv
        WHERE inv.child_execution_id=p_execution_id
          AND inv.parent_execution_id=v_exec.manifest#>>'{profile_handoff,source_execution_id}'
          AND inv.skill_run_id=v_exec.manifest#>>'{profile_handoff,skill_run_id}'
          AND inv.skill_code='RULE_CREATE_APPLY'
          AND inv.status='COMPLETED'
      ) THEN
        RAISE EXCEPTION 'LF_RULE_CREATE_IG_V2_REQUIRED: PANTALLA y TRANSVERSAL deben entrar por IG V2 CREATE / RULE_CREATE_APPLY';
      END IF;
    END IF;
    IF v_cfg ? 'lf_requested_state' AND upper(v_cfg->>'lf_requested_state')<>'CANDIDATO' THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_VIGENTE_FORBIDDEN: esta ruta solo crea CANDIDATO; VIGENTE no puede citar reglas CANDIDATO';
    END IF;
    IF (v_cfg ? 'config_ref') THEN
      v_config_scope:=v_cfg#>>'{config_ref,scope}';
      v_config_key:=v_cfg#>>'{config_ref,config_key}';
      IF NOT EXISTS(SELECT 1 FROM public.lf_global_config g
         WHERE g.scope=v_config_scope AND g.config_key=v_config_key AND g.value_status='REAL') THEN
        RAISE EXCEPTION 'LF_RULE_CREATE_CONFIG_REFERENCE_INVALID: declara scope y config_key reales en public.lf_global_config';
      END IF;
    END IF;
    IF EXISTS (
      SELECT 1 FROM lf_ops.reglas r
      WHERE lower(btrim(r.titulo))=lower(btrim(p_titulo))
        AND lower(btrim(r.categoria))=lower(btrim(p_categoria))
    ) THEN
      RAISE EXCEPTION 'LF_RULE_CREATE_EXACT_DUPLICATE: hay una regla con mismo titulo y categoria; revisa lf_ops.reglas antes de crear';
    END IF;
    IF EXISTS (
      SELECT 1 FROM lf_ops.reglas c
      WHERE c.estado='CANDIDATO' AND c.codigo<>p_codigo
        AND strpos(lower(concat_ws(' ',p_descripcion,p_razon,v_cfg::text)),lower(c.codigo))>0
    ) THEN
      v_review:='CANDIDATE_DEPENDENCY_NEEDS_REVIEW';
    END IF;
    INSERT INTO lf_ops.reglas(codigo,categoria,titulo,descripcion,razon,valor_config,
      es_transversal,estado,origen,pendiente_decision,pendiente_detalle,created_by)
    VALUES(p_codigo,p_categoria,p_titulo,p_descripcion,p_razon,v_cfg,
      coalesce(p_es_transversal,false),'CANDIDATO',p_origen,true,v_review,p_execution_id)
    RETURNING * INTO v_after;
  ELSE
    IF NOT FOUND THEN RAISE EXCEPTION 'LF_REGLA_UPDATE_NOT_FOUND:%',p_codigo; END IF;
    IF v_before.estado<>'CANDIDATO' THEN RAISE EXCEPTION 'LF_REGLA_UPDATE_REQUIRES_CANDIDATO:%:%',p_codigo,v_before.estado; END IF;
    UPDATE lf_ops.reglas SET categoria=p_categoria,titulo=p_titulo,descripcion=p_descripcion,
       razon=p_razon,valor_config=p_valor_config,es_transversal=coalesce(p_es_transversal,false),
       estado='CANDIDATO',origen=coalesce(p_origen,origen),
       pendiente_decision=true,pendiente_detalle='GOVERNED_CANDIDATE_REQUIRES_REVIEW',
       updated_at=now() WHERE codigo=p_codigo RETURNING * INTO v_after;
  END IF;
  RETURN jsonb_build_object(
    'result',CASE WHEN upper(p_action_code)='REGLA_CREATE' THEN 'RULE_CANDIDATE_CREATED' ELSE 'RULE_CANDIDATE_UPDATED' END,
    'operation_code',v_expected,'execution_id',p_execution_id,
    'before',CASE WHEN upper(p_action_code)='REGLA_UPDATE' THEN to_jsonb(v_before) ELSE null END,
    'after',to_jsonb(v_after));
END;
$lf_rule_writer$;

-- Genuine reversible PG17 regression against the writer, with real authorized handoff.
-- All 16 executions and their candidate rows must vanish at ROLLBACK TO SAVEPOINT.
SAVEPOINT lf_create_regression;
DO $lf_create_cases$
DECLARE
  v_parent public.lf_operation_execution%rowtype;
  v_case text;
  v_variant text;
  v_code text;
  v_exec text;
  v_desc text;
  v_cfg jsonb;
  v_reason text;
  v_origin text;
  v_trans boolean;
  v_title text;
  v_expected_error text;
  v_err text;
  v_result jsonb;
  v_negative integer:=0;
  v_positive integer:=0;
  v_before integer;
  v_after integer;
  v_candidate text;
BEGIN
  IF current_setting('server_version_num')::integer/10000 <> 17 THEN
    RAISE EXCEPTION 'LF_RULE_CREATE_PG17_REQUIRED';
  END IF;
  SELECT * INTO v_parent FROM public.lf_operation_execution
   WHERE execution_id='EXEC-PROFILE-GATE2-4F357C91F4C45CA308F88D88'
     AND operation_code='EJECUCION_PERFIL_LF' AND status='COMPLETED';
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_RULE_CREATE_REGRESSION_HANDOFF_INCOMPLETE'; END IF;
  SELECT codigo INTO v_candidate FROM lf_ops.reglas WHERE estado='CANDIDATO' ORDER BY codigo LIMIT 1;
  SELECT count(*) INTO v_before FROM lf_ops.reglas;

  FOREACH v_case IN ARRAY ARRAY[
    'RAZON','ORIGEN','SECCIONES','CIFRA_FIJA',
    'ALCANCE','PANTALLA_DIRECTA','TRANSVERSAL_DIRECTA','VIGENTE_CITA_CANDIDATO'
  ] LOOP
    FOREACH v_variant IN ARRAY ARRAY['DEFECTUOSA','CORREGIDA'] LOOP
      v_code:='IG-PG17-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,19));
      v_exec:='EXEC-IG-PG17-'||replace(gen_random_uuid()::text,'-','');
      v_title:='Prueba reversible '||v_case||' '||v_variant||' '||v_code;
      v_desc:='Condicion: El servicio recibe una regla. Alcance: Backend de autenticacion. Resultado: Guarda candidato para revision.';
      v_reason:='Razon de prueba para validar el contrato.';
      v_origin:='PG17_GOVERNED_TEST';
      v_cfg:=jsonb_build_object('lf_rule_scope','BACKEND','lf_screen_ids','[]'::jsonb,'lf_applicability','SERVICIO_INTERNO');
      v_trans:=false;
      v_expected_error:=null;
      IF v_variant='DEFECTUOSA' THEN
        CASE v_case
          WHEN 'RAZON' THEN v_reason:=null; v_expected_error:='LF_RULE_CREATE_REASON_REQUIRED';
          WHEN 'ORIGEN' THEN v_origin:=null; v_expected_error:='LF_RULE_CREATE_ORIGIN_REQUIRED';
          WHEN 'SECCIONES' THEN v_desc:='Servicio backend guarda una regla sin estructura.'; v_expected_error:='LF_RULE_CREATE_DESCRIPTION_SECTIONS_REQUIRED';
          WHEN 'CIFRA_FIJA' THEN v_desc:='Condicion: 5 intentos. Alcance: Backend. Resultado: Bloquea 5 intentos.'; v_expected_error:='LF_RULE_CREATE_HARDCODED_VALUE';
          WHEN 'ALCANCE' THEN v_cfg:='{}'::jsonb; v_expected_error:='LF_RULE_CREATE_SCOPE_REQUIRED';
          WHEN 'PANTALLA_DIRECTA' THEN v_cfg:=jsonb_build_object('lf_rule_scope','PANTALLA','lf_screen_ids',jsonb_build_array(51),'lf_applicability','B2B-AUTH-001'); v_expected_error:='LF_RULE_CREATE_IG_V2_REQUIRED';
          WHEN 'TRANSVERSAL_DIRECTA' THEN v_cfg:=jsonb_build_object('lf_rule_scope','TRANSVERSAL','lf_screen_ids','[]'::jsonb,'lf_applicability','TODAS_LAS_PANTALLAS'); v_trans:=true; v_expected_error:='LF_RULE_CREATE_IG_V2_REQUIRED';
          WHEN 'VIGENTE_CITA_CANDIDATO' THEN v_cfg:=v_cfg||jsonb_build_object('lf_requested_state','VIGENTE'); v_desc:=v_desc||' Referencia regla '||v_candidate; v_expected_error:='LF_RULE_CREATE_VIGENTE_FORBIDDEN';
        END CASE;
      ELSE
        IF v_case='CIFRA_FIJA' THEN
           v_desc:='Condicion: Alcanzar el umbral AUTH/OTP_MAX_ATTEMPTS de public.lf_global_config. Alcance: Backend. Resultado: Bloqueo configurado.';
           v_cfg:=v_cfg||jsonb_build_object('config_ref',jsonb_build_object('scope','AUTH','config_key','OTP_MAX_ATTEMPTS'));
        END IF;
        IF v_case='VIGENTE_CITA_CANDIDATO' THEN
           v_desc:=v_desc||' Referencia regla '||v_candidate;
        END IF;
      END IF;

      PERFORM public.fn_lf_operation_reserve_execution_v1(
        v_exec,'CREACION_REGLA_LF','REGLA',v_code,
        'ig-pg17-contract:'||v_exec,v_parent.request_sha256,v_parent.execution_id,
        NULL,NULL,jsonb_build_object('profile_handoff',jsonb_build_object(
           'source_execution_id',v_parent.execution_id,'via','GOVERNED_PROFILE'),
           'test_reversible',true)
      );
      v_err:=NULL; v_result:=NULL;
      BEGIN
        v_result:=public.lf_regla_candidate_write_v1(
           v_exec,'REGLA_CREATE',v_code,'SECURITY',v_title,v_desc,
           v_reason,v_cfg,v_trans,v_origin);
      EXCEPTION WHEN OTHERS THEN
        v_err:=SQLERRM;
      END;
      IF v_variant='DEFECTUOSA' THEN
        IF v_err IS NULL OR strpos(v_err,v_expected_error)=0
           OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_code) THEN
          RAISE EXCEPTION 'LF_RULE_CREATE_NEGATIVE_FAILED:%:error=%',v_case,coalesce(v_err,'NONE');
        END IF;
        v_negative:=v_negative+1;
      ELSE
        IF v_err IS NOT NULL OR v_result->>'result'<>'RULE_CANDIDATE_CREATED'
           OR v_result->'after'->>'estado'<>'CANDIDATO'
           OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_code AND estado='CANDIDATO') THEN
          RAISE EXCEPTION 'LF_RULE_CREATE_POSITIVE_FAILED:%:error=%',v_case,coalesce(v_err,'NONE');
        END IF;
        v_positive:=v_positive+1;
      END IF;
      RAISE NOTICE 'LF_RULE_CREATE_CASE=% variant=% result=% message=%',v_case,v_variant,
           CASE WHEN v_err IS NULL THEN 'ACCEPTED' ELSE 'REJECTED' END,coalesce(v_err,'NONE');
    END LOOP;
  END LOOP;
  SELECT count(*) INTO v_after FROM lf_ops.reglas;
  IF v_negative<>8 OR v_positive<>8 OR v_after<>v_before+8 THEN
    RAISE EXCEPTION 'LF_RULE_CREATE_REGRESSION_READBACK_MISMATCH:%:%:%:%',
      v_before,v_after,v_negative,v_positive;
  END IF;
  RAISE NOTICE 'LF_RULE_CREATE_PG17_REGRESSION_PASS:negative=% positive=% transient_rows=%',
    v_negative,v_positive,v_after-v_before;
END;
$lf_create_cases$;
ROLLBACK TO SAVEPOINT lf_create_regression;
RELEASE SAVEPOINT lf_create_regression;
COMMIT;
-- Final SELECT/readback of unchanged historical rows must be executed independently.

-- PG17 reversible baseline for the actual governed candidate writer.
-- Only transient execution IDs and candidate codes are generated inside this transaction.
-- Actor is resolved from the in-progress Merge Train execution; no owner/receipt fabricated.
-- No existing rule is updated, deleted, promoted or linked.
BEGIN;
DO $lf_rule_creation_probe$
DECLARE
  v_train text;
  v_before bigint;
  v_after bigint;
  v_reference text;
  v_case text;
  v_variant text;
  v_code text;
  v_exec text;
  v_sha text;
  v_reason text;
  v_origin text;
  v_desc text;
  v_title text;
  v_cfg jsonb;
  v_transversal boolean;
  v_res jsonb;
  v_writer jsonb;
  v_error text;
  v_ok boolean;
  v_positive integer := 0;
  v_negative_accepted integer := 0;
  v_negative_rejected integer := 0;
BEGIN
  IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
    RAISE EXCEPTION 'LF_IG_PG17_REQUIRED';
  END IF;

  SELECT e.execution_id INTO STRICT v_train
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code LIKE '%lf_rule_create_pg17_baseline_v1'
    AND e.status='IN_PROGRESS';

  SELECT count(*) INTO v_before FROM lf_ops.reglas;
  SELECT codigo INTO v_reference FROM lf_ops.reglas
   WHERE estado='CANDIDATO' ORDER BY codigo LIMIT 1;
  IF v_reference IS NULL THEN RAISE EXCEPTION 'LF_IG_NO_CANDIDATE_REFERENCE_FOR_NEGATIVE'; END IF;

  FOREACH v_case IN ARRAY ARRAY[
    'RAZON','ORIGEN','CIFRA_FIJA','ALCANCE','CANDIDATO_REF',
    'SECCIONES','PANTALLA_SIN_ENLACE','TRANSVERSAL_INCOHERENTE'
  ] LOOP
    FOREACH v_variant IN ARRAY ARRAY['DEFECTUOSA','CORREGIDA'] LOOP
      v_code:='IG-PG17-CR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,20));
      v_exec:='EXEC-IG-PG17-'||upper(replace(gen_random_uuid()::text,'-',''));
      v_sha:=encode(extensions.digest(convert_to(v_code,'UTF8'),'sha256'),'hex');
      v_res:=public.fn_lf_operation_reserve_execution_v1(
        v_exec,'CREACION_REGLA_LF','REGLA',v_code,
        'ig-pg17-baseline:'||v_exec,v_sha,v_train,null,null,
        jsonb_build_object('temporary_probe',true,'scope','READBACK_ROLLBACK_ONLY',
          'merge_train_execution_id',v_train));
      IF v_res->>'result'<>'RESERVED_NEW_EXECUTION' THEN
        RAISE EXCEPTION 'LF_IG_PROBE_RUN_RESERVE_FAILED:%',v_case;
      END IF;

      v_reason:='Control objetivo de creación: evidencia de prueba reversible.';
      v_origin:='PG17_TEST_ONLY';
      v_desc:='Condición: Se recibe una solicitud temporal de prueba. '
          ||'Acción: El servicio consulta su contrato de creación. '
          ||'Resultado: Devuelve una regla candidata sin publicación.';
      v_title:='Prueba reversible de entrada y alcance';
      v_cfg:=jsonb_build_object('lf_rule_scope','BACKEND',
        'lf_screen_ids',jsonb_build_array(),'lf_applicability','SERVICIO_INTERNO');
      v_transversal:=false;

      IF v_case='RAZON' AND v_variant='DEFECTUOSA' THEN v_reason:=null; END IF;
      IF v_case='ORIGEN' AND v_variant='DEFECTUOSA' THEN v_origin:=null; END IF;
      IF v_case='CIFRA_FIJA' THEN
        IF v_variant='DEFECTUOSA' THEN
          v_desc:='Condición: Se registran 5 intentos. Acción: El servicio bloquea '
             ||'tras 5 intentos. Resultado: acceso suspendido.';
        ELSE
          v_desc:='Condición: Se alcanza el umbral de intentos. '
             ||'Acción: Leer AUTH/OTP_MAX_ATTEMPTS en public.lf_global_config. '
             ||'Resultado: Aplicar el bloqueo configurado.';
        END IF;
      END IF;
      IF v_case='ALCANCE' AND v_variant='DEFECTUOSA' THEN
         v_cfg:='{}'::jsonb;
      END IF;
      IF v_case='CANDIDATO_REF' AND v_variant='DEFECTUOSA' THEN
         v_desc:=v_desc||' Depende de la regla '||v_reference||'.';
      END IF;
      IF v_case='SECCIONES' AND v_variant='DEFECTUOSA' THEN
         v_desc:='Este backend controla el resultado esperado del flujo.';
      END IF;
      IF v_case='PANTALLA_SIN_ENLACE' THEN
         v_cfg:=jsonb_build_object('lf_rule_scope','PANTALLA',
           'lf_screen_ids',case when v_variant='DEFECTUOSA' then '[]'::jsonb
                                else '[51]'::jsonb end,
           'lf_applicability','B2B-AUTH-001');
      END IF;
      IF v_case='TRANSVERSAL_INCOHERENTE' THEN
         v_cfg:=jsonb_build_object('lf_rule_scope','TRANSVERSAL',
           'lf_screen_ids','[]'::jsonb,
           'lf_applicability',case when v_variant='DEFECTUOSA' then ''
                                   else 'ALCANCE_GLOBAL_DECLARADO' end);
         v_transversal:=v_variant='CORREGIDA';
      END IF;

      v_error:=null;
      v_ok:=false;
      BEGIN
        v_writer:=public.lf_regla_candidate_write_v1(v_exec,
          'REGLA_CREATE',v_code,'SECURITY',v_title,v_desc,
          v_reason,v_cfg,v_transversal,v_origin);
        v_ok:=(v_writer->>'result'='RULE_CANDIDATE_CREATED'
          AND v_writer->'after'->>'estado'='CANDIDATO'
          AND EXISTS(SELECT 1 FROM lf_ops.reglas r WHERE r.codigo=v_code
            AND r.estado='CANDIDATO'));
      EXCEPTION WHEN OTHERS THEN
        v_error:=SQLERRM;
      END;

      IF v_variant='CORREGIDA' THEN
        IF NOT v_ok THEN
          RAISE EXCEPTION 'LF_IG_POSITIVE_BASELINE_FAIL:%:%',v_case,v_error;
        END IF;
        v_positive:=v_positive+1;
      ELSE
        IF v_ok THEN
          v_negative_accepted:=v_negative_accepted+1;
        ELSE
          v_negative_rejected:=v_negative_rejected+1;
        END IF;
      END IF;

      RAISE NOTICE 'LF_IG_PG17_CASE:%:%:accepted=%:error=%',
        v_case,v_variant,v_ok,coalesce(v_error,'NONE');
    END LOOP;
  END LOOP;

  SELECT count(*) INTO v_after FROM lf_ops.reglas;
  IF v_after<>v_before+v_positive+v_negative_accepted THEN
    RAISE EXCEPTION 'LF_IG_PROBE_READBACK_COUNT_MISMATCH:%:%:%',
      v_before,v_after,v_positive+v_negative_accepted;
  END IF;
  RAISE NOTICE 'LF_IG_PG17_SUMMARY:base=%:after_transient=%:corrected_accepted=%:defective_accepted=%:defective_rejected=%',
    v_before,v_after,v_positive,v_negative_accepted,v_negative_rejected;
END;
$lf_rule_creation_probe$;
ROLLBACK;
-- Train ledger is the only persistent effect of this test-only migration.

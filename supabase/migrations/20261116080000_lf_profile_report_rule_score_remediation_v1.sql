-- LF Step80: every screen-bound profile reports score<85 without authorizing promotions.
-- Sandbox migration ONLY through LF Merge Train. No rule mutations in this helper.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_rule_score_report_v1(p_execution_id text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'lf_ops'
AS $fn$
DECLARE
  v_screen text;
  v_items jsonb := '[]'::jsonb;
  v_missing jsonb;
  v_score integer;
  v_hard boolean;
  v_destination text;
  v_action text;
  v_category text;
  v_question text;
  x record;
BEGIN
  SELECT s.evidence_payload #>> '{resolved_scope,resolved_screen_code}'
    INTO v_screen
  FROM public.lf_operation_execution_steps s
  WHERE s.execution_id=p_execution_id
    AND s.step_id='input_validate'
    AND s.status='STEP_PASS_WITH_EVIDENCE'
  LIMIT 1;

  IF nullif(v_screen,'') IS NULL THEN
    RETURN jsonb_build_object('status','NOT_APPLICABLE','screen_code',null,
      'rule_reports','[]'::jsonb,'count',0,'promotion_performed',false);
  END IF;

  FOR x IN
    SELECT r.codigo, r.estado, r.categoria, r.pendiente_decision,
           r.pendiente_detalle,
           public.lf_rule_promotion_score_v1(p_execution_id,r.codigo) AS scoring,
           (SELECT count(*) FROM lf_ops.regla_behavior_tests bt
             WHERE bt.regla_codigo=r.codigo) AS test_count
    FROM lf_ops.pantallas p
    JOIN lf_ops.reglas_pantallas rp ON rp.pantalla_id=p.id
    JOIN lf_ops.reglas r ON r.id=rp.regla_id
    WHERE p.codigo=v_screen
      AND (
        p.codigo <> 'B2B-AUTH-001'
        OR r.codigo ~ '^B2B-RULE-AUTH-'
        OR r.codigo ~ '^B2B-RULE-SESSION-'
        OR r.codigo IN (
          'B2B-RULE-RATE-001','B2B-RULE-SECURITY-BASELINE-001',
          'B2B-RULE-TIMEOUT-001','B2B-RULE-INPUT-APPLICABILITY-001'
        )
      )
    ORDER BY r.codigo
  LOOP
    v_score:=coalesce((x.scoring->>'score')::integer,0);
    v_hard:=coalesce((x.scoring->>'hard_block')::boolean,true);
    IF v_score>=85 AND NOT v_hard THEN CONTINUE; END IF;

    v_missing:='[]'::jsonb;
    IF coalesce((x.scoring->>'A')::integer,0)<40 THEN
      v_missing:=v_missing||jsonb_build_array(
        CASE WHEN x.test_count=0 THEN 'A: NO_RULE_BEHAVIOR_TEST_ROW'
             ELSE 'A: PG17_PG18_CI_PASS_NOT_ATTESTED_OR_JUDGE_BINDING_MISSING' END);
    END IF;
    IF coalesce((x.scoring->>'B')::integer,0)<30 THEN
      v_missing:=v_missing||jsonb_build_array(
        'B: STEP50_RULE_SOURCE_REF_AND_STEP70_BINDING_NOT_PROVEN');
    END IF;
    IF coalesce((x.scoring->>'C')::integer,0)<20 THEN
      v_missing:=v_missing||jsonb_build_array('C: PENDIENTE_DECISION_TRUE');
    END IF;
    IF coalesce((x.scoring->>'D')::integer,0)<10 THEN
      v_missing:=v_missing||jsonb_build_array(
        'D: RULE_CURRENTNESS_BEFORE_STEP70_NOT_PROVEN_OR_B_UNSCORED');
    END IF;

    v_category:=CASE
      WHEN x.pendiente_decision IS TRUE THEN 'PENDING_DECISION'
      WHEN x.codigo LIKE 'B2B-RULE-AUTH-%' THEN 'AUTH'
      WHEN x.categoria IN ('LEGAL','APPROVAL','OFERTAS_CUOTAS','AUTH','PRIVACY','PAGOS')
        THEN x.categoria
      WHEN x.codigo LIKE '%INSTALLMENT%' THEN 'OFERTAS_CUOTAS'
      ELSE NULL END;
    v_question:=CASE WHEN x.pendiente_decision IS TRUE
      THEN '¿Qué definición autorizada resuelve lo siguiente? '||
           coalesce(nullif(x.pendiente_detalle,''),'Motivo humano no documentado en la regla '||x.codigo)
      ELSE NULL END;
    v_destination:=CASE
      WHEN x.pendiente_decision IS TRUE OR (v_hard AND v_score>=85) THEN 'DECISION_HUMANA'
      WHEN coalesce((x.scoring->>'A')::integer,0)<40
           AND x.test_count>0 THEN 'T_REMED'
      WHEN coalesce((x.scoring->>'A')::integer,0)<40 THEN 'REPARAR_REGLA'
      WHEN coalesce((x.scoring->>'B')::integer,0)<30 THEN 'T_REMED'
      ELSE 'REPARAR_REGLA' END;
    v_action:=CASE v_destination
      WHEN 'DECISION_HUMANA' THEN
        'Registrar pregunta y respuesta en DECISIONES_PENDIENTES; mantener MANUAL sin promoción'
      WHEN 'T_REMED' THEN
        'Derivar al T_REMED canónico; obtener fuente y evidencia vinculada antes de recalcular score'
      ELSE
        'Reparar regla, pruebas PG17/PG18, CI y referencias Step50→70 por ruta gobernada; recalcular score'
      END;
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'regla',x.codigo,'estado_actual',x.estado,
      'score',v_score,
      'A',jsonb_build_object('obtenidos',coalesce((x.scoring->>'A')::integer,0),'maximo',40),
      'B',jsonb_build_object('obtenidos',coalesce((x.scoring->>'B')::integer,0),'maximo',30),
      'C',jsonb_build_object('obtenidos',coalesce((x.scoring->>'C')::integer,0),'maximo',20),
      'D',jsonb_build_object('obtenidos',coalesce((x.scoring->>'D')::integer,0),'maximo',10),
      'faltantes',v_missing,'destino',v_destination,
      'accion',v_action,
      'hard_block',v_hard,'hard_block_categoria',v_category,
      'decision_puntaje',x.scoring->>'decision',
      'pregunta_humana',v_question,
      'promocion_autorizada',false
    ));
  END LOOP;

  RETURN jsonb_build_object('schema_version','LF_PROFILE_RULE_SCORE_REPORT_V1',
    'status','READY','execution_id',p_execution_id,'screen_code',v_screen,
    'rule_reports',v_items,'count',jsonb_array_length(v_items),
    'promotion_performed',false);
END
$fn$;

-- AUTH is a governed domain, not just a literal category; login codes must be MANUAL.
-- Existing score and threshold remain unchanged. No rule state is modified.
DO $auth$
DECLARE d text; d0 text;
BEGIN
  d:=pg_get_functiondef('public.lf_rule_promotion_score_v1(text,text)'::regprocedure);
  d0:=d;
  d:=replace(d,
    $a$OR p_rule_code LIKE '%INSTALLMENT%';$a$,
    $b$OR p_rule_code LIKE '%INSTALLMENT%' OR p_rule_code LIKE 'B2B-RULE-AUTH-%';$b$);
  IF d=d0 OR position('B2B-RULE-AUTH-%' IN d)=0 THEN
    RAISE EXCEPTION 'LF_RULE_AUTH_HARD_BLOCK_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;
END
$auth$;

-- Patch the actual Step80 source without changing existing steps, ACL, or score rules.
DO $patch$
DECLARE d text; d0 text;
BEGIN
  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
  d0:=d;
  d:=replace(d,
    $old$'family_source_receipts',public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id),$old$,
    $new$'rule_score_report',public.lf_profile_rule_score_report_v1(p_execution_id),
        'family_source_receipts',public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id),$new$);
  IF d=d0 OR position('''rule_score_report'',public.lf_profile_rule_score_report_v1(p_execution_id)' IN d)=0 THEN
    RAISE EXCEPTION 'LF_RULE_SCORE_REPORT_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;
END
$patch$;
COMMIT;

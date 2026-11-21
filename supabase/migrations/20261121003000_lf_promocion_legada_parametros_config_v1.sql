-- Promoción legada (lf_rule_promotion_score_v1): pesos, umbrales y listas pasan a lf_global_config.
-- Antes: 40/30/20/10, 60, 85, categorías siempre manuales y '%INSTALLMENT%' escritos en la función.
-- Los umbrales son los mismos del núcleo (NUCLEO_EVAL.UMBRAL_AUTO / UMBRAL_MANUAL): una sola fuente.
-- Con los valores registrados el resultado es idéntico: la migración compara la huella de todas las
-- combinaciones ejecución × regla de las promociones registradas antes y después, y se revierte si difieren.
-- Si falta un valor de configuración, la función falla cerrada (LF_PROMOTION_SCORE_CONFIG_MISSING).
BEGIN;

INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('PROMOCION_LEGADO','PESO_PRUEBAS_COMPORTAMIENTO','40','INTEGER','REAL','Promoción legada (lf_rule_promotion_score_v1): puntos A por pruebas de comportamiento en PG17 y PG18 con corrida de CI.'),
 ('PROMOCION_LEGADO','PESO_EJECUCION_LIGADA','30','INTEGER','REAL','Promoción legada: puntos B por ejecución ligada (pasos 40-70 con evidencia y juez válido) que cita la regla.'),
 ('PROMOCION_LEGADO','PESO_SIN_DECISION_PENDIENTE','20','INTEGER','REAL','Promoción legada: puntos C cuando la regla no tiene decisión pendiente.'),
 ('PROMOCION_LEGADO','PESO_FRESCURA','10','INTEGER','REAL','Promoción legada: puntos D cuando la regla no cambió después del juicio.'),
 ('PROMOCION_LEGADO','CATEGORIAS_SIEMPRE_MANUAL','["LEGAL","APPROVAL","OFERTAS_CUOTAS","AUTH","PRIVACY","PAGOS"]','JSON','REAL','Promoción legada: categorías de lf_ops.reglas que siempre requieren decisión humana.'),
 ('PROMOCION_LEGADO','PATRON_CODIGO_SIEMPRE_MANUAL','%INSTALLMENT%','TEXT','REAL','Promoción legada: patrón LIKE de códigos de regla que siempre requieren decisión humana.');

CREATE TEMP TABLE _lf_score_antes ON COMMIT DROP AS SELECT * FROM (SELECT count(*) AS n, md5(string_agg(e.x || '|' || r.codigo || '|' || public.lf_rule_promotion_score_v1(e.x, r.codigo)::text, E'\n' ORDER BY e.x, r.codigo)) AS h
   FROM (SELECT DISTINCT request_execution_id AS x FROM public.lf_rule_promotion_v1) e CROSS JOIN lf_ops.reglas r) a;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_score_v1(p_execution_id text, p_rule_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  r record; p40 record; p50 record; p60 record; p70 record;
  refs jsonb; is_bound boolean:=false; has_ref boolean:=false;
  a integer:=0; b integer:=0; c integer:=0; d integer:=0; total integer;
  hard_block boolean; decision text;
  -- Pesos, umbrales y listas desde lf_global_config (antes estaban escritos en esta función)
  cfg jsonb; w_a integer; w_b integer; w_c integer; w_d integer; u_manual integer; u_auto integer;
  blocked_categories text[]; patron_manual text;
BEGIN
  SELECT jsonb_object_agg(g.scope || '.' || g.config_key, g.config_value) INTO cfg
    FROM (SELECT DISTINCT ON (scope, config_key) scope, config_key, config_value FROM public.lf_global_config
           WHERE scope IN ('PROMOCION_LEGADO','NUCLEO_EVAL') AND valid_from <= now()
           ORDER BY scope, config_key, valid_from DESC) g;
  w_a := (cfg->>'PROMOCION_LEGADO.PESO_PRUEBAS_COMPORTAMIENTO')::int; w_b := (cfg->>'PROMOCION_LEGADO.PESO_EJECUCION_LIGADA')::int;
  w_c := (cfg->>'PROMOCION_LEGADO.PESO_SIN_DECISION_PENDIENTE')::int; w_d := (cfg->>'PROMOCION_LEGADO.PESO_FRESCURA')::int;
  u_manual := (cfg->>'NUCLEO_EVAL.UMBRAL_MANUAL')::int; u_auto := (cfg->>'NUCLEO_EVAL.UMBRAL_AUTO')::int;
  patron_manual := cfg->>'PROMOCION_LEGADO.PATRON_CODIGO_SIEMPRE_MANUAL';
  SELECT array_agg(x) INTO blocked_categories FROM jsonb_array_elements_text((cfg->>'PROMOCION_LEGADO.CATEGORIAS_SIEMPRE_MANUAL')::jsonb) x;
  IF w_a IS NULL OR w_b IS NULL OR w_c IS NULL OR w_d IS NULL OR u_manual IS NULL OR u_auto IS NULL
     OR patron_manual IS NULL OR blocked_categories IS NULL THEN
    RAISE EXCEPTION 'LF_PROMOTION_SCORE_CONFIG_MISSING';
  END IF;
  SELECT codigo,estado,categoria,pendiente_decision,updated_at INTO r FROM lf_ops.reglas WHERE codigo=p_rule_code;
  IF NOT FOUND THEN RETURN jsonb_build_object('score',0,'A',0,'B',0,'C',0,'D',0,'hard_block',true,
    'decision','BLOCKED','next_gate','RETURN_TO_ROUTER','reason','RULE_NOT_FOUND'); END IF;
  SELECT * INTO p40 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=40 AND step_id='input_validate';
  SELECT * INTO p50 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=50 AND step_id='execute_profile';
  SELECT * INTO p60 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=60 AND step_id='output_validate';
  SELECT * INTO p70 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=70 AND step_id='semantic_judge';
  is_bound:=p40.status='STEP_PASS_WITH_EVIDENCE'
    AND p50.status='STEP_PASS_WITH_EVIDENCE'
    AND p60.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.evidence_payload#>>'{semantic_judge_result,verdict}'
      IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
    AND p50.evidence_payload->>'raw_output_sha256' ~ '^[0-9a-f]{64}$'
    AND p50.evidence_payload->>'raw_output_sha256'=p60.evidence_payload->>'raw_output_sha256'
    AND p50.evidence_payload->>'raw_output_sha256'=p70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
    AND p40.evidence_payload->>'scope_authority_packet_sha256'
      ='sha256:'||(p70.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}')
    AND jsonb_typeof(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
    AND jsonb_array_length(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0;
  refs:=p50.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}';
  IF jsonb_typeof(refs)='array' THEN
    SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
      WHERE x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code) INTO has_ref;
  END IF;
  IF NOT has_ref
     AND p50.evidence_payload#>>'{step50_effect_verification,status}'='VERIFIED'
     AND jsonb_typeof(p50.evidence_payload#>'{step50_effect_verification,rule_receipts}')='array'
   THEN
     SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(
       p50.evidence_payload#>'{step50_effect_verification,rule_receipts}') x
       WHERE x->>'rule_code'=p_rule_code
         AND x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code
     ) INTO has_ref;
   END IF;
   IF is_bound AND has_ref THEN b:=w_b; END IF;
  IF r.pendiente_decision IS FALSE THEN c:=w_c; END IF;
  IF b>0 AND r.updated_at<p70.observed_at THEN d:=w_d; END IF;
  IF is_bound AND EXISTS (SELECT 1 FROM lf_ops.regla_behavior_tests bt WHERE bt.regla_codigo=p_rule_code AND bt.pg17='PASS' AND bt.pg18='PASS' AND bt.ci_run IS NOT NULL AND btrim(bt.ci_run)<>'') THEN a:=w_a; END IF;
  hard_block:=coalesce(r.pendiente_decision,true) OR r.categoria=ANY(blocked_categories)
    OR p_rule_code LIKE patron_manual;
  total:=a+b+c+d;
  -- Bajo el umbral de revisión siempre vuelve al Router; hard_block fuerza MANUAL desde ese umbral.
  IF r.estado<>'CANDIDATO' OR total<u_manual THEN decision:='BLOCKED';
  ELSIF hard_block THEN decision:='MANUAL';
  ELSIF total>=u_auto THEN decision:='AUTO';
  ELSE decision:='MANUAL'; END IF;
  RETURN jsonb_build_object('score',total,'A',a,'B',b,'C',c,'D',d,
    'hard_block',hard_block,'decision',decision,
    'next_gate',CASE WHEN decision='BLOCKED' THEN 'RETURN_TO_ROUTER' ELSE 'PROMOTION_REQUEST' END,
    'judge_independence',CASE
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
       THEN 'NOT_PROVEN_OWNER_ACCEPTED'
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
       THEN 'INDEPENDENCE_ASSERTED_NOT_REVERIFIED'
      ELSE 'NO_VALID_JUDGE' END,
    'reason','A from lf_ops.regla_behavior_tests');
END $function$;


DO $verif$
DECLARE antes record; despues record;
BEGIN
  SELECT * INTO antes FROM _lf_score_antes;
  SELECT * INTO despues FROM (SELECT count(*) AS n, md5(string_agg(e.x || '|' || r.codigo || '|' || public.lf_rule_promotion_score_v1(e.x, r.codigo)::text, E'\n' ORDER BY e.x, r.codigo)) AS h
   FROM (SELECT DISTINCT request_execution_id AS x FROM public.lf_rule_promotion_v1) e CROSS JOIN lf_ops.reglas r) d;
  IF antes.n IS DISTINCT FROM despues.n OR antes.h IS DISTINCT FROM despues.h THEN
    RAISE EXCEPTION 'LF_PROMOTION_SCORE_EQUIVALENCE_FAILED: antes % (%), después % (%)', antes.n, antes.h, despues.n, despues.h;
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.lf_rule_promotion_score_v1(text,text)'::regprocedure) ~ '(:=|<|>=)\s*(40|30|20|10|60|85)\s*;|INSTALLMENT|''LEGAL''' THEN
    RAISE EXCEPTION 'LF_PROMOTION_SCORE_LITERAL_REMAINS';
  END IF;
  BEGIN
    DELETE FROM public.lf_global_config WHERE scope = 'PROMOCION_LEGADO' AND config_key = 'PESO_FRESCURA';
    PERFORM public.lf_rule_promotion_score_v1('x', 'x');
    RAISE EXCEPTION 'LF_PROMOTION_SCORE_FAIL_OPEN';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'LF_PROMOTION_SCORE_CONFIG_MISSING' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'LF_PROMOTION_SCORE_EQUIVALENCE_OK: % combinaciones, huella %', despues.n, despues.h;
END $verif$;
COMMIT;

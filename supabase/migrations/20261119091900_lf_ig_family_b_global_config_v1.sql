-- IG Familia B: una sola migracion de parametros operativos (20 keys, 13 reglas).
-- Fuente: estado VIGENTE original de lf_ops.reglas; mantiene exactamente valores previos.
-- REG_OBS_003 reutiliza ALERTAS/PASO1_SUBMIT_ERROR_RATE_MAX de REG_ALR_004;
-- REG_OBS_004 solo parametriza alertas de sesiones: LCP/CLS/FID son referencias tecnicas.
-- REG_ACC_005 excluida: dimension WCAG, no umbral de negocio.
-- Sin cambiar reglas, pantallas, politicas, contratos ni backend E2E.
BEGIN;
CREATE TEMP TABLE ig_family_b_config_source (
 scope text NOT NULL, config_key text NOT NULL, config_value text NOT NULL,
 value_type text NOT NULL, rule_code text NOT NULL, source_path text[] NOT NULL,
 expected_source_value text NOT NULL, PRIMARY KEY(scope,config_key)
) ON COMMIT DROP;
INSERT INTO pg_temp.ig_family_b_config_source
(scope,config_key,config_value,value_type,rule_code,source_path,expected_source_value) VALUES
  ('ALERTAS','OTP_VERIFICATION_MIN_RATE','0.6','DECIMAL','REG_ALR_001',ARRAY['valor_config','umbral_minimo']::text[],'0.6'),
  ('ALERTAS','OTP_VERIFICATION_WINDOW_MINUTES','30','INTEGER','REG_ALR_001',ARRAY['valor_config','ventana_minutos']::text[],'30'),
  ('ALERTAS','PASO1_ABANDON_RATE_MAX','0.8','DECIMAL','REG_ALR_002',ARRAY['valor_config','umbral_maximo']::text[],'0.8'),
  ('ALERTAS','PASO1_ABANDON_WINDOW_HOURS','1','INTEGER','REG_ALR_002',ARRAY['valor_config','ventana_horas']::text[],'1'),
  ('ALERTAS','OTP_WEBHOOK_CONSECUTIVE_FAILURE_LIMIT','3','INTEGER','REG_ALR_003',ARRAY['valor_config','condicion']::text[],'3_fallos_consecutivos'),
  ('ALERTAS','PASO1_SUBMIT_ERROR_RATE_MAX','0.05','DECIMAL','REG_ALR_004',ARRAY['valor_config','umbral_maximo']::text[],'0.05'),
  ('ALERTAS','PASO1_SUBMIT_ERROR_WINDOW_MINUTES','15','INTEGER','REG_ALR_004',ARRAY['valor_config','ventana_minutos']::text[],'15'),
  ('ALERTAS','LCP_ALERT_THRESHOLD_MS','4000','INTEGER','REG_ALR_005',ARRAY['valor_config','umbral_ms']::text[],'4000'),
  ('ALERTAS','LCP_ALERT_SESSIONS_RATIO','0.2','DECIMAL','REG_ALR_005',ARRAY['valor_config','porcentaje_sesiones']::text[],'0.2'),
  ('ALERTAS','LCP_ALERT_WINDOW_HOURS','1','INTEGER','REG_ALR_005',ARRAY['valor_config','ventana_horas']::text[],'1'),
  ('OBSERVABILIDAD','CORE_WEB_VITALS_ALERT_SESSIONS_PERCENT','10','INTEGER','REG_OBS_004',ARRAY['valor_config','alerta_porcentaje_sesiones']::text[],'10'),
  ('OBSERVABILIDAD','OTP_DELIVERY_P95_SECONDS_MAX','30','INTEGER','REG_OBS_005',ARRAY['valor_config','p95_segundos']::text[],'30'),
  ('UX','SKELETON_SHOW_AFTER_MS','300','INTEGER','REG_TEC_006',ARRAY['valor_config','umbral_ms']::text[],'300'),
  ('UX','SELECTION_RECALC_MAX_LATENCY_MS','100','INTEGER','REG_DAT_003',ARRAY['valor_config','latencia_maxima_ms']::text[],'100'),
  ('UX','MODAL_APPLY_MAX_LATENCY_MS','100','INTEGER','REG_MOD_003',ARRAY['valor_config','latencia_maxima_ms']::text[],'100'),
  ('UX','HOME_VARIANT_MAX_SKELETON_SECONDS','5','INTEGER','REG_UI_007',ARRAY['valor_config','duracion_maxima_s']::text[],'5'),
  ('UX','COMPONENT_TRANSITION_MIN_MS','150','INTEGER','REG_UI_008',ARRAY['valor_config','transicion_componente_ms','min']::text[],'150'),
  ('UX','COMPONENT_TRANSITION_MAX_MS','300','INTEGER','REG_UI_008',ARRAY['valor_config','transicion_componente_ms','max']::text[],'300'),
  ('UX','SCREEN_FADE_MS','200','INTEGER','REG_UI_008',ARRAY['valor_config','cambio_pantalla_ms']::text[],'200'),
  ('UX','SKELETON_FADE_MS','300','INTEGER','REG_UI_008',ARRAY['valor_config','skeleton_fade_ms']::text[],'300');
CREATE TEMP TABLE ig_family_b_rule_baseline AS
SELECT codigo, to_jsonb(r) AS payload FROM lf_ops.reglas r;
DO $pre$
DECLARE n integer; v_count integer;
BEGIN
 SELECT count(*) INTO n FROM pg_temp.ig_family_b_config_source;
 SELECT count(*) INTO v_count FROM pg_temp.ig_family_b_rule_baseline;
 IF n<>20
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN (
 'REG_ALR_001','REG_ALR_002','REG_ALR_003','REG_ALR_004','REG_ALR_005',
 'REG_OBS_003','REG_OBS_004','REG_OBS_005','REG_TEC_006','REG_DAT_003',
 'REG_MOD_003','REG_UI_007','REG_UI_008') AND estado='VIGENTE')<>13
 OR (SELECT count(*) FROM lf_ops.v_reglas_historial WHERE codigo IN (
 'REG_ALR_001','REG_ALR_002','REG_ALR_003','REG_ALR_004','REG_ALR_005',
 'REG_OBS_003','REG_OBS_004','REG_OBS_005','REG_TEC_006','REG_DAT_003',
 'REG_MOD_003','REG_UI_007','REG_UI_008') AND es_actual AND version=1)<>13
 OR EXISTS (
  SELECT 1 FROM pg_temp.ig_family_b_config_source m
  LEFT JOIN lf_ops.reglas r ON r.codigo=m.rule_code AND r.estado='VIGENTE'
  WHERE r.codigo IS NULL OR to_jsonb(r)#>>m.source_path IS DISTINCT FROM m.expected_source_value
 )
 OR EXISTS (
  SELECT 1 FROM pg_temp.ig_family_b_config_source m
  JOIN public.lf_global_config g ON g.scope=m.scope AND g.config_key=m.config_key
 )
 OR NOT EXISTS (
  SELECT 1 FROM lf_ops.reglas WHERE codigo='REG_OBS_003' AND estado='VIGENTE'
  AND valor_config->'alertas_criticas' @> '["paso1_submit_error_rate>5%"]'::jsonb
 )
 OR (SELECT count(*) FROM pg_temp.ig_family_b_rule_baseline WHERE codigo='REG_ACC_005')<>1
 OR v_count<>(SELECT count(*) FROM lf_ops.reglas)
 THEN RAISE EXCEPTION 'IG_FAMILY_B_GLOBAL_CONFIG_SOURCE_DRIFT'; END IF;
 RAISE NOTICE 'IG_FAMILY_B_SOURCE_CHECK_20_KEYS_13_RULES_PASS';
END $pre$;
SAVEPOINT ig_family_b_config_positive;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
SELECT scope,config_key,config_value,value_type,'REAL',
 'IG Familia B: valor vigente de '||rule_code||', campo '||array_to_string(source_path,'.')||
 '; sin cambio de umbral ni activacion de backend.'
FROM pg_temp.ig_family_b_config_source ORDER BY scope,config_key;
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config g
  JOIN pg_temp.ig_family_b_config_source m
  ON g.scope=m.scope AND g.config_key=m.config_key
  WHERE g.config_value=m.config_value AND g.value_type=m.value_type
  AND g.value_status='REAL')<>20
 THEN RAISE EXCEPTION 'IG_FAMILY_B_CONFIG_INSERT_PROBE_FAILED'; END IF;
 RAISE NOTICE 'IG_FAMILY_B_POSITIVE_PROBE_PASS';
END $test$;
ROLLBACK TO SAVEPOINT ig_family_b_config_positive;
RELEASE SAVEPOINT ig_family_b_config_positive;
DO $rb$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_global_config g
 JOIN pg_temp.ig_family_b_config_source m ON g.scope=m.scope AND g.config_key=m.config_key)
 THEN RAISE EXCEPTION 'IG_FAMILY_B_CONFIG_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_FAMILY_B_REAL_SAVEPOINT_ROLLBACK_PASS';
END $rb$;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
SELECT scope,config_key,config_value,value_type,'REAL',
 'IG Familia B: valor vigente de '||rule_code||', campo '||array_to_string(source_path,'.')||
 '; sin cambio de umbral ni activacion de backend.'
FROM pg_temp.ig_family_b_config_source ORDER BY scope,config_key;
DO $final$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config g
  JOIN pg_temp.ig_family_b_config_source m ON g.scope=m.scope AND g.config_key=m.config_key
  WHERE g.config_value=m.config_value AND g.value_type=m.value_type
  AND g.value_status='REAL')<>20
 OR EXISTS(SELECT 1 FROM lf_ops.reglas r
  FULL JOIN pg_temp.ig_family_b_rule_baseline b USING(codigo)
  WHERE b.codigo IS NULL OR r.codigo IS NULL OR to_jsonb(r) IS DISTINCT FROM b.payload)
 THEN RAISE EXCEPTION 'IG_FAMILY_B_FINAL_READBACK_OR_RULE_MUTATION'; END IF;
 RAISE NOTICE 'IG_FAMILY_B_CONFIG_20_REAL; RULES_UNCHANGED; PG17_PROBE_ROLLBACK_PASS; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;

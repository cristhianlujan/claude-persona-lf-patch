-- Decisiones del dueño (2026-11-20 23:15 Lima) aplicadas a la configuración del núcleo en LF y SALY:
--   D4 plazo de implementación por defecto: 15 días, valor real (antes de muestra).
--   D5 ninguna familia ni tipo pasa siempre por decisión humana: solo lo que no alcanza el umbral automático.
-- Se registran como versiones nuevas de la configuración (valid_from), así queda el historial de los valores anteriores.
BEGIN;
INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO','PLAZO_IMPLEMENTACION_DIAS','15','INTEGER','REAL','Días desde la publicación de una versión con impacto hasta que es exigible en cada nodo, si la propuesta no indica plazo. Decisión del dueño D4 (2026-11-20).'),
 ('NUCLEO_EVAL','FAMILIAS_SIEMPRE_MANUAL','[]','JSON','REAL','Familias que siempre requieren decisión humana. Vacía por decisión del dueño D5 (2026-11-20): solo lo que no alcanza el umbral va a decisión humana.'),
 ('NUCLEO_EVAL','TIPOS_SIEMPRE_MANUAL','[]','JSON','REAL','Tipos de familia que siempre requieren decisión humana. Vacía por decisión del dueño D5 (2026-11-20).');
INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO','PLAZO_IMPLEMENTACION_DIAS','15','INTEGER','REAL','Días desde la publicación de una versión con impacto hasta que es exigible, si la propuesta no indica plazo. Decisión del dueño D4 (2026-11-20).'),
 ('NUCLEO_EVAL','FAMILIAS_SIEMPRE_MANUAL','[]','JSON','REAL','Familias de SALY que siempre requieren decisión humana. Vacía por decisión del dueño D5 (2026-11-20).'),
 ('NUCLEO_EVAL','TIPOS_SIEMPRE_MANUAL','[]','JSON','REAL','Tipos de familia de SALY que siempre requieren decisión humana. Vacía por decisión del dueño D5 (2026-11-20).');

DO $v$
DECLARE v_err text;
BEGIN
  SELECT string_agg(i || '.' || k, ', ') INTO v_err FROM (
    SELECT 'LF' i, k FROM unnest(ARRAY['NUCLEO.PLAZO_IMPLEMENTACION_DIAS','NUCLEO_EVAL.FAMILIAS_SIEMPRE_MANUAL','NUCLEO_EVAL.TIPOS_SIEMPRE_MANUAL']) k
     WHERE lf_ops.nucleo_param_valor_v1(k) IS DISTINCT FROM CASE WHEN k LIKE '%PLAZO%' THEN '15' ELSE '[]' END
    UNION ALL
    SELECT 'SALY', k FROM unnest(ARRAY['NUCLEO.PLAZO_IMPLEMENTACION_DIAS','NUCLEO_EVAL.FAMILIAS_SIEMPRE_MANUAL','NUCLEO_EVAL.TIPOS_SIEMPRE_MANUAL']) k
     WHERE saly.nucleo_param_valor_v1(k) IS DISTINCT FROM CASE WHEN k LIKE '%PLAZO%' THEN '15' ELSE '[]' END) x;
  IF v_err IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_DECISION_NO_VIGENTE: %', v_err; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope = 'NUCLEO' AND config_key = 'PLAZO_IMPLEMENTACION_DIAS' AND valid_from = (SELECT max(valid_from) FROM public.lf_global_config WHERE scope = 'NUCLEO' AND config_key = 'PLAZO_IMPLEMENTACION_DIAS') AND value_status <> 'REAL')
    THEN RAISE EXCEPTION 'NUCLEO_DECISION_PLAZO_NO_REAL'; END IF;
  RAISE NOTICE 'NUCLEO_AUTOTEST LF: % · % · % · %', lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1(), lf_ops.nucleo_autotest_cambio_v1(), lf_ops.nucleo_autotest_contrato_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST SALY: % · % · % · %', saly.nucleo_autotest_puerta_v1(), saly.nucleo_autotest_evaluacion_v1(), saly.nucleo_autotest_cambio_v1(), saly.nucleo_autotest_contrato_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST %', public.lf_nucleo_autotest_conjunto_v1();
END $v$;
COMMIT;

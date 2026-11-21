-- Núcleo de reglas, acople (3): lista priorizada para decidir el alcance de las reglas legadas de cobertura parcial (solo LF).
-- Para cada regla con varias pantallas que no cubre todo su ancestro común (última corrida de lf_ops.lf_legado_alcance)
-- cuenta qué pantallas del ancestro le faltan y si se crearon antes o después de la regla, y sugiere:
--   HEREDAR_PROBABLE         solo le faltan pantallas creadas después de la regla (la copia no se extendió)
--   REVISAR_COPIA_INCOMPLETA cubre al menos el umbral alto del ancestro y le faltan pantallas que ya existían
--   SUBCONJUNTO_PROBABLE     cubre menos del umbral bajo del ancestro
--   REVISAR                  el resto
-- Los umbrales están en lf_global_config (NUCLEO_MIGRACION.*). La sugerencia no decide nada: la decisión es del dueño.
BEGIN;

INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO_MIGRACION','COBERTURA_ALTA','0.9','DECIMAL','REAL','Cobertura del ancestro común desde la que una regla legada parcial se sugiere como copia incompleta.'),
 ('NUCLEO_MIGRACION','COBERTURA_BAJA','0.3','DECIMAL','REAL','Cobertura del ancestro común bajo la cual una regla legada parcial se sugiere como subconjunto intencional.');

CREATE OR REPLACE VIEW lf_ops.v_legado_alcance_decision WITH (security_invoker = true) AS
WITH c AS (SELECT max(corrida) AS c FROM lf_ops.lf_legado_alcance),
p AS (SELECT a.regla_id, a.ancestro, a.pantallas_en_arbol, a.pantallas_bajo_ancestro
        FROM lf_ops.lf_legado_alcance a JOIN c ON a.corrida = c.c WHERE a.propuesta = 'APLICACIONES_POR_PANTALLA'),
bajo AS (SELECT p.regla_id, n.pantalla_id FROM p
          JOIN LATERAL (WITH RECURSIVE dn(cod) AS (SELECT p.ancestro UNION ALL SELECT m.codigo FROM lf_ops.nucleo_nodos m JOIN dn ON m.padre = dn.cod)
                        SELECT x.pantalla_id FROM lf_ops.nucleo_nodos x WHERE x.codigo IN (SELECT cod FROM dn) AND x.nivel = 'PANTALLA') n ON true),
falt AS (SELECT b.regla_id, count(*) FILTER (WHERE pa.created_at > r.created_at) AS posteriores,
                count(*) FILTER (WHERE pa.created_at <= r.created_at) AS anteriores
           FROM bajo b JOIN lf_ops.pantallas pa ON pa.id = b.pantalla_id JOIN lf_ops.reglas r ON r.id = b.regla_id
          WHERE NOT EXISTS (SELECT 1 FROM lf_ops.reglas_pantallas rp WHERE rp.regla_id = b.regla_id AND rp.pantalla_id = b.pantalla_id)
          GROUP BY b.regla_id),
u AS (SELECT (SELECT g.config_value::numeric FROM public.lf_global_config g WHERE g.scope = 'NUCLEO_MIGRACION' AND g.config_key = 'COBERTURA_ALTA' AND g.valid_from <= now() ORDER BY g.valid_from DESC LIMIT 1) AS alta,
             (SELECT g.config_value::numeric FROM public.lf_global_config g WHERE g.scope = 'NUCLEO_MIGRACION' AND g.config_key = 'COBERTURA_BAJA' AND g.valid_from <= now() ORDER BY g.valid_from DESC LIMIT 1) AS baja)
SELECT r.id AS regla_id, r.codigo, f.familia, r.estado, p.ancestro, p.pantallas_en_arbol AS enlazadas, p.pantallas_bajo_ancestro AS bajo_ancestro,
       round(p.pantallas_en_arbol::numeric / p.pantallas_bajo_ancestro, 2) AS cobertura,
       COALESCE(ft.posteriores, 0) AS faltan_posteriores, COALESCE(ft.anteriores, 0) AS faltan_anteriores,
       CASE WHEN COALESCE(ft.anteriores, 0) = 0 THEN 'HEREDAR_PROBABLE'
            WHEN p.pantallas_en_arbol::numeric / p.pantallas_bajo_ancestro >= u.alta THEN 'REVISAR_COPIA_INCOMPLETA'
            WHEN p.pantallas_en_arbol::numeric / p.pantallas_bajo_ancestro < u.baja THEN 'SUBCONJUNTO_PROBABLE'
            ELSE 'REVISAR' END AS sugerencia
  FROM p JOIN lf_ops.reglas r ON r.id = p.regla_id
  LEFT JOIN lf_ops.nucleo_regla_familia f ON f.regla_id = p.regla_id
  LEFT JOIN falt ft ON ft.regla_id = p.regla_id
  CROSS JOIN u;
COMMENT ON VIEW lf_ops.v_legado_alcance_decision IS 'Reglas legadas de cobertura parcial con la sugerencia de alcance para que el dueño decida (heredar en el ancestro o aplicar solo a esas pantallas).';

REVOKE ALL ON lf_ops.v_legado_alcance_decision FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN GRANT SELECT ON lf_ops.v_legado_alcance_decision TO service_role; END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN GRANT SELECT ON lf_ops.v_legado_alcance_decision TO supabase_read_only_user; END IF;
END $g$;

-- Verificación: una fila por regla parcial, sugerencia siempre presente, y las cuentas cuadran con los enlaces
DO $v$
DECLARE v_n bigint; v_p bigint; v_mal bigint;
BEGIN
  SELECT count(*) INTO v_n FROM lf_ops.v_legado_alcance_decision;
  SELECT count(*) INTO v_p FROM lf_ops.lf_legado_alcance WHERE corrida = (SELECT max(corrida) FROM lf_ops.lf_legado_alcance) AND propuesta = 'APLICACIONES_POR_PANTALLA';
  SELECT count(*) INTO v_mal FROM lf_ops.v_legado_alcance_decision
   WHERE sugerencia IS NULL OR enlazadas + faltan_posteriores + faltan_anteriores <> bajo_ancestro OR faltan_posteriores + faltan_anteriores = 0;
  IF v_n <> v_p OR v_mal <> 0 THEN RAISE EXCEPTION 'NUCLEO_ALCANCE_DECISION_INCONSISTENTE: % filas de %, % inconsistentes', v_n, v_p, v_mal; END IF;
  RAISE NOTICE 'NUCLEO_ALCANCE_DECISION: % reglas, sugerencias: %', v_n,
    (SELECT string_agg(sugerencia || '=' || c, ', ' ORDER BY sugerencia) FROM (SELECT sugerencia, count(*) c FROM lf_ops.v_legado_alcance_decision GROUP BY 1) x);
END $v$;
COMMIT;

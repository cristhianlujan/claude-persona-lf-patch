-- Núcleo de reglas: autoridades de las reglas legadas (decisión del dueño D6, 2026-11-20 23:40 Lima).
-- Las 167 etiquetas de origen de lf_ops.reglas se agrupan en 11 autoridades confirmadas por el dueño (LEG-*).
-- Las reglas sin origen (grupo SIN_ORIGEN) quedan sin autoridad hasta que tengan respaldo.
-- El mapa etiqueta → autoridad son datos (patrones en orden; gana el primero que coincide) y la sombra lo usa.
BEGIN;

INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion) VALUES
 ('LEG-LEGAL_NORMA','NORMA','Norma o texto legal vigente (leyes, SBS, INDECOPI, DS) (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-DUENO','DECISION_DUENO','Decisión o aprobación explícita del dueño (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-DECISION_REGISTRADA','DECISION_DUENO','Decisión de producto registrada con código DEC (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-SEGURIDAD','POLITICA','Seguridad y autenticación (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-PROVEEDOR','POLITICA','Definición del proveedor de pagos (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-HANDOFF','POLITICA','Entrega formal de requerimientos (handoff e insumos de backoffice) (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-UX','POLITICA','Diseño, experiencia y textos (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-PRODUCTO','POLITICA','Decisión de producto o negocio sin registro formal (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-REVISION_FUNCIONAL','ANALISIS','Revisión o conciliación funcional de pantallas y flujos (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-INVESTIGACION','ANALISIS','Investigación externa (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)'),
 ('LEG-TECNICO','ANALISIS','Criterio técnico, análisis de sesión, actividades y contratos existentes (grupo de origen de reglas legadas confirmado por el dueño, D6 2026-11-20)');

CREATE TABLE lf_ops.lf_legado_autoridad_mapa (
  orden integer PRIMARY KEY,
  patron text NOT NULL,
  sin_mayusculas boolean NOT NULL DEFAULT false,
  grupo text NOT NULL,
  autoridad text REFERENCES lf_ops.nucleo_autoridades(codigo),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lf_legado_autoridad_mapa_grupo CHECK ((grupo = 'SIN_ORIGEN') = (autoridad IS NULL))
);
COMMENT ON TABLE lf_ops.lf_legado_autoridad_mapa IS 'Mapa de etiquetas de origen de reglas legadas a autoridades del núcleo (D6). Gana el primer patrón que coincide.';
INSERT INTO lf_ops.lf_legado_autoridad_mapa (orden, patron, sin_mayusculas, grupo, autoridad) VALUES
 (10,'^legal$',false,'LEGAL_NORMA','LEG-LEGAL_NORMA'),
 (20,'ley_',false,'LEGAL_NORMA','LEG-LEGAL_NORMA'),
 (30,'^LEY_',false,'LEGAL_NORMA','LEG-LEGAL_NORMA'),
 (40,'^DS_',false,'LEGAL_NORMA','LEG-LEGAL_NORMA'),
 (50,'^INDECOPI',false,'LEGAL_NORMA','LEG-LEGAL_NORMA'),
 (60,'^SBS_',false,'LEGAL_NORMA','LEG-LEGAL_NORMA'),
 (70,'^OWNER_',false,'DUENO','LEG-DUENO'),
 (80,'^DECISION_USUARIO',false,'DUENO','LEG-DUENO'),
 (90,'^USER_REQUIREMENT',false,'DUENO','LEG-DUENO'),
 (100,'^IG_.*OWNER',false,'DUENO','LEG-DUENO'),
 (110,'^IG_\d+_USER_APPROVED',false,'DUENO','LEG-DUENO'),
 (120,'^DEC-',false,'DECISION_REGISTRADA','LEG-DECISION_REGISTRADA'),
 (130,'^seguridad$',false,'SEGURIDAD','LEG-SEGURIDAD'),
 (140,'AUTH',false,'SEGURIDAD','LEG-SEGURIDAD'),
 (150,'PASSWORD_RECOVERY',false,'SEGURIDAD','LEG-SEGURIDAD'),
 (160,'niubiz',true,'PROVEEDOR','LEG-PROVEEDOR'),
 (170,'^HANDOFF_',false,'HANDOFF','LEG-HANDOFF'),
 (180,'^LF_INPUTS_BACKOFFICE',false,'HANDOFF','LEG-HANDOFF'),
 (190,'^LF_BACKOFFICE_INPUT',false,'HANDOFF','LEG-HANDOFF'),
 (200,'^LF_BACKOFFICE_B2B$',false,'HANDOFF','LEG-HANDOFF'),
 (210,'^ux$',false,'UX','LEG-UX'),
 (220,'^copy$',false,'UX','LEG-UX'),
 (230,'^decision_ui',false,'UX','LEG-UX'),
 (240,'^SEALED_',false,'UX','LEG-UX'),
 (250,'^VD_',false,'UX','LEG-UX'),
 (260,'^decision_producto',false,'PRODUCTO','LEG-PRODUCTO'),
 (270,'^negocio$',false,'PRODUCTO','LEG-PRODUCTO'),
 (280,'^b2b$',false,'PRODUCTO','LEG-PRODUCTO'),
 (290,'^flujo$',false,'PRODUCTO','LEG-PRODUCTO'),
 (300,'^PRODUCT_ANALYSIS',false,'PRODUCTO','LEG-PRODUCTO'),
 (310,'^CLIENT_',false,'REVISION_FUNCIONAL','LEG-REVISION_FUNCIONAL'),
 (320,'^READBACK_',false,'REVISION_FUNCIONAL','LEG-REVISION_FUNCIONAL'),
 (330,'^CURRENT_CHAT_',false,'REVISION_FUNCIONAL','LEG-REVISION_FUNCIONAL'),
 (340,'^HOME_\d+',false,'REVISION_FUNCIONAL','LEG-REVISION_FUNCIONAL'),
 (350,'^REG_',false,'REVISION_FUNCIONAL','LEG-REVISION_FUNCIONAL'),
 (360,'^research_externo',false,'INVESTIGACION','LEG-INVESTIGACION'),
 (370,'competencia',false,'INVESTIGACION','LEG-INVESTIGACION'),
 (380,'^tecnico$',false,'TECNICO','LEG-TECNICO'),
 (390,'^analisis_sesion',false,'TECNICO','LEG-TECNICO'),
 (400,'^ACT-',false,'TECNICO','LEG-TECNICO'),
 (410,'^lf_knowledge_base',false,'TECNICO','LEG-TECNICO'),
 (420,'^EXISTING_',false,'TECNICO','LEG-TECNICO'),
 (430,'^LF_E21_',false,'TECNICO','LEG-TECNICO'),
 (440,'^LF_EMPRESA_',false,'TECNICO','LEG-TECNICO'),
 (450,'^\(vacío\)$',false,'SIN_ORIGEN',NULL);

CREATE OR REPLACE FUNCTION lf_ops.lf_legado_autoridad_v1(p_origen text)
RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, lf_ops AS $$
  SELECT m.autoridad FROM lf_legado_autoridad_mapa m
   WHERE CASE WHEN m.sin_mayusculas THEN COALESCE(p_origen, '(vacío)') ~* m.patron ELSE COALESCE(p_origen, '(vacío)') ~ m.patron END
   ORDER BY m.orden LIMIT 1
$$;

CREATE OR REPLACE FUNCTION lf_ops.lf_legado_sombra_regla_v1(p_regla integer, p_corrida timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  r record; a record; v_p jsonb; v_res jsonb; v_fall text[]; v_brechas text[]; v_sinexp text[]; v_alc text;
  v_mapa jsonb := '{"Campos obligatorios":"SIN_ESTRUCTURA","Condición bien formada":"SIN_ESTRUCTURA","Efecto coherente con la naturaleza":"SIN_ESTRUCTURA",
                    "Pruebas mínimas de la familia":"SIN_PRUEBAS","Pruebas relativas al parámetro":"SIN_PRUEBAS","Pruebas se ejecutan y pasan":"SIN_PRUEBAS",
                    "Autoridad vigente":"SIN_AUTORIDAD_REGISTRADA","Familia existe":"SIN_FAMILIA","Alcance existe":"ALCANCE_POR_DERIVAR",
                    "Clase coherente con el alcance":"ALCANCE_POR_DERIVAR","Código libre":"YA_EN_EL_NUCLEO","Clasificación contra lo existente":"DUPLICADO_EN_LEGADO",
                    "Sin conflicto con reglas fijas superiores":"CONFLICTO_FIJA"}';
BEGIN
  SELECT g.*, f.familia, f.naturaleza INTO r FROM reglas g LEFT JOIN nucleo_regla_familia f ON f.regla_id = g.id WHERE g.id = p_regla;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT * INTO a FROM lf_legado_alcance_v1(p_regla);
  v_alc := CASE WHEN a.propuesta IN ('TRANSVERSAL','UNA_PANTALLA','HEREDA_EN_ANCESTRO') THEN a.aplicaciones[1]
                WHEN a.propuesta = 'APLICACIONES_POR_PANTALLA' THEN a.aplicaciones[1] END;
  v_p := jsonb_build_object(
    'codigo', r.codigo, 'clave', left(trim(BOTH '_' FROM lower(regexp_replace(r.codigo, '[^A-Za-z0-9]+', '_', 'g'))), 80),
    'titulo', r.titulo, 'descripcion', r.descripcion, 'familia', r.familia, 'naturaleza', r.naturaleza,
    'autoridad', lf_legado_autoridad_v1(r.origen), 'dueno', COALESCE(r.created_by, 'LEGADO'), 'alcance', v_alc, 'modo', 'HEREDA',
    'clase', CASE WHEN a.propuesta = 'TRANSVERSAL' OR (SELECT nivel FROM nucleo_nodos WHERE codigo = v_alc) IN ('GLOBAL','AMBITO') THEN 'TRANSVERSAL' ELSE 'PANTALLA' END,
    'impacto', 'IMPLEMENTAR', 'origen', jsonb_build_object('tipo','MIGRACION','ref','lf_ops.reglas/' || r.id,'solicitante', COALESCE(r.created_by, 'legado')));
  v_res := nucleo_regla_proponer_v1(v_p, false);
  SELECT COALESCE(array_agg(DISTINCT x->>'control' ORDER BY x->>'control'), '{}') INTO v_fall
    FROM jsonb_array_elements(v_res->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
  SELECT COALESCE(array_agg(DISTINCT v_mapa->>f ORDER BY v_mapa->>f) FILTER (WHERE v_mapa ? f), '{}'),
         COALESCE(array_agg(f ORDER BY f) FILTER (WHERE NOT v_mapa ? f), '{}')
    INTO v_brechas, v_sinexp FROM unnest(v_fall) f;
  IF a.propuesta IN ('APLICACIONES_POR_PANTALLA','SIN_PANTALLAS_EN_ARBOL') THEN v_brechas := array_append(v_brechas, 'ALCANCE_POR_DERIVAR'); END IF;
  INSERT INTO lf_legado_sombra VALUES (p_corrida, r.id, r.codigo, r.estado, r.origen, r.created_by, r.familia,
    COALESCE(a.propuesta || ':' || array_to_string(a.aplicaciones, ','), a.propuesta), a.pantallas,
    v_res->>'resultado', v_fall, (SELECT COALESCE(array_agg(DISTINCT b ORDER BY b), '{}') FROM unnest(v_brechas) b), v_sinexp)
  ON CONFLICT (corrida, regla_id) DO UPDATE SET resultado = EXCLUDED.resultado, fallidos = EXCLUDED.fallidos, brechas = EXCLUDED.brechas,
    sin_explicar = EXCLUDED.sin_explicar, alcance_propuesto = EXCLUDED.alcance_propuesto, estado_legado = EXCLUDED.estado_legado;
END $$;

REVOKE ALL ON lf_ops.lf_legado_autoridad_mapa FROM PUBLIC, anon, authenticated;
ALTER TABLE lf_ops.lf_legado_autoridad_mapa ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.lf_legado_autoridad_mapa AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION lf_ops.lf_legado_autoridad_v1(text) FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.lf_legado_autoridad_v1(text) TO service_role; GRANT SELECT ON lf_ops.lf_legado_autoridad_mapa TO service_role;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.lf_legado_autoridad_v1(text) TO supabase_read_only_user; GRANT SELECT ON lf_ops.lf_legado_autoridad_mapa TO supabase_read_only_user;
  END IF;
END $g$;

-- Verificación: toda etiqueta cae en un grupo; solo SIN_ORIGEN queda sin autoridad; la sombra lo refleja
DO $v$
DECLARE v_sin bigint; v_noaut bigint; v_c timestamptz; v_brecha bigint; v_vacias bigint;
BEGIN
  SELECT count(*) INTO v_sin FROM (SELECT DISTINCT COALESCE(origen,'(vacío)') o FROM lf_ops.reglas) t
   WHERE NOT EXISTS (SELECT 1 FROM lf_ops.lf_legado_autoridad_mapa m WHERE CASE WHEN m.sin_mayusculas THEN t.o ~* m.patron ELSE t.o ~ m.patron END);
  SELECT count(*) INTO v_noaut FROM lf_ops.reglas WHERE lf_ops.lf_legado_autoridad_v1(origen) IS NULL;
  SELECT count(*) INTO v_vacias FROM lf_ops.reglas WHERE origen IS NULL OR btrim(origen) = '';
  IF v_sin <> 0 OR v_noaut <> (SELECT count(*) FROM lf_ops.reglas WHERE COALESCE(origen,'(vacío)') = '(vacío)') THEN
    RAISE EXCEPTION 'NUCLEO_AUTORIDAD_MAPA_INCOMPLETO: % etiquetas sin grupo, % reglas sin autoridad', v_sin, v_noaut;
  END IF;
  PERFORM lf_ops.lf_legado_sombra_v1(true);
  SELECT max(corrida) INTO v_c FROM lf_ops.lf_legado_alcance;
  SELECT count(*) INTO v_brecha FROM lf_ops.lf_legado_sombra WHERE corrida = v_c AND 'SIN_AUTORIDAD_REGISTRADA' = ANY (brechas);
  IF v_brecha <> v_noaut OR EXISTS (SELECT 1 FROM lf_ops.lf_legado_sombra WHERE corrida = v_c AND cardinality(sin_explicar) > 0) THEN
    RAISE EXCEPTION 'NUCLEO_AUTORIDAD_SOMBRA_INCONSISTENTE: % con brecha de autoridad, % sin autoridad', v_brecha, v_noaut;
  END IF;
  RAISE NOTICE 'NUCLEO_AUTORIDADES: 11 registradas; % reglas sin autoridad (sin origen); sombra con brecha de autoridad: %', v_noaut, v_brecha;
  RAISE NOTICE 'NUCLEO_AUTOTEST % · %', lf_ops.lf_puente_autotest_v1(), lf_ops.lf_puente2_autotest_v1();
END $v$;
COMMIT;

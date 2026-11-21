-- Núcleo de reglas, acople (parte reversible): A0 contratos de las puertas, A1 vista de compatibilidad, A2 modo sombra.
-- A0 (motor, en LF y en SALY, mismo código): contratos versionados de cada puerta, catálogo de los códigos de error
--    y casos de aceptación y rechazo como datos, con un verificador que cualquier cliente puede correr.
-- A1 (solo LF): lf_ops.v_reglas_compat_v1, con la misma forma que lf_ops.reglas: reglas legadas no migradas + reglas del núcleo.
-- A2 (solo LF): lf_ops.lf_legado_sombra_v1 evalúa sin escribir cada regla legada con la puerta del núcleo y explica cada
--    rechazo con una brecha conocida; la primera corrida queda guardada en lf_ops.lf_legado_sombra.
-- Nada de esto cambia lo que hoy escriben o leen IG, T_REMED ni los agentes: es reversible.
BEGIN;
-- ===== A0 en la instancia lf_ops =====
CREATE TABLE lf_ops.nucleo_contratos (
  puerta text NOT NULL,
  version integer NOT NULL,
  funcion text NOT NULL,
  descripcion text NOT NULL,
  entrada jsonb NOT NULL,
  salida jsonb NOT NULL,
  estado text NOT NULL DEFAULT 'VIGENTE',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (puerta, version),
  CONSTRAINT nucleo_contratos_estado CHECK (estado IN ('VIGENTE','REEMPLAZADO')),
  CONSTRAINT nucleo_contratos_descripcion CHECK (length(btrim(descripcion)) >= 20)
);
COMMENT ON TABLE lf_ops.nucleo_contratos IS 'Contratos versionados de las puertas del núcleo: función, entrada y salida. Los clientes (IG, T_REMED, perfiles, desarrollo) se acoplan solo a esto.';
INSERT INTO lf_ops.nucleo_contratos (puerta, version, funcion, descripcion, entrada, salida) VALUES
 ('LECTURA', 1, 'nucleo_reglas_efectivas_v1', 'Reglas que aplican a un nodo en una fecha, incluidas las heredadas; única puerta de lectura',
  '{"nodo":"text, código del árbol","fecha":"timestamptz, opcional (ahora)"}',
  '{"filas":["regla","clave","version","nodo_origen","modo","distancia","conflicto"]}'),
 ('PROPUESTA', 1, 'nucleo_regla_proponer_v1', 'Alta (NUEVA) o cambio (CAMBIO) de una regla; aplica los controles y deja una versión candidata; única puerta de escritura',
  '{"obligatorios":"ver nucleo_contrato_campos (globales y de la familia)","tipo":"NUEVA|CAMBIO","condicion":"árbol {op,izq,der} con hojas {hecho},{param},{lit}","pruebas":"[{casuistica,entrada,esperado}]","origen":"{tipo IG|CHAT|PERSONA|MIGRACION, ref, solicitante}","impacto":"NINGUNO|REVISAR|IMPLEMENTAR","plazo_dias":"entero, opcional","aplicar":"boolean, false = solo evaluar"}',
  '{"resultado":"CANDIDATA|RECHAZADA|EVALUADA_SIN_ESCRIBIR","tipo":"NUEVA|CAMBIO","version":"entero o null","clasificacion":"NUEVA|ESPECIALIZA x|DUPLICADO_DE x|NUEVA_VERSION_DE x","bloqueantes":"entero","avisos":"entero","controles":"[{n,control,ok,bloqueante,detalle}]"}'),
 ('JUICIO', 1, 'nucleo_juicio_registrar_v1', 'Registro del juicio semántico contra la rúbrica, atado al hash de la versión candidata y sus pruebas',
  '{"regla":"text","hash_evaluado":"sha256 del paquete","veredicto":"PASS|DEVOLVER","puntajes":"{criterio:{puntaje 0..1, observacion}}","juez":"text","modo":"INDEPENDIENTE|CONTEXTO_ACTUAL","revisor_es_productor":"boolean","llamadas_modelo":"entero","evidencia_ref":"text"}',
  '{"juicio_id":"bigint","version":"entero","calidad":"0..1","semantica":"0..1","coherencia":"0..1"}'),
 ('PROMOCION', 1, 'nucleo_regla_promover_v1', 'Evalúa la versión candidata y la publica si corresponde (AUTO) o con decisión de una autoridad (MANUAL)',
  '{"regla":"text","decision":"opcional {decision APROBAR|RECHAZAR, autoridad, motivo}"}',
  '{"resultado":"PROMOVIDA_AUTO|PROMOVIDA_MANUAL|PENDIENTE_DECISION|RECHAZADA_POR_DUENO|DEVUELTA|BLOQUEADA|NO_APLICA","nota":"entero","decision":"AUTO|MANUAL|DEVUELTA|BLOQUEADA","motivos":"[{dimension,detalle}]"}'),
 ('DESCARTE', 1, 'nucleo_version_descartar_v1', 'Descarta la versión candidata de una regla con autoridad y motivo; libera la regla para un cambio nuevo',
  '{"regla":"text","autoridad":"text","motivo":"text, mínimo 10 caracteres"}', '{"regla":"text","version":"entero","estado":"DESCARTADA"}'),
 ('COLA', 1, 'nucleo_cola_trabajo_v1', 'Estado de implementación de cada regla efectiva en cada nodo hoja',
  '{"nodo":"text, opcional","fecha":"timestamptz, opcional"}', '{"filas":["nodo","regla","version_implementada","version_pendiente","exigible_desde","estado AL_DIA|EN_PLAZO|DESFASADO"]}'),
 ('REVALIDACION', 1, 'nucleo_revalidacion_v1', 'Versiones vigentes o candidatas que dejaron de cumplir el contrato, sus pruebas o sus parámetros',
  '{}', '{"filas":["regla","version","motivo CONTRATO|PRUEBAS|PARAMETRO","detalle"]}');

CREATE TABLE lf_ops.nucleo_errores (
  codigo text PRIMARY KEY,
  puerta text NOT NULL,
  significado text NOT NULL,
  accion text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_errores_codigo CHECK (codigo ~ '^NUCLEO_[A-Z_]+$'),
  CONSTRAINT nucleo_errores_textos CHECK (length(btrim(significado)) >= 10 AND length(btrim(accion)) >= 10)
);
COMMENT ON TABLE lf_ops.nucleo_errores IS 'Catálogo de errores del núcleo: cada código que lanza el motor, qué significa y qué debe hacer quien llama. Una autoprueba exige que esté completo.';
INSERT INTO lf_ops.nucleo_errores (codigo, puerta, significado, accion) VALUES
 ('NUCLEO_NODO_INEXISTENTE','LECTURA','El nodo pedido no existe en el árbol de alcance','Usar un código de nucleo_nodos'),
 ('NUCLEO_REGLA_INEXISTENTE','PROMOCION','La regla indicada no existe','Revisar el código de la regla'),
 ('NUCLEO_EVAL_CONFIG_FALTA','PROMOCION','Falta un peso, umbral o plazo en la configuración de la instancia','Registrar el valor en la configuración global'),
 ('NUCLEO_EVAL_PESOS_INVALIDOS','PROMOCION','Los pesos de la evaluación no suman 100','Corregir los pesos en la configuración'),
 ('NUCLEO_EVAL_UMBRALES_INVALIDOS','PROMOCION','El umbral de revisión es mayor que el automático','Corregir los umbrales en la configuración'),
 ('NUCLEO_EVAL_HECHO_SIN_VALOR','PROPUESTA','Una prueba no trae valor para un dato de la condición','Agregar el dato a la entrada de la prueba'),
 ('NUCLEO_EVAL_NODO_INVALIDO','PROPUESTA','La condición tiene un nodo que no es un objeto','Corregir la forma de la condición'),
 ('NUCLEO_EVAL_OPERADOR_INVALIDO','PROPUESTA','La condición usa un operador desconocido','Usar y, o, no, =, !=, >, >=, <, <='),
 ('NUCLEO_EVAL_PARAM_INEXISTENTE','PROPUESTA','La condición o una prueba usa un parámetro que no existe','Registrar el parámetro o corregir su nombre'),
 ('NUCLEO_JUICIO_HASH_DISTINTO','JUICIO','El juez evaluó un contenido distinto del vigente','Volver a juzgar con el hash actual'),
 ('NUCLEO_JUICIO_RUBRICA_INCOMPLETA','JUICIO','Falta un criterio de la rúbrica o su observación','Puntuar todos los criterios activos y observar los menores que 1'),
 ('NUCLEO_JUICIO_SIN_VERSION_CANDIDATA','JUICIO','La regla no tiene una versión candidata que juzgar','Proponer una versión antes de juzgar'),
 ('NUCLEO_JUICIO_VEREDICTO_INCOHERENTE','JUICIO','Veredicto PASS con una dimensión bajo el umbral','Corregir el veredicto o los puntajes'),
 ('NUCLEO_DECISION_AUTORIDAD_NO_VIGENTE','PROMOCION','La autoridad de la decisión no está vigente','Usar una autoridad vigente de nucleo_autoridades'),
 ('NUCLEO_DECISION_NO_APLICA','PROMOCION','Se envió una decisión humana para una evaluación que no es MANUAL','Atender los motivos de la evaluación'),
 ('NUCLEO_PUBLICAR_NO_CANDIDATA','PROMOCION','La versión a publicar no está candidata','Revisar el estado de la versión'),
 ('NUCLEO_PUBLICAR_SIN_PROMOCION','PROMOCION','La versión no tiene evaluación AUTO ni aprobación sobre su contenido actual','Promover por nucleo_regla_promover_v1'),
 ('NUCLEO_DESCARTE_AUTORIDAD_NO_VIGENTE','DESCARTE','La autoridad del descarte no está vigente','Usar una autoridad vigente'),
 ('NUCLEO_DESCARTE_SIN_CANDIDATA','DESCARTE','La regla no tiene versión candidata que descartar','Revisar la regla'),
 ('NUCLEO_DESCARTE_SIN_MOTIVO','DESCARTE','Falta el motivo del descarte','Indicar un motivo de al menos 10 caracteres'),
 ('NUCLEO_HISTORIAL_INMUTABLE','INTERNO','Se intentó cambiar o borrar un registro de historial','El historial solo admite inserciones'),
 ('NUCLEO_IMPLEMENTACION_VERSION_NO_PUBLICADA','COLA','Se registró la implementación de una versión no publicada','Registrar solo versiones publicadas'),
 ('NUCLEO_PRUEBA_FUERA_DE_VERSION','PROPUESTA','Se agregaron pruebas a una versión ya registrada','Las pruebas se registran con su versión; proponer un cambio'),
 ('NUCLEO_PRUEBA_INMUTABLE','INTERNO','Se intentó cambiar o borrar una prueba','Proponer un cambio de la regla'),
 ('NUCLEO_VERSION_ALTA_INVALIDA','INTERNO','Una versión intentó nacer publicada o con fechas','Registrar por la puerta de propuesta'),
 ('NUCLEO_VERSION_INMUTABLE','INTERNO','Se intentó cambiar el contenido de una versión','Proponer un cambio de la regla'),
 ('NUCLEO_VERSION_TRANSICION_FUERA_DE_RUTA','INTERNO','Se cambió el estado de una versión sin pasar por promoción o descarte','Usar las puertas de promoción o descarte'),
 ('NUCLEO_VERSION_TRANSICION_INVALIDA','INTERNO','Transición de estado de versión no permitida','Revisar el ciclo CANDIDATA, PUBLICADA, DESCARTADA'),
 ('NUCLEO_NODO_NIVEL_INVALIDO','INTERNO','Un nodo cuelga de otro de nivel igual o inferior','Respetar GLOBAL, AMBITO, MODULO, PANTALLA, COMPONENTE'),
 ('NUCLEO_PARAMETRO_INEXISTENTE','INTERNO','Se registraron metadatos de un parámetro que no existe en la configuración','Crear primero el parámetro'),
 ('NUCLEO_RELACION_CICLO','INTERNO','Una dependencia o reemplazo cerraría un ciclo','Revisar las relaciones entre reglas'),
 ('NUCLEO_HECHO_COLUMNA_INEXISTENTE','INTERNO','Un hecho apunta a una columna que no existe','Corregir tabla y columna de referencia');

-- Casos de contrato (aceptación y rechazo) como datos, para que cada cliente los ejecute
CREATE TABLE lf_ops.nucleo_contrato_casos (
  caso text PRIMARY KEY,
  puerta text NOT NULL,
  descripcion text NOT NULL,
  entrada jsonb NOT NULL,
  esperado jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_contrato_casos_puerta CHECK (puerta IN ('LECTURA','PROPUESTA'))
);
COMMENT ON TABLE lf_ops.nucleo_contrato_casos IS 'Casos de aceptación y rechazo de las puertas. PROPUESTA: la entrada se aplica sobre una propuesta válida de prueba. Se ejecutan con nucleo_contrato_verificar_v1().';
INSERT INTO lf_ops.nucleo_contrato_casos (caso, puerta, descripcion, entrada, esperado) VALUES
 ('P01','PROPUESTA','Una regla válida se acepta','{}','{"resultado":"EVALUADA_SIN_ESCRIBIR","fallidos":[]}'),
 ('P02','PROPUESTA','Un valor fijo en la condición se rechaza','{"condicion":{"op":">=","izq":{"hecho":"zzt_intentos"},"der":{"lit":3}}}','{"resultado":"RECHAZADA","fallidos":["Sin datos fijos"]}'),
 ('P03','PROPUESTA','Un campo obligatorio vacío se rechaza','{"titulo":""}','{"resultado":"RECHAZADA","fallidos":["Campos obligatorios"]}'),
 ('P04','PROPUESTA','Una familia inexistente se rechaza','{"familia":"NO_EXISTE"}','{"resultado":"RECHAZADA","fallidos":["Familia existe"]}'),
 ('P05','PROPUESTA','Un dato fuera del vocabulario se rechaza','{"condicion":{"op":">=","izq":{"hecho":"sueldo"},"der":{"param":"ZZT.MAX_INTENTOS"}}}','{"resultado":"RECHAZADA","fallidos":["Datos dentro del vocabulario"]}'),
 ('P06','PROPUESTA','Un parámetro inexistente se rechaza','{"condicion":{"op":">=","izq":{"hecho":"zzt_intentos"},"der":{"param":"ZZT.NO_EXISTE"}}}','{"resultado":"RECHAZADA","fallidos":["Parámetros existen"]}'),
 ('P07','PROPUESTA','Una condición mal formada se rechaza','{"condicion":"intentos >= 3"}','{"resultado":"RECHAZADA","fallidos":["Condición bien formada"]}'),
 ('P08','PROPUESTA','Una regla nueva sin impacto se rechaza','{"impacto":"NINGUNO"}','{"resultado":"RECHAZADA","fallidos":["Impacto declarado"]}'),
 ('P09','PROPUESTA','Un origen con tipo desconocido se rechaza','{"origen":{"tipo":"OTRO","ref":"EXEC-1","solicitante":"cliente"}}','{"resultado":"RECHAZADA","fallidos":["Origen del cambio"]}'),
 ('P10','PROPUESTA','El cambio de una regla inexistente se rechaza','{"tipo":"CAMBIO","codigo":"ZZT-NO-EXISTE"}','{"resultado":"RECHAZADA","fallidos":["Regla a cambiar"]}'),
 ('L01','LECTURA','Un nodo inexistente devuelve error','{"nodo":"NO-EXISTE"}','{"error":"NUCLEO_NODO_INEXISTENTE"}'),
 ('L02','LECTURA','Un nodo válido sin reglas devuelve cero filas','{"nodo":"ZZT-MOD-1"}','{"filas":0}');

-- Verificador de los casos (corre con datos propios dentro de una subtransacción y los deshace)
CREATE OR REPLACE FUNCTION lf_ops.nucleo_contrato_verificar_v1()
RETURNS TABLE (caso text, ok boolean, obtenido jsonb, esperado jsonb)
LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE c record; base jsonb; r jsonb; v_res jsonb := '[]';
BEGIN
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    base := jsonb_build_object('codigo','ZZT-CT-1','clave','zzt_contrato','titulo','Bloqueo por intentos de prueba',
      'descripcion','Bloquea al alcanzar el máximo de intentos configurado para la prueba de contrato',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','CONTRATO','alcance','ZZT-AMB','modo','HEREDA',
      'clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','contrato-casos','solicitante','contrato'),
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
        jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
        jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));
    FOR c IN SELECT * FROM lf_ops.nucleo_contrato_casos ORDER BY 1 LOOP
      IF c.puerta = 'PROPUESTA' THEN
        r := lf_ops.nucleo_regla_proponer_v1(base || c.entrada, false);
        r := jsonb_build_object('resultado', r->>'resultado', 'fallidos', COALESCE((SELECT jsonb_agg(DISTINCT x->>'control')
               FROM jsonb_array_elements(r->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean), '[]'));
        v_res := v_res || jsonb_build_object('caso', c.caso, 'obtenido', r, 'esperado', c.esperado,
          'ok', r->>'resultado' = c.esperado->>'resultado' AND (r->'fallidos') @> (c.esperado->'fallidos')
                AND (jsonb_array_length(c.esperado->'fallidos') > 0 OR jsonb_array_length(r->'fallidos') = 0));
      ELSE
        BEGIN
          r := jsonb_build_object('filas', (SELECT count(*) FROM lf_ops.nucleo_reglas_efectivas_v1(c.entrada->>'nodo')));
        EXCEPTION WHEN others THEN
          r := jsonb_build_object('error', substring(SQLERRM FROM '^(NUCLEO_[A-Z_]+)'));
        END;
        v_res := v_res || jsonb_build_object('caso', c.caso, 'obtenido', r, 'esperado', c.esperado, 'ok', r = c.esperado);
      END IF;
    END LOOP;
    RAISE EXCEPTION 'NUCLEO_CONTRATO_FIN';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_CONTRATO_FIN' THEN RAISE; END IF;
  END;
  RETURN QUERY SELECT x->>'caso', (x->>'ok')::boolean, x->'obtenido', x->'esperado' FROM jsonb_array_elements(v_res) x;
END $$;

-- Autoprueba del contrato: catálogo de errores completo y sin códigos muertos; todos los casos pasan
CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_contrato_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $autotest$
DECLARE v_txt text; v_n integer;
BEGIN
  SELECT string_agg(DISTINCT m[1], ', ') INTO v_txt
    FROM pg_proc p, regexp_matches(p.prosrc, 'RAISE EXCEPTION ''(NUCLEO_[A-Z_]+)', 'g') m
   WHERE p.pronamespace = 'lf_ops'::regnamespace AND (p.proname LIKE 'nucleo%' OR p.proname LIKE 'fn_nucleo%')
     AND p.proname NOT LIKE 'nucleo_autotest%' AND p.proname <> 'nucleo_contrato_verificar_v1'
     AND NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_errores e WHERE e.codigo = m[1]);
  IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T1 códigos sin catalogar: %', v_txt; END IF;
  SELECT string_agg(e.codigo, ', ') INTO v_txt FROM lf_ops.nucleo_errores e
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'lf_ops'::regnamespace
                      AND (p.proname LIKE 'nucleo%' OR p.proname LIKE 'fn_nucleo%') AND p.proname NOT LIKE 'nucleo_autotest%'
                      AND p.prosrc LIKE '%RAISE EXCEPTION ''' || e.codigo || '%');
  IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T2 códigos catalogados que ya no se lanzan: %', v_txt; END IF;
  SELECT string_agg(caso || ' obtuvo ' || obtenido::text, '; '), count(*) INTO v_txt, v_n FROM lf_ops.nucleo_contrato_verificar_v1() WHERE ok IS NOT TRUE;
  IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T3 casos de contrato que fallan: %', v_txt; END IF;
  SELECT count(*) INTO v_n FROM lf_ops.nucleo_contrato_verificar_v1();
  IF v_n <> (SELECT count(*) FROM lf_ops.nucleo_contrato_casos) OR v_n < 12 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T4 casos no ejecutados (%)', v_n; END IF;
  RETURN 'CONTRATO 4/4 (' || v_n || ' casos)';
END $autotest$;

REVOKE ALL ON lf_ops.nucleo_contratos, lf_ops.nucleo_errores, lf_ops.nucleo_contrato_casos FROM PUBLIC, anon, authenticated;
ALTER TABLE lf_ops.nucleo_contratos ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_errores ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_contrato_casos ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_contratos AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_errores AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_contrato_casos AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION lf_ops.nucleo_contrato_verificar_v1(), lf_ops.nucleo_autotest_contrato_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_contrato_verificar_v1(), lf_ops.nucleo_autotest_contrato_v1() TO service_role;
  END IF;
END $g$;

-- ===== A0 en la instancia saly =====
CREATE TABLE saly.nucleo_contratos (
  puerta text NOT NULL,
  version integer NOT NULL,
  funcion text NOT NULL,
  descripcion text NOT NULL,
  entrada jsonb NOT NULL,
  salida jsonb NOT NULL,
  estado text NOT NULL DEFAULT 'VIGENTE',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (puerta, version),
  CONSTRAINT nucleo_contratos_estado CHECK (estado IN ('VIGENTE','REEMPLAZADO')),
  CONSTRAINT nucleo_contratos_descripcion CHECK (length(btrim(descripcion)) >= 20)
);
COMMENT ON TABLE saly.nucleo_contratos IS 'Contratos versionados de las puertas del núcleo: función, entrada y salida. Los clientes (IG, T_REMED, perfiles, desarrollo) se acoplan solo a esto.';
INSERT INTO saly.nucleo_contratos (puerta, version, funcion, descripcion, entrada, salida) VALUES
 ('LECTURA', 1, 'nucleo_reglas_efectivas_v1', 'Reglas que aplican a un nodo en una fecha, incluidas las heredadas; única puerta de lectura',
  '{"nodo":"text, código del árbol","fecha":"timestamptz, opcional (ahora)"}',
  '{"filas":["regla","clave","version","nodo_origen","modo","distancia","conflicto"]}'),
 ('PROPUESTA', 1, 'nucleo_regla_proponer_v1', 'Alta (NUEVA) o cambio (CAMBIO) de una regla; aplica los controles y deja una versión candidata; única puerta de escritura',
  '{"obligatorios":"ver nucleo_contrato_campos (globales y de la familia)","tipo":"NUEVA|CAMBIO","condicion":"árbol {op,izq,der} con hojas {hecho},{param},{lit}","pruebas":"[{casuistica,entrada,esperado}]","origen":"{tipo IG|CHAT|PERSONA|MIGRACION, ref, solicitante}","impacto":"NINGUNO|REVISAR|IMPLEMENTAR","plazo_dias":"entero, opcional","aplicar":"boolean, false = solo evaluar"}',
  '{"resultado":"CANDIDATA|RECHAZADA|EVALUADA_SIN_ESCRIBIR","tipo":"NUEVA|CAMBIO","version":"entero o null","clasificacion":"NUEVA|ESPECIALIZA x|DUPLICADO_DE x|NUEVA_VERSION_DE x","bloqueantes":"entero","avisos":"entero","controles":"[{n,control,ok,bloqueante,detalle}]"}'),
 ('JUICIO', 1, 'nucleo_juicio_registrar_v1', 'Registro del juicio semántico contra la rúbrica, atado al hash de la versión candidata y sus pruebas',
  '{"regla":"text","hash_evaluado":"sha256 del paquete","veredicto":"PASS|DEVOLVER","puntajes":"{criterio:{puntaje 0..1, observacion}}","juez":"text","modo":"INDEPENDIENTE|CONTEXTO_ACTUAL","revisor_es_productor":"boolean","llamadas_modelo":"entero","evidencia_ref":"text"}',
  '{"juicio_id":"bigint","version":"entero","calidad":"0..1","semantica":"0..1","coherencia":"0..1"}'),
 ('PROMOCION', 1, 'nucleo_regla_promover_v1', 'Evalúa la versión candidata y la publica si corresponde (AUTO) o con decisión de una autoridad (MANUAL)',
  '{"regla":"text","decision":"opcional {decision APROBAR|RECHAZAR, autoridad, motivo}"}',
  '{"resultado":"PROMOVIDA_AUTO|PROMOVIDA_MANUAL|PENDIENTE_DECISION|RECHAZADA_POR_DUENO|DEVUELTA|BLOQUEADA|NO_APLICA","nota":"entero","decision":"AUTO|MANUAL|DEVUELTA|BLOQUEADA","motivos":"[{dimension,detalle}]"}'),
 ('DESCARTE', 1, 'nucleo_version_descartar_v1', 'Descarta la versión candidata de una regla con autoridad y motivo; libera la regla para un cambio nuevo',
  '{"regla":"text","autoridad":"text","motivo":"text, mínimo 10 caracteres"}', '{"regla":"text","version":"entero","estado":"DESCARTADA"}'),
 ('COLA', 1, 'nucleo_cola_trabajo_v1', 'Estado de implementación de cada regla efectiva en cada nodo hoja',
  '{"nodo":"text, opcional","fecha":"timestamptz, opcional"}', '{"filas":["nodo","regla","version_implementada","version_pendiente","exigible_desde","estado AL_DIA|EN_PLAZO|DESFASADO"]}'),
 ('REVALIDACION', 1, 'nucleo_revalidacion_v1', 'Versiones vigentes o candidatas que dejaron de cumplir el contrato, sus pruebas o sus parámetros',
  '{}', '{"filas":["regla","version","motivo CONTRATO|PRUEBAS|PARAMETRO","detalle"]}');

CREATE TABLE saly.nucleo_errores (
  codigo text PRIMARY KEY,
  puerta text NOT NULL,
  significado text NOT NULL,
  accion text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_errores_codigo CHECK (codigo ~ '^NUCLEO_[A-Z_]+$'),
  CONSTRAINT nucleo_errores_textos CHECK (length(btrim(significado)) >= 10 AND length(btrim(accion)) >= 10)
);
COMMENT ON TABLE saly.nucleo_errores IS 'Catálogo de errores del núcleo: cada código que lanza el motor, qué significa y qué debe hacer quien llama. Una autoprueba exige que esté completo.';
INSERT INTO saly.nucleo_errores (codigo, puerta, significado, accion) VALUES
 ('NUCLEO_NODO_INEXISTENTE','LECTURA','El nodo pedido no existe en el árbol de alcance','Usar un código de nucleo_nodos'),
 ('NUCLEO_REGLA_INEXISTENTE','PROMOCION','La regla indicada no existe','Revisar el código de la regla'),
 ('NUCLEO_EVAL_CONFIG_FALTA','PROMOCION','Falta un peso, umbral o plazo en la configuración de la instancia','Registrar el valor en la configuración global'),
 ('NUCLEO_EVAL_PESOS_INVALIDOS','PROMOCION','Los pesos de la evaluación no suman 100','Corregir los pesos en la configuración'),
 ('NUCLEO_EVAL_UMBRALES_INVALIDOS','PROMOCION','El umbral de revisión es mayor que el automático','Corregir los umbrales en la configuración'),
 ('NUCLEO_EVAL_HECHO_SIN_VALOR','PROPUESTA','Una prueba no trae valor para un dato de la condición','Agregar el dato a la entrada de la prueba'),
 ('NUCLEO_EVAL_NODO_INVALIDO','PROPUESTA','La condición tiene un nodo que no es un objeto','Corregir la forma de la condición'),
 ('NUCLEO_EVAL_OPERADOR_INVALIDO','PROPUESTA','La condición usa un operador desconocido','Usar y, o, no, =, !=, >, >=, <, <='),
 ('NUCLEO_EVAL_PARAM_INEXISTENTE','PROPUESTA','La condición o una prueba usa un parámetro que no existe','Registrar el parámetro o corregir su nombre'),
 ('NUCLEO_JUICIO_HASH_DISTINTO','JUICIO','El juez evaluó un contenido distinto del vigente','Volver a juzgar con el hash actual'),
 ('NUCLEO_JUICIO_RUBRICA_INCOMPLETA','JUICIO','Falta un criterio de la rúbrica o su observación','Puntuar todos los criterios activos y observar los menores que 1'),
 ('NUCLEO_JUICIO_SIN_VERSION_CANDIDATA','JUICIO','La regla no tiene una versión candidata que juzgar','Proponer una versión antes de juzgar'),
 ('NUCLEO_JUICIO_VEREDICTO_INCOHERENTE','JUICIO','Veredicto PASS con una dimensión bajo el umbral','Corregir el veredicto o los puntajes'),
 ('NUCLEO_DECISION_AUTORIDAD_NO_VIGENTE','PROMOCION','La autoridad de la decisión no está vigente','Usar una autoridad vigente de nucleo_autoridades'),
 ('NUCLEO_DECISION_NO_APLICA','PROMOCION','Se envió una decisión humana para una evaluación que no es MANUAL','Atender los motivos de la evaluación'),
 ('NUCLEO_PUBLICAR_NO_CANDIDATA','PROMOCION','La versión a publicar no está candidata','Revisar el estado de la versión'),
 ('NUCLEO_PUBLICAR_SIN_PROMOCION','PROMOCION','La versión no tiene evaluación AUTO ni aprobación sobre su contenido actual','Promover por nucleo_regla_promover_v1'),
 ('NUCLEO_DESCARTE_AUTORIDAD_NO_VIGENTE','DESCARTE','La autoridad del descarte no está vigente','Usar una autoridad vigente'),
 ('NUCLEO_DESCARTE_SIN_CANDIDATA','DESCARTE','La regla no tiene versión candidata que descartar','Revisar la regla'),
 ('NUCLEO_DESCARTE_SIN_MOTIVO','DESCARTE','Falta el motivo del descarte','Indicar un motivo de al menos 10 caracteres'),
 ('NUCLEO_HISTORIAL_INMUTABLE','INTERNO','Se intentó cambiar o borrar un registro de historial','El historial solo admite inserciones'),
 ('NUCLEO_IMPLEMENTACION_VERSION_NO_PUBLICADA','COLA','Se registró la implementación de una versión no publicada','Registrar solo versiones publicadas'),
 ('NUCLEO_PRUEBA_FUERA_DE_VERSION','PROPUESTA','Se agregaron pruebas a una versión ya registrada','Las pruebas se registran con su versión; proponer un cambio'),
 ('NUCLEO_PRUEBA_INMUTABLE','INTERNO','Se intentó cambiar o borrar una prueba','Proponer un cambio de la regla'),
 ('NUCLEO_VERSION_ALTA_INVALIDA','INTERNO','Una versión intentó nacer publicada o con fechas','Registrar por la puerta de propuesta'),
 ('NUCLEO_VERSION_INMUTABLE','INTERNO','Se intentó cambiar el contenido de una versión','Proponer un cambio de la regla'),
 ('NUCLEO_VERSION_TRANSICION_FUERA_DE_RUTA','INTERNO','Se cambió el estado de una versión sin pasar por promoción o descarte','Usar las puertas de promoción o descarte'),
 ('NUCLEO_VERSION_TRANSICION_INVALIDA','INTERNO','Transición de estado de versión no permitida','Revisar el ciclo CANDIDATA, PUBLICADA, DESCARTADA'),
 ('NUCLEO_NODO_NIVEL_INVALIDO','INTERNO','Un nodo cuelga de otro de nivel igual o inferior','Respetar GLOBAL, AMBITO, MODULO, PANTALLA, COMPONENTE'),
 ('NUCLEO_PARAMETRO_INEXISTENTE','INTERNO','Se registraron metadatos de un parámetro que no existe en la configuración','Crear primero el parámetro'),
 ('NUCLEO_RELACION_CICLO','INTERNO','Una dependencia o reemplazo cerraría un ciclo','Revisar las relaciones entre reglas'),
 ('NUCLEO_HECHO_COLUMNA_INEXISTENTE','INTERNO','Un hecho apunta a una columna que no existe','Corregir tabla y columna de referencia');

-- Casos de contrato (aceptación y rechazo) como datos, para que cada cliente los ejecute
CREATE TABLE saly.nucleo_contrato_casos (
  caso text PRIMARY KEY,
  puerta text NOT NULL,
  descripcion text NOT NULL,
  entrada jsonb NOT NULL,
  esperado jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_contrato_casos_puerta CHECK (puerta IN ('LECTURA','PROPUESTA'))
);
COMMENT ON TABLE saly.nucleo_contrato_casos IS 'Casos de aceptación y rechazo de las puertas. PROPUESTA: la entrada se aplica sobre una propuesta válida de prueba. Se ejecutan con nucleo_contrato_verificar_v1().';
INSERT INTO saly.nucleo_contrato_casos (caso, puerta, descripcion, entrada, esperado) VALUES
 ('P01','PROPUESTA','Una regla válida se acepta','{}','{"resultado":"EVALUADA_SIN_ESCRIBIR","fallidos":[]}'),
 ('P02','PROPUESTA','Un valor fijo en la condición se rechaza','{"condicion":{"op":">=","izq":{"hecho":"zzt_intentos"},"der":{"lit":3}}}','{"resultado":"RECHAZADA","fallidos":["Sin datos fijos"]}'),
 ('P03','PROPUESTA','Un campo obligatorio vacío se rechaza','{"titulo":""}','{"resultado":"RECHAZADA","fallidos":["Campos obligatorios"]}'),
 ('P04','PROPUESTA','Una familia inexistente se rechaza','{"familia":"NO_EXISTE"}','{"resultado":"RECHAZADA","fallidos":["Familia existe"]}'),
 ('P05','PROPUESTA','Un dato fuera del vocabulario se rechaza','{"condicion":{"op":">=","izq":{"hecho":"sueldo"},"der":{"param":"ZZT.MAX_INTENTOS"}}}','{"resultado":"RECHAZADA","fallidos":["Datos dentro del vocabulario"]}'),
 ('P06','PROPUESTA','Un parámetro inexistente se rechaza','{"condicion":{"op":">=","izq":{"hecho":"zzt_intentos"},"der":{"param":"ZZT.NO_EXISTE"}}}','{"resultado":"RECHAZADA","fallidos":["Parámetros existen"]}'),
 ('P07','PROPUESTA','Una condición mal formada se rechaza','{"condicion":"intentos >= 3"}','{"resultado":"RECHAZADA","fallidos":["Condición bien formada"]}'),
 ('P08','PROPUESTA','Una regla nueva sin impacto se rechaza','{"impacto":"NINGUNO"}','{"resultado":"RECHAZADA","fallidos":["Impacto declarado"]}'),
 ('P09','PROPUESTA','Un origen con tipo desconocido se rechaza','{"origen":{"tipo":"OTRO","ref":"EXEC-1","solicitante":"cliente"}}','{"resultado":"RECHAZADA","fallidos":["Origen del cambio"]}'),
 ('P10','PROPUESTA','El cambio de una regla inexistente se rechaza','{"tipo":"CAMBIO","codigo":"ZZT-NO-EXISTE"}','{"resultado":"RECHAZADA","fallidos":["Regla a cambiar"]}'),
 ('L01','LECTURA','Un nodo inexistente devuelve error','{"nodo":"NO-EXISTE"}','{"error":"NUCLEO_NODO_INEXISTENTE"}'),
 ('L02','LECTURA','Un nodo válido sin reglas devuelve cero filas','{"nodo":"ZZT-MOD-1"}','{"filas":0}');

-- Verificador de los casos (corre con datos propios dentro de una subtransacción y los deshace)
CREATE OR REPLACE FUNCTION saly.nucleo_contrato_verificar_v1()
RETURNS TABLE (caso text, ok boolean, obtenido jsonb, esperado jsonb)
LANGUAGE plpgsql SET search_path = pg_catalog, saly, public AS $$
DECLARE c record; base jsonb; r jsonb; v_res jsonb := '[]';
BEGIN
  BEGIN
    PERFORM saly.nucleo_autotest_datos_v1();
    base := jsonb_build_object('codigo','ZZT-CT-1','clave','zzt_contrato','titulo','Bloqueo por intentos de prueba',
      'descripcion','Bloquea al alcanzar el máximo de intentos configurado para la prueba de contrato',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','CONTRATO','alcance','ZZT-AMB','modo','HEREDA',
      'clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','contrato-casos','solicitante','contrato'),
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
        jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
        jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));
    FOR c IN SELECT * FROM saly.nucleo_contrato_casos ORDER BY 1 LOOP
      IF c.puerta = 'PROPUESTA' THEN
        r := saly.nucleo_regla_proponer_v1(base || c.entrada, false);
        r := jsonb_build_object('resultado', r->>'resultado', 'fallidos', COALESCE((SELECT jsonb_agg(DISTINCT x->>'control')
               FROM jsonb_array_elements(r->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean), '[]'));
        v_res := v_res || jsonb_build_object('caso', c.caso, 'obtenido', r, 'esperado', c.esperado,
          'ok', r->>'resultado' = c.esperado->>'resultado' AND (r->'fallidos') @> (c.esperado->'fallidos')
                AND (jsonb_array_length(c.esperado->'fallidos') > 0 OR jsonb_array_length(r->'fallidos') = 0));
      ELSE
        BEGIN
          r := jsonb_build_object('filas', (SELECT count(*) FROM saly.nucleo_reglas_efectivas_v1(c.entrada->>'nodo')));
        EXCEPTION WHEN others THEN
          r := jsonb_build_object('error', substring(SQLERRM FROM '^(NUCLEO_[A-Z_]+)'));
        END;
        v_res := v_res || jsonb_build_object('caso', c.caso, 'obtenido', r, 'esperado', c.esperado, 'ok', r = c.esperado);
      END IF;
    END LOOP;
    RAISE EXCEPTION 'NUCLEO_CONTRATO_FIN';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_CONTRATO_FIN' THEN RAISE; END IF;
  END;
  RETURN QUERY SELECT x->>'caso', (x->>'ok')::boolean, x->'obtenido', x->'esperado' FROM jsonb_array_elements(v_res) x;
END $$;

-- Autoprueba del contrato: catálogo de errores completo y sin códigos muertos; todos los casos pasan
CREATE OR REPLACE FUNCTION saly.nucleo_autotest_contrato_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, saly, public AS $autotest$
DECLARE v_txt text; v_n integer;
BEGIN
  SELECT string_agg(DISTINCT m[1], ', ') INTO v_txt
    FROM pg_proc p, regexp_matches(p.prosrc, 'RAISE EXCEPTION ''(NUCLEO_[A-Z_]+)', 'g') m
   WHERE p.pronamespace = 'saly'::regnamespace AND (p.proname LIKE 'nucleo%' OR p.proname LIKE 'fn_nucleo%')
     AND p.proname NOT LIKE 'nucleo_autotest%' AND p.proname <> 'nucleo_contrato_verificar_v1'
     AND NOT EXISTS (SELECT 1 FROM saly.nucleo_errores e WHERE e.codigo = m[1]);
  IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T1 códigos sin catalogar: %', v_txt; END IF;
  SELECT string_agg(e.codigo, ', ') INTO v_txt FROM saly.nucleo_errores e
   WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace = 'saly'::regnamespace
                      AND (p.proname LIKE 'nucleo%' OR p.proname LIKE 'fn_nucleo%') AND p.proname NOT LIKE 'nucleo_autotest%'
                      AND p.prosrc LIKE '%RAISE EXCEPTION ''' || e.codigo || '%');
  IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T2 códigos catalogados que ya no se lanzan: %', v_txt; END IF;
  SELECT string_agg(caso || ' obtuvo ' || obtenido::text, '; '), count(*) INTO v_txt, v_n FROM saly.nucleo_contrato_verificar_v1() WHERE ok IS NOT TRUE;
  IF v_txt IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T3 casos de contrato que fallan: %', v_txt; END IF;
  SELECT count(*) INTO v_n FROM saly.nucleo_contrato_verificar_v1();
  IF v_n <> (SELECT count(*) FROM saly.nucleo_contrato_casos) OR v_n < 12 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: T4 casos no ejecutados (%)', v_n; END IF;
  RETURN 'CONTRATO 4/4 (' || v_n || ' casos)';
END $autotest$;

REVOKE ALL ON saly.nucleo_contratos, saly.nucleo_errores, saly.nucleo_contrato_casos FROM PUBLIC, anon, authenticated;
ALTER TABLE saly.nucleo_contratos ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.nucleo_errores ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.nucleo_contrato_casos ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON saly.nucleo_contratos AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON saly.nucleo_errores AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON saly.nucleo_contrato_casos AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION saly.nucleo_contrato_verificar_v1(), saly.nucleo_autotest_contrato_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION saly.nucleo_contrato_verificar_v1(), saly.nucleo_autotest_contrato_v1() TO service_role;
  END IF;
END $g$;

-- ===== A1 y A2 en LF: puente con las reglas legadas (no es parte del motor; nombres sin prefijo nucleo) =====

-- A1 vista de compatibilidad: misma forma que lf_ops.reglas. Reglas legadas aún no migradas + reglas del núcleo.
CREATE OR REPLACE VIEW lf_ops.v_reglas_compat_v1 WITH (security_invoker = true) AS
SELECT r.id, r.codigo, r.categoria, r.titulo, r.descripcion, r.razon, r.valor_config, r.es_transversal, r.estado,
       r.origen, r.created_at, r.updated_at, r.pendiente_decision, r.pendiente_detalle, r.created_by
  FROM lf_ops.reglas r
 WHERE NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas n WHERE n.regla_legacy_id = r.id AND n.estado IN ('CANDIDATA','VIGENTE'))
UNION ALL
SELECT n.regla_legacy_id, n.codigo, n.familia, v.titulo, v.descripcion, NULL::text,
       jsonb_build_object('nucleo', true, 'version', v.version, 'condicion', v.condicion, 'efecto', v.efecto),
       COALESCE(a.nivel IN ('GLOBAL','AMBITO'), false),
       CASE n.estado WHEN 'VIGENTE' THEN 'VIGENTE' ELSE 'CANDIDATO' END,
       v.origen->>'ref', n.created_at, v.created_at, false, NULL::text, v.origen->>'solicitante'
  FROM lf_ops.nucleo_reglas n
  JOIN LATERAL (SELECT x.* FROM lf_ops.nucleo_regla_versiones x WHERE x.regla = n.codigo AND x.estado <> 'DESCARTADA'
                 ORDER BY (x.estado = 'PUBLICADA' AND x.vigente_hasta IS NULL) DESC, x.version DESC LIMIT 1) v ON true
  LEFT JOIN LATERAL (SELECT nn.nivel FROM lf_ops.nucleo_aplicaciones ap JOIN lf_ops.nucleo_nodos nn ON nn.codigo = ap.nodo
                      WHERE ap.regla = n.codigo ORDER BY ap.nodo LIMIT 1) a ON true
 WHERE n.estado IN ('CANDIDATA','VIGENTE');
COMMENT ON VIEW lf_ops.v_reglas_compat_v1 IS 'Compatibilidad durante la migración: misma forma que lf_ops.reglas. Muestra las reglas legadas no migradas y las del núcleo; los lectores (agentes de desarrollo) pueden apuntar aquí.';

-- A2 modo sombra: el núcleo evalúa sin escribir cada regla legada y explica cada rechazo con una brecha conocida
CREATE TABLE lf_ops.lf_legado_sombra (
  corrida timestamptz NOT NULL,
  regla_id integer NOT NULL,
  codigo text NOT NULL,
  estado_legado text NOT NULL,
  origen text,
  creado_por text,
  familia text,
  alcance_propuesto text,
  pantallas integer NOT NULL,
  resultado text NOT NULL,
  fallidos text[] NOT NULL,
  brechas text[] NOT NULL,
  sin_explicar text[] NOT NULL,
  PRIMARY KEY (corrida, regla_id)
);
COMMENT ON TABLE lf_ops.lf_legado_sombra IS 'Resultado del modo sombra: qué haría el núcleo con cada regla legada y qué brecha explica cada rechazo. Una corrida por fecha.';

CREATE OR REPLACE FUNCTION lf_ops.lf_legado_sombra_v1(p_guardar boolean DEFAULT true)
RETURNS TABLE (estado_legado text, origen text, resultado text, brecha text, reglas bigint, sin_explicar bigint)
LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  r record; v_p jsonb; v_res jsonb; v_fall text[]; v_brechas text[]; v_sinexp text[]; v_alc text; v_n integer; v_raiz text; v_corrida timestamptz := clock_timestamp();
  v_mapa jsonb := '{"Campos obligatorios":"SIN_ESTRUCTURA","Condición bien formada":"SIN_ESTRUCTURA","Efecto coherente con la naturaleza":"SIN_ESTRUCTURA",
                    "Pruebas mínimas de la familia":"SIN_PRUEBAS","Pruebas relativas al parámetro":"SIN_PRUEBAS","Pruebas se ejecutan y pasan":"SIN_PRUEBAS",
                    "Autoridad vigente":"SIN_AUTORIDAD_REGISTRADA","Familia existe":"SIN_FAMILIA","Alcance existe":"ALCANCE_POR_DERIVAR",
                    "Clase coherente con el alcance":"ALCANCE_POR_DERIVAR","Código libre":"YA_EN_EL_NUCLEO","Clasificación contra lo existente":"DUPLICADO_EN_LEGADO",
                    "Sin conflicto con reglas fijas superiores":"CONFLICTO_FIJA"}';
BEGIN
  SELECT codigo INTO v_raiz FROM nucleo_nodos WHERE nivel = 'GLOBAL';
  CREATE TEMP TABLE IF NOT EXISTS _sombra (LIKE lf_ops.lf_legado_sombra) ON COMMIT DROP;
  TRUNCATE _sombra;
  FOR r IN SELECT g.*, f.familia, f.naturaleza FROM reglas g LEFT JOIN nucleo_regla_familia f ON f.regla_id = g.id ORDER BY g.id LOOP
    SELECT count(*) INTO v_n FROM reglas_pantallas rp WHERE rp.regla_id = r.id;
    v_alc := CASE WHEN r.es_transversal OR v_n = 0 THEN v_raiz
                  WHEN v_n = 1 THEN (SELECT 'PANTALLA-' || rp.pantalla_id FROM reglas_pantallas rp WHERE rp.regla_id = r.id)
                  ELSE NULL END;
    v_p := jsonb_build_object(
      'codigo', r.codigo, 'clave', left(trim(BOTH '_' FROM lower(regexp_replace(r.codigo, '[^A-Za-z0-9]+', '_', 'g'))), 80),
      'titulo', r.titulo, 'descripcion', r.descripcion, 'familia', r.familia, 'naturaleza', r.naturaleza,
      'autoridad', r.origen, 'dueno', COALESCE(r.created_by, 'LEGADO'), 'alcance', COALESCE(v_alc, v_raiz), 'modo', 'HEREDA',
      'clase', CASE WHEN COALESCE(v_alc, v_raiz) = v_raiz THEN 'TRANSVERSAL' ELSE 'PANTALLA' END,
      'impacto', 'IMPLEMENTAR', 'origen', jsonb_build_object('tipo','MIGRACION','ref','lf_ops.reglas/' || r.id,'solicitante', COALESCE(r.created_by, 'legado')));
    v_res := nucleo_regla_proponer_v1(v_p, false);
    SELECT COALESCE(array_agg(DISTINCT x->>'control' ORDER BY x->>'control'), '{}') INTO v_fall
      FROM jsonb_array_elements(v_res->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
    SELECT COALESCE(array_agg(DISTINCT v_mapa->>f ORDER BY v_mapa->>f) FILTER (WHERE v_mapa ? f), '{}'),
           COALESCE(array_agg(f ORDER BY f) FILTER (WHERE NOT v_mapa ? f), '{}')
      INTO v_brechas, v_sinexp FROM unnest(v_fall) f;
    IF v_n > 1 AND NOT r.es_transversal THEN v_brechas := array_append(v_brechas, 'ALCANCE_POR_DERIVAR'); END IF;
    INSERT INTO _sombra VALUES (v_corrida, r.id, r.codigo, r.estado, r.origen, r.created_by, r.familia, COALESCE(v_alc, 'VARIAS(' || v_n || ')'), v_n,
                                v_res->>'resultado', v_fall, (SELECT COALESCE(array_agg(DISTINCT b ORDER BY b), '{}') FROM unnest(v_brechas) b), v_sinexp);
  END LOOP;
  IF p_guardar THEN INSERT INTO lf_ops.lf_legado_sombra SELECT * FROM _sombra; END IF;
  RETURN QUERY
    SELECT s.estado_legado, s.origen, s.resultado, b, count(*), count(*) FILTER (WHERE cardinality(s.sin_explicar) > 0)
      FROM _sombra s LEFT JOIN LATERAL unnest(CASE WHEN cardinality(s.brechas) = 0 THEN ARRAY['NINGUNA'] ELSE s.brechas END) b ON true
     GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;
END $$;

-- Autoprueba del puente (solo LF): la vista coincide con lf_ops.reglas, y una regla del núcleo ligada a una legada la reemplaza
CREATE OR REPLACE FUNCTION lf_ops.lf_puente_autotest_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $autotest$
DECLARE v_n bigint; v_id integer; r jsonb;
BEGIN
  SELECT count(*) INTO v_n FROM (SELECT id, codigo, categoria, titulo, descripcion, razon, valor_config, es_transversal, estado, origen, created_at, updated_at, pendiente_decision, pendiente_detalle, created_by FROM lf_ops.reglas EXCEPT ALL SELECT id, codigo, categoria, titulo, descripcion, razon, valor_config, es_transversal, estado, origen, created_at, updated_at, pendiente_decision, pendiente_detalle, created_by FROM lf_ops.v_reglas_compat_v1) d;
  IF v_n <> 0 OR (SELECT count(*) FROM lf_ops.v_reglas_compat_v1) <> (SELECT count(*) FROM lf_ops.reglas) + (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado IN ('CANDIDATA','VIGENTE') AND regla_legacy_id IS NULL)
    THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: V1 la vista no reproduce lf_ops.reglas (% filas distintas)', v_n; END IF;
  IF (SELECT string_agg(column_name || ':' || data_type, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'lf_ops' AND table_name = 'reglas')
     IS DISTINCT FROM (SELECT string_agg(column_name || ':' || data_type, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'lf_ops' AND table_name = 'v_reglas_compat_v1')
    THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: V2 la vista no tiene la forma de lf_ops.reglas'; END IF;
  SELECT min(id) INTO v_id FROM lf_ops.reglas;
  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    r := lf_ops.nucleo_regla_proponer_v1(jsonb_build_object('codigo','ZZT-PU-1','clave','zzt_puente','titulo','Regla del núcleo en la vista',
      'descripcion','Regla de prueba que debe aparecer en la vista de compatibilidad como candidata',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA',
      'efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','MIGRACION','ref','autotest-puente','solicitante','autotest'),
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
        jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
        jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false))));
    IF NOT EXISTS (SELECT 1 FROM lf_ops.v_reglas_compat_v1 WHERE codigo = 'ZZT-PU-1' AND estado = 'CANDIDATO' AND origen = 'autotest-puente')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: V3 la regla del núcleo no aparece en la vista (%)', r; END IF;
    IF v_id IS NOT NULL THEN
      UPDATE lf_ops.nucleo_reglas SET regla_legacy_id = v_id WHERE codigo = 'ZZT-PU-1';
      IF (SELECT count(*) FROM lf_ops.v_reglas_compat_v1 WHERE id = v_id) <> 1
         OR NOT EXISTS (SELECT 1 FROM lf_ops.v_reglas_compat_v1 WHERE id = v_id AND codigo = 'ZZT-PU-1')
        THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: V4 la regla migrada no reemplaza a la legada'; END IF;
    END IF;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PUENTE 4/4';
END $autotest$;

REVOKE ALL ON lf_ops.lf_legado_sombra, lf_ops.v_reglas_compat_v1 FROM PUBLIC, anon, authenticated;
ALTER TABLE lf_ops.lf_legado_sombra ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.lf_legado_sombra AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON FUNCTION lf_ops.lf_legado_sombra_v1(boolean), lf_ops.lf_puente_autotest_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.lf_legado_sombra_v1(boolean), lf_ops.lf_puente_autotest_v1() TO service_role;
    GRANT SELECT ON lf_ops.v_reglas_compat_v1, lf_ops.lf_legado_sombra TO service_role;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    GRANT SELECT ON lf_ops.v_reglas_compat_v1, lf_ops.lf_legado_sombra TO supabase_read_only_user;
  END IF;
END $g$;

DO $run$
DECLARE v_s record; v_total bigint; v_sinexp bigint;
BEGIN
  RAISE NOTICE 'NUCLEO_AUTOTEST LF: % · % · % · %', lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1(), lf_ops.nucleo_autotest_cambio_v1(), lf_ops.nucleo_autotest_contrato_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST SALY: % · % · % · %', saly.nucleo_autotest_puerta_v1(), saly.nucleo_autotest_evaluacion_v1(), saly.nucleo_autotest_cambio_v1(), saly.nucleo_autotest_contrato_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST %', public.lf_nucleo_autotest_conjunto_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST %', lf_ops.lf_puente_autotest_v1();
  PERFORM lf_ops.lf_legado_sombra_v1(true);
  SELECT count(*), count(*) FILTER (WHERE cardinality(sin_explicar) > 0) INTO v_total, v_sinexp FROM lf_ops.lf_legado_sombra;
  IF v_total <> (SELECT count(*) FROM lf_ops.reglas) THEN RAISE EXCEPTION 'NUCLEO_SOMBRA_INCOMPLETA: % de %', v_total, (SELECT count(*) FROM lf_ops.reglas); END IF;
  RAISE NOTICE 'NUCLEO_SOMBRA: % reglas evaluadas, % con diferencias sin explicar', v_total, v_sinexp;
  IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo LIKE 'ZZT%') OR EXISTS (SELECT 1 FROM saly.nucleo_reglas WHERE codigo LIKE 'ZZT%')
     OR EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope = 'ZZT' OR config_value LIKE '%ZZT%')
     OR EXISTS (SELECT 1 FROM saly.config_global WHERE scope = 'ZZT' OR config_value LIKE '%ZZT%')
    THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_DEJO_DATOS'; END IF;
END $run$;
COMMIT;

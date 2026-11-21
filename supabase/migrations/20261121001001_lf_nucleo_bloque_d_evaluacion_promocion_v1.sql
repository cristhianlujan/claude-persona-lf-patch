-- Núcleo de reglas, bloque D (F2b, instancia LF): evaluación y promoción.
-- Una regla CANDIDATA se evalúa con cinco dimensiones (profundidad, calidad, semántica, juicio, frescura),
-- pesos y umbrales leídos de lf_global_config (scope NUCLEO_EVAL). Resultado:
--   AUTO → pasa a VIGENTE; MANUAL → requiere decisión de una autoridad vigente;
--   DEVUELTA → cola de remediación con motivos; BLOQUEADA → falta un requisito (juicio vigente, dependencias, valor real).
-- El juicio se registra contra la rúbrica (datos) y queda atado al hash del paquete (versión + pruebas).
-- La puerta del bloque C pasa a guardar las pruebas con su casuística. Las autopruebas quedan como funciones
-- para poder repetirlas como regresión en migraciones siguientes; se ejecutan al final y deshacen sus datos.
BEGIN;

-- Pesos, umbrales y listas de la evaluación (nada fijo en el código)
INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO_EVAL','PESO_PROFUNDIDAD','30','INTEGER','REAL','Peso de la profundidad (casuísticas cubiertas) en la nota de promoción del núcleo; los cinco pesos suman 100.'),
 ('NUCLEO_EVAL','PESO_CALIDAD','20','INTEGER','REAL','Peso de la calidad (rúbrica del juez) en la nota de promoción del núcleo.'),
 ('NUCLEO_EVAL','PESO_SEMANTICA','20','INTEGER','REAL','Peso de la semántica y coherencia (rúbrica del juez) en la nota de promoción del núcleo.'),
 ('NUCLEO_EVAL','PESO_JUICIO','20','INTEGER','REAL','Peso del veredicto vigente del juez atado al hash en la nota de promoción del núcleo.'),
 ('NUCLEO_EVAL','PESO_FRESCURA','10','INTEGER','REAL','Peso de la frescura del juicio en la nota de promoción del núcleo.'),
 ('NUCLEO_EVAL','UMBRAL_AUTO','85','INTEGER','REAL','Nota mínima para promover sin decisión humana (antes 85 fijo en lf_rule_promotion_score_v1).'),
 ('NUCLEO_EVAL','UMBRAL_MANUAL','60','INTEGER','REAL','Nota mínima para pasar a decisión humana; debajo se devuelve a remediación.'),
 ('NUCLEO_EVAL','UMBRAL_DIMENSION','0.8','DECIMAL','REAL','Puntaje mínimo por dimensión de la rúbrica para un veredicto PASS y sin motivo de mejora.'),
 ('NUCLEO_EVAL','DIAS_FRESCURA','90','INTEGER','REAL','Días durante los que un juicio se considera fresco.'),
 ('NUCLEO_EVAL','FRESCURA_VENCIDA','0.5','DECIMAL','REAL','Factor de frescura cuando el juicio supera DIAS_FRESCURA.'),
 ('NUCLEO_EVAL','TIPOS_SIEMPRE_MANUAL','["LEGAL"]','JSON','REAL','Tipos de familia que siempre requieren decisión humana para promover.'),
 ('NUCLEO_EVAL','FAMILIAS_SIEMPRE_MANUAL','["GOVERNANCE_APPROVAL","OFFERS_INSTALLMENTS","MFA_OTP_SSO","SESSION","PAYMENTS_CHECKOUT","FINANCIAL_INTEGRITY_RECONCILIATION"]','JSON','REAL','Familias que siempre requieren decisión humana (equivale a las categorías bloqueadas de la promoción legada: APPROVAL, OFERTAS_CUOTAS, AUTH, PAGOS).');

-- Casuísticas mínimas: familia NULL = válidas para toda familia de esa naturaleza; con familia = propias de la familia
CREATE TABLE lf_ops.nucleo_casuisticas (
  familia text REFERENCES lf_ops.nucleo_familias(codigo),
  naturaleza text NOT NULL,
  codigo text NOT NULL,
  descripcion text NOT NULL,
  estado text NOT NULL DEFAULT 'ACTIVA',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_casuisticas_naturaleza CHECK (naturaleza IN ('CONDUCTA','DEFINICION')),
  CONSTRAINT nucleo_casuisticas_codigo CHECK (codigo ~ '^[A-Z][A-Z0-9_]{2,60}$'),
  CONSTRAINT nucleo_casuisticas_descripcion CHECK (length(btrim(descripcion)) >= 10),
  CONSTRAINT nucleo_casuisticas_estado CHECK (estado IN ('ACTIVA','RETIRADA'))
);
CREATE UNIQUE INDEX nucleo_casuisticas_unica ON lf_ops.nucleo_casuisticas (COALESCE(familia,'*'), naturaleza, codigo);
INSERT INTO lf_ops.nucleo_casuisticas (familia, naturaleza, codigo, descripcion) VALUES
 (NULL,'CONDUCTA','EN_EL_LIMITE','El dato vale exactamente lo que fija el parámetro'),
 (NULL,'CONDUCTA','BAJO_EL_LIMITE','El dato queda justo por debajo de lo que fija el parámetro'),
 (NULL,'CONDUCTA','SOBRE_EL_LIMITE','El dato queda justo por encima de lo que fija el parámetro'),
 (NULL,'DEFINICION','VALOR_TIPICO','Un valor habitual produce el resultado definido'),
 (NULL,'DEFINICION','VALOR_BORDE','El valor en el borde del rango produce el resultado definido');
COMMENT ON TABLE lf_ops.nucleo_casuisticas IS 'Casuísticas que una regla debe cubrir con pruebas para tener profundidad completa.';

-- Pruebas de cada versión (se guardan al proponer; no se cambian después)
CREATE TABLE lf_ops.nucleo_regla_pruebas (
  regla text NOT NULL,
  version integer NOT NULL,
  n integer NOT NULL,
  casuistica text,
  entrada jsonb NOT NULL,
  esperado jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (regla, version, n),
  FOREIGN KEY (regla, version) REFERENCES lf_ops.nucleo_regla_versiones(regla, version) ON DELETE CASCADE
);
CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_pruebas_guardia_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'NUCLEO_PRUEBA_INMUTABLE: %/% n=%', OLD.regla, OLD.version, OLD.n; END IF;
  IF NOT EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = NEW.regla AND version = NEW.version AND created_at = now()) THEN
    RAISE EXCEPTION 'NUCLEO_PRUEBA_FUERA_DE_VERSION: las pruebas se registran junto con su versión (%/%)', NEW.regla, NEW.version;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_nucleo_pruebas_guardia BEFORE INSERT OR UPDATE OR DELETE ON lf_ops.nucleo_regla_pruebas
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_pruebas_guardia_v1();

-- Rúbrica del juez (datos): cada criterio se puntúa de 0 a 1; bajo 1 requiere observación
CREATE TABLE lf_ops.nucleo_rubrica (
  codigo text PRIMARY KEY,
  dimension text NOT NULL,
  criterio text NOT NULL,
  estado text NOT NULL DEFAULT 'ACTIVO',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_rubrica_dimension CHECK (dimension IN ('CALIDAD','SEMANTICA','COHERENCIA')),
  CONSTRAINT nucleo_rubrica_estado CHECK (estado IN ('ACTIVO','RETIRADO')),
  CONSTRAINT nucleo_rubrica_criterio CHECK (length(btrim(criterio)) >= 20)
);
INSERT INTO lf_ops.nucleo_rubrica (codigo, dimension, criterio) VALUES
 ('CAL_CLARIDAD','CALIDAD','El título y la descripción se entienden sin contexto adicional'),
 ('CAL_ACCIONABLE','CALIDAD','Dice qué ocurre cuando se cumple: efecto observable para el usuario o el sistema'),
 ('CAL_ALCANCE','CALIDAD','El alcance declarado corresponde a dónde debe aplicar según el texto'),
 ('SEM_NO_DUPLICA','SEMANTICA','No repite por significado otra regla vigente o candidata, aunque esté escrita distinto'),
 ('SEM_NO_CONTRADICE','SEMANTICA','No contradice otra regla vigente del mismo alcance o de sus ancestros'),
 ('COH_TEXTO_CONDICION','COHERENCIA','La condición expresa exactamente lo que dice el texto, sin más ni menos'),
 ('COH_EFECTO','COHERENCIA','El efecto declarado coincide con lo que el texto dice que ocurre');
COMMENT ON TABLE lf_ops.nucleo_rubrica IS 'Rúbrica del juez semántico del núcleo; el registro de un juicio exige todos los criterios activos.';

-- Juicios, evaluaciones y decisiones (historial; no se cambian)
CREATE TABLE lf_ops.nucleo_juicios (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  regla text NOT NULL,
  version integer NOT NULL,
  hash_evaluado text NOT NULL,
  veredicto text NOT NULL,
  calidad numeric(4,3) NOT NULL,
  semantica numeric(4,3) NOT NULL,
  coherencia numeric(4,3) NOT NULL,
  puntajes jsonb NOT NULL,
  juez text NOT NULL,
  modo text NOT NULL,
  revisor_es_productor boolean NOT NULL,
  llamadas_modelo integer NOT NULL,
  evidencia_ref text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (regla, version) REFERENCES lf_ops.nucleo_regla_versiones(regla, version) ON DELETE CASCADE,
  CONSTRAINT nucleo_juicios_hash CHECK (hash_evaluado ~ '^[0-9a-f]{64}$'),
  CONSTRAINT nucleo_juicios_veredicto CHECK (veredicto IN ('PASS','DEVOLVER')),
  CONSTRAINT nucleo_juicios_rango CHECK (calidad BETWEEN 0 AND 1 AND semantica BETWEEN 0 AND 1 AND coherencia BETWEEN 0 AND 1),
  CONSTRAINT nucleo_juicios_modo CHECK (modo IN ('INDEPENDIENTE','CONTEXTO_ACTUAL')),
  CONSTRAINT nucleo_juicios_llamadas CHECK (llamadas_modelo >= 0),
  CONSTRAINT nucleo_juicios_procedencia_honesta CHECK (modo <> 'INDEPENDIENTE' OR (NOT revisor_es_productor AND llamadas_modelo >= 1)),
  CONSTRAINT nucleo_juicios_evidencia CHECK (length(btrim(evidencia_ref)) >= 5)
);
CREATE INDEX nucleo_juicios_regla ON lf_ops.nucleo_juicios (regla, version, id DESC);

CREATE TABLE lf_ops.nucleo_evaluaciones (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  regla text NOT NULL REFERENCES lf_ops.nucleo_reglas(codigo) ON DELETE CASCADE,
  version integer NOT NULL,
  hash_paquete text NOT NULL,
  nota integer NOT NULL,
  decision text NOT NULL,
  componentes jsonb NOT NULL,
  motivos jsonb NOT NULL,
  config_usada jsonb NOT NULL,
  juicio_id bigint REFERENCES lf_ops.nucleo_juicios(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_evaluaciones_decision CHECK (decision IN ('AUTO','MANUAL','DEVUELTA','BLOQUEADA'))
);
CREATE INDEX nucleo_evaluaciones_regla ON lf_ops.nucleo_evaluaciones (regla, id DESC);

CREATE TABLE lf_ops.nucleo_decisiones (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  regla text NOT NULL REFERENCES lf_ops.nucleo_reglas(codigo) ON DELETE CASCADE,
  version integer NOT NULL,
  hash_paquete text NOT NULL,
  evaluacion_id bigint NOT NULL REFERENCES lf_ops.nucleo_evaluaciones(id),
  decision text NOT NULL,
  autoridad text NOT NULL REFERENCES lf_ops.nucleo_autoridades(codigo),
  motivo text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_decisiones_decision CHECK (decision IN ('APROBAR','RECHAZAR')),
  CONSTRAINT nucleo_decisiones_motivo CHECK (length(btrim(motivo)) >= 10)
);

CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_historial_inmutable_v1()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'NUCLEO_HISTORIAL_INMUTABLE: %', TG_TABLE_NAME; END $$;
CREATE TRIGGER trg_nucleo_juicios_inmutable BEFORE UPDATE OR DELETE ON lf_ops.nucleo_juicios
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_historial_inmutable_v1();
CREATE TRIGGER trg_nucleo_evaluaciones_inmutable BEFORE UPDATE OR DELETE ON lf_ops.nucleo_evaluaciones
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_historial_inmutable_v1();
CREATE TRIGGER trg_nucleo_decisiones_inmutable BEFORE UPDATE OR DELETE ON lf_ops.nucleo_decisiones
  FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_historial_inmutable_v1();

-- Valor numérico obligatorio de la configuración (falla si falta: no hay valor por defecto en el código)
CREATE OR REPLACE FUNCTION lf_ops.nucleo_config_num_v1(p_ref text)
RETURNS numeric LANGUAGE plpgsql STABLE SET search_path = pg_catalog, lf_ops AS $$
DECLARE v text := lf_ops.nucleo_param_valor_v1(p_ref);
BEGIN
  IF v IS NULL OR v !~ '^-?[0-9]+(\.[0-9]+)?$' THEN RAISE EXCEPTION 'NUCLEO_EVAL_CONFIG_FALTA: %', p_ref; END IF;
  RETURN v::numeric;
END $$;

-- Hash del paquete evaluable: hash de la versión + sus pruebas
CREATE OR REPLACE FUNCTION lf_ops.nucleo_hash_paquete_v1(p_regla text, p_version integer)
RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, lf_ops AS $$
  SELECT encode(sha256(convert_to(v.hash || '|' || COALESCE((
           SELECT string_agg(t.n || ':' || COALESCE(t.casuistica,'') || ':' || t.entrada::text || ':' || t.esperado::text, '|' ORDER BY t.n)
             FROM nucleo_regla_pruebas t WHERE t.regla = v.regla AND t.version = v.version), ''), 'UTF8')), 'hex')
    FROM nucleo_regla_versiones v WHERE v.regla = p_regla AND v.version = p_version
$$;

-- Puerta de entrada (bloque C) con casuísticas conocidas y pruebas guardadas
CREATE OR REPLACE FUNCTION lf_ops.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  ctl jsonb := '[]'::jsonb;
  v_fam record; v_falta text; v_txt text; v_n integer; v_ok boolean;
  v_clase text := upper(p->>'clase'); v_nat text := upper(p->>'naturaleza'); v_alc text := p->>'alcance';
  v_ambito text; v_nivel text; v_clasif text := 'NUEVA'; v_prueba jsonb; v_res jsonb; v_bloq integer;
  v_lits jsonb; v_efectos jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_proponer:' || coalesce(p->>'clave', ''), 0));

  -- 0 código libre
  v_ok := p->>'codigo' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nucleo_reglas WHERE codigo = p->>'codigo');
  ctl := ctl || jsonb_build_object('n',0,'control','Código libre','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'El código ya existe o falta: use otro código o proponga una versión nueva de la regla existente.' END);

  -- 1 familia existe
  SELECT * INTO v_fam FROM nucleo_familias WHERE codigo = p->>'familia';
  v_ok := FOUND AND v_fam.estado <> 'RETIRADA';
  ctl := ctl || jsonb_build_object('n',1,'control','Familia existe','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'familia' ELSE 'La familia ' || coalesce(p->>'familia','(vacía)') || ' no existe o está retirada: elija una de lf_ops.nucleo_familias.' END);

  -- 2 campos del contrato (global + extensión de la familia)
  SELECT string_agg(k.campo, ', ' ORDER BY k.campo) INTO v_falta FROM nucleo_contrato_campos k
   WHERE (k.familia IS NULL OR k.familia = p->>'familia')
     AND (NOT p ? k.campo OR jsonb_typeof(p->k.campo) = 'null' OR btrim(p->>k.campo) = '' OR p->k.campo IN ('[]'::jsonb, '{}'::jsonb));
  ctl := ctl || jsonb_build_object('n',2,'control','Campos obligatorios','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Faltan o están vacíos: ' || v_falta END);

  v_txt := nucleo_condicion_problema_v1(p->'condicion');
  ctl := ctl || jsonb_build_object('n',2,'control','Condición bien formada','ok',v_txt IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'La condición no es válida (' || v_txt || '). Use hojas {"hecho"}, {"param":"SCOPE.CLAVE"}, {"lit"} y operadores y, o, no, =, !=, >, >=, <, <=.' END);

  -- 3 alcance existe
  SELECT nivel INTO v_nivel FROM nucleo_nodos WHERE codigo = v_alc;
  ctl := ctl || jsonb_build_object('n',3,'control','Alcance existe','ok',v_nivel IS NOT NULL,'bloqueante',true,
    'detalle', CASE WHEN v_nivel IS NOT NULL THEN v_alc ELSE 'El alcance ' || coalesce(v_alc,'(vacío)') || ' no es un nodo del árbol (lf_ops.v_nucleo_nodos).' END);

  -- 4 datos dentro del vocabulario de la familia
  SELECT string_agg(DISTINCT x->>'hecho', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'hecho' AND NOT EXISTS (SELECT 1 FROM nucleo_familia_vocabulario v WHERE v.familia = p->>'familia' AND v.hecho = x->>'hecho');
  ctl := ctl || jsonb_build_object('n',4,'control','Datos dentro del vocabulario','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Datos fuera del vocabulario de la familia: ' || v_falta || '. Use un hecho de lf_ops.v_nucleo_vocabulario o regístrelo primero.' END);

  -- 5 sin datos fijos (literales permitidos en NUCLEO.LITERALES_PERMITIDOS)
  v_lits := COALESCE(nucleo_param_valor_v1('NUCLEO.LITERALES_PERMITIDOS')::jsonb, '[]'::jsonb);
  SELECT string_agg(x->>'lit', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'number' AND NOT v_lits @> jsonb_build_array(x->'lit');
  ctl := ctl || jsonb_build_object('n',5,'control','Sin datos fijos','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Valores fijos en la condición: ' || v_falta || '. Reemplácelos por {"param":"SCOPE.CLAVE"} de lf_global_config.' END);
  SELECT string_agg(x->>'lit', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'string';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',5,'control','Textos fijos en la condición','ok',false,'bloqueante',false,
      'detalle','Verifique que sean valores de una lista del vocabulario: ' || v_txt);
  END IF;

  -- 6 parámetros existen
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND nucleo_param_valor_v1(x->>'param') IS NULL;
  ctl := ctl || jsonb_build_object('n',6,'control','Parámetros existen','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Parámetros inexistentes en lf_global_config: ' || v_falta END);

  -- 13 unidades compatibles (hecho comparado con un parámetro registrado en nucleo_parametros)
  SELECT string_agg(format('%s (%s) vs %s (%s)', hi.codigo, hi.unidad, pa.scope || '.' || pa.config_key, hp.unidad), '; ') INTO v_falta
    FROM nucleo_nodos_condicion_v1(p->'condicion') x
    JOIN nucleo_hechos hi ON hi.codigo = COALESCE(x->'izq'->>'hecho', x->'der'->>'hecho')
    JOIN nucleo_parametros pa ON pa.scope || '.' || pa.config_key = COALESCE(x->'der'->>'param', x->'izq'->>'param')
    JOIN nucleo_hechos hp ON hp.codigo = pa.hecho
   WHERE x->>'op' IN ('>','>=','<','<=','=','!=') AND hi.unidad IS DISTINCT FROM hp.unidad;
  ctl := ctl || jsonb_build_object('n',13,'control','Unidades compatibles','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Unidades distintas: ' || v_falta END);
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND NOT EXISTS (SELECT 1 FROM nucleo_parametros pa WHERE pa.scope || '.' || pa.config_key = x->>'param');
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',13,'control','Parámetro sin metadatos','ok',false,'bloqueante',false,
      'detalle','Registre en lf_ops.nucleo_parametros el dato y la unidad de: ' || v_txt || ' (sin eso no se puede verificar la unidad).');
  END IF;

  -- 14 parámetro real (no de muestra)
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM public.lf_global_config g WHERE g.scope || '.' || g.config_key = x->>'param' AND g.value_status <> 'REAL');
  ctl := ctl || jsonb_build_object('n',14,'control','Parámetros con valor real','ok',v_txt IS NULL,'bloqueante',false,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'Usan valor de muestra (no bloquea el desarrollo, sí la producción): ' || v_txt END);

  -- 7 pruebas mínimas de la familia
  v_n := CASE WHEN jsonb_typeof(p->'pruebas') = 'array' THEN jsonb_array_length(p->'pruebas') ELSE 0 END;
  v_ok := v_fam.codigo IS NOT NULL AND v_n >= v_fam.min_pruebas;
  ctl := ctl || jsonb_build_object('n',7,'control','Pruebas mínimas de la familia','ok',v_ok,'bloqueante',true,
    'detalle', format('%s de %s', v_n, coalesce(v_fam.min_pruebas::text,'?')));

  SELECT string_agg(DISTINCT t->>'casuistica', ', ') INTO v_falta
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) t
   WHERE t ? 'casuistica' AND NOT EXISTS (SELECT 1 FROM nucleo_casuisticas k WHERE k.codigo = t->>'casuistica' AND k.estado = 'ACTIVA'
         AND k.naturaleza = v_nat AND (k.familia IS NULL OR k.familia = p->>'familia'));
  ctl := ctl || jsonb_build_object('n',7,'control','Casuísticas conocidas','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Casuísticas que no existen para esta familia y naturaleza: ' || v_falta || ' (ver lf_ops.nucleo_casuisticas).' END);

  -- 8 pruebas relativas al parámetro (ningún valor numérico fijo como entrada)
  SELECT count(*) INTO v_n FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) t,
       jsonb_each(COALESCE(t->'entrada','{}'::jsonb)) kv
   WHERE jsonb_typeof(kv.value) = 'number' AND NOT v_lits @> jsonb_build_array(kv.value);
  ctl := ctl || jsonb_build_object('n',8,'control','Pruebas relativas al parámetro','ok',v_n = 0,'bloqueante',true,
    'detalle', CASE WHEN v_n = 0 THEN '' ELSE v_n || ' entradas con valor fijo: use {"param":"SCOPE.CLAVE","mas":n}.' END);

  -- 15 las pruebas se ejecutan y pasan
  v_falta := NULL;
  IF jsonb_typeof(p->'pruebas') = 'array' THEN
    FOR v_prueba IN SELECT value FROM jsonb_array_elements(p->'pruebas') LOOP
      BEGIN
        v_res := nucleo_eval_v1(p->'condicion', v_prueba->'entrada');
        IF v_res IS DISTINCT FROM v_prueba->'esperado' THEN
          v_falta := concat_ws('; ', v_falta, format('entrada %s dio %s y se esperaba %s', v_prueba->'entrada', v_res, v_prueba->'esperado'));
        END IF;
      EXCEPTION WHEN others THEN
        v_falta := concat_ws('; ', v_falta, 'error al evaluar: ' || SQLERRM);
      END;
    END LOOP;
  END IF;
  ctl := ctl || jsonb_build_object('n',15,'control','Pruebas se ejecutan y pasan','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', coalesce(v_falta,''));

  -- 16 autoridad registrada y vigente
  v_ok := EXISTS (SELECT 1 FROM nucleo_autoridades WHERE codigo = p->>'autoridad' AND estado = 'VIGENTE');
  ctl := ctl || jsonb_build_object('n',16,'control','Autoridad vigente','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'autoridad' ELSE 'La autoridad ' || coalesce(p->>'autoridad','(vacía)') || ' no está en lf_ops.nucleo_autoridades o no está vigente.' END);

  -- 17 dependencias existen (no vigentes: aviso, frenan la promoción)
  SELECT string_agg(d, ', ') INTO v_falta FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
   WHERE NOT EXISTS (SELECT 1 FROM nucleo_reglas r WHERE r.codigo = d);
  ctl := ctl || jsonb_build_object('n',17,'control','Dependencias existen','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Dependencias inexistentes: ' || v_falta END);
  SELECT string_agg(d, ', ') INTO v_txt FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
   JOIN nucleo_reglas r ON r.codigo = d WHERE r.estado <> 'VIGENTE';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',17,'control','Depende de reglas no vigentes','ok',false,'bloqueante',false,
      'detalle','Entra como candidata, pero no podrá promoverse hasta que estén vigentes: ' || v_txt);
  END IF;

  -- 18 efecto coherente con la naturaleza
  v_efectos := COALESCE(nucleo_param_valor_v1(CASE v_nat WHEN 'DEFINICION' THEN 'NUCLEO.EFECTOS_DEFINICION' ELSE 'NUCLEO.EFECTOS_CONDUCTA' END)::jsonb, '[]');
  v_ok := v_nat IN ('CONDUCTA','DEFINICION') AND v_efectos @> jsonb_build_array(upper(p->>'efecto'));
  ctl := ctl || jsonb_build_object('n',18,'control','Efecto coherente con la naturaleza','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE format('Una regla de %s no puede tener el efecto %s; válidos: %s', coalesce(v_nat,'?'), coalesce(p->>'efecto','?'), v_efectos) END);

  -- 19 clase coherente con el alcance
  WITH RECURSIVE anc(c, nv) AS (
    SELECT codigo, nivel FROM nucleo_nodos WHERE codigo = v_alc
    UNION ALL SELECT n.padre, (SELECT nivel FROM nucleo_nodos WHERE codigo = n.padre)
      FROM nucleo_nodos n JOIN anc ON n.codigo = anc.c WHERE n.padre IS NOT NULL)
  SELECT max(c) FILTER (WHERE nv = 'AMBITO') INTO v_ambito FROM anc;
  v_ok := CASE v_clase
    WHEN 'BACKEND' THEN v_nivel = 'GLOBAL' OR v_ambito = 'BACKEND'
    WHEN 'PANTALLA' THEN v_ambito IN ('B2B','CLIENTE')
    WHEN 'TRANSVERSAL' THEN v_nivel IN ('GLOBAL','AMBITO')
    ELSE false END;
  ctl := ctl || jsonb_build_object('n',19,'control','Clase coherente con el alcance','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE format('Clase %s no corresponde al alcance %s (nivel %s, ámbito %s).', coalesce(v_clase,'?'), coalesce(v_alc,'?'), coalesce(v_nivel,'?'), coalesce(v_ambito,'-')) END);

  -- 9 sin conflicto con una regla FIJA superior de la misma clave
  IF v_nivel IS NOT NULL THEN
    SELECT string_agg(e.regla || ' en ' || e.nodo_origen, ', ') INTO v_falta
      FROM nucleo_reglas_efectivas_v1(v_alc) e WHERE e.clave = p->>'clave' AND e.modo = 'FIJA' AND e.distancia > 0;
  END IF;
  ctl := ctl || jsonb_build_object('n',9,'control','Sin conflicto con reglas fijas superiores','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Existe una regla FIJA superior con la misma clave: ' || v_falta END);

  -- 10 clasificación contra lo existente
  SELECT CASE WHEN a.nodo = v_alc AND v.condicion = p->'condicion' THEN 'DUPLICADO_DE ' || r.codigo
              WHEN a.nodo = v_alc THEN 'NUEVA_VERSION_DE ' || r.codigo
              ELSE 'ESPECIALIZA ' || r.codigo END
    INTO v_clasif
    FROM nucleo_reglas r
    JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND r.familia = p->>'familia' AND r.estado NOT IN ('RETIRADA')
     AND (a.nodo = v_alc OR a.nodo IN (
       WITH RECURSIVE up(c) AS (SELECT padre FROM nucleo_nodos WHERE codigo = v_alc
         UNION ALL SELECT n.padre FROM nucleo_nodos n JOIN up ON n.codigo = up.c WHERE n.padre IS NOT NULL)
       SELECT c FROM up WHERE c IS NOT NULL))
   ORDER BY (a.nodo = v_alc) DESC LIMIT 1;
  v_clasif := COALESCE(v_clasif, 'NUEVA');
  ctl := ctl || jsonb_build_object('n',10,'control','Clasificación contra lo existente',
    'ok', v_clasif NOT LIKE 'DUPLICADO%' AND v_clasif NOT LIKE 'NUEVA_VERSION%','bloqueante',true,
    'detalle', CASE WHEN v_clasif LIKE 'DUPLICADO%' THEN v_clasif || ': ya existe igual en el mismo alcance.'
                    WHEN v_clasif LIKE 'NUEVA_VERSION%' THEN v_clasif || ': es un cambio de una regla existente; use la ruta de versión de esa regla.'
                    ELSE v_clasif END);

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc;
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto','ok',false,'bloqueante',false,
      'detalle','Ya existe idéntica en otros nodos (' || v_txt || '): considere registrarla una vez en el nodo común y retirar las copias.');
  END IF;

  -- 12 hacia abajo: reglas de la misma clave en los descendientes (aviso)
  WITH RECURSIVE dn(c) AS (SELECT v_alc UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
   WHERE r.clave = p->>'clave' AND a.nodo IN (SELECT c FROM dn) AND a.nodo <> v_alc;
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',12,'control','Impacto hacia abajo','ok',false,'bloqueante',false,
      'detalle', CASE WHEN upper(p->>'modo') = 'FIJA' THEN 'Es FIJA y hay reglas de la misma clave abajo (deben resolverse antes de promover): '
                      ELSE 'Hay reglas de la misma clave abajo (quedan como especialización): ' END || v_txt);
  END IF;

  SELECT count(*) INTO v_bloq FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;

  IF v_bloq = 0 AND p_aplicar THEN
    INSERT INTO nucleo_reglas (codigo, clave, familia, naturaleza, estado)
    VALUES (p->>'codigo', p->>'clave', p->>'familia', v_nat, 'CANDIDATA');
    INSERT INTO nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, publicada_desde, exigible_desde)
    VALUES (p->>'codigo', p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad',
            now(), COALESCE((p->>'exigible_desde')::timestamptz, now()));
    INSERT INTO nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    SELECT p->>'codigo', 1, t.ord::int, t.v->>'casuistica', t.v->'entrada', t.v->'esperado'
      FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY t(v, ord);
    INSERT INTO nucleo_aplicaciones (regla, nodo, modo) VALUES (p->>'codigo', v_alc, upper(p->>'modo'));
    INSERT INTO nucleo_relaciones (origen, destino, tipo)
    SELECT p->>'codigo', d, 'DEPENDE' FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d;
  END IF;

  RETURN jsonb_build_object(
    'resultado', CASE WHEN v_bloq > 0 THEN 'RECHAZADA' WHEN p_aplicar THEN 'CANDIDATA' ELSE 'EVALUADA_SIN_ESCRIBIR' END,
    'clasificacion', v_clasif, 'bloqueantes', v_bloq,
    'avisos', (SELECT count(*) FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND NOT (x->>'bloqueante')::boolean),
    'controles', ctl);
END $$;

-- Registro de un juicio contra la rúbrica, atado al hash del paquete
CREATE OR REPLACE FUNCTION lf_ops.nucleo_juicio_registrar_v1(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  v_ver integer; v_hash text; v_falta text; v_cal numeric; v_sem numeric; v_coh numeric; v_min numeric; v_id bigint;
BEGIN
  SELECT max(version) INTO v_ver FROM nucleo_regla_versiones WHERE regla = p->>'regla' AND vigente_hasta IS NULL;
  IF v_ver IS NULL THEN RAISE EXCEPTION 'NUCLEO_JUICIO_REGLA_SIN_VERSION: %', p->>'regla'; END IF;
  v_hash := nucleo_hash_paquete_v1(p->>'regla', v_ver);
  IF p->>'hash_evaluado' IS DISTINCT FROM v_hash THEN
    RAISE EXCEPTION 'NUCLEO_JUICIO_HASH_DISTINTO: el juez evaluó % y el paquete vigente es %', p->>'hash_evaluado', v_hash;
  END IF;
  SELECT string_agg(r.codigo, ', ' ORDER BY r.codigo) INTO v_falta FROM nucleo_rubrica r
   WHERE r.estado = 'ACTIVO' AND (
     jsonb_typeof(p->'puntajes'->r.codigo->'puntaje') = 'number'
     AND (p->'puntajes'->r.codigo->>'puntaje')::numeric BETWEEN 0 AND 1
     AND ((p->'puntajes'->r.codigo->>'puntaje')::numeric = 1 OR length(btrim(COALESCE(p->'puntajes'->r.codigo->>'observacion',''))) >= 10)) IS NOT TRUE;
  IF v_falta IS NOT NULL THEN
    RAISE EXCEPTION 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA: falta puntaje (0 a 1) u observación (si es menor que 1) en: %', v_falta;
  END IF;
  SELECT avg((p->'puntajes'->codigo->>'puntaje')::numeric) FILTER (WHERE dimension = 'CALIDAD'),
         avg((p->'puntajes'->codigo->>'puntaje')::numeric) FILTER (WHERE dimension = 'SEMANTICA'),
         avg((p->'puntajes'->codigo->>'puntaje')::numeric) FILTER (WHERE dimension = 'COHERENCIA')
    INTO v_cal, v_sem, v_coh FROM nucleo_rubrica WHERE estado = 'ACTIVO';
  v_min := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_DIMENSION');
  IF p->>'veredicto' = 'PASS' AND least(v_cal, v_sem, v_coh) < v_min THEN
    RAISE EXCEPTION 'NUCLEO_JUICIO_VEREDICTO_INCOHERENTE: PASS con una dimensión bajo % (calidad %, semántica %, coherencia %)', v_min, round(v_cal,2), round(v_sem,2), round(v_coh,2);
  END IF;
  INSERT INTO nucleo_juicios (regla, version, hash_evaluado, veredicto, calidad, semantica, coherencia, puntajes, juez, modo,
                              revisor_es_productor, llamadas_modelo, evidencia_ref)
  VALUES (p->>'regla', v_ver, v_hash, p->>'veredicto', round(v_cal,3), round(v_sem,3), round(v_coh,3), p->'puntajes', p->>'juez',
          p->>'modo', (p->>'revisor_es_productor')::boolean, (p->>'llamadas_modelo')::int, p->>'evidencia_ref')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('juicio_id', v_id, 'version', v_ver, 'calidad', round(v_cal,3), 'semantica', round(v_sem,3), 'coherencia', round(v_coh,3));
END $$;

-- Evaluación de una regla candidata (escribe su resultado en el historial si p_registrar)
CREATE OR REPLACE FUNCTION lf_ops.nucleo_regla_evaluar_v1(p_regla text, p_registrar boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE
  r record; fam record; j record; t record;
  v_ver integer; v_hash text; v_motivos jsonb := '[]'; v_bloqueos jsonb := '[]';
  v_req integer; v_cub integer; v_faltan text; v_fallan text; v_fallan_n integer[] := '{}'; v_prof numeric; v_cal numeric := 0; v_sem numeric := 0;
  v_juicio_ok boolean := false; v_fres numeric := 0; v_nota integer; v_dec text; v_res jsonb; v_txt text; v_id bigint;
  pp numeric; pc numeric; ps numeric; pj numeric; pf numeric; u_auto numeric; u_manual numeric; u_dim numeric; v_cfg jsonb;
  v_siempre boolean;
BEGIN
  SELECT * INTO r FROM nucleo_reglas WHERE codigo = p_regla;
  IF NOT FOUND THEN RAISE EXCEPTION 'NUCLEO_REGLA_INEXISTENTE: %', p_regla; END IF;
  IF r.estado <> 'CANDIDATA' THEN RETURN jsonb_build_object('regla', p_regla, 'decision', 'NO_APLICA', 'estado', r.estado); END IF;
  SELECT * INTO fam FROM nucleo_familias WHERE codigo = r.familia;

  pp := nucleo_config_num_v1('NUCLEO_EVAL.PESO_PROFUNDIDAD'); pc := nucleo_config_num_v1('NUCLEO_EVAL.PESO_CALIDAD');
  ps := nucleo_config_num_v1('NUCLEO_EVAL.PESO_SEMANTICA');  pj := nucleo_config_num_v1('NUCLEO_EVAL.PESO_JUICIO');
  pf := nucleo_config_num_v1('NUCLEO_EVAL.PESO_FRESCURA');
  IF pp + pc + ps + pj + pf <> 100 THEN RAISE EXCEPTION 'NUCLEO_EVAL_PESOS_INVALIDOS: suman %', pp + pc + ps + pj + pf; END IF;
  u_auto := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_AUTO'); u_manual := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_MANUAL');
  u_dim := nucleo_config_num_v1('NUCLEO_EVAL.UMBRAL_DIMENSION');
  IF u_manual > u_auto THEN RAISE EXCEPTION 'NUCLEO_EVAL_UMBRALES_INVALIDOS: manual % > auto %', u_manual, u_auto; END IF;
  v_cfg := jsonb_build_object('pesos', jsonb_build_array(pp, pc, ps, pj, pf), 'umbral_auto', u_auto, 'umbral_manual', u_manual,
           'umbral_dimension', u_dim, 'dias_frescura', nucleo_config_num_v1('NUCLEO_EVAL.DIAS_FRESCURA'));

  SELECT max(version) INTO v_ver FROM nucleo_regla_versiones WHERE regla = p_regla AND vigente_hasta IS NULL;
  v_hash := nucleo_hash_paquete_v1(p_regla, v_ver);

  -- Pruebas guardadas: se vuelven a ejecutar ahora (con los parámetros vigentes)
  FOR t IN SELECT * FROM nucleo_regla_pruebas WHERE regla = p_regla AND version = v_ver ORDER BY n LOOP
    BEGIN
      v_res := nucleo_eval_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver), t.entrada);
      IF v_res IS DISTINCT FROM t.esperado THEN v_fallan := concat_ws(', ', v_fallan, 'prueba ' || t.n); v_fallan_n := v_fallan_n || t.n; END IF;
    EXCEPTION WHEN others THEN v_fallan := concat_ws(', ', v_fallan, 'prueba ' || t.n || ' (' || SQLERRM || ')'); v_fallan_n := v_fallan_n || t.n;
    END;
  END LOOP;
  IF v_fallan IS NOT NULL THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','PRUEBAS','detalle','Fallan con los parámetros vigentes: ' || v_fallan);
  END IF;

  -- Profundidad: casuísticas requeridas cubiertas por una prueba que pasa
  SELECT count(*), count(*) FILTER (WHERE cubierta), string_agg(codigo, ', ' ORDER BY codigo) FILTER (WHERE NOT cubierta)
    INTO v_req, v_cub, v_faltan
    FROM (SELECT k.codigo, EXISTS (
            SELECT 1 FROM nucleo_regla_pruebas t2 WHERE t2.regla = p_regla AND t2.version = v_ver AND t2.casuistica = k.codigo
               AND t2.n <> ALL (v_fallan_n)) AS cubierta
            FROM nucleo_casuisticas k
           WHERE k.estado = 'ACTIVA' AND k.naturaleza = r.naturaleza AND (k.familia IS NULL OR k.familia = r.familia)) x;
  v_prof := CASE WHEN v_req = 0 THEN 0 ELSE v_cub::numeric / v_req END;
  IF v_req = 0 THEN v_motivos := v_motivos || jsonb_build_object('dimension','PROFUNDIDAD','detalle','No hay casuísticas definidas para esta familia y naturaleza');
  ELSIF v_faltan IS NOT NULL THEN v_motivos := v_motivos || jsonb_build_object('dimension','PROFUNDIDAD','detalle','Faltan pruebas para las casuísticas: ' || v_faltan);
  END IF;

  -- Juicio vigente: el último de esta versión, atado al hash actual
  SELECT * INTO j FROM nucleo_juicios WHERE regla = p_regla AND version = v_ver ORDER BY id DESC LIMIT 1;
  IF j.id IS NULL THEN
    v_bloqueos := v_bloqueos || jsonb_build_object('dimension','JUICIO','detalle','No tiene juicio: debe juzgarse contra la rúbrica');
  ELSIF j.hash_evaluado <> v_hash THEN
    v_bloqueos := v_bloqueos || jsonb_build_object('dimension','JUICIO','detalle','El juicio corresponde a otro contenido: debe rejuzgarse');
  ELSE
    v_cal := j.calidad; v_sem := least(j.semantica, j.coherencia);
    v_juicio_ok := j.veredicto = 'PASS';
    v_fres := CASE WHEN j.created_at >= now() - make_interval(days => nucleo_config_num_v1('NUCLEO_EVAL.DIAS_FRESCURA')::int) THEN 1
                   ELSE nucleo_config_num_v1('NUCLEO_EVAL.FRESCURA_VENCIDA') END;
    IF v_fres < 1 THEN v_motivos := v_motivos || jsonb_build_object('dimension','FRESCURA','detalle','El juicio superó los días de frescura'); END IF;
    SELECT string_agg(format('%s (%s): %s', k.key, k.value->>'puntaje', k.value->>'observacion'), '; ' ORDER BY k.key) INTO v_txt
      FROM jsonb_each(j.puntajes) k WHERE (k.value->>'puntaje')::numeric < 1;
    IF j.calidad < u_dim OR j.semantica < u_dim OR j.coherencia < u_dim OR j.veredicto = 'DEVOLVER' OR v_txt IS NOT NULL THEN
      v_motivos := v_motivos || jsonb_build_object('dimension','JUEZ','detalle', CASE WHEN j.veredicto = 'DEVOLVER' THEN 'El juez devolvió la regla. ' ELSE '' END || COALESCE(v_txt,''));
    END IF;
  END IF;

  -- Requisitos para poder promover
  SELECT string_agg(d.destino, ', ') INTO v_txt FROM nucleo_relaciones d JOIN nucleo_reglas x ON x.codigo = d.destino
   WHERE d.origen = p_regla AND d.tipo = 'DEPENDE' AND x.estado <> 'VIGENTE';
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','DEPENDENCIAS','detalle','Depende de reglas no vigentes: ' || v_txt); END IF;
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt
    FROM nucleo_nodos_condicion_v1((SELECT condicion FROM nucleo_regla_versiones WHERE regla = p_regla AND version = v_ver)) x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM public.lf_global_config g WHERE g.scope || '.' || g.config_key = x->>'param'
         AND g.valid_from <= now() AND g.value_status <> 'REAL'
         AND g.valid_from = (SELECT max(g2.valid_from) FROM public.lf_global_config g2 WHERE g2.scope = g.scope AND g2.config_key = g.config_key AND g2.valid_from <= now()));
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','VALOR_REAL','detalle','Usa parámetros con valor de muestra: ' || v_txt); END IF;
  WITH RECURSIVE dn(c) AS (
      SELECT a.nodo FROM nucleo_aplicaciones a WHERE a.regla = p_regla AND a.modo = 'FIJA'
      UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(DISTINCT x.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas x JOIN nucleo_aplicaciones a ON a.regla = x.codigo
   WHERE x.clave = r.clave AND x.codigo <> p_regla AND x.estado IN ('CANDIDATA','VIGENTE') AND a.nodo IN (SELECT c FROM dn);
  IF v_txt IS NOT NULL THEN v_bloqueos := v_bloqueos || jsonb_build_object('dimension','FIJA','detalle','Es FIJA y hay reglas de la misma clave debajo que deben resolverse: ' || v_txt); END IF;

  v_nota := round(pp * v_prof + pc * v_cal + ps * v_sem + pj * (CASE WHEN v_juicio_ok THEN 1 ELSE 0 END) + pf * v_fres);
  v_siempre := COALESCE(nucleo_param_valor_v1('NUCLEO_EVAL.TIPOS_SIEMPRE_MANUAL')::jsonb, '[]') @> jsonb_build_array(fam.tipo)
            OR COALESCE(nucleo_param_valor_v1('NUCLEO_EVAL.FAMILIAS_SIEMPRE_MANUAL')::jsonb, '[]') @> jsonb_build_array(r.familia);
  v_dec := CASE
    WHEN jsonb_array_length(v_bloqueos) > 0 THEN 'BLOQUEADA'
    WHEN v_fallan IS NOT NULL OR j.veredicto = 'DEVOLVER' OR v_nota < u_manual THEN 'DEVUELTA'
    WHEN v_nota < u_auto OR v_siempre THEN 'MANUAL'
    ELSE 'AUTO' END;
  IF v_dec = 'MANUAL' AND v_siempre THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','POLITICA','detalle','La familia ' || r.familia || ' siempre requiere decisión humana');
  END IF;
  IF v_dec = 'MANUAL' AND v_nota < u_auto THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','NOTA','detalle', format('Nota %s bajo el umbral automático %s', v_nota, u_auto));
  END IF;
  IF v_dec = 'DEVUELTA' AND v_nota < u_manual THEN
    v_motivos := v_motivos || jsonb_build_object('dimension','NOTA','detalle', format('Nota %s bajo el umbral de revisión %s', v_nota, u_manual));
  END IF;

  IF p_registrar THEN
    INSERT INTO nucleo_evaluaciones (regla, version, hash_paquete, nota, decision, componentes, motivos, config_usada, juicio_id)
    VALUES (p_regla, v_ver, v_hash, v_nota, v_dec,
            jsonb_build_object('profundidad', round(v_prof,3), 'calidad', v_cal, 'semantica', v_sem, 'juicio', v_juicio_ok, 'frescura', v_fres),
            v_bloqueos || v_motivos, v_cfg, j.id)
    RETURNING id INTO v_id;
  END IF;
  RETURN jsonb_build_object('regla', p_regla, 'version', v_ver, 'hash_paquete', v_hash, 'nota', v_nota, 'decision', v_dec,
    'componentes', jsonb_build_object('profundidad', round(v_prof,3), 'calidad', v_cal, 'semantica', v_sem, 'juicio', v_juicio_ok, 'frescura', v_fres),
    'motivos', v_bloqueos || v_motivos, 'evaluacion_id', v_id);
END $$;

-- Promoción: AUTO pasa a VIGENTE; MANUAL exige decisión de una autoridad vigente; el resto no cambia el estado
CREATE OR REPLACE FUNCTION lf_ops.nucleo_regla_promover_v1(p_regla text, p_decision jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $$
DECLARE e jsonb; v_estado text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_promover:' || p_regla, 0));
  SELECT estado INTO v_estado FROM nucleo_reglas WHERE codigo = p_regla FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NUCLEO_REGLA_INEXISTENTE: %', p_regla; END IF;
  e := nucleo_regla_evaluar_v1(p_regla, true);
  IF e->>'decision' = 'NO_APLICA' THEN RETURN e || jsonb_build_object('resultado','NO_APLICA'); END IF;
  IF p_decision IS NOT NULL AND e->>'decision' <> 'MANUAL' THEN
    RAISE EXCEPTION 'NUCLEO_DECISION_NO_APLICA: la evaluación es % y una decisión humana solo resuelve MANUAL', e->>'decision';
  END IF;
  IF e->>'decision' = 'AUTO' THEN
    UPDATE nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = p_regla;
    RETURN e || jsonb_build_object('resultado','PROMOVIDA_AUTO');
  ELSIF e->>'decision' = 'MANUAL' THEN
    IF p_decision IS NULL THEN RETURN e || jsonb_build_object('resultado','PENDIENTE_DECISION'); END IF;
    IF NOT EXISTS (SELECT 1 FROM nucleo_autoridades WHERE codigo = p_decision->>'autoridad' AND estado = 'VIGENTE') THEN
      RAISE EXCEPTION 'NUCLEO_DECISION_AUTORIDAD_NO_VIGENTE: %', p_decision->>'autoridad';
    END IF;
    INSERT INTO nucleo_decisiones (regla, version, hash_paquete, evaluacion_id, decision, autoridad, motivo)
    VALUES (p_regla, (e->>'version')::int, e->>'hash_paquete', (e->>'evaluacion_id')::bigint, upper(p_decision->>'decision'),
            p_decision->>'autoridad', p_decision->>'motivo');
    IF upper(p_decision->>'decision') = 'APROBAR' THEN
      UPDATE nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = p_regla;
      RETURN e || jsonb_build_object('resultado','PROMOVIDA_MANUAL');
    END IF;
    RETURN e || jsonb_build_object('resultado','RECHAZADA_POR_DUENO');
  END IF;
  RETURN e || jsonb_build_object('resultado', e->>'decision');
END $$;

-- Cola de remediación: reglas candidatas cuyo último evento es una devolución (evaluación o decisión del dueño)
CREATE OR REPLACE VIEW lf_ops.v_nucleo_cola_remediacion WITH (security_invoker = true) AS
SELECT ult.regla, ult.version, ult.origen, ult.motivos, ult.created_at
  FROM (SELECT DISTINCT ON (regla) regla, version, origen, decision, motivos, created_at
          FROM (SELECT regla, version, 'EVALUACION' AS origen, decision, motivos, created_at, id::numeric AS secuencia FROM lf_ops.nucleo_evaluaciones
                UNION ALL
                SELECT regla, version, 'DECISION_DUENO', CASE decision WHEN 'RECHAZAR' THEN 'DEVUELTA' ELSE 'APROBADA' END,
                       jsonb_build_array(jsonb_build_object('dimension','DUENO','detalle', autoridad || ': ' || motivo)), created_at, evaluacion_id + 0.5
                  FROM lf_ops.nucleo_decisiones) ev
         ORDER BY regla, secuencia DESC) ult
  JOIN lf_ops.nucleo_reglas r ON r.codigo = ult.regla AND r.estado = 'CANDIDATA'
 WHERE ult.decision = 'DEVUELTA';
COMMENT ON VIEW lf_ops.v_nucleo_cola_remediacion IS 'Reglas devueltas con sus motivos; entrada de la remediación (T_REMED) en la fase de acople.';

-- Acceso
REVOKE ALL ON lf_ops.nucleo_casuisticas, lf_ops.nucleo_regla_pruebas, lf_ops.nucleo_rubrica, lf_ops.nucleo_juicios,
  lf_ops.nucleo_evaluaciones, lf_ops.nucleo_decisiones, lf_ops.v_nucleo_cola_remediacion FROM PUBLIC, anon, authenticated;
ALTER TABLE lf_ops.nucleo_casuisticas ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_regla_pruebas ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_rubrica ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_juicios ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_evaluaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_decisiones ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_casuisticas AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_regla_pruebas AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_rubrica AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_juicios AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_evaluaciones AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_decisiones AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

-- Autopruebas como funciones (regresión reutilizable); deshacen sus datos
CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_puerta_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $autotest$

DECLARE
  base jsonb; r jsonb; n integer;
  hoja text := (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'PANTALLA' AND padre IN
                 (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'MODULO' AND padre = 'B2B') ORDER BY codigo LIMIT 1);
BEGIN
  BEGIN
    base := jsonb_build_object(
      'codigo','ZZT-OTP-1','clave','zzt_otp_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de envíos en la ventana vigente',
      'familia','RATE_LIMIT','naturaleza','CONDUCTA','autoridad','Q01','dueno','LF_GOVERNANCE',
      'alcance','B2B','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS','mas',-1)),'esperado',false)));

    -- C1 regla correcta: CANDIDATA y escrita
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C1 correcta (%)', r; END IF;
    IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla = 'ZZT-OTP-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C1 sin versión'; END IF;
    -- C2 código repetido
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'RECHAZADA' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C2 código repetido'; END IF;
    -- C3 duplicado en el mismo alcance
    r := lf_ops.nucleo_regla_proponer_v1(base || '{"codigo":"ZZT-OTP-2"}');
    IF r->>'clasificacion' NOT LIKE 'DUPLICADO_DE ZZT-OTP-1' OR r->>'resultado' <> 'RECHAZADA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C3 duplicado (%)', r->>'clasificacion'; END IF;
    -- C4 especialización en una pantalla
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-3','alcance',hoja), false);
    IF r->>'clasificacion' <> 'ESPECIALIZA ZZT-OTP-1' OR r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C4 especialización (%)', r->>'clasificacion'; END IF;
    -- C5 evaluar sin escribir no escribe; la copia idéntica en otro nodo genera aviso 11
    IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-OTP-3') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5 escribió en modo evaluación'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '11' AND NOT (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5 sin aviso de alcance (11)'; END IF;
    -- C5b proponer arriba avisa de la regla de la misma clave abajo (12)
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-5','alcance','GLOBAL','clase','TRANSVERSAL'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '12' AND x->>'detalle' LIKE '%ZZT-OTP-1%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5b sin aviso hacia abajo (12)'; END IF;
    -- C5c familia retirada
    UPDATE lf_ops.nucleo_familias SET estado = 'RETIRADA' WHERE codigo = 'RATE_LIMIT';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X5C','clave','zzt_x5c'), false);
    UPDATE lf_ops.nucleo_familias SET estado = 'ACTIVA' WHERE codigo = 'RATE_LIMIT';
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '1' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5c familia retirada aceptada'; END IF;
    -- C6 dato fijo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X6','clave','zzt_x6',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('lit',3))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '5' AND (x->>'ok')::boolean = false AND (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C6 dato fijo no detectado'; END IF;
    -- C7 hecho fuera del vocabulario
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X7','clave','zzt_x7',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','sueldo'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '4' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C7 vocabulario'; END IF;
    -- C8 parámetro inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X8','clave','zzt_x8',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.NO_EXISTE'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '6' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C8 parámetro'; END IF;
    -- C9 pruebas que no pasan
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X9','clave','zzt_x9','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),'esperado',false),
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS','mas',-1)),'esperado',false))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C9 pruebas que fallan'; END IF;
    -- C10 pruebas con valor fijo y pruebas insuficientes
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X10','clave','zzt_x10','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',9),'esperado',true))), false);
    IF (SELECT count(*) FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' IN ('7','8') AND (x->>'ok')::boolean = false) <> 2
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C10 pruebas fijas/insuficientes'; END IF;
    -- C11 autoridad inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11','clave','zzt_x11','autoridad','Q99'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '16' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11 autoridad'; END IF;
    -- C11b autoridad retirada
    INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion, estado) VALUES ('ZZT-AUT','POLITICA','Autoridad de prueba retirada','RETIRADA');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11B','clave','zzt_x11b','autoridad','ZZT-AUT'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '16' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11b autoridad retirada aceptada'; END IF;
    -- C11c parámetro con valor de muestra: aviso, no bloqueo
    INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description)
    VALUES ('ZZT','PARAM_MUESTRA','4','INTEGER','FICTICIO','Parámetro de prueba con valor de muestra');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11C','clave','zzt_x11c',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','ZZT.PARAM_MUESTRA','mas',-1)),'esperado',false))), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '14' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11c valor de muestra (%)', r->>'resultado'; END IF;
    -- C12 unidad incompatible (parámetro registrado con otro dato)
    INSERT INTO lf_ops.nucleo_parametros (scope, config_key, hecho, dueno) VALUES ('AUTH','SESSION_IDLE_TIMEOUT_SECONDS','inactividad_sesion','LF_GOVERNANCE');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X12','clave','zzt_x12',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.SESSION_IDLE_TIMEOUT_SECONDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '13' AND (x->>'bloqueante')::boolean AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C12 unidades'; END IF;
    -- C13 efecto incoherente con la naturaleza
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X13','clave','zzt_x13','naturaleza','DEFINICION'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '18' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C13 efecto'; END IF;
    -- C14 clase BACKEND en un alcance de pantalla
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14','clave','zzt_x14','clase','BACKEND'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14 clase'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14B','clave','zzt_x14b','clase','BACKEND','alcance','BACKEND'), false);
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14b backend válido rechazado'; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14C','clave','zzt_x14c','clase','PANTALLA','alcance','BACKEND'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14c pantalla en backend aceptada'; END IF;
    -- C15 conflicto con FIJA superior
    UPDATE lf_ops.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-OTP-1';
    UPDATE lf_ops.nucleo_aplicaciones SET modo = 'FIJA' WHERE regla = 'ZZT-OTP-1';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-4','alcance',hoja), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '9' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C15 fija superior'; END IF;
    -- C16 dependencia no vigente: aviso, no bloqueo
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    UPDATE lf_ops.nucleo_reglas SET estado = 'CANDIDATA' WHERE codigo = 'ZZT-OTP-1';
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR (r->>'avisos')::int < 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C16 dependencia candidata (%)', r->>'resultado'; END IF;
    -- C17 extensión de contrato por familia
    INSERT INTO lf_ops.nucleo_contrato_campos (familia, campo) VALUES ('RATE_LIMIT','riesgo_operativo');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X17','clave','zzt_x17'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '2' AND (x->>'ok')::boolean = false AND x->>'detalle' LIKE '%riesgo_operativo%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C17 extensión de familia'; END IF;
    -- C18 familia inexistente y alcance inexistente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X18','clave','zzt_x18','familia','NO_EXISTE','alcance','NO-EXISTE'), false);
    IF (SELECT count(*) FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' IN ('1','3') AND (x->>'ok')::boolean = false) <> 2
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C18 familia/alcance'; END IF;

    -- C19 condición como texto: se rechaza por forma y no se cuelga el evaluador
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X19','clave','zzt_x19','condicion',to_jsonb('intentos >= 3'::text)), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND x->>'detalle' LIKE '%NUCLEO_EVAL_NODO_INVALIDO%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C19 condición texto'; END IF;
    -- C19b condición como lista
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X19B','clave','zzt_x19b','condicion','["hecho"]'::jsonb), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C19b condición lista'; END IF;
    -- C20 operador desconocido
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X20','clave','zzt_x20',
      'condicion', jsonb_build_object('op','~','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C20 operador desconocido'; END IF;
    -- C21 nodo ambiguo (operador y hoja a la vez)
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X21','clave','zzt_x21',
      'condicion', jsonb_build_object('op','>=','lit',3,'izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C21 hoja ambigua'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PUERTA 26/26';

END $autotest$;

CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_evaluacion_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, lf_ops, public AS $autotest$
DECLARE
  base jsonb; r jsonb; e jsonb; h text; ok boolean; pts jsonb; pts_bajo jsonb; jui jsonb;
  hoja text := (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'PANTALLA' AND padre IN
                 (SELECT codigo FROM lf_ops.nucleo_nodos WHERE nivel = 'MODULO' AND padre = 'B2B') ORDER BY codigo LIMIT 1);
BEGIN
  BEGIN
    SELECT jsonb_object_agg(codigo, jsonb_build_object('puntaje', 1)) INTO pts FROM lf_ops.nucleo_rubrica WHERE estado = 'ACTIVO';
    pts_bajo := pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.5,'observacion','El título no dice qué se bloquea'),
                                          'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.7,'observacion','No dice qué ve el usuario al bloquearse'),
                                          'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Parecida a otra regla de reintentos'));
    jui := jsonb_build_object('veredicto','PASS','juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,
                              'llamadas_modelo',0,'evidencia_ref','autotest bloque D');
    base := jsonb_build_object(
      'codigo','ZZT-EV-1','clave','zzt_ev_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de reenvíos configurado',
      'familia','RATE_LIMIT','naturaleza','CONDUCTA','autoridad','Q01','dueno','LF_GOVERNANCE',
      'alcance','B2B','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS','mas',1)),'esperado',true)));

    -- E1 sin juicio: BLOQUEADA, pruebas guardadas con su casuística
    r := lf_ops.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 propuesta (%)', r; END IF;
    IF (SELECT string_agg(casuistica, ',' ORDER BY n) FROM lf_ops.nucleo_regla_pruebas WHERE regla = 'ZZT-EV-1') IS DISTINCT FROM 'EN_EL_LIMITE,BAJO_EL_LIMITE,SOBRE_EL_LIMITE'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 pruebas no guardadas'; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-1');
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"JUICIO"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 sin juicio (%)', e; END IF;
    h := e->>'hash_paquete';

    -- E2 juicio con otro hash: rechazado
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',repeat('a',64),'puntajes',pts));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_HASH_DISTINTO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E2 hash distinto aceptado'; END IF;
    -- E3 rúbrica incompleta y puntaje bajo sin observación
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts - 'COH_EFECTO'));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA%COH_EFECTO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E3 rúbrica incompleta aceptada'; END IF;
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts || '{"CAL_ALCANCE":{"puntaje":0.9}}'));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA%CAL_ALCANCE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E3b puntaje bajo sin observación aceptado'; END IF;
    -- E4 PASS con dimensión bajo el umbral: incoherente
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts_bajo));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_VEREDICTO_INCOHERENTE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E4 PASS incoherente aceptado'; END IF;
    -- E5 procedencia: INDEPENDIENTE no puede ser el productor ni tener cero llamadas
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts,'modo','INDEPENDIENTE'));
    EXCEPTION WHEN check_violation THEN ok := SQLERRM LIKE '%procedencia_honesta%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E5 independencia sin prueba aceptada'; END IF;

    -- E6 juicio completo: AUTO con nota 100 y pasa a VIGENTE
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR (e->>'nota')::int IS DISTINCT FROM 100
       OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-EV-1') IS DISTINCT FROM 'VIGENTE'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E6 auto (%)', e; END IF;
    IF (SELECT count(*) FROM lf_ops.nucleo_evaluaciones WHERE regla = 'ZZT-EV-1') <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E6 historial'; END IF;

    -- E7 poca profundidad y calidad media: MANUAL con motivos; sin decisión queda pendiente
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-2','clave','zzt_ev_dos','pruebas', (base->'pruebas') - 2));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-2', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-2','hash_evaluado',e->>'hash_paquete','puntajes',
      pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.8,'observacion','El título podría nombrar el canal de envío'),
                                'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.8,'observacion','No dice qué mensaje ve el usuario'),
                                'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Revisar si se solapa con otra regla de reenvíos'),
                                'SEM_NO_CONTRADICE', jsonb_build_object('puntaje',0.8,'observacion','Confirmar que no choca con el límite de intentos'))));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-2');
    IF e->>'resultado' IS DISTINCT FROM 'PENDIENTE_DECISION' OR e->>'decision' <> 'MANUAL'
       OR NOT (e->'motivos' @> '[{"dimension":"PROFUNDIDAD"}]') OR position('SOBRE_EL_LIMITE' IN e::text) = 0
       OR NOT (e->'motivos' @> '[{"dimension":"NOTA"}]')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E7 manual (%)', e; END IF;
    -- E8 el dueño rechaza: queda en la cola de remediación; luego aprueba: VIGENTE y sale de la cola
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-2', '{"decision":"RECHAZAR","autoridad":"Q01","motivo":"Falta la prueba sobre el límite"}');
    IF e->>'resultado' IS DISTINCT FROM 'RECHAZADA_POR_DUENO' OR NOT EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-2' AND origen = 'DECISION_DUENO')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E8 rechazo (%)', e; END IF;
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-2', '{"decision":"APROBAR","autoridad":"Q01","motivo":"Aceptada con la cobertura actual"}');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_MANUAL' OR EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-2')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E8 aprobación (%)', e; END IF;
    -- E9 autoridad no vigente en la decisión
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-3','clave','zzt_ev_tres','pruebas', (base->'pruebas') - 2));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-3','hash_evaluado',e->>'hash_paquete','puntajes',
      pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.8,'observacion','El título podría nombrar el canal de envío'),
                                'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.8,'observacion','No dice qué mensaje ve el usuario'),
                                'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Revisar si se solapa con otra regla de reenvíos'),
                                'SEM_NO_CONTRADICE', jsonb_build_object('puntaje',0.8,'observacion','Confirmar que no choca con el límite de intentos'))));
    INSERT INTO lf_ops.nucleo_autoridades (codigo, tipo, descripcion, estado) VALUES ('ZZT-AUT-D','POLITICA','Autoridad de prueba retirada','RETIRADA');
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_regla_promover_v1('ZZT-EV-3', '{"decision":"APROBAR","autoridad":"ZZT-AUT-D","motivo":"Aprobación con autoridad retirada"}');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DECISION_AUTORIDAD_NO_VIGENTE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E9 autoridad retirada aceptada'; END IF;
    -- E10 umbral cambiado solo en configuración: la misma regla pasa a AUTO
    UPDATE public.lf_global_config SET config_value = '80' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    IF e->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E10 umbral por configuración (%)', e; END IF;
    UPDATE public.lf_global_config SET config_value = '85' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    -- E10b nota bajo el umbral de revisión (cambiado en configuración): DEVUELTA con motivo
    UPDATE public.lf_global_config SET config_value = '90' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    UPDATE public.lf_global_config SET config_value = '84' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_MANUAL';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    IF e->>'decision' IS DISTINCT FROM 'DEVUELTA' OR position('bajo el umbral de revisión 84' IN e::text) = 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E10b umbral de revisión (%)', e; END IF;
    UPDATE public.lf_global_config SET config_value = '85' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    UPDATE public.lf_global_config SET config_value = '60' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_MANUAL';
    -- E11 decisión humana sobre algo que no es MANUAL: rechazada
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-4','clave','zzt_ev_cuatro'));
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_regla_promover_v1('ZZT-EV-4', '{"decision":"APROBAR","autoridad":"Q01","motivo":"Intento de saltar el juicio"}');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DECISION_NO_APLICA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E11 decisión sobre BLOQUEADA aceptada'; END IF;
    -- E12 juicio atado al hash: una prueba agregada después invalida el juicio
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-4','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    INSERT INTO lf_ops.nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    VALUES ('ZZT-EV-4', 1, 9, 'EN_EL_LIMITE', jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')), 'true');
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR position('rejuzgarse' IN e::text) = 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E12 hash (%)', e; END IF;
    -- E13 juez devuelve: DEVUELTA y en la cola con sus observaciones
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-4','hash_evaluado',e->>'hash_paquete','veredicto','DEVOLVER','puntajes',pts_bajo));
    e := lf_ops.nucleo_regla_promover_v1('ZZT-EV-4');
    IF e->>'resultado' IS DISTINCT FROM 'DEVUELTA' OR (e->'componentes'->>'juicio')::boolean IS NOT FALSE
       OR NOT EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-4' AND motivos::text LIKE '%qué ve el usuario%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E13 devuelta (%)', e; END IF;
    -- E14 pruebas relativas: cambiar el parámetro no rompe las pruebas
    INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description, valid_from)
    VALUES ('AUTH','OTP_MAX_RESENDS','7','INTEGER','REAL','Prueba de cambio de parámetro (autotest)', now());
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    IF e->'motivos' @> '[{"dimension":"PRUEBAS"}]' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E14 pruebas rotas por cambio de parámetro'; END IF;
    DELETE FROM public.lf_global_config WHERE scope = 'AUTH' AND config_key = 'OTP_MAX_RESENDS' AND description LIKE 'Prueba de cambio de parámetro%';
    -- E15 prueba que falla con los parámetros vigentes: DEVUELTA
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-5','clave','zzt_ev_cinco'));
    INSERT INTO lf_ops.nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    VALUES ('ZZT-EV-5', 1, 9, NULL, jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','AUTH.OTP_MAX_RESENDS')), 'false');
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-5', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-5','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-5', false);
    IF e->>'decision' IS DISTINCT FROM 'DEVUELTA' OR NOT (e->'motivos' @> '[{"dimension":"PRUEBAS"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E15 prueba fallida (%)', e; END IF;
    -- E16 parámetro con valor de muestra: BLOQUEADA
    INSERT INTO public.lf_global_config (scope, config_key, config_value, value_type, value_status, description)
    VALUES ('ZZT','EV_MUESTRA','4','INTEGER','FICTICIO','Parámetro de prueba con valor de muestra');
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-6','clave','zzt_ev_seis',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','intentos_envio_otp'),'der',jsonb_build_object('param','ZZT.EV_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','ZZT.EV_MUESTRA')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('intentos_envio_otp',jsonb_build_object('param','ZZT.EV_MUESTRA','mas',-1)),'esperado',false))));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-6', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-6','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-6', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"VALOR_REAL"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E16 valor de muestra (%)', e; END IF;
    -- E17 dependencia no vigente: BLOQUEADA; al quedar vigente, deja de bloquear
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-7','clave','zzt_ev_siete','depende','["ZZT-EV-5"]'::jsonb));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-7','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"DEPENDENCIAS"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17 dependencia (%)', e; END IF;
    UPDATE lf_ops.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-EV-5';
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    IF e->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17b dependencia vigente (%)', e; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-7', true);
    IF EXISTS (SELECT 1 FROM lf_ops.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-7') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17c regla no devuelta en la cola'; END IF;
    -- E18 familia que siempre requiere decisión humana: MANUAL aunque la nota sea 100
    r := lf_ops.nucleo_regla_proponer_v1(jsonb_build_object(
      'codigo','ZZT-EV-8','clave','zzt_ev_sesion','titulo','Cierre de sesión por inactividad',
      'descripcion','La sesión se cierra cuando la inactividad alcanza el tiempo máximo configurado',
      'familia','SESSION','naturaleza','CONDUCTA','autoridad','Q01','dueno','LF_GOVERNANCE',
      'alcance','B2B','modo','HEREDA','clase','TRANSVERSAL','efecto','BLOQUEAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','inactividad_sesion'),'der',jsonb_build_object('param','AUTH.SESSION_IDLE_TIMEOUT_SECONDS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('inactividad_sesion',jsonb_build_object('param','AUTH.SESSION_IDLE_TIMEOUT_SECONDS')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('inactividad_sesion',jsonb_build_object('param','AUTH.SESSION_IDLE_TIMEOUT_SECONDS','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('inactividad_sesion',jsonb_build_object('param','AUTH.SESSION_IDLE_TIMEOUT_SECONDS','mas',1)),'esperado',true))));
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E18 propuesta (%)', r; END IF;
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-8', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-8','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-8', false);
    IF e->>'decision' IS DISTINCT FROM 'MANUAL' OR (e->>'nota')::int <> 100 OR NOT (e->'motivos' @> '[{"dimension":"POLITICA"}]')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E18 siempre manual (%)', e; END IF;
    -- E19 regla FIJA con la misma clave debajo: BLOQUEADA
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-9','clave','zzt_ev_fija','alcance',hoja));
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-10','clave','zzt_ev_fija','modo','FIJA'));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-10', false);
    PERFORM lf_ops.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-10','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-10', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"FIJA"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E19 fija con especializaciones (%)', e; END IF;
    -- E20 casuística desconocida en la propuesta
    r := lf_ops.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-11','clave','zzt_ev_once','pruebas',
      jsonb_set(base->'pruebas', '{0,casuistica}', '"NO_EXISTE"')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Casuísticas conocidas' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E20 casuística desconocida'; END IF;
    -- E21 historial y pruebas no se modifican
    ok := false;
    BEGIN UPDATE lf_ops.nucleo_regla_pruebas SET esperado = 'false' WHERE regla = 'ZZT-EV-1' AND n = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_PRUEBA_INMUTABLE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E21 prueba modificable'; END IF;
    ok := false;
    BEGIN UPDATE lf_ops.nucleo_juicios SET veredicto = 'PASS' WHERE regla = 'ZZT-EV-4';
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_HISTORIAL_INMUTABLE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E21b juicio modificable'; END IF;
    -- E22 pesos que no suman 100: falla cerrado
    UPDATE public.lf_global_config SET config_value = '15' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'PESO_FRESCURA';
    ok := false;
    BEGIN PERFORM lf_ops.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_EVAL_PESOS_INVALIDOS%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E22 pesos inválidos aceptados'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'EVALUACION 23/23';
END $autotest$;

REVOKE ALL ON FUNCTION lf_ops.nucleo_juicio_registrar_v1(jsonb), lf_ops.nucleo_regla_evaluar_v1(text, boolean),
  lf_ops.nucleo_regla_promover_v1(text, jsonb), lf_ops.nucleo_hash_paquete_v1(text, integer), lf_ops.nucleo_config_num_v1(text),
  lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1(), lf_ops.nucleo_regla_proponer_v1(jsonb, boolean),
  lf_ops.fn_nucleo_pruebas_guardia_v1(), lf_ops.fn_nucleo_historial_inmutable_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION lf_ops.nucleo_juicio_registrar_v1(jsonb), lf_ops.nucleo_regla_evaluar_v1(text, boolean),
      lf_ops.nucleo_regla_promover_v1(text, jsonb), lf_ops.nucleo_hash_paquete_v1(text, integer), lf_ops.nucleo_config_num_v1(text),
      lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1(), lf_ops.nucleo_regla_proponer_v1(jsonb, boolean) TO service_role;
  END IF;
END $g$;

-- Ejecutar las autopruebas (regresión de la puerta + evaluación). Si una falla, se revierte toda la migración.
DO $run$ BEGIN
  RAISE NOTICE 'NUCLEO_AUTOTEST: % · %', lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1();
  IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo LIKE 'ZZT-%')
     OR EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope = 'ZZT' OR description LIKE '%(autotest)%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_autoridades WHERE codigo LIKE 'ZZT-%')
    THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_DEJO_DATOS'; END IF;
END $run$;
COMMIT;

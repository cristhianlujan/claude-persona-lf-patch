-- Núcleo de reglas: instancia SALY (decisión D1: un motor, una instancia por producto, cada una en su esquema).
-- Tablas, vista y funciones generadas de la definición vigente del núcleo LF, cambiando solo el esquema
-- (lf_ops → saly) y la configuración (public.lf_global_config → saly.config_global). Sin pantallas;
-- los campos y las reglas legadas apuntan a saly.campos y saly.reglas. No incluye la clasificación de reglas
-- legadas de LF (nucleo_regla_familia), propia de LF.
-- Datos iniciales de SALY: configuración, autoridades (decisiones VALIDADAS de saly.decisiones), familias
-- (categorías actuales de saly.reglas), árbol (GLOBAL > ADELANTO) y contrato, casuísticas y rúbrica copiados de LF.
-- Pruebas: las mismas autopruebas del núcleo corren en SALY con sus propios datos, y una prueba conjunta verifica
-- paridad de código, aislamiento entre productos y que una misma regla mala se rechaza igual en ambos.
-- Las 14 reglas de saly.reglas no se migran aquí: entran con la ruta de migración del acople (fase A).
BEGIN;

DO $pre$ BEGIN
  IF to_regclass('saly.reglas') IS NULL OR to_regclass('saly.campos') IS NULL OR to_regclass('saly.decisiones') IS NULL THEN
    RAISE EXCEPTION 'NUCLEO_SALY_FALTA_ESQUEMA_BASE';
  END IF;
  IF to_regclass('saly.nucleo_reglas') IS NOT NULL OR to_regclass('saly.config_global') IS NOT NULL THEN
    RAISE EXCEPTION 'NUCLEO_SALY_YA_EXISTE';
  END IF;
END $pre$;

-- Configuración global de SALY (misma estructura que la de LF, separada)
CREATE TABLE saly.config_global (
  scope text NOT NULL,
  config_key text NOT NULL,
  config_value text NOT NULL,
  value_type text NOT NULL,
  value_status text NOT NULL,
  description text,
  valid_from timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT config_global_scope_nonempty CHECK (btrim(scope) <> ''),
  CONSTRAINT config_global_key_nonempty CHECK (btrim(config_key) <> ''),
  CONSTRAINT config_global_value_nonempty CHECK (btrim(config_value) <> ''),
  CONSTRAINT config_global_type_check CHECK (value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
  CONSTRAINT config_global_status_check CHECK (value_status IN ('FICTICIO','REAL')),
  CONSTRAINT config_global_unique_version UNIQUE (scope, config_key, valid_from)
);
COMMENT ON TABLE saly.config_global IS 'Configuración global de SALY: variables y parámetros del producto, separados de los de LF.';

--
-- PostgreSQL database dump
--

\restrict 7tdh9L4zaum0gLDqEPp7iiwfxB0zKE8vZGGiddJWdbdyzfLaNGi1HKT8uV88WWM

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)




--
-- Name: nucleo_aplicaciones; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_aplicaciones (
    regla text NOT NULL,
    nodo text NOT NULL,
    modo text DEFAULT 'HEREDA'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_aplicaciones_modo_valido CHECK ((modo = ANY (ARRAY['HEREDA'::text, 'FIJA'::text, 'SOLO_AQUI'::text])))
);


ALTER TABLE saly.nucleo_aplicaciones OWNER TO postgres;

--
-- Name: TABLE nucleo_aplicaciones; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_aplicaciones IS 'Dónde se aplica cada regla. HEREDA baja a los descendientes; FIJA baja y no se puede especializar; SOLO_AQUI no se hereda.';


--
-- Name: nucleo_autoridades; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_autoridades (
    codigo text NOT NULL,
    tipo text NOT NULL,
    descripcion text NOT NULL,
    estado text DEFAULT 'VIGENTE'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_autoridades_descripcion_minima CHECK ((length(btrim(descripcion)) >= 10)),
    CONSTRAINT nucleo_autoridades_estado_valido CHECK ((estado = ANY (ARRAY['VIGENTE'::text, 'REEMPLAZADA'::text, 'RETIRADA'::text]))),
    CONSTRAINT nucleo_autoridades_tipo_valido CHECK ((tipo = ANY (ARRAY['DECISION_DUENO'::text, 'NORMA'::text, 'POLITICA'::text, 'ANALISIS'::text])))
);


ALTER TABLE saly.nucleo_autoridades OWNER TO postgres;

--
-- Name: TABLE nucleo_autoridades; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_autoridades IS 'Autoridades que respaldan reglas (control 16 de la puerta).';


--
-- Name: nucleo_casuisticas; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_casuisticas (
    familia text,
    naturaleza text NOT NULL,
    codigo text NOT NULL,
    descripcion text NOT NULL,
    estado text DEFAULT 'ACTIVA'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_casuisticas_codigo CHECK ((codigo ~ '^[A-Z][A-Z0-9_]{2,60}$'::text)),
    CONSTRAINT nucleo_casuisticas_descripcion CHECK ((length(btrim(descripcion)) >= 10)),
    CONSTRAINT nucleo_casuisticas_estado CHECK ((estado = ANY (ARRAY['ACTIVA'::text, 'RETIRADA'::text]))),
    CONSTRAINT nucleo_casuisticas_naturaleza CHECK ((naturaleza = ANY (ARRAY['CONDUCTA'::text, 'DEFINICION'::text])))
);


ALTER TABLE saly.nucleo_casuisticas OWNER TO postgres;

--
-- Name: TABLE nucleo_casuisticas; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_casuisticas IS 'Casuísticas que una regla debe cubrir con pruebas para tener profundidad completa.';


--
-- Name: nucleo_contrato_campos; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_contrato_campos (
    familia text,
    campo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_contrato_campo_formato CHECK ((campo ~ '^[a-z][a-z0-9_]{1,60}$'::text))
);


ALTER TABLE saly.nucleo_contrato_campos OWNER TO postgres;

--
-- Name: TABLE nucleo_contrato_campos; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_contrato_campos IS 'Contrato de la regla: familia NULL = global; con familia = extensión de esa familia.';


--
-- Name: nucleo_decisiones; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_decisiones (
    id bigint NOT NULL,
    regla text NOT NULL,
    version integer NOT NULL,
    hash_paquete text NOT NULL,
    evaluacion_id bigint NOT NULL,
    decision text NOT NULL,
    autoridad text NOT NULL,
    motivo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_decisiones_decision CHECK ((decision = ANY (ARRAY['APROBAR'::text, 'RECHAZAR'::text]))),
    CONSTRAINT nucleo_decisiones_motivo CHECK ((length(btrim(motivo)) >= 10))
);


ALTER TABLE saly.nucleo_decisiones OWNER TO postgres;

--
-- Name: nucleo_decisiones_id_seq; Type: SEQUENCE; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_decisiones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME saly.nucleo_decisiones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: nucleo_evaluaciones; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_evaluaciones (
    id bigint NOT NULL,
    regla text NOT NULL,
    version integer NOT NULL,
    hash_paquete text NOT NULL,
    nota integer NOT NULL,
    decision text NOT NULL,
    componentes jsonb NOT NULL,
    motivos jsonb NOT NULL,
    config_usada jsonb NOT NULL,
    juicio_id bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_evaluaciones_decision CHECK ((decision = ANY (ARRAY['AUTO'::text, 'MANUAL'::text, 'DEVUELTA'::text, 'BLOQUEADA'::text])))
);


ALTER TABLE saly.nucleo_evaluaciones OWNER TO postgres;

--
-- Name: nucleo_evaluaciones_id_seq; Type: SEQUENCE; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_evaluaciones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME saly.nucleo_evaluaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: nucleo_familia_vocabulario; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_familia_vocabulario (
    familia text NOT NULL,
    hecho text NOT NULL,
    origen text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_familia_vocabulario_origen_valido CHECK ((origen = ANY (ARRAY['ENTIDAD_CAMPO'::text, 'CURADO'::text, 'COLUMNA_NEGOCIO'::text, 'JUEZ'::text])))
);


ALTER TABLE saly.nucleo_familia_vocabulario OWNER TO postgres;

--
-- Name: TABLE nucleo_familia_vocabulario; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_familia_vocabulario IS 'Vocabulario permitido por familia (control 4 de la puerta de entrada).';


--
-- Name: nucleo_familias; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_familias (
    codigo text NOT NULL,
    dominio text NOT NULL,
    origen text NOT NULL,
    descripcion text NOT NULL,
    estado text DEFAULT 'EN_FORMACION'::text NOT NULL,
    min_pruebas integer DEFAULT 2 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tipo text NOT NULL,
    CONSTRAINT nucleo_familias_codigo_formato CHECK ((codigo ~ '^[A-Z][A-Z0-9_]{2,62}$'::text)),
    CONSTRAINT nucleo_familias_descripcion_minima CHECK ((length(btrim(descripcion)) >= 20)),
    CONSTRAINT nucleo_familias_dominio_valido CHECK ((dominio = ANY (ARRAY['CALIDAD'::text, 'NEGOCIO'::text, 'BACKEND'::text]))),
    CONSTRAINT nucleo_familias_estado_valido CHECK ((estado = ANY (ARRAY['EN_FORMACION'::text, 'ACTIVA'::text, 'RETIRADA'::text]))),
    CONSTRAINT nucleo_familias_min_pruebas_positivo CHECK ((min_pruebas >= 1)),
    CONSTRAINT nucleo_familias_origen_valido CHECK ((origen = ANY (ARRAY['IG'::text, 'NUEVA'::text]))),
    CONSTRAINT nucleo_familias_tipo_valido CHECK ((tipo = ANY (ARRAY['TECNICA'::text, 'VISUAL'::text, 'NEGOCIO'::text, 'LEGAL'::text])))
);


ALTER TABLE saly.nucleo_familias OWNER TO postgres;

--
-- Name: TABLE nucleo_familias; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_familias IS 'Catálogo de familias del núcleo de reglas (instancia LF). Familia = tema de la regla; el alcance es otra dimensión. min_pruebas es propio de cada familia.';


--
-- Name: nucleo_hechos; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_hechos (
    codigo text NOT NULL,
    campo_id integer,
    tipo_dato text,
    unidad text,
    descripcion text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tabla_ref text,
    columna_ref text,
    CONSTRAINT nucleo_hechos_calculado_completo CHECK (((campo_id IS NOT NULL) OR (columna_ref IS NOT NULL) OR ((tipo_dato IS NOT NULL) AND (unidad IS NOT NULL) AND (length(btrim(COALESCE(descripcion, ''::text))) >= 10)))),
    CONSTRAINT nucleo_hechos_campo_por_id CHECK (((campo_id IS NULL) OR (codigo = ('CAMPO-'::text || campo_id)))),
    CONSTRAINT nucleo_hechos_campo_sin_copia CHECK (((campo_id IS NULL) OR ((tipo_dato IS NULL) AND (descripcion IS NULL)))),
    CONSTRAINT nucleo_hechos_columna_por_ref CHECK (((columna_ref IS NULL) OR ((codigo = ((('COL-'::text || tabla_ref) || '.'::text) || columna_ref)) AND (tipo_dato IS NULL) AND (descripcion IS NULL)))),
    CONSTRAINT nucleo_hechos_origen_unico CHECK ((((((campo_id IS NOT NULL))::integer + ((columna_ref IS NOT NULL))::integer) <= 1) AND ((tabla_ref IS NULL) = (columna_ref IS NULL)))),
    CONSTRAINT nucleo_hechos_unidad_valida CHECK (((unidad IS NULL) OR (unidad = ANY (ARRAY['veces'::text, 'cantidad'::text, 'segundos'::text, 'minutos'::text, 'horas'::text, 'dias'::text, 'meses'::text, 'milisegundos'::text, 'proporcion'::text, 'soles'::text, 'ninguna'::text]))))
);


ALTER TABLE saly.nucleo_hechos OWNER TO postgres;

--
-- Name: TABLE nucleo_hechos; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_hechos IS 'Datos que pueden usar las condiciones de las reglas. Los campos se referencian por id (CAMPO-<id>).';


--
-- Name: nucleo_implementaciones; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_implementaciones (
    regla text NOT NULL,
    version integer NOT NULL,
    nodo text NOT NULL,
    evidencia_ref text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_implementaciones_evidencia CHECK ((length(btrim(evidencia_ref)) >= 5))
);


ALTER TABLE saly.nucleo_implementaciones OWNER TO postgres;

--
-- Name: TABLE nucleo_implementaciones; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_implementaciones IS 'Qué versión publicada de cada regla implementa cada nodo, con su evidencia (PR, commit o prueba).';


--
-- Name: nucleo_juicios; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_juicios (
    id bigint NOT NULL,
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_juicios_evidencia CHECK ((length(btrim(evidencia_ref)) >= 5)),
    CONSTRAINT nucleo_juicios_hash CHECK ((hash_evaluado ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT nucleo_juicios_llamadas CHECK ((llamadas_modelo >= 0)),
    CONSTRAINT nucleo_juicios_modo CHECK ((modo = ANY (ARRAY['INDEPENDIENTE'::text, 'CONTEXTO_ACTUAL'::text]))),
    CONSTRAINT nucleo_juicios_procedencia_honesta CHECK (((modo <> 'INDEPENDIENTE'::text) OR ((NOT revisor_es_productor) AND (llamadas_modelo >= 1)))),
    CONSTRAINT nucleo_juicios_rango CHECK (((calidad >= (0)::numeric) AND (calidad <= (1)::numeric) AND ((semantica >= (0)::numeric) AND (semantica <= (1)::numeric)) AND ((coherencia >= (0)::numeric) AND (coherencia <= (1)::numeric)))),
    CONSTRAINT nucleo_juicios_veredicto CHECK ((veredicto = ANY (ARRAY['PASS'::text, 'DEVOLVER'::text])))
);


ALTER TABLE saly.nucleo_juicios OWNER TO postgres;

--
-- Name: nucleo_juicios_id_seq; Type: SEQUENCE; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_juicios ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME saly.nucleo_juicios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: nucleo_nodos; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_nodos (
    codigo text NOT NULL,
    padre text,
    nivel text NOT NULL,
    pantalla_id integer,
    nota text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_nodos_nivel_valido CHECK ((nivel = ANY (ARRAY['GLOBAL'::text, 'AMBITO'::text, 'MODULO'::text, 'PANTALLA'::text, 'COMPONENTE'::text]))),
    CONSTRAINT nucleo_nodos_pantalla_coherente CHECK (((nivel = 'PANTALLA'::text) = (pantalla_id IS NOT NULL))),
    CONSTRAINT nucleo_nodos_pantalla_por_id CHECK (((nivel <> 'PANTALLA'::text) OR (codigo = ('PANTALLA-'::text || pantalla_id)))),
    CONSTRAINT nucleo_nodos_raiz_unica CHECK (((nivel = 'GLOBAL'::text) = (padre IS NULL)))
);


ALTER TABLE saly.nucleo_nodos OWNER TO postgres;

--
-- Name: TABLE nucleo_nodos; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_nodos IS 'Árbol de alcance del núcleo de reglas (instancia LF). Las reglas se aplican a un nodo y se heredan hacia abajo.';


--
-- Name: nucleo_parametros; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_parametros (
    scope text NOT NULL,
    config_key text NOT NULL,
    hecho text,
    minimo numeric,
    maximo numeric,
    dueno text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_parametros_rango_valido CHECK (((minimo IS NULL) OR (maximo IS NULL) OR (minimo <= maximo)))
);


ALTER TABLE saly.nucleo_parametros OWNER TO postgres;

--
-- Name: TABLE nucleo_parametros; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_parametros IS 'Metadatos de cada parámetro de saly.config_global: dato que compara, rango permitido y dueño. El valor sigue viviendo solo en config_global.';


--
-- Name: nucleo_regla_pruebas; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_regla_pruebas (
    regla text NOT NULL,
    version integer NOT NULL,
    n integer NOT NULL,
    casuistica text,
    entrada jsonb NOT NULL,
    esperado jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE saly.nucleo_regla_pruebas OWNER TO postgres;

--
-- Name: nucleo_regla_versiones; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_regla_versiones (
    regla text NOT NULL,
    version integer NOT NULL,
    titulo text NOT NULL,
    descripcion text NOT NULL,
    condicion jsonb,
    efecto text,
    autoridad text NOT NULL,
    publicada_desde timestamp with time zone,
    exigible_desde timestamp with time zone,
    vigente_hasta timestamp with time zone,
    hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    estado text DEFAULT 'CANDIDATA'::text NOT NULL,
    impacto text NOT NULL,
    origen jsonb NOT NULL,
    ficha jsonb NOT NULL,
    plazo_dias integer,
    CONSTRAINT nucleo_versiones_descripcion_minima CHECK ((length(btrim(descripcion)) >= 20)),
    CONSTRAINT nucleo_versiones_estado CHECK ((estado = ANY (ARRAY['CANDIDATA'::text, 'PUBLICADA'::text, 'DESCARTADA'::text]))),
    CONSTRAINT nucleo_versiones_exigible_tras_publicacion CHECK ((exigible_desde >= publicada_desde)),
    CONSTRAINT nucleo_versiones_ficha CHECK ((jsonb_typeof(ficha) = 'object'::text)),
    CONSTRAINT nucleo_versiones_impacto CHECK ((impacto = ANY (ARRAY['NINGUNO'::text, 'REVISAR'::text, 'IMPLEMENTAR'::text]))),
    CONSTRAINT nucleo_versiones_intervalo_valido CHECK (((vigente_hasta IS NULL) OR (vigente_hasta >= publicada_desde))),
    CONSTRAINT nucleo_versiones_origen CHECK (((jsonb_typeof(origen) = 'object'::text) AND ((origen ->> 'tipo'::text) = ANY (ARRAY['IG'::text, 'CHAT'::text, 'PERSONA'::text, 'MIGRACION'::text])) AND (length(btrim(COALESCE((origen ->> 'ref'::text), ''::text))) >= 3) AND (length(btrim(COALESCE((origen ->> 'solicitante'::text), ''::text))) >= 3))),
    CONSTRAINT nucleo_versiones_plazo CHECK (((plazo_dias IS NULL) OR (plazo_dias >= 0))),
    CONSTRAINT nucleo_versiones_publicacion CHECK ((((estado = 'PUBLICADA'::text) = (publicada_desde IS NOT NULL)) AND ((publicada_desde IS NULL) = (exigible_desde IS NULL)) AND ((vigente_hasta IS NULL) OR (estado = 'PUBLICADA'::text)))),
    CONSTRAINT nucleo_versiones_version_positiva CHECK ((version >= 1))
);


ALTER TABLE saly.nucleo_regla_versiones OWNER TO postgres;

--
-- Name: TABLE nucleo_regla_versiones; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_regla_versiones IS 'Versiones de cada regla. Nacen CANDIDATA; al promoverse pasan a PUBLICADA y cierran la anterior; o se DESCARTAN. El contenido no se modifica nunca.';


--
-- Name: nucleo_reglas; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_reglas (
    codigo text NOT NULL,
    clave text NOT NULL,
    familia text NOT NULL,
    naturaleza text NOT NULL,
    estado text DEFAULT 'CANDIDATA'::text NOT NULL,
    regla_legacy_id integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_reglas_clave_formato CHECK ((clave ~ '^[a-z][a-z0-9_]{2,80}$'::text)),
    CONSTRAINT nucleo_reglas_codigo_formato CHECK ((codigo ~ '^[A-Z][A-Z0-9_.-]{2,80}$'::text)),
    CONSTRAINT nucleo_reglas_estado_valido CHECK ((estado = ANY (ARRAY['BORRADOR'::text, 'CANDIDATA'::text, 'VIGENTE'::text, 'DEPRECADA'::text, 'RETIRADA'::text]))),
    CONSTRAINT nucleo_reglas_naturaleza_valida CHECK ((naturaleza = ANY (ARRAY['CONDUCTA'::text, 'DEFINICION'::text])))
);


ALTER TABLE saly.nucleo_reglas OWNER TO postgres;

--
-- Name: TABLE nucleo_reglas; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_reglas IS 'Identidad estable de cada regla del núcleo. clave = concepto que gobierna (dos reglas con la misma clave se especializan o compiten).';


--
-- Name: nucleo_relaciones; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_relaciones (
    origen text NOT NULL,
    destino text NOT NULL,
    tipo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_relaciones_no_reflexiva CHECK ((origen <> destino)),
    CONSTRAINT nucleo_relaciones_tipo_valido CHECK ((tipo = ANY (ARRAY['REFINA'::text, 'SOBRESCRIBE'::text, 'DEPENDE'::text, 'CONFLICTA'::text, 'REEMPLAZA'::text])))
);


ALTER TABLE saly.nucleo_relaciones OWNER TO postgres;

--
-- Name: nucleo_rubrica; Type: TABLE; Schema: saly; Owner: postgres
--

CREATE TABLE saly.nucleo_rubrica (
    codigo text NOT NULL,
    dimension text NOT NULL,
    criterio text NOT NULL,
    estado text DEFAULT 'ACTIVO'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT nucleo_rubrica_criterio CHECK ((length(btrim(criterio)) >= 20)),
    CONSTRAINT nucleo_rubrica_dimension CHECK ((dimension = ANY (ARRAY['CALIDAD'::text, 'SEMANTICA'::text, 'COHERENCIA'::text]))),
    CONSTRAINT nucleo_rubrica_estado CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'RETIRADO'::text])))
);


ALTER TABLE saly.nucleo_rubrica OWNER TO postgres;

--
-- Name: TABLE nucleo_rubrica; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON TABLE saly.nucleo_rubrica IS 'Rúbrica del juez semántico del núcleo; el registro de un juicio exige todos los criterios activos.';


--
-- Name: v_nucleo_cola_remediacion; Type: VIEW; Schema: saly; Owner: postgres
--

CREATE VIEW saly.v_nucleo_cola_remediacion WITH (security_invoker='true') AS
 SELECT ult.regla,
    ult.version,
    ult.origen,
    ult.motivos,
    ult.created_at
   FROM (( SELECT DISTINCT ON (ev.regla) ev.regla,
            ev.version,
            ev.origen,
            ev.decision,
            ev.motivos,
            ev.created_at
           FROM ( SELECT nucleo_evaluaciones.regla,
                    nucleo_evaluaciones.version,
                    'EVALUACION'::text AS origen,
                    nucleo_evaluaciones.decision,
                    nucleo_evaluaciones.motivos,
                    nucleo_evaluaciones.created_at,
                    (nucleo_evaluaciones.id)::numeric AS secuencia
                   FROM saly.nucleo_evaluaciones
                UNION ALL
                 SELECT nucleo_decisiones.regla,
                    nucleo_decisiones.version,
                    'DECISION_DUENO'::text AS text,
                        CASE nucleo_decisiones.decision
                            WHEN 'RECHAZAR'::text THEN 'DEVUELTA'::text
                            ELSE 'APROBADA'::text
                        END AS "case",
                    jsonb_build_array(jsonb_build_object('dimension', 'DUENO', 'detalle', ((nucleo_decisiones.autoridad || ': '::text) || nucleo_decisiones.motivo))) AS jsonb_build_array,
                    nucleo_decisiones.created_at,
                    ((nucleo_decisiones.evaluacion_id)::numeric + 0.5)
                   FROM saly.nucleo_decisiones) ev
          ORDER BY ev.regla, ev.secuencia DESC) ult
     JOIN saly.nucleo_regla_versiones vv ON (((vv.regla = ult.regla) AND (vv.version = ult.version) AND (vv.estado = 'CANDIDATA'::text))))
  WHERE (ult.decision = 'DEVUELTA'::text);


ALTER VIEW saly.v_nucleo_cola_remediacion OWNER TO postgres;

--
-- Name: VIEW v_nucleo_cola_remediacion; Type: COMMENT; Schema: saly; Owner: postgres
--

COMMENT ON VIEW saly.v_nucleo_cola_remediacion IS 'Versiones candidatas devueltas con sus motivos; entrada de la remediación (T_REMED) en la fase de acople.';


--
-- PostgreSQL database dump complete
--

\unrestrict 7tdh9L4zaum0gLDqEPp7iiwfxB0zKE8vZGGiddJWdbdyzfLaNGi1HKT8uV88WWM


CREATE OR REPLACE FUNCTION saly.fn_nucleo_hechos_columna_existe_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
  IF NEW.columna_ref IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
        WHERE attrelid = to_regclass(NEW.tabla_ref) AND attname = NEW.columna_ref AND attnum > 0 AND NOT attisdropped) THEN
    RAISE EXCEPTION 'NUCLEO_HECHO_COLUMNA_INEXISTENTE: %.%', NEW.tabla_ref, NEW.columna_ref;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_historial_inmutable_v1()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN RAISE EXCEPTION 'NUCLEO_HISTORIAL_INMUTABLE: %', TG_TABLE_NAME; END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_implementaciones_guardia_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'NUCLEO_HISTORIAL_INMUTABLE: nucleo_implementaciones'; END IF;
  IF NOT EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = NEW.regla AND version = NEW.version AND estado = 'PUBLICADA') THEN
    RAISE EXCEPTION 'NUCLEO_IMPLEMENTACION_VERSION_NO_PUBLICADA: % v%', NEW.regla, NEW.version;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_nodos_nivel_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v_orden text[] := ARRAY['GLOBAL','AMBITO','MODULO','PANTALLA','COMPONENTE']; v_padre text;
BEGIN
  IF NEW.padre IS NOT NULL THEN
    SELECT nivel INTO v_padre FROM saly.nucleo_nodos WHERE codigo = NEW.padre;
    IF array_position(v_orden, NEW.nivel) <= array_position(v_orden, v_padre) THEN
      RAISE EXCEPTION 'NUCLEO_NODO_NIVEL_INVALIDO: % (%) no puede colgar de % (%)', NEW.codigo, NEW.nivel, NEW.padre, v_padre;
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' AND EXISTS (
       SELECT 1 FROM saly.nucleo_nodos h
        WHERE h.padre = NEW.codigo
          AND array_position(v_orden, h.nivel) <= array_position(v_orden, NEW.nivel)) THEN
    RAISE EXCEPTION 'NUCLEO_NODO_NIVEL_INVALIDO: cambiar % a % deja hijos con nivel igual o superior', NEW.codigo, NEW.nivel;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_parametros_existe_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM saly.config_global WHERE scope = NEW.scope AND config_key = NEW.config_key) THEN
    RAISE EXCEPTION 'NUCLEO_PARAMETRO_INEXISTENTE: %.%', NEW.scope, NEW.config_key;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_pruebas_guardia_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'NUCLEO_PRUEBA_INMUTABLE: %/% n=%', OLD.regla, OLD.version, OLD.n; END IF;
  IF NOT EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = NEW.regla AND version = NEW.version AND created_at = now()) THEN
    RAISE EXCEPTION 'NUCLEO_PRUEBA_FUERA_DE_VERSION: las pruebas se registran junto con su versión (%/%)', NEW.regla, NEW.version;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_relaciones_sin_ciclo_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
  IF NEW.tipo IN ('DEPENDE','REEMPLAZA') AND EXISTS (
    WITH RECURSIVE alcanza(r) AS (
      SELECT NEW.destino
      UNION
      SELECT x.destino FROM saly.nucleo_relaciones x JOIN alcanza a ON x.origen = a.r WHERE x.tipo = NEW.tipo)
    SELECT 1 FROM alcanza WHERE r = NEW.origen) THEN
    RAISE EXCEPTION 'NUCLEO_RELACION_CICLO: % % % cerraría un ciclo', NEW.origen, NEW.tipo, NEW.destino;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_versiones_alta_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('saly.nucleo_regla_versiones:' || NEW.regla, 0));
  IF NEW.estado IS DISTINCT FROM 'CANDIDATA' OR NEW.publicada_desde IS NOT NULL OR NEW.exigible_desde IS NOT NULL OR NEW.vigente_hasta IS NOT NULL THEN
    RAISE EXCEPTION 'NUCLEO_VERSION_ALTA_INVALIDA: una versión nace CANDIDATA y sin fechas (%)', NEW.regla;
  END IF;
  SELECT COALESCE(max(version), 0) + 1 INTO NEW.version FROM saly.nucleo_regla_versiones WHERE regla = NEW.regla;
  NEW.hash := encode(sha256(convert_to(concat_ws('|', NEW.regla, NEW.version, NEW.titulo, NEW.descripcion,
                 NEW.condicion::text, NEW.efecto, NEW.autoridad, NEW.impacto), 'UTF8')), 'hex');
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION saly.fn_nucleo_versiones_inmutables_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v_marca text := COALESCE(current_setting('lf.nucleo_publicando', true), '');
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'NUCLEO_VERSION_INMUTABLE: no se borra la versión % de %', OLD.version, OLD.regla;
  END IF;
  IF ROW(NEW.regla, NEW.version, NEW.titulo, NEW.descripcion, NEW.condicion, NEW.efecto, NEW.autoridad, NEW.hash,
         NEW.impacto, NEW.origen, NEW.ficha, NEW.plazo_dias, NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.regla, OLD.version, OLD.titulo, OLD.descripcion, OLD.condicion, OLD.efecto, OLD.autoridad, OLD.hash,
         OLD.impacto, OLD.origen, OLD.ficha, OLD.plazo_dias, OLD.created_at) THEN
    RAISE EXCEPTION 'NUCLEO_VERSION_INMUTABLE: la versión % de % no se modifica; cree una versión nueva', OLD.version, OLD.regla;
  END IF;
  IF v_marca NOT LIKE OLD.regla || ':%' THEN
    RAISE EXCEPTION 'NUCLEO_VERSION_TRANSICION_FUERA_DE_RUTA: % v% solo cambia de estado por promoción o descarte', OLD.regla, OLD.version;
  END IF;
  IF (OLD.estado = 'CANDIDATA' AND NEW.estado = 'PUBLICADA' AND OLD.publicada_desde IS NULL AND NEW.vigente_hasta IS NULL)
     OR (OLD.estado = 'CANDIDATA' AND NEW.estado = 'DESCARTADA' AND NEW.publicada_desde IS NULL)
     OR (OLD.estado = 'PUBLICADA' AND NEW.estado = 'PUBLICADA' AND OLD.vigente_hasta IS NULL AND NEW.vigente_hasta IS NOT NULL
         AND NEW.publicada_desde = OLD.publicada_desde AND NEW.exigible_desde = OLD.exigible_desde) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'NUCLEO_VERSION_TRANSICION_INVALIDA: % v% de % a %', OLD.regla, OLD.version, OLD.estado, NEW.estado;
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_cambio_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  base jsonb; r jsonb; e jsonb; ok boolean; pts jsonb; jui jsonb; n integer; t text;
  hoja text := 'ZZT-MOD-1';
  hoja2 text := 'ZZT-MOD-2';
BEGIN
  BEGIN
    PERFORM saly.nucleo_autotest_datos_v1();
    SELECT jsonb_object_agg(codigo, jsonb_build_object('puntaje', 1)) INTO pts FROM saly.nucleo_rubrica WHERE estado = 'ACTIVO';
    jui := jsonb_build_object('veredicto','PASS','juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,
                              'llamadas_modelo',0,'evidencia_ref','autotest bloque E','puntajes',pts);
    base := jsonb_build_object(
      'codigo','ZZT-CB-1','clave','zzt_cb_reenvios','titulo','Bloqueo por reenvíos de OTP',
      'descripcion','Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos configurado',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','plazo_dias',10,
      'origen', jsonb_build_object('tipo','IG','ref','EXEC-AUTOTEST-E','solicitante','autotest'),
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));

    -- K1 sin origen, origen inválido e impacto NINGUNO en una regla nueva: rechazados por el control específico
    r := saly.nucleo_regla_proponer_v1(base - 'origen', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Campos obligatorios' AND x->>'detalle' LIKE '%origen%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1 sin origen (%)', r; END IF;
    r := saly.nucleo_regla_proponer_v1(base || '{"origen":{"tipo":"OTRO","ref":"EXEC-VALIDA","solicitante":"autotest"}}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Origen del cambio' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1b tipo de origen inválido'; END IF;
    r := saly.nucleo_regla_proponer_v1(base || '{"origen":{"tipo":"IG","ref":"x","solicitante":"autotest"}}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Origen del cambio' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1b2 referencia de origen vacía'; END IF;
    r := saly.nucleo_regla_proponer_v1(base || '{"impacto":"NINGUNO"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Impacto declarado' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K1c impacto NINGUNO en regla nueva'; END IF;

    -- K2 alta: versión 1 CANDIDATA sin fechas, con origen guardado; el resolvedor no la ve
    r := saly.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K2 alta (%)', r; END IF;
    IF (SELECT estado || '|' || COALESCE(publicada_desde::text,'-') || '|' || (origen->>'ref') || '|' || impacto FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1)
       IS DISTINCT FROM 'CANDIDATA|-|EXEC-AUTOTEST-E|IMPLEMENTAR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K2 versión guardada'; END IF;
    -- K2b una versión no puede nacer publicada
    ok := false;
    BEGIN INSERT INTO saly.nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, estado, publicada_desde, exigible_desde)
          SELECT regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, 'PUBLICADA', now(), now() FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_ALTA_INVALIDA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K2b versión nacida publicada'; END IF;
    -- K3 publicar sin promoción: rechazado; cambio de estado directo: rechazado
    ok := false;
    BEGIN PERFORM saly.nucleo_version_publicar_v1('ZZT-CB-1', 1); EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_PUBLICAR_SIN_PROMOCION%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K3 publicar sin promoción'; END IF;
    ok := false;
    BEGIN UPDATE saly.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-CB-1';
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_TRANSICION_FUERA_DE_RUTA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K3b publicación directa'; END IF;
    -- K4 juicio y promoción: PUBLICADA, regla VIGENTE, exigible a los 10 días pedidos; el resolvedor la ve en una hoja
    e := saly.nucleo_regla_evaluar_v1('ZZT-CB-1', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-1','hash_evaluado',e->>'hash_paquete'));
    e := saly.nucleo_regla_promover_v1('ZZT-CB-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO'
       OR (SELECT estado || '|' || (exigible_desde - publicada_desde)::text FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1) IS DISTINCT FROM 'PUBLICADA|10 days'
       OR (SELECT estado FROM saly.nucleo_reglas WHERE codigo = 'ZZT-CB-1') IS DISTINCT FROM 'VIGENTE'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K4 promoción (%)', e; END IF;
    IF (SELECT version FROM saly.nucleo_reglas_efectivas_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K4 resolvedor v1'; END IF;

    -- K5 cambio sin cambios, cambio de identidad y cambio de alcance: rechazados
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'detalle' LIKE 'SIN_CAMBIOS%') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K5 sin cambios (%)', r; END IF;
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","clave":"zzt_cb_otra","descripcion":"Bloquea el reenvío de OTP con otra clave distinta a la original"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K5b cambio de identidad'; END IF;
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('tipo','CAMBIO','alcance',hoja,'descripcion','Bloquea el reenvío de OTP solo en esta pantalla concreta del flujo'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K5c cambio de alcance'; END IF;
    -- K6 cambio válido: v2 CANDIDATA; la regla sigue VIGENTE con v1 en efecto
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; aplica a SMS y correo","origen":{"tipo":"CHAT","ref":"chat-autotest-e","solicitante":"autotest"}}');
    IF r->>'resultado' <> 'CANDIDATA' OR (r->>'version')::int IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K6 cambio (%)', r; END IF;
    IF (SELECT version FROM saly.nucleo_reglas_efectivas_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 1
       OR (SELECT estado FROM saly.nucleo_reglas WHERE codigo = 'ZZT-CB-1') IS DISTINCT FROM 'VIGENTE'
       OR (SELECT count(*) FROM saly.nucleo_regla_pruebas WHERE regla = 'ZZT-CB-1' AND version = 2) <> 3
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K6 la candidata entró en efecto o sin pruebas'; END IF;
    -- K7 segundo cambio con una candidata abierta: rechazado
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Otro cambio mientras la versión dos sigue abierta en revisión"}', false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false AND x->>'detalle' LIKE '%candidata%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K7 dos candidatas'; END IF;

    -- K8 implementación de v1 en una hoja; v2 publicada: la hoja queda EN_PLAZO y pasa a DESFASADO tras el plazo
    INSERT INTO saly.nucleo_implementaciones (regla, version, nodo, evidencia_ref) VALUES ('ZZT-CB-1', 1, hoja, 'PR autotest v1');
    ok := false;
    BEGIN INSERT INTO saly.nucleo_implementaciones (regla, version, nodo, evidencia_ref) VALUES ('ZZT-CB-1', 2, hoja, 'PR autotest v2 antes de tiempo');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_IMPLEMENTACION_VERSION_NO_PUBLICADA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 implementación de candidata'; END IF;
    IF (SELECT estado FROM saly.nucleo_cola_trabajo_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 'AL_DIA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 al día con v1'; END IF;
    e := saly.nucleo_regla_evaluar_v1('ZZT-CB-1', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-1','hash_evaluado',e->>'hash_paquete'));
    e := saly.nucleo_regla_promover_v1('ZZT-CB-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR (e->>'version')::int <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 promover v2 (%)', e; END IF;
    IF (SELECT string_agg(version::text, ',') FROM saly.nucleo_reglas_efectivas_v1(hoja) WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM '2'
       OR (SELECT vigente_hasta IS NOT NULL FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 1) IS NOT TRUE
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 v2 en efecto y v1 cerrada'; END IF;
    SELECT estado INTO t FROM saly.nucleo_cola_trabajo_v1(hoja) WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'EN_PLAZO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 en plazo (%)', t; END IF;
    SELECT estado INTO t FROM saly.nucleo_cola_trabajo_v1(hoja, now() + interval '11 days') WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'DESFASADO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K8 desfasado tras el plazo (%)', t; END IF;
    -- K9 otra hoja sin ninguna implementación: debe la versión vigente y hoy está en plazo
    SELECT estado INTO t FROM saly.nucleo_cola_trabajo_v1(hoja2) WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'EN_PLAZO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K9 hoja sin implementar hoy (%)', t; END IF;
    -- K10 implementar v2: AL_DIA
    INSERT INTO saly.nucleo_implementaciones (regla, version, nodo, evidencia_ref) VALUES ('ZZT-CB-1', 2, hoja, 'PR autotest v2');
    SELECT estado INTO t FROM saly.nucleo_cola_trabajo_v1(hoja, now() + interval '11 days') WHERE regla = 'ZZT-CB-1';
    IF t IS DISTINCT FROM 'AL_DIA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K10 al día con v2 (%)', t; END IF;
    -- K11 v3 sin impacto (aclaración de texto): exigible de inmediato y la hoja sigue AL_DIA
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","impacto":"NINGUNO","titulo":"Bloqueo por reenvíos de código OTP","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; aplica a SMS y correo"}');
    e := saly.nucleo_regla_evaluar_v1('ZZT-CB-1', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-1','hash_evaluado',e->>'hash_paquete'));
    e := saly.nucleo_regla_promover_v1('ZZT-CB-1');
    IF (SELECT exigible_desde = publicada_desde FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-CB-1' AND version = 3) IS NOT TRUE
       OR (SELECT estado FROM saly.nucleo_cola_trabajo_v1(hoja, now() + interval '11 days') WHERE regla = 'ZZT-CB-1') IS DISTINCT FROM 'AL_DIA'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K11 aclaración sin impacto (%)', e; END IF;
    -- K12 inmutabilidad: contenido de una versión publicada y descartada → publicada no se pueden cambiar
    ok := false;
    BEGIN PERFORM set_config('lf.nucleo_publicando', 'ZZT-CB-1:1', true);
          UPDATE saly.nucleo_regla_versiones SET titulo = 'Cambiado' WHERE regla = 'ZZT-CB-1' AND version = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_INMUTABLE%'; END;
    PERFORM set_config('lf.nucleo_publicando', '', true);
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K12 contenido modificable'; END IF;
    -- K13 descarte: la candidata se descarta con autoridad y motivo; luego se acepta un cambio nuevo
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; cambio que se descartará"}');
    ok := false;
    BEGIN PERFORM saly.nucleo_version_descartar_v1('ZZT-CB-1', 'ZZT-Q', 'corto'); EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DESCARTE_SIN_MOTIVO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13 descarte sin motivo'; END IF;
    PERFORM saly.nucleo_version_descartar_v1('ZZT-CB-1', 'ZZT-Q', 'Se reemplaza por otro cambio con mejor redacción');
    IF saly.nucleo_regla_evaluar_v1('ZZT-CB-1', false)->>'decision' IS DISTINCT FROM 'NO_APLICA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13a evaluar sin candidata'; END IF;
    ok := false;
    BEGIN PERFORM set_config('lf.nucleo_publicando', 'ZZT-CB-1:4', true);
          UPDATE saly.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-CB-1' AND version = 4;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_VERSION_TRANSICION_INVALIDA%'; END;
    PERFORM set_config('lf.nucleo_publicando', '', true);
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13b descartada a publicada'; END IF;
    r := saly.nucleo_regla_proponer_v1(base || '{"tipo":"CAMBIO","descripcion":"Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; redacción final aprobada"}', false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13c cambio tras descarte (%)', r; END IF;
    IF (SELECT estado FROM saly.nucleo_reglas WHERE codigo = 'ZZT-CB-1') IS DISTINCT FROM 'VIGENTE' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K13d descarte cambió la regla vigente'; END IF;

    -- K14 revalidación: un campo nuevo en el contrato y un parámetro de muestra aparecen; al quitarlos, desaparecen
    IF EXISTS (SELECT 1 FROM saly.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14 revalidación con regla sana'; END IF;
    INSERT INTO saly.nucleo_contrato_campos (familia, campo) VALUES ('ZZT_FAM', 'zzt_campo_nuevo');
    IF NOT EXISTS (SELECT 1 FROM saly.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1' AND motivo = 'CONTRATO' AND detalle LIKE '%zzt_campo_nuevo%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14 contrato nuevo no detectado'; END IF;
    DELETE FROM saly.nucleo_contrato_campos WHERE campo = 'zzt_campo_nuevo';
    UPDATE saly.config_global SET value_status = 'FICTICIO' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS'
       AND valid_from = (SELECT max(valid_from) FROM saly.config_global WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS' AND valid_from <= now());
    IF NOT EXISTS (SELECT 1 FROM saly.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1' AND motivo = 'PARAMETRO')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14b parámetro de muestra no detectado'; END IF;
    UPDATE saly.config_global SET value_status = 'REAL' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS' AND value_status = 'FICTICIO';
    IF EXISTS (SELECT 1 FROM saly.nucleo_revalidacion_v1() WHERE regla = 'ZZT-CB-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K14c revalidación no se limpia'; END IF;
    -- K15 una regla con solo una candidata descartada queda RETIRADA
    r := saly.nucleo_regla_proponer_v1(base || '{"codigo":"ZZT-CB-2","clave":"zzt_cb_dos"}');
    e := saly.nucleo_regla_evaluar_v1('ZZT-CB-2', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-CB-2','hash_evaluado',e->>'hash_paquete','veredicto','DEVOLVER'));
    PERFORM saly.nucleo_regla_evaluar_v1('ZZT-CB-2', true);
    IF NOT EXISTS (SELECT 1 FROM saly.v_nucleo_cola_remediacion WHERE regla = 'ZZT-CB-2') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K15 devuelta fuera de la cola'; END IF;
    PERFORM saly.nucleo_version_descartar_v1('ZZT-CB-2', 'ZZT-Q', 'Se descarta la regla antes de publicarse');
    IF EXISTS (SELECT 1 FROM saly.v_nucleo_cola_remediacion WHERE regla = 'ZZT-CB-2') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K15b descartada sigue en la cola'; END IF;
    IF (SELECT estado FROM saly.nucleo_reglas WHERE codigo = 'ZZT-CB-2') IS DISTINCT FROM 'RETIRADA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: K15 retirada'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'CAMBIO 16/16';
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_datos_v1()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE v_raiz text := (SELECT codigo FROM saly.nucleo_nodos WHERE nivel = 'GLOBAL');
BEGIN
  IF v_raiz IS NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_SIN_RAIZ'; END IF;
  INSERT INTO saly.nucleo_familias (codigo, dominio, origen, descripcion, estado, min_pruebas, tipo) VALUES
    ('ZZT_FAM','BACKEND','NUEVA','Familia de prueba del núcleo (autotest)','ACTIVA',2,'TECNICA'),
    ('ZZT_FAM_MANUAL','BACKEND','NUEVA','Familia de prueba que siempre pide decisión humana (autotest)','ACTIVA',2,'TECNICA');
  INSERT INTO saly.nucleo_hechos (codigo, tipo_dato, unidad, descripcion) VALUES
    ('zzt_intentos','integer','veces','Intentos de prueba del núcleo (autotest)'),
    ('zzt_inactividad','integer','segundos','Inactividad de prueba del núcleo (autotest)');
  INSERT INTO saly.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
    ('ZZT_FAM','zzt_intentos','CURADO'), ('ZZT_FAM_MANUAL','zzt_inactividad','CURADO');
  INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description) VALUES
    ('ZZT','MAX_INTENTOS','3','INTEGER','REAL','Parámetro de prueba del núcleo (autotest)'),
    ('ZZT','INACTIVIDAD_MAX','900','INTEGER','REAL','Parámetro de prueba del núcleo (autotest)');
  INSERT INTO saly.nucleo_autoridades (codigo, tipo, descripcion) VALUES ('ZZT-Q','POLITICA','Autoridad de prueba del núcleo (autotest)');
  INSERT INTO saly.nucleo_nodos (codigo, padre, nivel) VALUES
    ('ZZT-AMB', v_raiz, 'AMBITO'), ('ZZT-BACK', v_raiz, 'AMBITO'), ('ZZT-MOD-1', 'ZZT-AMB', 'MODULO'), ('ZZT-MOD-2', 'ZZT-AMB', 'MODULO');
  UPDATE saly.config_global g SET config_value = (g.config_value::jsonb || to_jsonb(x.extra))::text
    FROM (VALUES ('AMBITOS_PANTALLA','ZZT-AMB'), ('AMBITOS_BACKEND','ZZT-BACK')) x(clave, extra)
   WHERE g.scope = 'NUCLEO' AND g.config_key = x.clave
     AND g.valid_from = (SELECT max(valid_from) FROM saly.config_global WHERE scope = 'NUCLEO' AND config_key = x.clave AND valid_from <= now());
  UPDATE saly.config_global g SET config_value = (g.config_value::jsonb || '["ZZT_FAM_MANUAL"]')::text
   WHERE g.scope = 'NUCLEO_EVAL' AND g.config_key = 'FAMILIAS_SIEMPRE_MANUAL'
     AND g.valid_from = (SELECT max(valid_from) FROM saly.config_global WHERE scope = 'NUCLEO_EVAL' AND config_key = 'FAMILIAS_SIEMPRE_MANUAL' AND valid_from <= now());
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_evaluacion_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  base jsonb; r jsonb; e jsonb; h text; ok boolean; pts jsonb; pts_bajo jsonb; jui jsonb;
  hoja text := 'ZZT-MOD-1';
BEGIN
  BEGIN
    PERFORM saly.nucleo_autotest_datos_v1();
    SELECT jsonb_object_agg(codigo, jsonb_build_object('puntaje', 1)) INTO pts FROM saly.nucleo_rubrica WHERE estado = 'ACTIVO';
    pts_bajo := pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.5,'observacion','El título no dice qué se bloquea'),
                                          'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.7,'observacion','No dice qué ve el usuario al bloquearse'),
                                          'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Parecida a otra regla de reintentos'));
    jui := jsonb_build_object('veredicto','PASS','juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,
                              'llamadas_modelo',0,'evidencia_ref','autotest bloque D');
    base := jsonb_build_object(
      'codigo','ZZT-EV-1','clave','zzt_ev_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de reenvíos configurado',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','origen', jsonb_build_object('tipo','CHAT','ref','autotest-nucleo','solicitante','autotest'),'impacto','IMPLEMENTAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));

    -- E1 sin juicio: BLOQUEADA, pruebas guardadas con su casuística
    r := saly.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 propuesta (%)', r; END IF;
    IF (SELECT string_agg(casuistica, ',' ORDER BY n) FROM saly.nucleo_regla_pruebas WHERE regla = 'ZZT-EV-1') IS DISTINCT FROM 'EN_EL_LIMITE,BAJO_EL_LIMITE,SOBRE_EL_LIMITE'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 pruebas no guardadas'; END IF;
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-1');
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"JUICIO"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E1 sin juicio (%)', e; END IF;
    h := e->>'hash_paquete';

    -- E2 juicio con otro hash: rechazado
    ok := false;
    BEGIN PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',repeat('a',64),'puntajes',pts));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_HASH_DISTINTO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E2 hash distinto aceptado'; END IF;
    -- E3 rúbrica incompleta y puntaje bajo sin observación
    ok := false;
    BEGIN PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts - 'COH_EFECTO'));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA%COH_EFECTO%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E3 rúbrica incompleta aceptada'; END IF;
    ok := false;
    BEGIN PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts || '{"CAL_ALCANCE":{"puntaje":0.9}}'));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_RUBRICA_INCOMPLETA%CAL_ALCANCE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E3b puntaje bajo sin observación aceptado'; END IF;
    -- E4 PASS con dimensión bajo el umbral: incoherente
    ok := false;
    BEGIN PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts_bajo));
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_JUICIO_VEREDICTO_INCOHERENTE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E4 PASS incoherente aceptado'; END IF;
    -- E5 procedencia: INDEPENDIENTE no puede ser el productor ni tener cero llamadas
    ok := false;
    BEGIN PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts,'modo','INDEPENDIENTE'));
    EXCEPTION WHEN check_violation THEN ok := SQLERRM LIKE '%procedencia_honesta%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E5 independencia sin prueba aceptada'; END IF;

    -- E6 juicio completo: AUTO con nota 100 y pasa a VIGENTE
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-1','hash_evaluado',h,'puntajes',pts));
    e := saly.nucleo_regla_promover_v1('ZZT-EV-1');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR (e->>'nota')::int IS DISTINCT FROM 100
       OR (SELECT estado FROM saly.nucleo_reglas WHERE codigo = 'ZZT-EV-1') IS DISTINCT FROM 'VIGENTE'
       OR (SELECT estado FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-EV-1' AND version = 1) IS DISTINCT FROM 'PUBLICADA'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E6 auto (%)', e; END IF;
    IF (SELECT count(*) FROM saly.nucleo_evaluaciones WHERE regla = 'ZZT-EV-1') <> 2 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E6 historial'; END IF;

    -- E7 poca profundidad y calidad media: MANUAL con motivos; sin decisión queda pendiente
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-2','clave','zzt_ev_dos','pruebas', (base->'pruebas') - 2));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-2', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-2','hash_evaluado',e->>'hash_paquete','puntajes',
      pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.8,'observacion','El título podría nombrar el canal de envío'),
                                'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.8,'observacion','No dice qué mensaje ve el usuario'),
                                'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Revisar si se solapa con otra regla de reenvíos'),
                                'SEM_NO_CONTRADICE', jsonb_build_object('puntaje',0.8,'observacion','Confirmar que no choca con el límite de intentos'))));
    e := saly.nucleo_regla_promover_v1('ZZT-EV-2');
    IF e->>'resultado' IS DISTINCT FROM 'PENDIENTE_DECISION' OR e->>'decision' <> 'MANUAL'
       OR NOT (e->'motivos' @> '[{"dimension":"PROFUNDIDAD"}]') OR position('SOBRE_EL_LIMITE' IN e::text) = 0
       OR NOT (e->'motivos' @> '[{"dimension":"NOTA"}]')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E7 manual (%)', e; END IF;
    -- E8 el dueño rechaza: queda en la cola de remediación; luego aprueba: VIGENTE y sale de la cola
    e := saly.nucleo_regla_promover_v1('ZZT-EV-2', '{"decision":"RECHAZAR","autoridad":"ZZT-Q","motivo":"Falta la prueba sobre el límite"}');
    IF e->>'resultado' IS DISTINCT FROM 'RECHAZADA_POR_DUENO' OR NOT EXISTS (SELECT 1 FROM saly.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-2' AND origen = 'DECISION_DUENO')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E8 rechazo (%)', e; END IF;
    e := saly.nucleo_regla_promover_v1('ZZT-EV-2', '{"decision":"APROBAR","autoridad":"ZZT-Q","motivo":"Aceptada con la cobertura actual"}');
    IF e->>'resultado' IS DISTINCT FROM 'PROMOVIDA_MANUAL' OR EXISTS (SELECT 1 FROM saly.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-2')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E8 aprobación (%)', e; END IF;
    -- E9 autoridad no vigente en la decisión
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-3','clave','zzt_ev_tres','pruebas', (base->'pruebas') - 2));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-3','hash_evaluado',e->>'hash_paquete','puntajes',
      pts || jsonb_build_object('CAL_CLARIDAD', jsonb_build_object('puntaje',0.8,'observacion','El título podría nombrar el canal de envío'),
                                'CAL_ACCIONABLE', jsonb_build_object('puntaje',0.8,'observacion','No dice qué mensaje ve el usuario'),
                                'SEM_NO_DUPLICA', jsonb_build_object('puntaje',0.8,'observacion','Revisar si se solapa con otra regla de reenvíos'),
                                'SEM_NO_CONTRADICE', jsonb_build_object('puntaje',0.8,'observacion','Confirmar que no choca con el límite de intentos'))));
    INSERT INTO saly.nucleo_autoridades (codigo, tipo, descripcion, estado) VALUES ('ZZT-AUT-D','POLITICA','Autoridad de prueba retirada','RETIRADA');
    ok := false;
    BEGIN PERFORM saly.nucleo_regla_promover_v1('ZZT-EV-3', '{"decision":"APROBAR","autoridad":"ZZT-AUT-D","motivo":"Aprobación con autoridad retirada"}');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DECISION_AUTORIDAD_NO_VIGENTE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E9 autoridad retirada aceptada'; END IF;
    -- E10 umbral cambiado solo en configuración: la misma regla pasa a AUTO
    UPDATE saly.config_global SET config_value = '80' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    IF e->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E10 umbral por configuración (%)', e; END IF;
    UPDATE saly.config_global SET config_value = '85' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    -- E10b nota bajo el umbral de revisión (cambiado en configuración): DEVUELTA con motivo
    UPDATE saly.config_global SET config_value = '90' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    UPDATE saly.config_global SET config_value = '84' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_MANUAL';
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    IF e->>'decision' IS DISTINCT FROM 'DEVUELTA' OR position('bajo el umbral de revisión 84' IN e::text) = 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E10b umbral de revisión (%)', e; END IF;
    UPDATE saly.config_global SET config_value = '85' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_AUTO';
    UPDATE saly.config_global SET config_value = '60' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'UMBRAL_MANUAL';
    -- E11 decisión humana sobre algo que no es MANUAL: rechazada
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-4','clave','zzt_ev_cuatro'));
    ok := false;
    BEGIN PERFORM saly.nucleo_regla_promover_v1('ZZT-EV-4', '{"decision":"APROBAR","autoridad":"ZZT-Q","motivo":"Intento de saltar el juicio"}');
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_DECISION_NO_APLICA%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E11 decisión sobre BLOQUEADA aceptada'; END IF;
    -- E12 juicio atado al hash: una prueba agregada después invalida el juicio
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-4','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    INSERT INTO saly.nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    VALUES ('ZZT-EV-4', 1, 9, 'EN_EL_LIMITE', jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')), 'true');
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR position('rejuzgarse' IN e::text) = 0 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E12 hash (%)', e; END IF;
    -- E13 juez devuelve: DEVUELTA y en la cola con sus observaciones
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-4','hash_evaluado',e->>'hash_paquete','veredicto','DEVOLVER','puntajes',pts_bajo));
    e := saly.nucleo_regla_promover_v1('ZZT-EV-4');
    IF e->>'resultado' IS DISTINCT FROM 'DEVUELTA' OR (e->'componentes'->>'juicio')::boolean IS NOT FALSE
       OR NOT EXISTS (SELECT 1 FROM saly.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-4' AND motivos::text LIKE '%qué ve el usuario%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E13 devuelta (%)', e; END IF;
    -- E14 pruebas relativas: cambiar el parámetro no rompe las pruebas
    UPDATE saly.config_global SET config_value = '7' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS';
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-4', false);
    IF e->'motivos' @> '[{"dimension":"PRUEBAS"}]' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E14 pruebas rotas por cambio de parámetro'; END IF;
    UPDATE saly.config_global SET config_value = '3' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS';
    -- E15 prueba que falla con los parámetros vigentes: DEVUELTA
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-5','clave','zzt_ev_cinco'));
    INSERT INTO saly.nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    VALUES ('ZZT-EV-5', 1, 9, NULL, jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')), 'false');
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-5', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-5','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-5', false);
    IF e->>'decision' IS DISTINCT FROM 'DEVUELTA' OR NOT (e->'motivos' @> '[{"dimension":"PRUEBAS"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E15 prueba fallida (%)', e; END IF;
    -- E16 parámetro con valor de muestra: BLOQUEADA
    INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description)
    VALUES ('ZZT','EV_MUESTRA','4','INTEGER','FICTICIO','Parámetro de prueba con valor de muestra');
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-6','clave','zzt_ev_seis',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.EV_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.EV_MUESTRA')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.EV_MUESTRA','mas',-1)),'esperado',false))));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-6', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-6','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-6', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"VALOR_REAL"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E16 valor de muestra (%)', e; END IF;
    -- E17 dependencia no vigente: BLOQUEADA; al quedar vigente, deja de bloquear
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-7','clave','zzt_ev_siete','depende','["ZZT-EV-5"]'::jsonb));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-7','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"DEPENDENCIAS"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17 dependencia (%)', e; END IF;
    UPDATE saly.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-EV-5';
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-7', false);
    IF e->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17b dependencia vigente (%)', e; END IF;
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-7', true);
    IF EXISTS (SELECT 1 FROM saly.v_nucleo_cola_remediacion WHERE regla = 'ZZT-EV-7') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E17c regla no devuelta en la cola'; END IF;
    -- E18 familia que siempre requiere decisión humana: MANUAL aunque la nota sea 100
    r := saly.nucleo_regla_proponer_v1(jsonb_build_object(
      'codigo','ZZT-EV-8','clave','zzt_ev_sesion','titulo','Cierre de sesión por inactividad',
      'descripcion','La sesión se cierra cuando la inactividad alcanza el tiempo máximo configurado',
      'familia','ZZT_FAM_MANUAL','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','TRANSVERSAL','efecto','BLOQUEAR','origen', jsonb_build_object('tipo','CHAT','ref','autotest-nucleo','solicitante','autotest'),'impacto','IMPLEMENTAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_inactividad'),'der',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_inactividad',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX')),'esperado',true),
         jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_inactividad',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX','mas',-1)),'esperado',false),
         jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_inactividad',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX','mas',1)),'esperado',true))));
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E18 propuesta (%)', r; END IF;
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-8', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-8','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-8', false);
    IF e->>'decision' IS DISTINCT FROM 'MANUAL' OR (e->>'nota')::int <> 100 OR NOT (e->'motivos' @> '[{"dimension":"POLITICA"}]')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E18 siempre manual (%)', e; END IF;
    -- E19 regla FIJA con la misma clave debajo: BLOQUEADA
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-9','clave','zzt_ev_fija','alcance',hoja));
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-10','clave','zzt_ev_fija','modo','FIJA'));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-10', false);
    PERFORM saly.nucleo_juicio_registrar_v1(jui || jsonb_build_object('regla','ZZT-EV-10','hash_evaluado',e->>'hash_paquete','puntajes',pts));
    e := saly.nucleo_regla_evaluar_v1('ZZT-EV-10', false);
    IF e->>'decision' IS DISTINCT FROM 'BLOQUEADA' OR NOT (e->'motivos' @> '[{"dimension":"FIJA"}]') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E19 fija con especializaciones (%)', e; END IF;
    -- E20 casuística desconocida en la propuesta
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-EV-11','clave','zzt_ev_once','pruebas',
      jsonb_set(base->'pruebas', '{0,casuistica}', '"NO_EXISTE"')), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Casuísticas conocidas' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E20 casuística desconocida'; END IF;
    -- E21 historial y pruebas no se modifican
    ok := false;
    BEGIN UPDATE saly.nucleo_regla_pruebas SET esperado = 'false' WHERE regla = 'ZZT-EV-1' AND n = 1;
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_PRUEBA_INMUTABLE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E21 prueba modificable'; END IF;
    ok := false;
    BEGIN UPDATE saly.nucleo_juicios SET veredicto = 'PASS' WHERE regla = 'ZZT-EV-4';
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_HISTORIAL_INMUTABLE%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E21b juicio modificable'; END IF;
    -- E22 pesos que no suman 100: falla cerrado
    UPDATE saly.config_global SET config_value = '15' WHERE scope = 'NUCLEO_EVAL' AND config_key = 'PESO_FRESCURA';
    ok := false;
    BEGIN PERFORM saly.nucleo_regla_evaluar_v1('ZZT-EV-3', false);
    EXCEPTION WHEN others THEN ok := SQLERRM LIKE 'NUCLEO_EVAL_PESOS_INVALIDOS%'; END;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: E22 pesos inválidos aceptados'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'EVALUACION 23/23';
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_autotest_puerta_v1()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$

DECLARE
  base jsonb; r jsonb; n integer;
  hoja text := 'ZZT-MOD-1';
BEGIN
  BEGIN
    PERFORM saly.nucleo_autotest_datos_v1();
    base := jsonb_build_object(
      'codigo','ZZT-OTP-1','clave','zzt_otp_envios','titulo','Bloqueo por envíos de OTP',
      'descripcion','Bloquea el envío de OTP al alcanzar el máximo de envíos en la ventana vigente',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','LF_GOVERNANCE',
      'alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','origen', jsonb_build_object('tipo','CHAT','ref','autotest-nucleo','solicitante','autotest'),'impacto','IMPLEMENTAR',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));

    -- C1 regla correcta: CANDIDATA y escrita
    r := saly.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C1 correcta (%)', r; END IF;
    IF NOT EXISTS (SELECT 1 FROM saly.nucleo_regla_versiones WHERE regla = 'ZZT-OTP-1') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C1 sin versión'; END IF;
    -- C2 código repetido
    r := saly.nucleo_regla_proponer_v1(base);
    IF r->>'resultado' <> 'RECHAZADA' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '0' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C2 código repetido'; END IF;
    -- C3 duplicado en el mismo alcance
    r := saly.nucleo_regla_proponer_v1(base || '{"codigo":"ZZT-OTP-2"}');
    IF r->>'clasificacion' NOT LIKE 'DUPLICADO_DE ZZT-OTP-1' OR r->>'resultado' <> 'RECHAZADA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C3 duplicado (%)', r->>'clasificacion'; END IF;
    -- C4 especialización en una pantalla
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-3','alcance',hoja), false);
    IF r->>'clasificacion' <> 'ESPECIALIZA ZZT-OTP-1' OR r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C4 especialización (%)', r->>'clasificacion'; END IF;
    -- C5 evaluar sin escribir no escribe; la copia idéntica en otro nodo genera aviso 11
    IF EXISTS (SELECT 1 FROM saly.nucleo_reglas WHERE codigo = 'ZZT-OTP-3') THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5 escribió en modo evaluación'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '11' AND NOT (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5 sin aviso de alcance (11)'; END IF;
    -- C5b proponer arriba avisa de la regla de la misma clave abajo (12)
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-5','alcance','GLOBAL','clase','TRANSVERSAL'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '12' AND x->>'detalle' LIKE '%ZZT-OTP-1%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5b sin aviso hacia abajo (12)'; END IF;
    -- C5c familia retirada
    UPDATE saly.nucleo_familias SET estado = 'RETIRADA' WHERE codigo = 'ZZT_FAM';
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X5C','clave','zzt_x5c'), false);
    UPDATE saly.nucleo_familias SET estado = 'ACTIVA' WHERE codigo = 'ZZT_FAM';
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '1' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C5c familia retirada aceptada'; END IF;
    -- C6 dato fijo
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X6','clave','zzt_x6',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('lit',3))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '5' AND (x->>'ok')::boolean = false AND (x->>'bloqueante')::boolean)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C6 dato fijo no detectado'; END IF;
    -- C7 hecho fuera del vocabulario
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X7','clave','zzt_x7',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','sueldo'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '4' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C7 vocabulario'; END IF;
    -- C8 parámetro inexistente
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X8','clave','zzt_x8',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.NO_EXISTE'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '6' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C8 parámetro'; END IF;
    -- C9 pruebas que no pasan
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X9','clave','zzt_x9','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',false),
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C9 pruebas que fallan'; END IF;
    -- C10 pruebas con valor fijo y pruebas insuficientes
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X10','clave','zzt_x10','pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',9),'esperado',true))), false);
    IF (SELECT count(*) FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' IN ('7','8') AND (x->>'ok')::boolean = false) <> 2
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C10 pruebas fijas/insuficientes'; END IF;
    -- C11 autoridad inexistente
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11','clave','zzt_x11','autoridad','Q99'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '16' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11 autoridad'; END IF;
    -- C11b autoridad retirada
    INSERT INTO saly.nucleo_autoridades (codigo, tipo, descripcion, estado) VALUES ('ZZT-AUT','POLITICA','Autoridad de prueba retirada','RETIRADA');
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11B','clave','zzt_x11b','autoridad','ZZT-AUT'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '16' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11b autoridad retirada aceptada'; END IF;
    -- C11c parámetro con valor de muestra: aviso, no bloqueo
    INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description)
    VALUES ('ZZT','PARAM_MUESTRA','4','INTEGER','FICTICIO','Parámetro de prueba con valor de muestra');
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X11C','clave','zzt_x11c',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),
      'pruebas', jsonb_build_array(
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.PARAM_MUESTRA')),'esperado',true),
         jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.PARAM_MUESTRA','mas',-1)),'esperado',false))), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '14' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C11c valor de muestra (%)', r->>'resultado'; END IF;
    -- C12 unidad incompatible (parámetro registrado con otro dato)
    INSERT INTO saly.nucleo_parametros (scope, config_key, hecho, dueno) VALUES ('ZZT','INACTIVIDAD_MAX','zzt_inactividad','LF_GOVERNANCE');
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X12','clave','zzt_x12',
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.INACTIVIDAD_MAX'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '13' AND (x->>'bloqueante')::boolean AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C12 unidades'; END IF;
    -- C13 efecto incoherente con la naturaleza
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X13','clave','zzt_x13','naturaleza','DEFINICION'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '18' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C13 efecto'; END IF;
    -- C14 clase BACKEND en un alcance de pantalla
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14','clave','zzt_x14','clase','BACKEND'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14 clase'; END IF;
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14B','clave','zzt_x14b','clase','BACKEND','alcance','ZZT-BACK'), false);
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14b backend válido rechazado'; END IF;
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X14C','clave','zzt_x14c','clase','PANTALLA','alcance','ZZT-BACK'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '19' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C14c pantalla en backend aceptada'; END IF;
    -- C15 conflicto con FIJA superior
    UPDATE saly.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-OTP-1';
    PERFORM set_config('lf.nucleo_publicando', 'ZZT-OTP-1:1', true);
    UPDATE saly.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-OTP-1' AND version = 1;
    PERFORM set_config('lf.nucleo_publicando', '', true);
    UPDATE saly.nucleo_aplicaciones SET modo = 'FIJA' WHERE regla = 'ZZT-OTP-1';
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-OTP-4','alcance',hoja), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '9' AND (x->>'ok')::boolean = false) THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C15 fija superior'; END IF;
    -- C16 dependencia no vigente: aviso, no bloqueo
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    UPDATE saly.nucleo_reglas SET estado = 'CANDIDATA' WHERE codigo = 'ZZT-OTP-1';
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X16','clave','zzt_x16','depende',jsonb_build_array('ZZT-OTP-1')), false);
    IF r->>'resultado' <> 'EVALUADA_SIN_ESCRIBIR' OR (r->>'avisos')::int < 1 THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C16 dependencia candidata (%)', r->>'resultado'; END IF;
    -- C17 extensión de contrato por familia
    INSERT INTO saly.nucleo_contrato_campos (familia, campo) VALUES ('ZZT_FAM','riesgo_operativo');
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X17','clave','zzt_x17'), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '2' AND (x->>'ok')::boolean = false AND x->>'detalle' LIKE '%riesgo_operativo%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C17 extensión de familia'; END IF;
    -- C18 familia inexistente y alcance inexistente
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X18','clave','zzt_x18','familia','NO_EXISTE','alcance','NO-EXISTE'), false);
    IF (SELECT count(*) FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' IN ('1','3') AND (x->>'ok')::boolean = false) <> 2
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C18 familia/alcance'; END IF;

    -- C19 condición como texto: se rechaza por forma y no se cuelga el evaluador
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X19','clave','zzt_x19','condicion',to_jsonb('intentos >= 3'::text)), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n' = '15' AND x->>'detalle' LIKE '%NUCLEO_EVAL_NODO_INVALIDO%')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C19 condición texto'; END IF;
    -- C19b condición como lista
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X19B','clave','zzt_x19b','condicion','["hecho"]'::jsonb), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C19b condición lista'; END IF;
    -- C20 operador desconocido
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X20','clave','zzt_x20',
      'condicion', jsonb_build_object('op','~','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C20 operador desconocido'; END IF;
    -- C21 nodo ambiguo (operador y hoja a la vez)
    r := saly.nucleo_regla_proponer_v1(base || jsonb_build_object('codigo','ZZT-X21','clave','zzt_x21',
      'condicion', jsonb_build_object('op','>=','lit',3,'izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS'))), false);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'control' = 'Condición bien formada' AND (x->>'ok')::boolean = false)
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: C21 hoja ambigua'; END IF;

    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'PUERTA 26/26';

END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_cola_trabajo_v1(p_nodo text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS TABLE(nodo text, regla text, version_implementada integer, version_pendiente integer, exigible_desde timestamp with time zone, estado text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE h text;
BEGIN
  FOR h IN SELECT n.codigo FROM nucleo_nodos n
            WHERE NOT EXISTS (SELECT 1 FROM nucleo_nodos c WHERE c.padre = n.codigo)
              AND (p_nodo IS NULL OR n.codigo = p_nodo) ORDER BY n.codigo LOOP
    RETURN QUERY
    SELECT h, e.regla, impl.v,
           pend.version, pend.exigible_desde,
           CASE WHEN pend.version IS NULL THEN 'AL_DIA'
                WHEN EXISTS (SELECT 1 FROM nucleo_regla_versiones w WHERE w.regla = e.regla AND w.estado = 'PUBLICADA'
                              AND w.impacto <> 'NINGUNO' AND w.version > COALESCE(impl.v, 0) AND w.version <= e.version
                              AND w.exigible_desde <= p_fecha) THEN 'DESFASADO'
                ELSE 'EN_PLAZO' END
      FROM nucleo_reglas_efectivas_v1(h, p_fecha) e
      LEFT JOIN LATERAL (SELECT max(i.version) AS v FROM nucleo_implementaciones i WHERE i.regla = e.regla AND i.nodo = h) impl ON true
      LEFT JOIN LATERAL (
        SELECT w.version, w.exigible_desde FROM nucleo_regla_versiones w
         WHERE w.regla = e.regla AND w.estado = 'PUBLICADA' AND w.impacto <> 'NINGUNO'
           AND w.version > COALESCE(impl.v, 0) AND w.version <= e.version
         ORDER BY w.version DESC LIMIT 1) pend ON true;
  END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_condicion_problema_v1(c jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE hojas integer;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RETURN 'nodo que no es objeto: ' || coalesce(c::text, 'nulo'); END IF;
  hojas := (c ? 'hecho')::int + (c ? 'param')::int + (c ? 'lit')::int;
  IF hojas > 1 OR (hojas = 1 AND c ? 'op') THEN RETURN 'nodo con más de un tipo: ' || c::text; END IF;
  IF hojas = 1 THEN
    IF (c ? 'hecho' AND jsonb_typeof(c->'hecho') <> 'string') OR (c ? 'param' AND (jsonb_typeof(c->'param') <> 'string' OR c->>'param' !~ '^[A-Z][A-Z0-9_]*\.[A-Z0-9_.]+$'))
      THEN RETURN 'hoja mal escrita: ' || c::text; END IF;
    RETURN NULL;
  END IF;
  IF NOT c ? 'op' OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=') THEN RETURN 'operador desconocido o ausente: ' || c::text; END IF;
  IF c->>'op' = 'no' THEN RETURN saly.nucleo_condicion_problema_v1(c->'izq'); END IF;
  RETURN COALESCE(saly.nucleo_condicion_problema_v1(c->'izq'), saly.nucleo_condicion_problema_v1(c->'der'));
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_config_num_v1(p_ref text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE v text := saly.nucleo_param_valor_v1(p_ref);
BEGIN
  IF v IS NULL OR v !~ '^-?[0-9]+(\.[0-9]+)?$' THEN RAISE EXCEPTION 'NUCLEO_EVAL_CONFIG_FALTA: %', p_ref; END IF;
  RETURN v::numeric;
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_eval_v1(c jsonb, e jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
DECLARE a jsonb; b jsonb; v jsonb;
BEGIN
  IF c IS NULL OR jsonb_typeof(c) <> 'object' THEN RAISE EXCEPTION 'NUCLEO_EVAL_NODO_INVALIDO: %', c; END IF;
  IF c ? 'lit' THEN RETURN c->'lit'; END IF;
  IF c ? 'param' THEN
    v := to_jsonb(saly.nucleo_param_valor_v1(c->>'param'));
    IF v IS NULL OR v = 'null'::jsonb THEN RAISE EXCEPTION 'NUCLEO_EVAL_PARAM_INEXISTENTE: %', c->>'param'; END IF;
    RETURN CASE WHEN (v #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN to_jsonb((v #>> '{}')::numeric) ELSE v END;
  END IF;
  IF c ? 'hecho' THEN
    v := e->(c->>'hecho');
    IF v IS NULL THEN RAISE EXCEPTION 'NUCLEO_EVAL_HECHO_SIN_VALOR: %', c->>'hecho'; END IF;
    IF jsonb_typeof(v) = 'object' AND v ? 'param' THEN
      RETURN to_jsonb(saly.nucleo_param_valor_v1(v->>'param')::numeric + COALESCE((v->>'mas')::numeric, 0));
    END IF;
    RETURN v;
  END IF;
  IF c->>'op' IS NULL OR c->>'op' NOT IN ('y','o','no','=','!=','>','>=','<','<=') THEN RAISE EXCEPTION 'NUCLEO_EVAL_OPERADOR_INVALIDO: %', c->>'op'; END IF;
  IF c->>'op' = 'no' THEN RETURN to_jsonb(NOT (saly.nucleo_eval_v1(c->'izq', e))::text::boolean); END IF;
  a := saly.nucleo_eval_v1(c->'izq', e);
  b := saly.nucleo_eval_v1(c->'der', e);
  RETURN to_jsonb(CASE c->>'op'
    WHEN 'y'  THEN a::text::boolean AND b::text::boolean
    WHEN 'o'  THEN a::text::boolean OR b::text::boolean
    WHEN '='  THEN a = b
    WHEN '!=' THEN a <> b
    WHEN '>'  THEN (a #>> '{}')::numeric >  (b #>> '{}')::numeric
    WHEN '>=' THEN (a #>> '{}')::numeric >= (b #>> '{}')::numeric
    WHEN '<'  THEN (a #>> '{}')::numeric <  (b #>> '{}')::numeric
    WHEN '<=' THEN (a #>> '{}')::numeric <= (b #>> '{}')::numeric
    END);
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_hash_paquete_v1(p_regla text, p_version integer)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
  SELECT encode(sha256(convert_to(v.hash || '|' || COALESCE((
           SELECT string_agg(t.n || ':' || COALESCE(t.casuistica,'') || ':' || t.entrada::text || ':' || t.esperado::text, '|' ORDER BY t.n)
             FROM nucleo_regla_pruebas t WHERE t.regla = v.regla AND t.version = v.version), ''), 'UTF8')), 'hex')
    FROM nucleo_regla_versiones v WHERE v.regla = p_regla AND v.version = p_version
$function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_juicio_registrar_v1(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  v_ver integer; v_hash text; v_falta text; v_cal numeric; v_sem numeric; v_coh numeric; v_min numeric; v_id bigint;
BEGIN
  SELECT version INTO v_ver FROM nucleo_regla_versiones WHERE regla = p->>'regla' AND estado = 'CANDIDATA';
  IF v_ver IS NULL THEN RAISE EXCEPTION 'NUCLEO_JUICIO_SIN_VERSION_CANDIDATA: %', p->>'regla'; END IF;
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
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_nodos_condicion_v1(c jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH RECURSIVE t(n) AS (
    SELECT c WHERE jsonb_typeof(c) = 'object'
    UNION ALL
    SELECT x FROM t, LATERAL (VALUES (t.n->'izq'), (t.n->'der')) y(x)
     WHERE x IS NOT NULL AND jsonb_typeof(x) = 'object')
  SELECT n FROM t
$function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_param_valor_v1(p_ref text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT g.config_value FROM saly.config_global g
   WHERE g.scope = split_part(p_ref, '.', 1)
     AND g.config_key = substr(p_ref, length(split_part(p_ref, '.', 1)) + 2)
     AND g.valid_from <= now()
   ORDER BY g.valid_from DESC LIMIT 1
$function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_regla_evaluar_v1(p_regla text, p_registrar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
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
  SELECT version INTO v_ver FROM nucleo_regla_versiones WHERE regla = p_regla AND estado = 'CANDIDATA';
  IF v_ver IS NULL THEN RETURN jsonb_build_object('regla', p_regla, 'decision', 'NO_APLICA', 'estado', r.estado); END IF;
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
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM saly.config_global g WHERE g.scope || '.' || g.config_key = x->>'param'
         AND g.valid_from <= now() AND g.value_status <> 'REAL'
         AND g.valid_from = (SELECT max(g2.valid_from) FROM saly.config_global g2 WHERE g2.scope = g.scope AND g2.config_key = g.config_key AND g2.valid_from <= now()));
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
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_regla_promover_v1(p_regla text, p_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE e jsonb; v_estado text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_promover:' || p_regla, 0));
  SELECT estado INTO v_estado FROM nucleo_reglas WHERE codigo = p_regla FOR UPDATE;
  -- la publicación cierra la versión anterior y deja la regla VIGENTE
  IF NOT FOUND THEN RAISE EXCEPTION 'NUCLEO_REGLA_INEXISTENTE: %', p_regla; END IF;
  e := nucleo_regla_evaluar_v1(p_regla, true);
  IF e->>'decision' = 'NO_APLICA' THEN RETURN e || jsonb_build_object('resultado','NO_APLICA'); END IF;
  IF p_decision IS NOT NULL AND e->>'decision' <> 'MANUAL' THEN
    RAISE EXCEPTION 'NUCLEO_DECISION_NO_APLICA: la evaluación es % y una decisión humana solo resuelve MANUAL', e->>'decision';
  END IF;
  IF e->>'decision' = 'AUTO' THEN
    PERFORM nucleo_version_publicar_v1(p_regla, (e->>'version')::int);
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
      PERFORM nucleo_version_publicar_v1(p_regla, (e->>'version')::int);
      RETURN e || jsonb_build_object('resultado','PROMOVIDA_MANUAL');
    END IF;
    RETURN e || jsonb_build_object('resultado','RECHAZADA_POR_DUENO');
  END IF;
  RETURN e || jsonb_build_object('resultado', e->>'decision');
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_regla_proponer_v1(p jsonb, p_aplicar boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE
  ctl jsonb := '[]'::jsonb;
  v_fam record; v_falta text; v_txt text; v_n integer; v_ok boolean;
  v_clase text := upper(p->>'clase'); v_nat text := upper(p->>'naturaleza'); v_alc text := p->>'alcance';
  v_ambito text; v_nivel text; v_clasif text := 'NUEVA'; v_prueba jsonb; v_res jsonb; v_bloq integer;
  v_lits jsonb; v_efectos jsonb;
  v_tipo text := upper(COALESCE(p->>'tipo','NUEVA')); v_r0 record; v_nodo0 text; v_ultima record; v_ver integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('nucleo_proponer:' || coalesce(p->>'clave', ''), 0));

  -- 0 identidad: NUEVA exige código libre; CAMBIO exige la regla existente con la misma identidad y alcance, sin otra candidata
  IF v_tipo = 'NUEVA' THEN
    v_ok := p->>'codigo' IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nucleo_reglas WHERE codigo = p->>'codigo');
    ctl := ctl || jsonb_build_object('n',0,'control','Código libre','ok',v_ok,'bloqueante',true,
      'detalle', CASE WHEN v_ok THEN '' ELSE 'El código ya existe o falta: use otro código o proponga un CAMBIO de la regla existente.' END);
  ELSIF v_tipo = 'CAMBIO' THEN
    SELECT * INTO v_r0 FROM nucleo_reglas WHERE codigo = p->>'codigo';
    SELECT nodo INTO v_nodo0 FROM nucleo_aplicaciones WHERE regla = p->>'codigo' ORDER BY nodo LIMIT 1;
    v_txt := CASE
      WHEN v_r0.codigo IS NULL THEN 'La regla ' || COALESCE(p->>'codigo','(vacía)') || ' no existe: proponga una regla NUEVA.'
      WHEN v_r0.estado NOT IN ('CANDIDATA','VIGENTE') THEN 'La regla está ' || v_r0.estado || ' y no admite cambios.'
      WHEN v_r0.clave <> p->>'clave' OR v_r0.familia <> p->>'familia' OR v_r0.naturaleza <> v_nat THEN 'Un cambio no altera clave, familia ni naturaleza: eso es una regla nueva.'
      WHEN v_nodo0 IS DISTINCT FROM v_alc THEN 'Un cambio no altera el alcance (' || COALESCE(v_nodo0,'-') || '): eso es una regla nueva o una especialización.'
      WHEN EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = p->>'codigo' AND estado = 'CANDIDATA') THEN 'Ya hay una versión candidata abierta: promuévala o descártela antes de otro cambio.'
      END;
    ctl := ctl || jsonb_build_object('n',0,'control','Regla a cambiar','ok',v_txt IS NULL,'bloqueante',true,'detalle',COALESCE(v_txt,''));
  ELSE
    ctl := ctl || jsonb_build_object('n',0,'control','Tipo de propuesta','ok',false,'bloqueante',true,'detalle','El tipo debe ser NUEVA o CAMBIO.');
  END IF;

  -- 1 familia existe
  SELECT * INTO v_fam FROM nucleo_familias WHERE codigo = p->>'familia';
  v_ok := FOUND AND v_fam.estado <> 'RETIRADA';
  ctl := ctl || jsonb_build_object('n',1,'control','Familia existe','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN p->>'familia' ELSE 'La familia ' || coalesce(p->>'familia','(vacía)') || ' no existe o está retirada: elija una de saly.nucleo_familias.' END);

  -- 2 campos del contrato (global + extensión de la familia)
  SELECT string_agg(k.campo, ', ' ORDER BY k.campo) INTO v_falta FROM nucleo_contrato_campos k
   WHERE (k.familia IS NULL OR k.familia = p->>'familia')
     AND (NOT p ? k.campo OR jsonb_typeof(p->k.campo) = 'null' OR btrim(p->>k.campo) = '' OR p->k.campo IN ('[]'::jsonb, '{}'::jsonb));
  ctl := ctl || jsonb_build_object('n',2,'control','Campos obligatorios','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Faltan o están vacíos: ' || v_falta END);

  v_txt := nucleo_condicion_problema_v1(p->'condicion');
  ctl := ctl || jsonb_build_object('n',2,'control','Condición bien formada','ok',v_txt IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_txt IS NULL THEN '' ELSE 'La condición no es válida (' || v_txt || '). Use hojas {"hecho"}, {"param":"SCOPE.CLAVE"}, {"lit"} y operadores y, o, no, =, !=, >, >=, <, <=.' END);

  v_ok := jsonb_typeof(p->'origen') = 'object' AND p->'origen'->>'tipo' IN ('IG','CHAT','PERSONA','MIGRACION')
          AND length(btrim(COALESCE(p->'origen'->>'ref',''))) >= 3 AND length(btrim(COALESCE(p->'origen'->>'solicitante',''))) >= 3;
  ctl := ctl || jsonb_build_object('n',2,'control','Origen del cambio','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'El origen debe indicar tipo (IG, CHAT, PERSONA o MIGRACION), referencia y solicitante.' END);
  v_ok := upper(p->>'impacto') IN ('NINGUNO','REVISAR','IMPLEMENTAR') AND NOT (v_tipo = 'NUEVA' AND upper(p->>'impacto') = 'NINGUNO')
          AND (p->'plazo_dias' IS NULL OR (jsonb_typeof(p->'plazo_dias') = 'number' AND (p->>'plazo_dias')::numeric >= 0 AND (p->>'plazo_dias')::numeric = trunc((p->>'plazo_dias')::numeric)));
  ctl := ctl || jsonb_build_object('n',18,'control','Impacto declarado','ok',v_ok,'bloqueante',true,
    'detalle', CASE WHEN v_ok THEN '' ELSE 'Impacto NINGUNO, REVISAR o IMPLEMENTAR (una regla nueva no puede ser NINGUNO); plazo_dias entero no negativo.' END);

  -- 3 alcance existe
  SELECT nivel INTO v_nivel FROM nucleo_nodos WHERE codigo = v_alc;
  ctl := ctl || jsonb_build_object('n',3,'control','Alcance existe','ok',v_nivel IS NOT NULL,'bloqueante',true,
    'detalle', CASE WHEN v_nivel IS NOT NULL THEN v_alc ELSE 'El alcance ' || coalesce(v_alc,'(vacío)') || ' no es un nodo del árbol (saly.v_nucleo_nodos).' END);

  -- 4 datos dentro del vocabulario de la familia
  SELECT string_agg(DISTINCT x->>'hecho', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'hecho' AND NOT EXISTS (SELECT 1 FROM nucleo_familia_vocabulario v WHERE v.familia = p->>'familia' AND v.hecho = x->>'hecho');
  ctl := ctl || jsonb_build_object('n',4,'control','Datos dentro del vocabulario','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Datos fuera del vocabulario de la familia: ' || v_falta || '. Use un hecho de saly.v_nucleo_vocabulario o regístrelo primero.' END);

  -- 5 sin datos fijos (literales permitidos en NUCLEO.LITERALES_PERMITIDOS)
  v_lits := COALESCE(nucleo_param_valor_v1('NUCLEO.LITERALES_PERMITIDOS')::jsonb, '[]'::jsonb);
  SELECT string_agg(x->>'lit', ', ') INTO v_falta FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'lit' AND jsonb_typeof(x->'lit') = 'number' AND NOT v_lits @> jsonb_build_array(x->'lit');
  ctl := ctl || jsonb_build_object('n',5,'control','Sin datos fijos','ok',v_falta IS NULL,'bloqueante',true,
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Valores fijos en la condición: ' || v_falta || '. Reemplácelos por {"param":"SCOPE.CLAVE"} de config_global.' END);
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
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Parámetros inexistentes en config_global: ' || v_falta END);

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
      'detalle','Registre en saly.nucleo_parametros el dato y la unidad de: ' || v_txt || ' (sin eso no se puede verificar la unidad).');
  END IF;

  -- 14 parámetro real (no de muestra)
  SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(p->'condicion') x
   WHERE x ? 'param' AND EXISTS (SELECT 1 FROM saly.config_global g WHERE g.scope || '.' || g.config_key = x->>'param' AND g.value_status <> 'REAL');
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
    'detalle', CASE WHEN v_falta IS NULL THEN '' ELSE 'Casuísticas que no existen para esta familia y naturaleza: ' || v_falta || ' (ver saly.nucleo_casuisticas).' END);

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
    'detalle', CASE WHEN v_ok THEN p->>'autoridad' ELSE 'La autoridad ' || coalesce(p->>'autoridad','(vacía)') || ' no está en saly.nucleo_autoridades o no está vigente.' END);

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
    WHEN 'BACKEND' THEN v_nivel = 'GLOBAL' OR COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_BACKEND')::jsonb, '[]') @> jsonb_build_array(v_ambito)
    WHEN 'PANTALLA' THEN COALESCE(nucleo_param_valor_v1('NUCLEO.AMBITOS_PANTALLA')::jsonb, '[]') @> jsonb_build_array(v_ambito)
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
   WHERE r.clave = p->>'clave' AND r.familia = p->>'familia' AND r.estado NOT IN ('RETIRADA') AND r.codigo IS DISTINCT FROM CASE WHEN v_tipo = 'CAMBIO' THEN p->>'codigo' END
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

  IF v_tipo = 'CAMBIO' THEN
    SELECT * INTO v_ultima FROM nucleo_regla_versiones WHERE regla = p->>'codigo' AND estado <> 'DESCARTADA' ORDER BY version DESC LIMIT 1;
    IF v_ultima.version IS NOT NULL
       AND ROW(v_ultima.titulo, v_ultima.descripcion, v_ultima.condicion, v_ultima.efecto, v_ultima.autoridad, v_ultima.impacto)
           IS NOT DISTINCT FROM ROW(p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad', upper(p->>'impacto'))
       AND (SELECT COALESCE(jsonb_agg(jsonb_build_object('c',casuistica,'e',entrada,'x',esperado) ORDER BY n), '[]') FROM nucleo_regla_pruebas
             WHERE regla = v_ultima.regla AND version = v_ultima.version)
           IS NOT DISTINCT FROM (SELECT COALESCE(jsonb_agg(jsonb_build_object('c',t.v->>'casuistica','e',t.v->'entrada','x',t.v->'esperado') ORDER BY t.o), '[]')
             FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p->'pruebas')='array' THEN p->'pruebas' ELSE '[]' END) WITH ORDINALITY t(v, o)) THEN
      ctl := ctl || jsonb_build_object('n',10,'control','Cambio con contenido','ok',false,'bloqueante',true,
        'detalle','SIN_CAMBIOS: igual a la versión ' || v_ultima.version || '.');
    END IF;
  END IF;

  -- 11 alcance correcto: copias idénticas en otros nodos (aviso)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
    JOIN LATERAL (SELECT condicion FROM nucleo_regla_versiones WHERE regla = r.codigo ORDER BY version DESC LIMIT 1) v ON true
   WHERE r.clave = p->>'clave' AND v.condicion = p->'condicion' AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',11,'control','Alcance correcto','ok',false,'bloqueante',false,
      'detalle','Ya existe idéntica en otros nodos (' || v_txt || '): considere registrarla una vez en el nodo común y retirar las copias.');
  END IF;

  -- 12 hacia abajo: reglas de la misma clave en los descendientes (aviso)
  WITH RECURSIVE dn(c) AS (SELECT v_alc UNION ALL SELECT n.codigo FROM nucleo_nodos n JOIN dn ON n.padre = dn.c)
  SELECT string_agg(r.codigo || ' en ' || a.nodo, ', ') INTO v_txt
    FROM nucleo_reglas r JOIN nucleo_aplicaciones a ON a.regla = r.codigo
   WHERE r.clave = p->>'clave' AND a.nodo IN (SELECT c FROM dn) AND a.nodo <> v_alc AND r.codigo <> p->>'codigo';
  IF v_txt IS NOT NULL THEN
    ctl := ctl || jsonb_build_object('n',12,'control','Impacto hacia abajo','ok',false,'bloqueante',false,
      'detalle', CASE WHEN upper(p->>'modo') = 'FIJA' THEN 'Es FIJA y hay reglas de la misma clave abajo (deben resolverse antes de promover): '
                      ELSE 'Hay reglas de la misma clave abajo (quedan como especialización): ' END || v_txt);
  END IF;

  SELECT count(*) INTO v_bloq FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;

  IF v_bloq = 0 AND p_aplicar THEN
    IF v_tipo = 'NUEVA' THEN
      INSERT INTO nucleo_reglas (codigo, clave, familia, naturaleza, estado)
      VALUES (p->>'codigo', p->>'clave', p->>'familia', v_nat, 'CANDIDATA');
      INSERT INTO nucleo_aplicaciones (regla, nodo, modo) VALUES (p->>'codigo', v_alc, upper(p->>'modo'));
    END IF;
    INSERT INTO nucleo_regla_versiones (regla, titulo, descripcion, condicion, efecto, autoridad, impacto, origen, ficha, plazo_dias)
    VALUES (p->>'codigo', p->>'titulo', p->>'descripcion', p->'condicion', upper(p->>'efecto'), p->>'autoridad',
            upper(p->>'impacto'), p->'origen', p - 'pruebas', (p->>'plazo_dias')::int)
    RETURNING version INTO v_ver;
    INSERT INTO nucleo_regla_pruebas (regla, version, n, casuistica, entrada, esperado)
    SELECT p->>'codigo', v_ver, t.ord::int, t.v->>'casuistica', t.v->'entrada', t.v->'esperado'
      FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY t(v, ord);
    INSERT INTO nucleo_relaciones (origen, destino, tipo)
    SELECT p->>'codigo', d, 'DEPENDE' FROM jsonb_array_elements_text(COALESCE(p->'depende','[]'::jsonb)) d
     WHERE NOT EXISTS (SELECT 1 FROM nucleo_relaciones x WHERE x.origen = p->>'codigo' AND x.destino = d AND x.tipo = 'DEPENDE');
  END IF;

  RETURN jsonb_build_object(
    'resultado', CASE WHEN v_bloq > 0 THEN 'RECHAZADA' WHEN p_aplicar THEN 'CANDIDATA' ELSE 'EVALUADA_SIN_ESCRIBIR' END,
    'tipo', v_tipo, 'version', v_ver, 'clasificacion', v_clasif, 'bloqueantes', v_bloq,
    'avisos', (SELECT count(*) FROM jsonb_array_elements(ctl) x WHERE (x->>'ok')::boolean IS NOT TRUE AND NOT (x->>'bloqueante')::boolean),
    'controles', ctl);
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_reglas_efectivas_v1(p_nodo text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS TABLE(regla text, clave text, version integer, nodo_origen text, modo text, distancia integer, conflicto text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM saly.nucleo_nodos WHERE codigo = p_nodo) THEN
    RAISE EXCEPTION 'NUCLEO_NODO_INEXISTENTE: %', p_nodo;
  END IF;
  RETURN QUERY
  WITH RECURSIVE anc(nodo, d) AS (
    SELECT p_nodo, 0
    UNION ALL
    SELECT n.padre, anc.d + 1 FROM saly.nucleo_nodos n JOIN anc ON n.codigo = anc.nodo WHERE n.padre IS NOT NULL),
  cand AS (
    SELECT r.codigo AS regla, r.clave, v.version, a.nodo, a.modo, anc.d
      FROM saly.nucleo_aplicaciones a
      JOIN anc ON anc.nodo = a.nodo
      JOIN saly.nucleo_reglas r ON r.codigo = a.regla AND r.estado = 'VIGENTE'
      JOIN saly.nucleo_regla_versiones v ON v.regla = r.codigo
       AND v.publicada_desde <= p_fecha AND (v.vigente_hasta IS NULL OR v.vigente_hasta > p_fecha)
     WHERE a.modo <> 'SOLO_AQUI' OR anc.d = 0),
  fija AS (SELECT c.clave, max(c.d) AS d FROM cand c WHERE c.modo = 'FIJA' GROUP BY c.clave),
  elegido AS (
    SELECT c.clave, COALESCE(f.d, min(c.d)) AS d
      FROM cand c LEFT JOIN fija f ON f.clave = c.clave
     GROUP BY c.clave, f.d)
  SELECT c.regla, c.clave, c.version, c.nodo, c.modo, c.d,
         CASE
           WHEN (SELECT count(*) FROM cand x WHERE x.clave = c.clave AND x.d = c.d) > 1 THEN 'MISMO_NIVEL'
           WHEN c.modo = 'FIJA' AND EXISTS (SELECT 1 FROM cand x WHERE x.clave = c.clave AND x.d < c.d) THEN 'FIJA_IGNORA_ESPECIALIZACION'
         END
    FROM cand c JOIN elegido e ON e.clave = c.clave AND e.d = c.d
   WHERE NOT EXISTS (SELECT 1 FROM fija f WHERE f.clave = c.clave) OR c.modo = 'FIJA';
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_revalidacion_v1()
 RETURNS TABLE(regla text, version integer, motivo text, detalle text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE v record; t record; r jsonb; v_txt text;
BEGIN
  FOR v IN SELECT x.*, rr.familia FROM nucleo_regla_versiones x JOIN nucleo_reglas rr ON rr.codigo = x.regla
            WHERE x.estado = 'CANDIDATA' OR (x.estado = 'PUBLICADA' AND x.vigente_hasta IS NULL) ORDER BY x.regla, x.version LOOP
    SELECT string_agg(k.campo, ', ' ORDER BY k.campo) INTO v_txt FROM nucleo_contrato_campos k
     WHERE (k.familia IS NULL OR k.familia = v.familia) AND (k.campo <> 'pruebas')
       AND (NOT v.ficha ? k.campo OR jsonb_typeof(v.ficha->k.campo) = 'null' OR btrim(v.ficha->>k.campo) = '');
    IF v_txt IS NOT NULL THEN regla := v.regla; version := v.version; motivo := 'CONTRATO'; detalle := 'Falta: ' || v_txt; RETURN NEXT; END IF;
    v_txt := NULL;
    FOR t IN SELECT * FROM nucleo_regla_pruebas p WHERE p.regla = v.regla AND p.version = v.version ORDER BY p.n LOOP
      BEGIN
        r := nucleo_eval_v1(v.condicion, t.entrada);
        IF r IS DISTINCT FROM t.esperado THEN v_txt := concat_ws(', ', v_txt, 'prueba ' || t.n); END IF;
      EXCEPTION WHEN others THEN v_txt := concat_ws(', ', v_txt, 'prueba ' || t.n || ' (' || SQLERRM || ')');
      END;
    END LOOP;
    IF v_txt IS NOT NULL THEN regla := v.regla; version := v.version; motivo := 'PRUEBAS'; detalle := 'Fallan con los parámetros vigentes: ' || v_txt; RETURN NEXT; END IF;
    SELECT string_agg(DISTINCT x->>'param', ', ') INTO v_txt FROM nucleo_nodos_condicion_v1(v.condicion) x
     WHERE x ? 'param' AND (nucleo_param_valor_v1(x->>'param') IS NULL OR EXISTS (
       SELECT 1 FROM saly.config_global g WHERE g.scope || '.' || g.config_key = x->>'param' AND g.valid_from <= now() AND g.value_status <> 'REAL'
          AND g.valid_from = (SELECT max(g2.valid_from) FROM saly.config_global g2 WHERE g2.scope = g.scope AND g2.config_key = g.config_key AND g2.valid_from <= now())));
    IF v_txt IS NOT NULL THEN regla := v.regla; version := v.version; motivo := 'PARAMETRO'; detalle := 'Inexistente o con valor de muestra: ' || v_txt; RETURN NEXT; END IF;
  END LOOP;
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_version_descartar_v1(p_regla text, p_autoridad text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE v_ver integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM nucleo_autoridades WHERE codigo = p_autoridad AND estado = 'VIGENTE') THEN
    RAISE EXCEPTION 'NUCLEO_DESCARTE_AUTORIDAD_NO_VIGENTE: %', p_autoridad;
  END IF;
  IF length(btrim(COALESCE(p_motivo,''))) < 10 THEN RAISE EXCEPTION 'NUCLEO_DESCARTE_SIN_MOTIVO'; END IF;
  SELECT version INTO v_ver FROM nucleo_regla_versiones WHERE regla = p_regla AND estado = 'CANDIDATA' FOR UPDATE;
  IF v_ver IS NULL THEN RAISE EXCEPTION 'NUCLEO_DESCARTE_SIN_CANDIDATA: %', p_regla; END IF;
  PERFORM set_config('lf.nucleo_publicando', p_regla || ':' || v_ver, true);
  UPDATE nucleo_regla_versiones SET estado = 'DESCARTADA' WHERE regla = p_regla AND version = v_ver;
  PERFORM set_config('lf.nucleo_publicando', '', true);
  IF NOT EXISTS (SELECT 1 FROM nucleo_regla_versiones WHERE regla = p_regla AND estado = 'PUBLICADA') THEN
    UPDATE nucleo_reglas SET estado = 'RETIRADA' WHERE codigo = p_regla;
  END IF;
  RETURN jsonb_build_object('regla', p_regla, 'version', v_ver, 'estado', 'DESCARTADA', 'autoridad', p_autoridad, 'motivo', p_motivo);
END $function$
;

CREATE OR REPLACE FUNCTION saly.nucleo_version_publicar_v1(p_regla text, p_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'saly', 'public'
AS $function$
DECLARE v record; ev record; v_hash text; v_plazo integer;
BEGIN
  SELECT * INTO v FROM nucleo_regla_versiones WHERE regla = p_regla AND version = p_version FOR UPDATE;
  IF NOT FOUND OR v.estado <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_PUBLICAR_NO_CANDIDATA: % v%', p_regla, p_version; END IF;
  v_hash := nucleo_hash_paquete_v1(p_regla, p_version);
  SELECT * INTO ev FROM nucleo_evaluaciones WHERE regla = p_regla ORDER BY id DESC LIMIT 1;
  IF ev.id IS NULL OR ev.version <> p_version OR ev.hash_paquete <> v_hash OR NOT (
       ev.decision = 'AUTO' OR (ev.decision = 'MANUAL' AND EXISTS (
         SELECT 1 FROM nucleo_decisiones d WHERE d.evaluacion_id = ev.id AND d.decision = 'APROBAR'))) THEN
    RAISE EXCEPTION 'NUCLEO_PUBLICAR_SIN_PROMOCION: % v% no tiene evaluación AUTO ni aprobación sobre su contenido actual', p_regla, p_version;
  END IF;
  v_plazo := CASE WHEN v.impacto = 'NINGUNO' THEN 0
                  ELSE COALESCE(v.plazo_dias, nucleo_config_num_v1('NUCLEO.PLAZO_IMPLEMENTACION_DIAS')::int) END;
  PERFORM set_config('lf.nucleo_publicando', p_regla || ':' || p_version, true);
  UPDATE nucleo_regla_versiones SET vigente_hasta = now()
   WHERE regla = p_regla AND estado = 'PUBLICADA' AND vigente_hasta IS NULL;
  UPDATE nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() + make_interval(days => v_plazo)
   WHERE regla = p_regla AND version = p_version;
  PERFORM set_config('lf.nucleo_publicando', '', true);
  UPDATE nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = p_regla AND estado <> 'VIGENTE';
  RETURN jsonb_build_object('regla', p_regla, 'version', p_version, 'exigible_en_dias', v_plazo);
END $function$
;


--
-- PostgreSQL database dump
--

\restrict 2KejlWmsfdO6qwwBjAvRDkKHWmylgIosng3pToUO0EcyA5rDZS93BtUfAewAwDg

-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)



--
-- Name: nucleo_aplicaciones nucleo_aplicaciones_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_aplicaciones
    ADD CONSTRAINT nucleo_aplicaciones_pkey PRIMARY KEY (regla, nodo);


--
-- Name: nucleo_autoridades nucleo_autoridades_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_autoridades
    ADD CONSTRAINT nucleo_autoridades_pkey PRIMARY KEY (codigo);


--
-- Name: nucleo_decisiones nucleo_decisiones_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_decisiones
    ADD CONSTRAINT nucleo_decisiones_pkey PRIMARY KEY (id);


--
-- Name: nucleo_evaluaciones nucleo_evaluaciones_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_evaluaciones
    ADD CONSTRAINT nucleo_evaluaciones_pkey PRIMARY KEY (id);


--
-- Name: nucleo_familia_vocabulario nucleo_familia_vocabulario_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_familia_vocabulario
    ADD CONSTRAINT nucleo_familia_vocabulario_pkey PRIMARY KEY (familia, hecho);


--
-- Name: nucleo_familias nucleo_familias_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_familias
    ADD CONSTRAINT nucleo_familias_pkey PRIMARY KEY (codigo);


--
-- Name: nucleo_hechos nucleo_hechos_campo_id_key; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_hechos
    ADD CONSTRAINT nucleo_hechos_campo_id_key UNIQUE (campo_id);


--
-- Name: nucleo_hechos nucleo_hechos_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_hechos
    ADD CONSTRAINT nucleo_hechos_pkey PRIMARY KEY (codigo);


--
-- Name: nucleo_implementaciones nucleo_implementaciones_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_implementaciones
    ADD CONSTRAINT nucleo_implementaciones_pkey PRIMARY KEY (regla, nodo, version);


--
-- Name: nucleo_juicios nucleo_juicios_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_juicios
    ADD CONSTRAINT nucleo_juicios_pkey PRIMARY KEY (id);


--
-- Name: nucleo_nodos nucleo_nodos_pantalla_id_key; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_nodos
    ADD CONSTRAINT nucleo_nodos_pantalla_id_key UNIQUE (pantalla_id);


--
-- Name: nucleo_nodos nucleo_nodos_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_nodos
    ADD CONSTRAINT nucleo_nodos_pkey PRIMARY KEY (codigo);


--
-- Name: nucleo_parametros nucleo_parametros_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_parametros
    ADD CONSTRAINT nucleo_parametros_pkey PRIMARY KEY (scope, config_key);


--
-- Name: nucleo_regla_pruebas nucleo_regla_pruebas_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_regla_pruebas
    ADD CONSTRAINT nucleo_regla_pruebas_pkey PRIMARY KEY (regla, version, n);


--
-- Name: nucleo_regla_versiones nucleo_regla_versiones_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_regla_versiones
    ADD CONSTRAINT nucleo_regla_versiones_pkey PRIMARY KEY (regla, version);


--
-- Name: nucleo_reglas nucleo_reglas_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_reglas
    ADD CONSTRAINT nucleo_reglas_pkey PRIMARY KEY (codigo);


--
-- Name: nucleo_reglas nucleo_reglas_regla_legacy_id_key; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_reglas
    ADD CONSTRAINT nucleo_reglas_regla_legacy_id_key UNIQUE (regla_legacy_id);


--
-- Name: nucleo_relaciones nucleo_relaciones_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_relaciones
    ADD CONSTRAINT nucleo_relaciones_pkey PRIMARY KEY (origen, destino, tipo);


--
-- Name: nucleo_rubrica nucleo_rubrica_pkey; Type: CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_rubrica
    ADD CONSTRAINT nucleo_rubrica_pkey PRIMARY KEY (codigo);


--
-- Name: nucleo_casuisticas_unica; Type: INDEX; Schema: saly; Owner: postgres
--

CREATE UNIQUE INDEX nucleo_casuisticas_unica ON saly.nucleo_casuisticas USING btree (COALESCE(familia, '*'::text), naturaleza, codigo);


--
-- Name: nucleo_contrato_campos_unico; Type: INDEX; Schema: saly; Owner: postgres
--

CREATE UNIQUE INDEX nucleo_contrato_campos_unico ON saly.nucleo_contrato_campos USING btree (COALESCE(familia, '*'::text), campo);


--
-- Name: nucleo_evaluaciones_regla; Type: INDEX; Schema: saly; Owner: postgres
--

CREATE INDEX nucleo_evaluaciones_regla ON saly.nucleo_evaluaciones USING btree (regla, id DESC);


--
-- Name: nucleo_juicios_regla; Type: INDEX; Schema: saly; Owner: postgres
--

CREATE INDEX nucleo_juicios_regla ON saly.nucleo_juicios USING btree (regla, version, id DESC);


--
-- Name: nucleo_nodos_una_raiz; Type: INDEX; Schema: saly; Owner: postgres
--

CREATE UNIQUE INDEX nucleo_nodos_una_raiz ON saly.nucleo_nodos USING btree ((true)) WHERE (nivel = 'GLOBAL'::text);


--
-- Name: nucleo_versiones_una_candidata; Type: INDEX; Schema: saly; Owner: postgres
--

CREATE UNIQUE INDEX nucleo_versiones_una_candidata ON saly.nucleo_regla_versiones USING btree (regla) WHERE (estado = 'CANDIDATA'::text);


--
-- Name: nucleo_decisiones trg_nucleo_decisiones_inmutable; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_decisiones_inmutable BEFORE DELETE OR UPDATE ON saly.nucleo_decisiones FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_historial_inmutable_v1();


--
-- Name: nucleo_evaluaciones trg_nucleo_evaluaciones_inmutable; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_evaluaciones_inmutable BEFORE DELETE OR UPDATE ON saly.nucleo_evaluaciones FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_historial_inmutable_v1();


--
-- Name: nucleo_hechos trg_nucleo_hechos_columna_existe_v1; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_hechos_columna_existe_v1 BEFORE INSERT OR UPDATE OF tabla_ref, columna_ref ON saly.nucleo_hechos FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_hechos_columna_existe_v1();


--
-- Name: nucleo_implementaciones trg_nucleo_implementaciones_guardia; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_implementaciones_guardia BEFORE INSERT OR DELETE OR UPDATE ON saly.nucleo_implementaciones FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_implementaciones_guardia_v1();


--
-- Name: nucleo_juicios trg_nucleo_juicios_inmutable; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_juicios_inmutable BEFORE DELETE OR UPDATE ON saly.nucleo_juicios FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_historial_inmutable_v1();


--
-- Name: nucleo_nodos trg_nucleo_nodos_nivel_v1; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_nodos_nivel_v1 BEFORE INSERT OR UPDATE OF padre, nivel ON saly.nucleo_nodos FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_nodos_nivel_v1();


--
-- Name: nucleo_parametros trg_nucleo_parametros_existe_v1; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_parametros_existe_v1 BEFORE INSERT OR UPDATE OF scope, config_key ON saly.nucleo_parametros FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_parametros_existe_v1();


--
-- Name: nucleo_regla_pruebas trg_nucleo_pruebas_guardia; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_pruebas_guardia BEFORE INSERT OR DELETE OR UPDATE ON saly.nucleo_regla_pruebas FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_pruebas_guardia_v1();


--
-- Name: nucleo_relaciones trg_nucleo_relaciones_sin_ciclo_v1; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_relaciones_sin_ciclo_v1 BEFORE INSERT OR UPDATE ON saly.nucleo_relaciones FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_relaciones_sin_ciclo_v1();


--
-- Name: nucleo_regla_versiones trg_nucleo_versiones_alta_v1; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_versiones_alta_v1 BEFORE INSERT ON saly.nucleo_regla_versiones FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_versiones_alta_v1();


--
-- Name: nucleo_regla_versiones trg_nucleo_versiones_inmutables_v1; Type: TRIGGER; Schema: saly; Owner: postgres
--

CREATE TRIGGER trg_nucleo_versiones_inmutables_v1 BEFORE DELETE OR UPDATE ON saly.nucleo_regla_versiones FOR EACH ROW EXECUTE FUNCTION saly.fn_nucleo_versiones_inmutables_v1();


--
-- Name: nucleo_aplicaciones nucleo_aplicaciones_nodo_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_aplicaciones
    ADD CONSTRAINT nucleo_aplicaciones_nodo_fkey FOREIGN KEY (nodo) REFERENCES saly.nucleo_nodos(codigo);


--
-- Name: nucleo_aplicaciones nucleo_aplicaciones_regla_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_aplicaciones
    ADD CONSTRAINT nucleo_aplicaciones_regla_fkey FOREIGN KEY (regla) REFERENCES saly.nucleo_reglas(codigo);


--
-- Name: nucleo_casuisticas nucleo_casuisticas_familia_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_casuisticas
    ADD CONSTRAINT nucleo_casuisticas_familia_fkey FOREIGN KEY (familia) REFERENCES saly.nucleo_familias(codigo);


--
-- Name: nucleo_contrato_campos nucleo_contrato_campos_familia_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_contrato_campos
    ADD CONSTRAINT nucleo_contrato_campos_familia_fkey FOREIGN KEY (familia) REFERENCES saly.nucleo_familias(codigo);


--
-- Name: nucleo_decisiones nucleo_decisiones_autoridad_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_decisiones
    ADD CONSTRAINT nucleo_decisiones_autoridad_fkey FOREIGN KEY (autoridad) REFERENCES saly.nucleo_autoridades(codigo);


--
-- Name: nucleo_decisiones nucleo_decisiones_evaluacion_id_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_decisiones
    ADD CONSTRAINT nucleo_decisiones_evaluacion_id_fkey FOREIGN KEY (evaluacion_id) REFERENCES saly.nucleo_evaluaciones(id);


--
-- Name: nucleo_decisiones nucleo_decisiones_regla_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_decisiones
    ADD CONSTRAINT nucleo_decisiones_regla_fkey FOREIGN KEY (regla) REFERENCES saly.nucleo_reglas(codigo) ON DELETE CASCADE;


--
-- Name: nucleo_evaluaciones nucleo_evaluaciones_juicio_id_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_evaluaciones
    ADD CONSTRAINT nucleo_evaluaciones_juicio_id_fkey FOREIGN KEY (juicio_id) REFERENCES saly.nucleo_juicios(id);


--
-- Name: nucleo_evaluaciones nucleo_evaluaciones_regla_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_evaluaciones
    ADD CONSTRAINT nucleo_evaluaciones_regla_fkey FOREIGN KEY (regla) REFERENCES saly.nucleo_reglas(codigo) ON DELETE CASCADE;


--
-- Name: nucleo_familia_vocabulario nucleo_familia_vocabulario_familia_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_familia_vocabulario
    ADD CONSTRAINT nucleo_familia_vocabulario_familia_fkey FOREIGN KEY (familia) REFERENCES saly.nucleo_familias(codigo);


--
-- Name: nucleo_familia_vocabulario nucleo_familia_vocabulario_hecho_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_familia_vocabulario
    ADD CONSTRAINT nucleo_familia_vocabulario_hecho_fkey FOREIGN KEY (hecho) REFERENCES saly.nucleo_hechos(codigo) ON DELETE CASCADE;


--
-- Name: nucleo_hechos nucleo_hechos_campo_id_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_hechos
    ADD CONSTRAINT nucleo_hechos_campo_id_fkey FOREIGN KEY (campo_id) REFERENCES saly.campos(id) ON DELETE CASCADE;


--
-- Name: nucleo_implementaciones nucleo_implementaciones_nodo_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_implementaciones
    ADD CONSTRAINT nucleo_implementaciones_nodo_fkey FOREIGN KEY (nodo) REFERENCES saly.nucleo_nodos(codigo);


--
-- Name: nucleo_implementaciones nucleo_implementaciones_regla_version_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_implementaciones
    ADD CONSTRAINT nucleo_implementaciones_regla_version_fkey FOREIGN KEY (regla, version) REFERENCES saly.nucleo_regla_versiones(regla, version);


--
-- Name: nucleo_juicios nucleo_juicios_regla_version_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_juicios
    ADD CONSTRAINT nucleo_juicios_regla_version_fkey FOREIGN KEY (regla, version) REFERENCES saly.nucleo_regla_versiones(regla, version) ON DELETE CASCADE;


--
-- Name: nucleo_nodos nucleo_nodos_padre_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_nodos
    ADD CONSTRAINT nucleo_nodos_padre_fkey FOREIGN KEY (padre) REFERENCES saly.nucleo_nodos(codigo);




--
-- Name: nucleo_parametros nucleo_parametros_hecho_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_parametros
    ADD CONSTRAINT nucleo_parametros_hecho_fkey FOREIGN KEY (hecho) REFERENCES saly.nucleo_hechos(codigo);


--
-- Name: nucleo_regla_pruebas nucleo_regla_pruebas_regla_version_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_regla_pruebas
    ADD CONSTRAINT nucleo_regla_pruebas_regla_version_fkey FOREIGN KEY (regla, version) REFERENCES saly.nucleo_regla_versiones(regla, version) ON DELETE CASCADE;


--
-- Name: nucleo_regla_versiones nucleo_regla_versiones_regla_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_regla_versiones
    ADD CONSTRAINT nucleo_regla_versiones_regla_fkey FOREIGN KEY (regla) REFERENCES saly.nucleo_reglas(codigo);


--
-- Name: nucleo_reglas nucleo_reglas_familia_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_reglas
    ADD CONSTRAINT nucleo_reglas_familia_fkey FOREIGN KEY (familia) REFERENCES saly.nucleo_familias(codigo);


--
-- Name: nucleo_reglas nucleo_reglas_regla_legacy_id_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_reglas
    ADD CONSTRAINT nucleo_reglas_regla_legacy_id_fkey FOREIGN KEY (regla_legacy_id) REFERENCES saly.reglas(id) ON DELETE SET NULL;


--
-- Name: nucleo_relaciones nucleo_relaciones_destino_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_relaciones
    ADD CONSTRAINT nucleo_relaciones_destino_fkey FOREIGN KEY (destino) REFERENCES saly.nucleo_reglas(codigo);


--
-- Name: nucleo_relaciones nucleo_relaciones_origen_fkey; Type: FK CONSTRAINT; Schema: saly; Owner: postgres
--

ALTER TABLE ONLY saly.nucleo_relaciones
    ADD CONSTRAINT nucleo_relaciones_origen_fkey FOREIGN KEY (origen) REFERENCES saly.nucleo_reglas(codigo);


--
-- Name: nucleo_aplicaciones deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_aplicaciones TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_autoridades deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_autoridades TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_casuisticas deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_casuisticas TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_contrato_campos deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_contrato_campos TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_decisiones deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_decisiones TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_evaluaciones deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_evaluaciones TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_familia_vocabulario deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_familia_vocabulario TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_familias deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_familias TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_hechos deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_hechos TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_implementaciones deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_implementaciones TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_juicios deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_juicios TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_nodos deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_nodos TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_parametros deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_parametros TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_regla_pruebas deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_regla_pruebas TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_regla_versiones deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_regla_versiones TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_reglas deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_reglas TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_relaciones deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_relaciones TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_rubrica deny_direct_client_access; Type: POLICY; Schema: saly; Owner: postgres
--

CREATE POLICY deny_direct_client_access ON saly.nucleo_rubrica TO anon, authenticated USING (false) WITH CHECK (false);


--
-- Name: nucleo_aplicaciones; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_aplicaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_autoridades; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_autoridades ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_casuisticas; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_casuisticas ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_contrato_campos; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_contrato_campos ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_decisiones; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_decisiones ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_evaluaciones; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_evaluaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_familia_vocabulario; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_familia_vocabulario ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_familias; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_familias ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_hechos; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_hechos ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_implementaciones; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_implementaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_juicios; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_juicios ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_nodos; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_nodos ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_parametros; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_parametros ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_regla_pruebas; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_regla_pruebas ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_regla_versiones; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_regla_versiones ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_reglas; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_reglas ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_relaciones; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_relaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: nucleo_rubrica; Type: ROW SECURITY; Schema: saly; Owner: postgres
--

ALTER TABLE saly.nucleo_rubrica ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 2KejlWmsfdO6qwwBjAvRDkKHWmylgIosng3pToUO0EcyA5rDZS93BtUfAewAwDg


-- Datos iniciales de SALY
INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description)
SELECT scope, config_key, config_value, value_type, value_status, description
  FROM (SELECT DISTINCT ON (scope, config_key) * FROM public.lf_global_config
         WHERE scope IN ('NUCLEO','NUCLEO_EVAL') AND valid_from <= now() ORDER BY scope, config_key, valid_from DESC) g
 WHERE NOT (scope = 'NUCLEO' AND config_key IN ('AMBITOS_PANTALLA','AMBITOS_BACKEND'))
   AND NOT (scope = 'NUCLEO_EVAL' AND config_key = 'FAMILIAS_SIEMPRE_MANUAL');
INSERT INTO saly.config_global (scope, config_key, config_value, value_type, value_status, description) VALUES
 ('NUCLEO','AMBITOS_PANTALLA','[]','JSON','REAL','Ámbitos de SALY con reglas de clase PANTALLA (control 19). SALY aún no registra pantallas en el núcleo.'),
 ('NUCLEO','AMBITOS_BACKEND','["ADELANTO"]','JSON','REAL','Ámbitos de SALY donde valen reglas de clase BACKEND, además de la raíz (control 19).'),
 ('NUCLEO_EVAL','FAMILIAS_SIEMPRE_MANUAL','["MOTOR_DISPONIBLE","CALENDARIO","GOBERNANZA"]','JSON','REAL','Familias de SALY que siempre requieren decisión humana para promover. Todas, hasta que el dueño defina cuáles pueden promoverse solas.');

INSERT INTO saly.nucleo_autoridades (codigo, tipo, descripcion)
SELECT 'SALY-DEC-' || d.id, 'DECISION_DUENO', left(d.titulo, 180) || ' (decisión ' || COALESCE(d.codigo, d.id::text) || ' de saly.decisiones)'
  FROM saly.decisiones d WHERE d.estado = 'VALIDADO' AND d.vigente IS TRUE;
INSERT INTO saly.nucleo_autoridades (codigo, tipo, descripcion)
VALUES ('D1','DECISION_DUENO','Núcleo de reglas: un motor con una instancia por producto (LF y SALY)');

INSERT INTO saly.nucleo_familias (codigo, dominio, origen, descripcion, estado, min_pruebas, tipo) VALUES
 ('MOTOR_DISPONIBLE','NEGOCIO','NUEVA','Cálculo del saldo disponible de adelanto: curvas, topes, límites de retiro, bloqueos y excepciones','ACTIVA',2,'NEGOCIO'),
 ('CALENDARIO','NEGOCIO','NUEVA','Ciclos materializados de pago, corte y descuento sobre los que se calcula el disponible','ACTIVA',2,'NEGOCIO'),
 ('GOBERNANZA','BACKEND','NUEVA','Reglas monetarias, trazabilidad del cálculo y autorización de excepciones del motor de SALY','ACTIVA',2,'TECNICA');

INSERT INTO saly.nucleo_nodos (codigo, padre, nivel, nota) VALUES
 ('GLOBAL', NULL, 'GLOBAL', 'Raíz de la instancia SALY: reglas transversales del producto'),
 ('ADELANTO', 'GLOBAL', 'AMBITO', 'Producto de adelanto de sueldo (producto_codigo ADELANTO de saly.reglas)');

INSERT INTO saly.nucleo_contrato_campos (familia, campo) SELECT NULL, campo FROM lf_ops.nucleo_contrato_campos WHERE familia IS NULL;
INSERT INTO saly.nucleo_casuisticas (familia, naturaleza, codigo, descripcion, estado)
  SELECT NULL, naturaleza, codigo, descripcion, estado FROM lf_ops.nucleo_casuisticas WHERE familia IS NULL;
INSERT INTO saly.nucleo_rubrica (codigo, dimension, criterio, estado) SELECT codigo, dimension, criterio, estado FROM lf_ops.nucleo_rubrica;

-- Acceso: igual que LF (sin acceso directo de clientes; funciones para service_role; consultas para solo lectura)
REVOKE ALL ON saly.config_global FROM PUBLIC, anon, authenticated;
ALTER TABLE saly.config_global ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON saly.config_global AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
DO $acc$
DECLARE f record;
BEGIN
  FOR f IN SELECT c.oid::regclass AS r FROM pg_class c WHERE c.relnamespace = 'saly'::regnamespace
            AND (c.relname LIKE 'nucleo%' OR c.relname LIKE 'v_nucleo%') AND c.relkind IN ('r','v') LOOP
    EXECUTE format('REVOKE ALL ON %s FROM PUBLIC, anon, authenticated', f.r);
  END LOOP;
  FOR f IN SELECT p.oid::regprocedure AS p FROM pg_proc p WHERE p.pronamespace = 'saly'::regnamespace
            AND (p.proname LIKE 'nucleo%' OR p.proname LIKE 'fn_nucleo%') LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.p);
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') AND f.p::text NOT LIKE 'saly.fn_nucleo%' THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.p);
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    GRANT EXECUTE ON FUNCTION saly.nucleo_reglas_efectivas_v1(text, timestamptz), saly.nucleo_cola_trabajo_v1(text, timestamptz),
      saly.nucleo_revalidacion_v1() TO supabase_read_only_user;
  END IF;
END $acc$;

-- Prueba conjunta LF + SALY
CREATE OR REPLACE FUNCTION public.lf_nucleo_autotest_conjunto_v1()
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, public AS $autotest$
DECLARE
  v_dif text; v_n_lf integer; v_n_saly integer; mala jsonb; c_lf text; c_saly text; r jsonb;
BEGIN
  -- J1 paridad de código: cada función del núcleo es igual en ambas instancias salvo el nombre del esquema y de la configuración
  SELECT count(*) INTO v_n_lf FROM pg_proc WHERE pronamespace = 'lf_ops'::regnamespace AND (proname LIKE 'nucleo%' OR proname LIKE 'fn_nucleo%');
  SELECT count(*) INTO v_n_saly FROM pg_proc WHERE pronamespace = 'saly'::regnamespace AND (proname LIKE 'nucleo%' OR proname LIKE 'fn_nucleo%');
  SELECT string_agg(COALESCE(l.proname, s.proname), ', ') INTO v_dif
    FROM (SELECT proname, replace(replace(replace(replace(prosrc, 'lf_ops.', 'saly.'), '''lf_ops''', '''saly'''), 'public.lf_global_config', 'saly.config_global'), 'lf_global_config', 'config_global') AS src,
                 replace(array_to_string(proconfig, ','), 'lf_ops', 'saly') AS cfg
            FROM pg_proc WHERE pronamespace = 'lf_ops'::regnamespace AND (proname LIKE 'nucleo%' OR proname LIKE 'fn_nucleo%')) l
    FULL JOIN (SELECT proname, prosrc AS src, array_to_string(proconfig, ',') AS cfg
            FROM pg_proc WHERE pronamespace = 'saly'::regnamespace AND (proname LIKE 'nucleo%' OR proname LIKE 'fn_nucleo%')) s
      ON s.proname = l.proname
   WHERE l.src IS DISTINCT FROM s.src OR l.cfg IS DISTINCT FROM s.cfg;
  IF v_dif IS NOT NULL OR v_n_lf <> v_n_saly THEN
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J1 código distinto entre instancias (% / % funciones): %', v_n_lf, v_n_saly, v_dif;
  END IF;
  -- J2 paridad de tablas: mismas columnas y tipos (LF conserva además su clasificación de reglas legadas)
  SELECT string_agg(COALESCE(l.t, s.t) || '.' || COALESCE(l.c, s.c), ', ') INTO v_dif
    FROM (SELECT table_name t, column_name c, data_type d, is_nullable n FROM information_schema.columns
           WHERE table_schema = 'lf_ops' AND table_name LIKE 'nucleo%' AND table_name <> 'nucleo_regla_familia') l
    FULL JOIN (SELECT table_name t, column_name c, data_type d, is_nullable n FROM information_schema.columns
           WHERE table_schema = 'saly' AND table_name LIKE 'nucleo%') s ON s.t = l.t AND s.c = l.c
   WHERE l.d IS DISTINCT FROM s.d OR l.n IS DISTINCT FROM s.n;
  IF v_dif IS NOT NULL THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J2 tablas distintas entre instancias: %', v_dif; END IF;

  BEGIN
    PERFORM lf_ops.nucleo_autotest_datos_v1();
    PERFORM saly.nucleo_autotest_datos_v1();
    -- J3 una misma regla mala (valor fijo) se rechaza igual en ambas instancias
    mala := jsonb_build_object('codigo','ZZT-J-1','clave','zzt_j_uno','titulo','Regla conjunta con valor fijo',
      'descripcion','Bloquea al superar un número fijo de intentos escrito en la condición',
      'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-AMB','modo','HEREDA',
      'clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-conjunto','solicitante','autotest'),
      'condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('lit',3)),
      'pruebas', jsonb_build_array(jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',3),'esperado',true)));
    SELECT string_agg(x->>'control', ', ' ORDER BY x->>'control') INTO c_lf
      FROM jsonb_array_elements(lf_ops.nucleo_regla_proponer_v1(mala, false)->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
    SELECT string_agg(x->>'control', ', ' ORDER BY x->>'control') INTO c_saly
      FROM jsonb_array_elements(saly.nucleo_regla_proponer_v1(mala, false)->'controles') x WHERE (x->>'ok')::boolean IS NOT TRUE AND (x->>'bloqueante')::boolean;
    IF c_lf IS DISTINCT FROM c_saly OR position('Sin datos fijos' IN COALESCE(c_lf,'')) = 0 THEN
      RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J3 rechazo distinto (LF: % / SALY: %)', c_lf, c_saly;
    END IF;
    -- J4 aislamiento: una regla creada en SALY no existe ni rige en LF, y al revés
    mala := mala || jsonb_build_object('condicion', jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
      'pruebas', jsonb_build_array(
        jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
        jsonb_build_object('entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false)));
    r := saly.nucleo_regla_proponer_v1(mala || '{"codigo":"ZZT-J-SALY"}');
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J4 alta en SALY (%)', r; END IF;
    r := lf_ops.nucleo_regla_proponer_v1(mala || '{"codigo":"ZZT-J-LF"}');
    IF r->>'resultado' <> 'CANDIDATA' THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J4 alta en LF (%)', r; END IF;
    IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo = 'ZZT-J-SALY') OR EXISTS (SELECT 1 FROM saly.nucleo_reglas WHERE codigo = 'ZZT-J-LF')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J4 una regla cruzó de instancia'; END IF;
    PERFORM set_config('lf.nucleo_publicando', 'ZZT-J-SALY:1', true);
    UPDATE saly.nucleo_reglas SET estado = 'VIGENTE' WHERE codigo = 'ZZT-J-SALY';
    UPDATE saly.nucleo_regla_versiones SET estado = 'PUBLICADA', publicada_desde = now(), exigible_desde = now() WHERE regla = 'ZZT-J-SALY';
    PERFORM set_config('lf.nucleo_publicando', '', true);
    IF EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas_efectivas_v1('ZZT-MOD-1') WHERE regla = 'ZZT-J-SALY')
       OR NOT EXISTS (SELECT 1 FROM saly.nucleo_reglas_efectivas_v1('ZZT-MOD-1') WHERE regla = 'ZZT-J-SALY')
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J4 la regla de SALY rige en LF o no rige en SALY'; END IF;
    -- J5 un parámetro de una instancia no cambia la otra
    UPDATE saly.config_global SET config_value = '7' WHERE scope = 'ZZT' AND config_key = 'MAX_INTENTOS';
    IF lf_ops.nucleo_param_valor_v1('ZZT.MAX_INTENTOS') IS DISTINCT FROM '3' OR saly.nucleo_param_valor_v1('ZZT.MAX_INTENTOS') IS DISTINCT FROM '7'
      THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_FALLA: J5 parámetro compartido entre instancias'; END IF;
    RAISE EXCEPTION 'NUCLEO_AUTOTEST_OK';
  EXCEPTION WHEN others THEN
    IF SQLERRM <> 'NUCLEO_AUTOTEST_OK' THEN RAISE; END IF;
  END;
  RETURN 'CONJUNTO 5/5';
END $autotest$;
REVOKE ALL ON FUNCTION public.lf_nucleo_autotest_conjunto_v1() FROM PUBLIC, anon, authenticated;
DO $g$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.lf_nucleo_autotest_conjunto_v1() TO service_role;
  END IF;
END $g$;

DO $run$ BEGIN
  RAISE NOTICE 'NUCLEO_AUTOTEST SALY: % · % · %', saly.nucleo_autotest_puerta_v1(), saly.nucleo_autotest_evaluacion_v1(), saly.nucleo_autotest_cambio_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST LF: % · % · %', lf_ops.nucleo_autotest_puerta_v1(), lf_ops.nucleo_autotest_evaluacion_v1(), lf_ops.nucleo_autotest_cambio_v1();
  RAISE NOTICE 'NUCLEO_AUTOTEST %', public.lf_nucleo_autotest_conjunto_v1();
  IF EXISTS (SELECT 1 FROM saly.nucleo_reglas) OR EXISTS (SELECT 1 FROM saly.nucleo_nodos WHERE codigo LIKE 'ZZT%')
     OR EXISTS (SELECT 1 FROM saly.config_global WHERE scope = 'ZZT' OR config_value LIKE '%ZZT%')
     OR EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo LIKE 'ZZT%')
     OR EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope = 'ZZT' OR config_value LIKE '%ZZT%')
    THEN RAISE EXCEPTION 'NUCLEO_AUTOTEST_DEJO_DATOS'; END IF;
END $run$;
COMMIT;

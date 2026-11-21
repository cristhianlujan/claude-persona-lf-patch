-- PG17 isolated dependency fixture, not a production dump.
-- Core legacy table columns/types/defaults checked against information_schema 2026-11-21.
-- Business tables are column projections from the 41 COL-* references in lf_nucleo_bloque_a_taxonomia_vocabulario_v1.
-- Synthetic rows only; screen identity seed comes from lf_nucleo_nodos_v1. No customer data.
CREATE SCHEMA lf_ops;
CREATE SCHEMA saly;
CREATE SCHEMA lf_proto;
CREATE SCHEMA lf_client;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE supabase_read_only_user NOLOGIN;
CREATE TABLE public.lf_decisiones_gov (decision_number bigint PRIMARY KEY);
CREATE TABLE lf_ops.modulos (module_id bigint PRIMARY KEY);
CREATE TABLE lf_ops.pantallas (
 id serial PRIMARY KEY,codigo text NOT NULL UNIQUE,nombre text NOT NULL,descripcion text,flujo text,paso text,
 estado text NOT NULL DEFAULT 'CANDIDATO',activa boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now(),
 drive_file_id text,drive_url text,drive_filename text,drive_updated_at timestamptz,module_code text,version text NOT NULL DEFAULT 'v0.1',
 owner_name text,objective text,allowed_profiles jsonb NOT NULL DEFAULT '[]',dependencies jsonb NOT NULL DEFAULT '[]',
 source_decision_id text,updated_at timestamptz NOT NULL DEFAULT now(),module_id bigint REFERENCES lf_ops.modulos(module_id),
 source_decision_number bigint REFERENCES public.lf_decisiones_gov(decision_number)
);
CREATE TABLE lf_ops.reglas (
 id serial PRIMARY KEY,codigo text NOT NULL UNIQUE,categoria text NOT NULL,titulo text NOT NULL,descripcion text NOT NULL,
 razon text,valor_config jsonb,es_transversal boolean NOT NULL DEFAULT false,estado text NOT NULL DEFAULT 'CANDIDATO',origen text,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),pendiente_decision boolean NOT NULL DEFAULT false,
 pendiente_detalle text,created_by text
);
CREATE TABLE lf_ops.reglas_pantallas (
 id serial PRIMARY KEY,regla_id integer NOT NULL REFERENCES lf_ops.reglas(id),pantalla_id integer NOT NULL REFERENCES lf_ops.pantallas(id),
 nota text,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(regla_id,pantalla_id)
);
CREATE TABLE lf_ops.campos (
 id serial PRIMARY KEY,codigo text NOT NULL UNIQUE,nombre text NOT NULL,tipo_dato text NOT NULL,descripcion text,
 es_requerido boolean NOT NULL DEFAULT true,es_sensible boolean NOT NULL DEFAULT false,estado text NOT NULL DEFAULT 'ACTIVO',
 created_at timestamptz NOT NULL DEFAULT now(),entity_code text,source_type text NOT NULL DEFAULT 'SYSTEM',
 pii_classification text NOT NULL DEFAULT 'NONE',masking_rule text,retention_class text NOT NULL DEFAULT 'OPERATIONAL',
 analytics_allowed boolean NOT NULL DEFAULT false,logs_allowed boolean NOT NULL DEFAULT false,source_decision_id text,
 updated_at timestamptz NOT NULL DEFAULT now(),source_decision_number bigint REFERENCES public.lf_decisiones_gov(decision_number),
 CHECK(pii_classification IN ('NONE','INTERNAL','PERSONAL','SENSITIVE','FINANCIAL')),
 CHECK(retention_class IN ('TRANSIENT','OPERATIONAL','AUDIT','LEGAL','CONFIGURATION')),
 CHECK(source_type IN ('USER','SESSION','SYSTEM','FILE','POLICY','INTEGRATION','CALCULATED'))
);
CREATE TABLE public.lf_global_config (
 scope text NOT NULL CHECK(btrim(scope)<>''),config_key text NOT NULL CHECK(btrim(config_key)<>''),
 config_value text NOT NULL CHECK(btrim(config_value)<>''),value_type text NOT NULL CHECK(value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
 value_status text NOT NULL CHECK(value_status IN ('FICTICIO','REAL')),description text,valid_from timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(scope,config_key,valid_from)
);
CREATE TABLE saly.decisiones (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text NOT NULL UNIQUE,categoria text NOT NULL,titulo text NOT NULL,
 decision text NOT NULL,estado text NOT NULL CHECK(estado IN ('VALIDADO','PROPUESTA','DESCARTADO','SUPERADO')),
 evidencia_nivel text NOT NULL DEFAULT 'CHAT' CHECK(evidencia_nivel IN ('CHAT','HISTORICO','DOCUMENTAL','CALCULADO')),
 vigente boolean NOT NULL DEFAULT true,notas text,metadata jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE saly.campos (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text NOT NULL UNIQUE,entidad_tipo text NOT NULL,nombre text NOT NULL,
 tipo_dato text NOT NULL,descripcion text,fuente_tipo text NOT NULL DEFAULT 'SYSTEM',es_sensible boolean NOT NULL DEFAULT false,
 clasificacion_pii text NOT NULL DEFAULT 'NONE' CHECK(clasificacion_pii IN ('NONE','LOW','MEDIUM','HIGH','SENSITIVE')),
 regla_enmascarado text,clase_retencion text NOT NULL DEFAULT 'OPERATIONAL',analytics_permitido boolean NOT NULL DEFAULT false,
 logs_permitidos boolean NOT NULL DEFAULT false,estado text NOT NULL DEFAULT 'BORRADOR',vigente boolean NOT NULL DEFAULT true,
 decision_id bigint REFERENCES saly.decisiones(id),metadata jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE saly.reglas (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,codigo text NOT NULL UNIQUE,categoria text NOT NULL,titulo text NOT NULL,regla text NOT NULL,
 razon text,alcance text NOT NULL DEFAULT 'PRODUCTO',producto_codigo text,valor_config jsonb NOT NULL DEFAULT '{}',
 parametrizable boolean NOT NULL DEFAULT true,es_transversal boolean NOT NULL DEFAULT false,estado text NOT NULL DEFAULT 'BORRADOR',
 vigente boolean NOT NULL DEFAULT true,decision_id bigint REFERENCES saly.decisiones(id) ON DELETE RESTRICT,fuente text,metadata jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
-- Domain column projections: no legacy domain logic is emulated here.
CREATE TABLE lf_client.client_accounts(document_type text,activated_at timestamptz,disabled_at timestamptz);
CREATE TABLE lf_client.client_auth_sessions(last_seen_at timestamptz,revoked_at timestamptz,revocation_reason text);
CREATE TABLE lf_client.client_phone_bindings(verified_at timestamptz,valid_to timestamptz);
CREATE TABLE lf_ops.empresas(authorization_status text,operational_status text,enabled_product_codes jsonb,payment_method_codes jsonb,trusted_device_duration_days integer);
CREATE TABLE lf_proto.checkout_pricing_quotes(offers_subtotal_today numeric,management_fee_customer numeric,niubiz_fee_customer numeric,final_customer_price numeric,total_savings numeric,savings_verified boolean,quote_status text,expires_at timestamptz);
CREATE TABLE lf_proto.proto_offers(ally_status text,estado text,creditor_current text,modalidades_count integer,tiene_cuotas boolean,tiene_pago_unico boolean,expires_at timestamptz,carta_no_adeudo boolean,variante_paso3 text);
CREATE TABLE public.lf_b2b_pricing_config(valid_to timestamptz,management_fee_value numeric,igv_rate numeric,niubiz_fee_value numeric,show_final_price boolean,collection_channel text,campaign_override_allowed boolean);
CREATE TABLE public.lf_user_offer_access(revoked_at timestamptz);
CREATE TABLE public.lf_user_offer_selections(offer_version text,modality text,plan_id text);
INSERT INTO lf_ops.pantallas(id,codigo,nombre) VALUES
(1,'ONB_001','Fixture'),(2,'ONB_002','Fixture'),(3,'ONB_003','Fixture'),(4,'HOME_001','Fixture'),(5,'HOME_002','Fixture'),(6,'HOME_003','Fixture'),
(7,'PASO3_SIN_OFERTA','Fixture'),(10,'PASO3_OFERTA_UNICA_AMBAS','Fixture'),(11,'PASO3_MULTI_OFERTA','Fixture'),(13,'PASO3_MODAL_CUOTAS','Fixture'),
(15,'PASO3_OFERTA_UNICA_PAGO_UNICO_V2','Fixture'),(16,'PASO3_MODAL_DETALLE_PRECIO','Fixture'),(17,'PASO3_CUOTAS_SELECCION','Fixture'),
(18,'PASO3_CUOTAS_DESGLOSE_V2','Fixture'),(19,'PASO3_OFERTA_UNICA_CUOTAS_V2','Fixture'),(21,'CHECKOUT_CUOTAS_MEDIO_PAGO','Fixture'),
(24,'CHECKOUT_MODAL_CRONOGRAMA','Fixture'),(25,'CHECKOUT_ESTADO_ABRIENDO','Fixture'),(27,'CHECKOUT_ESTADO_CONFIRMANDO','Fixture'),
(28,'CHECKOUT_ESTADO_YAPE_QR','Fixture'),(30,'CHECKOUT_ESTADO_TARJETA','Fixture'),(33,'CHECKOUT_PAGO_EXITOSO','Fixture'),(34,'CHECKOUT_ERROR_PAGO','Fixture'),
(36,'PANT_LIBRO_RECLAMACIONES','Fixture'),(37,'PANT_RESPALDO_CONFIANZA','Fixture'),(38,'HOME_S9_FOOTER','Fixture'),
(39,'HOME_APRENDA_ANTES_DECIDIR','Fixture'),(41,'HOME_RUTA_CLARIDAD','Fixture'),(42,'HOME_FAQ','Fixture'),
(43,'B2B-CARGA-001','Fixture'),(44,'B2B-CARGA-002','Fixture'),(45,'B2B-CARGA-003','Fixture'),(46,'B2B-CARGA-004','Fixture'),(47,'B2B-CARGA-005','Fixture'),
(48,'B2B-ADMIN-001','Fixture'),(49,'B2B-ADMIN-002','Fixture'),(50,'B2B-ADMIN-003','Fixture'),(51,'B2B-AUTH-001','Fixture'),
(52,'B2B-AUTH-002','Fixture'),(53,'B2B-AUTH-003','Fixture'),(54,'B2B-AUTH-004','Fixture'),(56,'B2B-AUTH-006','Fixture'),
(57,'ONB_004','Fixture'),(58,'REC_001','Fixture'),(59,'CHECKOUT_PAGO_UNICO_MEDIO_PAGO','Fixture'),(60,'B2B-DASH-001','Fixture'),
(61,'B2B-SIMULA-001','Fixture'),(62,'B2B-SIMULA-002','Fixture'),(63,'B2B-SIMULA-003','Fixture'),(64,'B2B-OFERTA-001','Fixture'),
(65,'B2B-SIMULA-004','Fixture'),(66,'B2B-CARGA-006','Fixture'),(67,'B2B-CARGA-007','Fixture'),
(99999,'FIXTURE_FUERA_ARBOL','Synthetic outside-tree screen');
INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion) VALUES
(1,'FIXTURE-LEGACY-1','checkout','Regla previa de prueba','Regla previa sintética para comparar la vista y las relaciones');
INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id) VALUES(1,59);
INSERT INTO lf_ops.campos(codigo,nombre,tipo_dato,entity_code) VALUES('FIXTURE_FIELD','Campo ficticio','text','COMPANY');
-- Two AUTH values used by the historical embedded tests, observed in LF config on 2026-11-21.
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description,valid_from) VALUES
('AUTH','OTP_MAX_RESENDS','3','INTEGER','REAL','Historical fixture value','2020-01-01'),
('AUTH','SESSION_IDLE_TIMEOUT_SECONDS','86400','INTEGER','REAL','Historical fixture value','2020-01-01');

-- EKB dependency for migrations of CI findings. Column names/types read
-- from information_schema in LF on 2026-11-21. Empty local fixture, no live data.
CREATE TABLE public.lf_error_knowledge (
 id uuid, codigo text, categoria text, titulo text, descripcion text,
 causa_raiz text, patron text, prevencion text, validacion text, severidad text,
 frecuencia integer, primera_vez timestamptz, ultima_vez timestamptz,
 lote_origen text, pr text, estado text, evidencia text, created_at timestamptz,
 updated_at timestamptz, lifecycle_phase text, consumer_role text[],
 root_cause_family text, detectability text, source_context text, source_ref text
);

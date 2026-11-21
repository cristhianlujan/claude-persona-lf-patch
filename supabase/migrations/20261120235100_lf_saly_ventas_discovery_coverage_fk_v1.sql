-- SALY Ventas L28. Applies AFTER 20261120235000_lf_saly_ventas_discovery_staging_v1.sql.
-- DO NOT apply old L19/L20 CREATE TABLE ventas_hallazgos. No seeds/grants/writer.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'SALY_PROJECT_INVALID'; END IF;
 IF to_regclass('saly.ventas_discovery_ingestas') IS NULL
 OR to_regclass('saly.ventas_hallazgos') IS NULL
 OR to_regclass('saly.ventas_unidades_operativas') IS NULL
 THEN RAISE EXCEPTION 'L27_MISSING'; END IF;
 IF EXISTS (SELECT 1 FROM unnest(ARRAY[
 'ventas_discovery_catalogo','ventas_discovery_runs',
 'ventas_discovery_plan_fuentes','ventas_discovery_plan_batches',
 'ventas_discovery_ejecuciones','ventas_discovery_consultas']) AS obj(tabla)
 WHERE to_regclass(format('saly.%I',obj.tabla)) IS NOT NULL)
 THEN RAISE EXCEPTION 'L28_ALREADY_EXISTS'; END IF;
END $pre$;
CREATE TABLE saly.ventas_discovery_catalogo (
 catalog_version text NOT NULL CHECK(length(btrim(catalog_version))>0),
 source_id text NOT NULL CHECK(length(btrim(source_id))>0),
 connector_id text NOT NULL CHECK(length(btrim(connector_id))>0),
 substep_code text NOT NULL CHECK(substep_code ~ '^1[2-7]\.[0-9]{2}$'),
 step smallint NOT NULL CHECK(step BETWEEN 12 AND 17),
 familia text NOT NULL,
 nombre text NOT NULL,
 landing_page text,
 rights_status text NOT NULL DEFAULT 'PENDIENTE_VERIFICAR',
 rights_evidence_ref text,
 rights_checked_at timestamptz,
 persist_business_data boolean NOT NULL DEFAULT false,
 habilitada boolean NOT NULL DEFAULT false,
 runtime_status text NOT NULL DEFAULT 'SPEC_ONLY_NOT_CONNECTED',
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(catalog_version,source_id),
 UNIQUE(catalog_version,source_id,connector_id,substep_code),
 UNIQUE(catalog_version,source_id,connector_id,substep_code,persist_business_data,habilitada),
 UNIQUE(catalog_version,substep_code),
 UNIQUE(catalog_version,connector_id),
 CHECK (split_part(substep_code,'.',1)=step::text),
 CHECK (NOT (persist_business_data OR habilitada) OR
        rights_status IN ('LECTURA_AUTORIZADA','LECTURA_LIMITADA','PERSISTENCIA_PERMITIDA')),
 CHECK (NOT persist_business_data OR rights_status='PERSISTENCIA_PERMITIDA'),
 CONSTRAINT saly_l28_rights_evidence_required CHECK(
  NOT (persist_business_data OR habilitada) OR
  (length(btrim(coalesce(rights_evidence_ref,'')))>0 AND rights_checked_at IS NOT NULL))
);
CREATE TABLE saly.ventas_discovery_runs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 run_ref text NOT NULL UNIQUE CHECK(length(btrim(run_ref))>0),
 catalog_version text NOT NULL CHECK(length(btrim(catalog_version))>0),
 scope jsonb NOT NULL,
 plan_hash text NOT NULL CHECK(plan_hash ~ '^[0-9a-f]{64}$'),
 estado text NOT NULL DEFAULT 'PREPARADO'
 CHECK(estado IN ('PREPARADO','EN_EJECUCION','PARTIAL','HOLD','CERRADO')),
 -- Before finalizing RUNs, deploy a verified frozen-source coverage gate.
 CONSTRAINT saly_l28_run_close_disabled CHECK(estado <> 'CERRADO'),
 created_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 UNIQUE(id,catalog_version),
 UNIQUE(id,run_ref,catalog_version)
);
CREATE TABLE saly.ventas_discovery_plan_fuentes (
 run_id uuid NOT NULL,
 catalog_version text NOT NULL,
 source_id text NOT NULL,
 connector_id text NOT NULL,
 substep_code text NOT NULL,
 scope_key text NOT NULL CHECK(length(btrim(scope_key))>0),
 seleccion text NOT NULL CHECK(seleccion IN ('UNASSESSED','REQUIRED','IN_SCOPE','EXCLUDED','NOT_APPLICABLE')),
 motivo text,
 estado text NOT NULL DEFAULT 'PLANIFICADO'
 CHECK(estado IN ('PLANIFICADO','EN_EJECUCION','HOLD','PARCIAL','VERIFICADO','NO_APLICA')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(run_id,source_id,scope_key),
 FOREIGN KEY(run_id,catalog_version)
  REFERENCES saly.ventas_discovery_runs(id,catalog_version) ON DELETE RESTRICT,
 FOREIGN KEY(catalog_version,source_id,connector_id,substep_code)
  REFERENCES saly.ventas_discovery_catalogo(catalog_version,source_id,connector_id,substep_code) ON DELETE RESTRICT,
 UNIQUE(run_id,source_id,scope_key,catalog_version,connector_id,substep_code),
 CHECK (seleccion NOT IN ('EXCLUDED','NOT_APPLICABLE') OR
        (length(btrim(coalesce(motivo,'')))>0 AND estado='NO_APLICA')),
 CHECK (seleccion IN ('EXCLUDED','NOT_APPLICABLE') OR estado!='NO_APLICA')
);
CREATE TABLE saly.ventas_discovery_plan_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 run_id uuid NOT NULL,
 source_id text NOT NULL,
 scope_key text NOT NULL,
 batch_key text NOT NULL CHECK(length(btrim(batch_key))>0),
 query_hash text NOT NULL CHECK(query_hash ~ '^[0-9a-f]{64}$'),
 filtros jsonb NOT NULL DEFAULT '{}'::jsonb,
 estado text NOT NULL DEFAULT 'NOT_RUN'
 CHECK(estado IN ('NOT_RUN','FOUND','EMPTY','BLOCKED','ERROR','SKIPPED_POLICY')),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(run_id,source_id,scope_key)
  REFERENCES saly.ventas_discovery_plan_fuentes(run_id,source_id,scope_key) ON DELETE RESTRICT,
 UNIQUE(run_id,source_id,scope_key,batch_key),
 UNIQUE(run_id,source_id,scope_key,batch_key,query_hash)
);
CREATE TABLE saly.ventas_discovery_ejecuciones (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 run_id uuid NOT NULL,
 catalog_version text NOT NULL,
 source_id text NOT NULL,
 connector_id text NOT NULL,
 substep_code text NOT NULL,
 scope_key text NOT NULL,
 estado text NOT NULL DEFAULT 'NOT_RUN'
 CHECK(estado IN ('NOT_RUN','FOUND','EMPTY','BLOCKED','ERROR','SKIPPED_POLICY','NOT_APPLICABLE')),
 evidencia_ref text,
 ultima_consulta_en timestamptz,
 total_encontrados integer CHECK(total_encontrados>=0),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(run_id,source_id,scope_key,catalog_version,connector_id,substep_code)
  REFERENCES saly.ventas_discovery_plan_fuentes(run_id,source_id,scope_key,catalog_version,connector_id,substep_code) ON DELETE RESTRICT,
 UNIQUE(run_id,source_id,scope_key),
 UNIQUE(id,run_id,source_id,scope_key,catalog_version,connector_id,substep_code),
 CHECK(estado NOT IN ('FOUND','EMPTY') OR
       (length(btrim(coalesce(evidencia_ref,'')))>0 AND ultima_consulta_en IS NOT NULL))
);
CREATE TABLE saly.ventas_discovery_consultas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ejecucion_id uuid NOT NULL,
 run_id uuid NOT NULL,
 run_ref text NOT NULL,
 catalog_version text NOT NULL,
 source_id text NOT NULL,
 connector_id text NOT NULL,
 substep_code text NOT NULL,
 scope_key text NOT NULL,
 batch_key text NOT NULL,
 query_hash text NOT NULL CHECK(query_hash ~ '^[0-9a-f]{64}$'),
 herramienta text NOT NULL CHECK(length(btrim(herramienta))>0),
 inicio timestamptz NOT NULL,
 fin timestamptz,
 estado text NOT NULL CHECK(estado IN ('FOUND','EMPTY','BLOCKED','ERROR','SKIPPED_POLICY')),
 cantidad_hallazgos integer CHECK(cantidad_hallazgos>=0),
 evidencia_ref text NOT NULL CHECK(length(btrim(evidencia_ref))>0),
 error_codigo text,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(run_id,run_ref,catalog_version)
  REFERENCES saly.ventas_discovery_runs(id,run_ref,catalog_version) ON DELETE RESTRICT,
 FOREIGN KEY(ejecucion_id,run_id,source_id,scope_key,catalog_version,connector_id,substep_code)
  REFERENCES saly.ventas_discovery_ejecuciones(id,run_id,source_id,scope_key,catalog_version,connector_id,substep_code) ON DELETE RESTRICT,
 FOREIGN KEY(run_id,source_id,scope_key,batch_key,query_hash)
  REFERENCES saly.ventas_discovery_plan_batches(run_id,source_id,scope_key,batch_key,query_hash) ON DELETE RESTRICT,
 UNIQUE(ejecucion_id,batch_key,query_hash),
 UNIQUE(id,run_ref,catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,query_hash,evidencia_ref),
 CHECK(fin IS NULL OR fin>=inicio)
);
-- L27 has no authorised writer. A nonempty L27 ledger blocks this migration.
ALTER TABLE saly.ventas_discovery_ingestas
 ADD COLUMN consulta_id uuid NOT NULL,
 ADD COLUMN fuente_habilitada boolean NOT NULL DEFAULT true CHECK(fuente_habilitada);
ALTER TABLE saly.ventas_discovery_ingestas
 ADD CONSTRAINT saly_l28_ingesta_catalog_rights_fk
 FOREIGN KEY(catalog_version,source_id,connector_id,substep_code,derechos_verificados,fuente_habilitada)
 REFERENCES saly.ventas_discovery_catalogo(catalog_version,source_id,connector_id,substep_code,persist_business_data,habilitada) ON DELETE RESTRICT,
 ADD CONSTRAINT saly_l28_ingesta_query_lineage_fk
 FOREIGN KEY(consulta_id,run_ref,catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,query_hash,consulta_evidencia_ref)
 REFERENCES saly.ventas_discovery_consultas(id,run_ref,catalog_version,source_id,connector_id,substep_code,scope_key,batch_key,query_hash,evidencia_ref) ON DELETE RESTRICT;
CREATE INDEX saly_l28_coverage_run_idx ON saly.ventas_discovery_plan_fuentes(run_id,seleccion);
CREATE INDEX saly_l28_batch_run_idx ON saly.ventas_discovery_plan_batches(run_id,estado);
CREATE INDEX saly_l28_ejec_run_idx ON saly.ventas_discovery_ejecuciones(run_id,estado);
CREATE INDEX saly_l28_ingesta_consulta_idx ON saly.ventas_discovery_ingestas(consulta_id);
ALTER TABLE saly.ventas_discovery_catalogo ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_discovery_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_discovery_plan_fuentes ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_discovery_plan_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_discovery_ejecuciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_discovery_consultas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON saly.ventas_discovery_catalogo,saly.ventas_discovery_runs,
 saly.ventas_discovery_plan_fuentes,saly.ventas_discovery_plan_batches,
 saly.ventas_discovery_ejecuciones,saly.ventas_discovery_consultas
 FROM PUBLIC,anon,authenticated;
-- No seed, grants, outreach, or direct CRM writer. Only a governed RUN may persist.
COMMIT;

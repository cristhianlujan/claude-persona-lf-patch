-- SALY ventas | vínculos empresariales v1 | SOLO ESTRUCTURA VACIA.
-- DRAFT: sin importación OECE, sin habilitar escritores ni prospección.
BEGIN;
DO $pre$
BEGIN
 IF to_regclass('saly.ventas_hallazgos') IS NULL THEN
   RAISE EXCEPTION 'SALY_DISCOVERY_BASE_MISSING'; END IF;
 IF to_regclass('saly.ventas_vinculos_empresariales_v1') IS NOT NULL
 OR to_regclass('saly.ventas_vinculos_evidencias_v1') IS NOT NULL THEN
   RAISE EXCEPTION 'SALY_VINCULOS_ALREADY_EXIST'; END IF;
END $pre$;
CREATE TABLE saly.ventas_vinculos_empresariales_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 empresa_ruc text NOT NULL CHECK (empresa_ruc ~ '^20[0-9]{9}$'),
 vinculada_ruc text NOT NULL CHECK (vinculada_ruc ~ '^20[0-9]{9}$'),
 tipo_relacion text NOT NULL CHECK (tipo_relacion IN
  ('SOCIO_DECLARADO','CONTROL_ACCIONARIO','PERTENENCIA_CORPORATIVA')),
 estado text NOT NULL DEFAULT 'CANDIDATO' CHECK (estado IN
  ('CANDIDATO','CORROBORADO','CONTROL_VERIFICADO','DESCARTADO')),
 fuente_id text NOT NULL CHECK (btrim(fuente_id) <> ''),
 fuente_version text NOT NULL CHECK (btrim(fuente_version) <> ''),
 fuente_corte date NOT NULL,
 fuente_sha256 text CHECK (fuente_sha256 IS NULL OR fuente_sha256 ~ '^[a-f0-9]{64}$'),
 participacion_pct numeric(7,4) CHECK (participacion_pct BETWEEN 0 AND 100),
 verificado_por text,
 verificado_en timestamptz,
 evidencia_control_ref text,
 creada_en timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT ventas_vinculos_no_autorelacion CHECK (empresa_ruc <> vinculada_ruc),
 CONSTRAINT ventas_vinculos_control_gate CHECK (
   estado NOT IN ('CORROBORADO','CONTROL_VERIFICADO') OR
   ((estado='CORROBORADO' OR tipo_relacion='CONTROL_ACCIONARIO')
    AND nullif(btrim(coalesce(verificado_por,'')),'') IS NOT NULL
    AND verificado_en IS NOT NULL
    AND nullif(btrim(coalesce(evidencia_control_ref,'')),'') IS NOT NULL)
 ),
 UNIQUE(empresa_ruc,vinculada_ruc,tipo_relacion,fuente_id,fuente_version,fuente_corte)
);
COMMENT ON TABLE saly.ventas_vinculos_empresariales_v1 IS
 'Aristas societarias, no grupos economicos. Socio compartido no demuestra control.';
CREATE INDEX ventas_vinculos_empresa_ruc_v1_idx
 ON saly.ventas_vinculos_empresariales_v1(empresa_ruc,estado);
CREATE INDEX ventas_vinculos_vinculada_ruc_v1_idx
 ON saly.ventas_vinculos_empresariales_v1(vinculada_ruc,estado);
CREATE TABLE saly.ventas_vinculos_evidencias_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vinculo_id uuid NOT NULL REFERENCES saly.ventas_vinculos_empresariales_v1(id)
   ON DELETE RESTRICT,
 evidencia_ref text NOT NULL CHECK (btrim(evidencia_ref) <> ''),
 url_fuente text NOT NULL CHECK (url_fuente ~ '^https://'),
 soporte_sha256 text CHECK (soporte_sha256 IS NULL OR soporte_sha256 ~ '^[a-f0-9]{64}$'),
 fila_fuente integer CHECK (fila_fuente IS NULL OR fila_fuente > 0),
 clase_evidencia text NOT NULL CHECK (clase_evidencia IN
  ('DECLARACION_RNP','REPORTE_SOCIEDAD','REGISTRO_SOCIAL','INFORME_CORPORATIVO')),
 derechos_estado text NOT NULL CHECK (derechos_estado IN
  ('NO_DETERMINADOS','AUTORIZADOS','RESTRINGIDOS')),
 observacion text,
 capturado_en timestamptz NOT NULL DEFAULT now(),
 UNIQUE(vinculo_id,evidencia_ref)
);
COMMENT ON TABLE saly.ventas_vinculos_evidencias_v1 IS
 'Soportes y derechos; no autoriza reutilizacion comercial ni contacto.';
ALTER TABLE saly.ventas_vinculos_empresariales_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_vinculos_empresariales_v1 FORCE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_vinculos_evidencias_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_vinculos_evidencias_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE saly.ventas_vinculos_empresariales_v1,
 saly.ventas_vinculos_evidencias_v1 FROM PUBLIC, anon, authenticated, service_role;
DO $verify$
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='saly' AND c.relname IN
   ('ventas_vinculos_empresariales_v1','ventas_vinculos_evidencias_v1')
  AND c.relrowsecurity AND c.relforcerowsecurity) <> 2
 THEN RAISE EXCEPTION 'SALY_VINCULOS_RLS_MISSING'; END IF;
 IF has_table_privilege('anon','saly.ventas_vinculos_empresariales_v1','SELECT')
 OR has_table_privilege('authenticated','saly.ventas_vinculos_empresariales_v1','INSERT')
 OR has_table_privilege('service_role','saly.ventas_vinculos_evidencias_v1','SELECT')
 THEN RAISE EXCEPTION 'SALY_VINCULOS_UNEXPECTED_GRANT'; END IF;
END $verify$;
COMMIT;

-- Núcleo de reglas, fase F0: vocabulario por familia (instancia LF), primera parte.
-- nucleo_hechos = datos que una regla puede usar en su condición. Si el dato es un campo del
-- diccionario (lf_ops.campos) se referencia por id y su tipo/descripción se leen de ahí (no se copian).
-- Los hechos calculados (p. ej. intentos, inactividad) llevan su propio tipo y unidad.
-- nucleo_familia_vocabulario = qué hechos puede usar cada familia.
-- Esta parte carga los 201 campos del diccionario, enlazados a su familia por la entidad a la que pertenecen.
BEGIN;
CREATE TABLE lf_ops.nucleo_hechos (
  codigo text PRIMARY KEY,
  campo_id integer UNIQUE REFERENCES lf_ops.campos(id) ON DELETE CASCADE,
  tipo_dato text,
  unidad text,
  descripcion text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_hechos_campo_por_id CHECK (campo_id IS NULL OR codigo = 'CAMPO-' || campo_id),
  CONSTRAINT nucleo_hechos_campo_sin_copia CHECK (campo_id IS NULL OR (tipo_dato IS NULL AND descripcion IS NULL)),
  CONSTRAINT nucleo_hechos_calculado_completo CHECK (campo_id IS NOT NULL OR (tipo_dato IS NOT NULL AND length(btrim(coalesce(descripcion,''))) >= 10))
);
CREATE TABLE lf_ops.nucleo_familia_vocabulario (
  familia text NOT NULL REFERENCES lf_ops.nucleo_familias(codigo),
  hecho text NOT NULL REFERENCES lf_ops.nucleo_hechos(codigo) ON DELETE CASCADE,
  origen text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (familia, hecho),
  CONSTRAINT nucleo_familia_vocabulario_origen_valido CHECK (origen IN ('ENTIDAD_CAMPO','CURADO','JUEZ'))
);
CREATE VIEW lf_ops.v_nucleo_vocabulario WITH (security_invoker = true) AS
SELECT v.familia, h.codigo AS hecho, h.campo_id,
       COALESCE(c.codigo, h.codigo) AS etiqueta,
       COALESCE(c.tipo_dato, h.tipo_dato) AS tipo_dato,
       h.unidad,
       COALESCE(c.descripcion, h.descripcion) AS descripcion,
       c.entity_code, v.origen
  FROM lf_ops.nucleo_familia_vocabulario v
  JOIN lf_ops.nucleo_hechos h ON h.codigo = v.hecho
  LEFT JOIN lf_ops.campos c ON c.id = h.campo_id;
COMMENT ON TABLE lf_ops.nucleo_hechos IS 'Datos que pueden usar las condiciones de las reglas. Los campos se referencian por id (CAMPO-<id>).';
COMMENT ON TABLE lf_ops.nucleo_familia_vocabulario IS 'Vocabulario permitido por familia (control 4 de la puerta de entrada).';
COMMENT ON VIEW lf_ops.v_nucleo_vocabulario IS 'Vocabulario por familia con tipo y descripción vigentes leídos del diccionario de campos.';

REVOKE ALL ON TABLE lf_ops.nucleo_hechos, lf_ops.nucleo_familia_vocabulario FROM PUBLIC;
ALTER TABLE lf_ops.nucleo_hechos ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_ops.nucleo_familia_vocabulario ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_hechos
  AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_familia_vocabulario
  AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON lf_ops.nucleo_hechos, lf_ops.nucleo_familia_vocabulario, lf_ops.v_nucleo_vocabulario FROM anon, authenticated;
REVOKE ALL ON lf_ops.v_nucleo_vocabulario FROM PUBLIC;

INSERT INTO lf_ops.nucleo_hechos (codigo, campo_id)
SELECT 'CAMPO-' || id, id FROM lf_ops.campos;

INSERT INTO lf_ops.nucleo_familia_vocabulario (familia, hecho, origen)
SELECT CASE
         WHEN entity_code IN ('UPLOAD_BATCH','UPLOAD_FILE','IMPORT_OFFER') THEN 'B2B_PORTFOLIO_LOADS'
         WHEN entity_code IN ('IMPORT_INSTALLMENT','SIMULATION_INPUT') THEN 'OFFERS_INSTALLMENTS'
         WHEN entity_code = 'COMPANY' THEN 'B2B_PARTNERS'
         WHEN entity_code = 'COMPANY_USER' THEN 'PERMISSIONS'
         WHEN entity_code IN ('APPROVAL_POLICY','APPROVAL_RECORD') THEN 'GOVERNANCE_APPROVAL'
         WHEN entity_code = 'RECLAMACION' THEN 'LEGAL_CONSENT'
         WHEN entity_code IN ('DASHBOARD_METRIC','FILTER') THEN 'DASHBOARD_REPORTING'
         WHEN entity_code = 'AUDIT_EVENT' THEN 'AUDIT'
         WHEN entity_code IN ('MFA_FACTOR','PASSWORD_RECOVERY') THEN 'MFA_OTP_SSO'
         WHEN entity_code = 'VALIDATION' THEN 'VALIDATIONS'
         ELSE 'FIELDS'
       END,
       'CAMPO-' || id, 'ENTIDAD_CAMPO'
  FROM lf_ops.campos;
COMMIT;

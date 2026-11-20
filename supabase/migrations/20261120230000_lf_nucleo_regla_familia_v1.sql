BEGIN;
-- Núcleo de reglas, fase F0: familia de cada regla (instancia LF).
-- Asigna una familia a cada regla de lf_ops.reglas. metodo indica cómo se asignó:
--   CATEGORIA     = por su categoría actual (determinístico)
--   PALABRA_CLAVE = por palabras del título/descripción en categorías mezcladas (pendiente de validar por el juez)
--   MANUAL        = casos sin coincidencia, asignados explícitamente (pendiente de validar)
-- Falla cerrada: si alguna regla queda sin familia al aplicar, no se inserta nada.
CREATE TABLE lf_ops.nucleo_regla_familia (
  regla_id integer PRIMARY KEY REFERENCES lf_ops.reglas(id) ON DELETE CASCADE,
  familia text NOT NULL REFERENCES lf_ops.nucleo_familias(codigo),
  metodo text NOT NULL,
  pendiente_validacion boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nucleo_regla_familia_metodo_valido CHECK (metodo IN ('CATEGORIA','PALABRA_CLAVE','MANUAL','JUEZ')),
  CONSTRAINT nucleo_regla_familia_validacion_coherente CHECK (metodo <> 'CATEGORIA' OR NOT pendiente_validacion)
);
COMMENT ON TABLE lf_ops.nucleo_regla_familia IS
  'Familia asignada a cada regla. Las asignaciones PALABRA_CLAVE y MANUAL quedan pendientes de validación por el juez semántico.';
REVOKE ALL ON TABLE lf_ops.nucleo_regla_familia FROM PUBLIC;
ALTER TABLE lf_ops.nucleo_regla_familia ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON lf_ops.nucleo_regla_familia
  AS PERMISSIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
REVOKE ALL ON lf_ops.nucleo_regla_familia FROM anon, authenticated;

DO $asignar$
DECLARE v_sin integer; v_lista text;
BEGIN
  CREATE TEMP TABLE tmp_regla_familia ON COMMIT DROP AS
  WITH base AS (
    SELECT r.id, lower(r.categoria) AS c, lower(r.titulo || ' ' || coalesce(r.descripcion, '')) AS t
      FROM lf_ops.reglas r)
  SELECT id, CASE
    WHEN c IN ('checkout','pago','niubiz','client_checkout') THEN 'C:PAYMENTS_CHECKOUT'
    WHEN c IN ('oferta','ofertas_cuotas','precio','beneficios','home_variante') THEN 'C:OFFERS_INSTALLMENTS'
    WHEN c IN ('b2b_cargas','cargas') THEN 'C:B2B_PORTFOLIO_LOADS'
    WHEN c = 'legal' THEN 'C:LEGAL_CONSENT'
    WHEN c = 'commercial_campaign' THEN 'C:COMMERCIAL_CAMPAIGNS'
    WHEN c = 'documento' THEN 'C:DOCUMENTS_CERTIFICATES'
    WHEN c IN ('notificaciones','notificacion') THEN 'C:NOTIFICATIONS_DELIVERY'
    WHEN c = 'retention' THEN 'C:DATA_RETENTION'
    WHEN c = 'heatmap' THEN 'C:HEATMAP_SESSION_RECORDING'
    WHEN c = 'ab_testing' THEN 'C:EXPERIMENTS_AB'
    WHEN c IN ('governance','approval','product_governance') THEN 'C:GOVERNANCE_APPROVAL'
    WHEN c IN ('business','negocio','datos','b2b','tecnico','ux','contenido','workflow','integrity') THEN CASE
      WHEN t ~ '(concilia|ledger|liquidaci|redonde)' THEN 'K:FINANCIAL_INTEGRITY_RECONCILIATION'
      WHEN t ~ '(webhook|n8n|proveedor|integraci|sdk)' THEN 'K:INTEGRATIONS_WEBHOOKS'
      WHEN t ~ '(medianoche|nocturn|programad|batch|job)' THEN 'K:SCHEDULED_PROCESSES'
      WHEN t ~ '(m[aá]quina de estados|lifecycle|ciclo de vida|transici[oó]n de dominio)' THEN 'K:DOMAIN_LIFECYCLE'
      WHEN t ~ '(dashboard|reporte|indicador)' THEN 'K:DASHBOARD_REPORTING'
      WHEN t ~ '(carga|cartera|excel)' THEN 'K:B2B_PORTFOLIO_LOADS'
      WHEN t ~ '(aliado|empresa b2b|sla)' THEN 'K:B2B_PARTNERS'
      WHEN t ~ '(cuota|oferta|plan|descuento|ahorro|modalidad|precio|monto)' THEN 'K:OFFERS_INSTALLMENTS'
      WHEN t ~ '(pago|checkout|cobro)' THEN 'K:PAYMENTS_CHECKOUT'
      WHEN t ~ '(campa[ñn]a|marketing)' THEN 'K:COMMERCIAL_CAMPAIGNS'
      WHEN t ~ '(carta|documento|constancia)' THEN 'K:DOCUMENTS_CERTIFICATES'
      WHEN t ~ '(timeout|reintent|retry)' THEN 'K:TIMEOUT_RETRY'
      WHEN t ~ '(error|falla|rechaz)' THEN 'K:LOADING_EMPTY_ERROR_STATES'
      WHEN t ~ '(contraseñ|password|credencial|otp)' THEN 'K:MFA_OTP_SSO'
      WHEN t ~ '(estado|visual|card|bot[oó]n|cta)' THEN 'K:STATES'
      WHEN t ~ '(campo|input|formulario|autocomplet|teclado)' THEN 'K:FIELDS'
      WHEN t ~ '(mensaje|copy|texto|label)' THEN 'K:UI_MESSAGES'
      WHEN t ~ '(api|endpoint|respuesta|contrato)' THEN 'K:API_DATA_CONTRACT'
      WHEN t ~ '(navega|paso|regres|flujo)' THEN 'K:TRANSITIONS'
      WHEN t ~ '(idempoten)' THEN 'K:IDEMPOTENCY_CONCURRENCY'
      WHEN t ~ '(feature flag|rollout)' THEN 'M:FEATURE_FLAGS'
      WHEN t ~ '(prefijo|tel[eé]fono)' THEN 'M:FIELDS'
      WHEN t ~ '(capa cognitiva|decisi[oó]n humana)' THEN 'M:GOVERNANCE_APPROVAL'
      WHEN t ~ '(gamificaci|insignia)' THEN 'M:FEATURE_FLAGS'
      END
    WHEN c IN ('security','seguridad','ataques','storage') THEN 'C:SECURITY'
    WHEN c = 'rate_limiting' THEN 'C:RATE_LIMIT'
    WHEN c IN ('sesion','session') THEN 'C:SESSION'
    WHEN c = 'autenticacion' THEN 'C:MFA_OTP_SSO'
    WHEN c = 'authorization' THEN 'C:PERMISSIONS'
    WHEN c = 'resilience' THEN 'C:TIMEOUT_RETRY'
    WHEN c IN ('observabilidad','observability','alertas') THEN 'C:OBSERVABILITY'
    WHEN c IN ('auditoria','audit') THEN 'C:AUDIT'
    WHEN c IN ('analytics','tageo') THEN 'C:ANALYTICS'
    WHEN c = 'performance' THEN 'C:PERFORMANCE'
    WHEN c = 'compatibility' THEN 'C:BROWSER_PLATFORM'
    WHEN c IN ('configuration','ux_runtime') THEN 'C:RUNTIME_CONFIG'
    WHEN c IN ('error','error_handling') THEN 'C:ERRORS'
    WHEN c = 'testing' THEN 'C:TESTING_OBLIGATIONS'
    WHEN c = 'privacy' THEN 'C:PRIVACY_PII'
    WHEN c = 'api' THEN 'C:API_DATA_CONTRACT'
    WHEN c IN ('unicidad','validation') THEN 'C:VALIDATIONS'
    WHEN c = 'flujo' THEN 'C:TRANSITIONS'
    WHEN c IN ('estados_ui','ui') THEN 'C:STATES'
    WHEN c = 'copy' THEN 'C:UI_MESSAGES'
    WHEN c = 'error_states' THEN 'C:LOADING_EMPTY_ERROR_STATES'
    WHEN c IN ('accesibilidad','accessibility') THEN 'C:ACCESSIBILITY'
    WHEN c = 'responsive' THEN 'C:RESPONSIVE'
    WHEN c = 'theme' THEN 'C:THEME_LIGHT_DARK_SYSTEM'
    WHEN c = 'design' THEN 'C:DESIGN_SYSTEM'
    WHEN c = 'brand' THEN 'C:ASSETS_ICONS'
    WHEN c IN ('navegacion','navigation','shell') THEN 'C:ROUTING_NAVIGATION'
  END AS f
  FROM base;

  SELECT count(*), string_agg(id::text, ',') INTO v_sin, v_lista FROM tmp_regla_familia WHERE f IS NULL;
  IF v_sin > 0 THEN
    RAISE EXCEPTION 'NUCLEO_REGLA_SIN_FAMILIA: % reglas sin familia (ids %)', v_sin, v_lista;
  END IF;

  INSERT INTO lf_ops.nucleo_regla_familia (regla_id, familia, metodo, pendiente_validacion)
  SELECT id, substr(f, 3),
         CASE left(f, 1) WHEN 'C' THEN 'CATEGORIA' WHEN 'K' THEN 'PALABRA_CLAVE' ELSE 'MANUAL' END,
         left(f, 1) <> 'C'
    FROM tmp_regla_familia;
END $asignar$;
COMMIT;

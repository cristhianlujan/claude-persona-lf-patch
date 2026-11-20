-- Núcleo de reglas, bloque A (cierre de F0, instancia LF).
-- 1) Taxonomía de dos ejes: el TIPO vive en la familia (la regla lo hereda, no se copia);
--    la NATURALEZA (CONDUCTA obliga/prohíbe, DEFINICION define) se asigna por regla, pendiente de validar.
-- 2) Vocabulario de negocio: hechos que referencian columnas reales de tablas de dominio (COL-<tabla>.<columna>);
--    el tipo se lee del catálogo (pg_attribute) y un trigger impide referenciar columnas inexistentes.
BEGIN;
-- 1a) tipo por familia
ALTER TABLE lf_ops.nucleo_familias ADD COLUMN tipo text;
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'ACCESSIBILITY';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'ACTIONS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'ANALYTICS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'API_DATA_CONTRACT';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'APPLICABILITY_READINESS';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'ASSETS_ICONS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'AUDIT';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'B2B_PARTNERS';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'B2B_PORTFOLIO_LOADS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'BROWSER_PLATFORM';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'COMMERCIAL_CAMPAIGNS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'CONFLICT_PRECEDENCE';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'CONTEXT_BUDGET_RETRIEVAL_POLICY';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'DASHBOARD_REPORTING';
UPDATE lf_ops.nucleo_familias SET tipo = 'LEGAL' WHERE codigo = 'DATA_RETENTION';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'DEPENDENCIES';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'DESIGN_SYSTEM';
UPDATE lf_ops.nucleo_familias SET tipo = 'LEGAL' WHERE codigo = 'DOCUMENTS_CERTIFICATES';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'DOMAIN_LIFECYCLE';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'EKB';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'ERRORS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'EXPERIMENTS_AB';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'FEATURE_FLAGS';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'FIELDS';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'FINANCIAL_INTEGRITY_RECONCILIATION';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'FORCED_COLORS_CONTRAST';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'FRESHNESS_INVALIDATION';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'GOVERNANCE_APPROVAL';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'HEATMAP_SESSION_RECORDING';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'I18N_FORMATS';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'IDEMPOTENCY_CONCURRENCY';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'INTEGRATIONS_WEBHOOKS';
UPDATE lf_ops.nucleo_familias SET tipo = 'LEGAL' WHERE codigo = 'LEGAL_CONSENT';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'LOADING_EMPTY_ERROR_STATES';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'MFA_OTP_SSO';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'NEGATIVE_REQUIREMENTS';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'NOTIFICATIONS_DELIVERY';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'OBJECTIVE_OUTCOMES';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'OBSERVABILITY';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'OFFERS_INSTALLMENTS';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'PAYMENTS_CHECKOUT';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'PERFORMANCE';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'PERMISSIONS';
UPDATE lf_ops.nucleo_familias SET tipo = 'LEGAL' WHERE codigo = 'PRIVACY_PII';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'PROFILES';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'RATE_LIMIT';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'REDUCED_MOTION';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'RESPONSIVE';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'ROLLOUT_PRODUCTION_GATES';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'ROUTING_NAVIGATION';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'RUNTIME_CONFIG';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'SCHEDULED_PROCESSES';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'SCREEN_IDENTITY';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'SECURITY';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'SESSION';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'SOURCE_AUTHORITY_PROVENANCE';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'STATES';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'TESTING_OBLIGATIONS';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'THEME_LIGHT_DARK_SYSTEM';
UPDATE lf_ops.nucleo_familias SET tipo = 'TECNICA' WHERE codigo = 'TIMEOUT_RETRY';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'TRANSITIONS';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'UI_MESSAGES';
UPDATE lf_ops.nucleo_familias SET tipo = 'NEGOCIO' WHERE codigo = 'VALIDATIONS';
UPDATE lf_ops.nucleo_familias SET tipo = 'VISUAL' WHERE codigo = 'VISUAL_EVIDENCE';
ALTER TABLE lf_ops.nucleo_familias ALTER COLUMN tipo SET NOT NULL;
ALTER TABLE lf_ops.nucleo_familias ADD CONSTRAINT nucleo_familias_tipo_valido CHECK (tipo IN ('TECNICA','VISUAL','NEGOCIO','LEGAL'));

-- 1b) naturaleza por regla (heurística sobre el texto, pendiente de validación)
ALTER TABLE lf_ops.nucleo_regla_familia ADD COLUMN naturaleza text;
UPDATE lf_ops.nucleo_regla_familia a
   SET naturaleza = CASE WHEN lower(r.titulo || ' ' || coalesce(r.descripcion,'')) ~
     '(estados normalizados|estructura |formato |anatom|identificador|c[oó]digo [úu]nico|cat[aá]logo|mapa funcional|herramienta |variables gtm|breakpoints|se define|definici[oó]n|contrato reutilizable|contrato conductual|base de c[aá]lculo|tres estados)'
     THEN 'DEFINICION' ELSE 'CONDUCTA' END
  FROM lf_ops.reglas r WHERE r.id = a.regla_id;
ALTER TABLE lf_ops.nucleo_regla_familia ALTER COLUMN naturaleza SET NOT NULL;
ALTER TABLE lf_ops.nucleo_regla_familia ADD CONSTRAINT nucleo_regla_familia_naturaleza_valida CHECK (naturaleza IN ('CONDUCTA','DEFINICION'));
ALTER TABLE lf_ops.nucleo_regla_familia ADD COLUMN naturaleza_pendiente boolean NOT NULL DEFAULT true;

CREATE OR REPLACE VIEW lf_ops.v_nucleo_regla_clasificacion WITH (security_invoker = true) AS
SELECT a.regla_id, r.codigo, a.familia, f.tipo, f.dominio, a.naturaleza,
       a.metodo, a.pendiente_validacion, a.naturaleza_pendiente
  FROM lf_ops.nucleo_regla_familia a
  JOIN lf_ops.reglas r ON r.id = a.regla_id
  JOIN lf_ops.nucleo_familias f ON f.codigo = a.familia;
REVOKE ALL ON lf_ops.v_nucleo_regla_clasificacion FROM PUBLIC;
REVOKE ALL ON lf_ops.v_nucleo_regla_clasificacion FROM anon, authenticated;

-- 2) hechos referidos a columnas de dominio
ALTER TABLE lf_ops.nucleo_hechos ADD COLUMN tabla_ref text, ADD COLUMN columna_ref text;
ALTER TABLE lf_ops.nucleo_hechos DROP CONSTRAINT nucleo_hechos_calculado_completo;
ALTER TABLE lf_ops.nucleo_hechos DROP CONSTRAINT nucleo_hechos_calculado_con_unidad;
ALTER TABLE lf_ops.nucleo_hechos ADD CONSTRAINT nucleo_hechos_origen_unico CHECK (
  (campo_id IS NOT NULL)::int + (columna_ref IS NOT NULL)::int <= 1
  AND (tabla_ref IS NULL) = (columna_ref IS NULL));
ALTER TABLE lf_ops.nucleo_hechos ADD CONSTRAINT nucleo_hechos_columna_por_ref CHECK (
  columna_ref IS NULL OR (codigo = 'COL-' || tabla_ref || '.' || columna_ref AND tipo_dato IS NULL AND descripcion IS NULL));
ALTER TABLE lf_ops.nucleo_hechos ADD CONSTRAINT nucleo_hechos_calculado_completo CHECK (
  campo_id IS NOT NULL OR columna_ref IS NOT NULL
  OR (tipo_dato IS NOT NULL AND unidad IS NOT NULL AND length(btrim(coalesce(descripcion,''))) >= 10));

CREATE OR REPLACE FUNCTION lf_ops.fn_nucleo_hechos_columna_existe_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF NEW.columna_ref IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute
        WHERE attrelid = to_regclass(NEW.tabla_ref) AND attname = NEW.columna_ref AND attnum > 0 AND NOT attisdropped) THEN
    RAISE EXCEPTION 'NUCLEO_HECHO_COLUMNA_INEXISTENTE: %.%', NEW.tabla_ref, NEW.columna_ref;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_nucleo_hechos_columna_existe_v1 BEFORE INSERT OR UPDATE OF tabla_ref, columna_ref
  ON lf_ops.nucleo_hechos FOR EACH ROW EXECUTE FUNCTION lf_ops.fn_nucleo_hechos_columna_existe_v1();

ALTER TABLE lf_ops.nucleo_familia_vocabulario DROP CONSTRAINT nucleo_familia_vocabulario_origen_valido;
ALTER TABLE lf_ops.nucleo_familia_vocabulario ADD CONSTRAINT nucleo_familia_vocabulario_origen_valido
  CHECK (origen IN ('ENTIDAD_CAMPO','CURADO','COLUMNA_NEGOCIO','JUEZ'));

INSERT INTO lf_ops.nucleo_hechos (codigo, tabla_ref, columna_ref, unidad) VALUES
  ('COL-lf_proto.proto_offers.estado', 'lf_proto.proto_offers', 'estado', 'ninguna'),
  ('COL-lf_proto.proto_offers.modalidades_count', 'lf_proto.proto_offers', 'modalidades_count', 'cantidad'),
  ('COL-lf_proto.proto_offers.tiene_cuotas', 'lf_proto.proto_offers', 'tiene_cuotas', 'ninguna'),
  ('COL-lf_proto.proto_offers.tiene_pago_unico', 'lf_proto.proto_offers', 'tiene_pago_unico', 'ninguna'),
  ('COL-lf_proto.proto_offers.expires_at', 'lf_proto.proto_offers', 'expires_at', 'ninguna'),
  ('COL-lf_proto.proto_offers.variante_paso3', 'lf_proto.proto_offers', 'variante_paso3', 'ninguna'),
  ('COL-lf_proto.proto_offers.creditor_current', 'lf_proto.proto_offers', 'creditor_current', 'ninguna'),
  ('COL-lf_proto.proto_offers.ally_status', 'lf_proto.proto_offers', 'ally_status', 'ninguna'),
  ('COL-lf_proto.proto_offers.carta_no_adeudo', 'lf_proto.proto_offers', 'carta_no_adeudo', 'ninguna'),
  ('COL-public.lf_user_offer_selections.modality', 'public.lf_user_offer_selections', 'modality', 'ninguna'),
  ('COL-public.lf_user_offer_selections.plan_id', 'public.lf_user_offer_selections', 'plan_id', 'ninguna'),
  ('COL-public.lf_user_offer_selections.offer_version', 'public.lf_user_offer_selections', 'offer_version', 'ninguna'),
  ('COL-public.lf_user_offer_access.revoked_at', 'public.lf_user_offer_access', 'revoked_at', 'ninguna'),
  ('COL-lf_proto.checkout_pricing_quotes.offers_subtotal_today', 'lf_proto.checkout_pricing_quotes', 'offers_subtotal_today', 'soles'),
  ('COL-lf_proto.checkout_pricing_quotes.management_fee_customer', 'lf_proto.checkout_pricing_quotes', 'management_fee_customer', 'soles'),
  ('COL-lf_proto.checkout_pricing_quotes.niubiz_fee_customer', 'lf_proto.checkout_pricing_quotes', 'niubiz_fee_customer', 'soles'),
  ('COL-lf_proto.checkout_pricing_quotes.final_customer_price', 'lf_proto.checkout_pricing_quotes', 'final_customer_price', 'soles'),
  ('COL-lf_proto.checkout_pricing_quotes.total_savings', 'lf_proto.checkout_pricing_quotes', 'total_savings', 'soles'),
  ('COL-lf_proto.checkout_pricing_quotes.savings_verified', 'lf_proto.checkout_pricing_quotes', 'savings_verified', 'ninguna'),
  ('COL-lf_proto.checkout_pricing_quotes.quote_status', 'lf_proto.checkout_pricing_quotes', 'quote_status', 'ninguna'),
  ('COL-lf_proto.checkout_pricing_quotes.expires_at', 'lf_proto.checkout_pricing_quotes', 'expires_at', 'ninguna'),
  ('COL-public.lf_b2b_pricing_config.igv_rate', 'public.lf_b2b_pricing_config', 'igv_rate', 'proporcion'),
  ('COL-public.lf_b2b_pricing_config.management_fee_value', 'public.lf_b2b_pricing_config', 'management_fee_value', 'ninguna'),
  ('COL-public.lf_b2b_pricing_config.niubiz_fee_value', 'public.lf_b2b_pricing_config', 'niubiz_fee_value', 'ninguna'),
  ('COL-public.lf_b2b_pricing_config.collection_channel', 'public.lf_b2b_pricing_config', 'collection_channel', 'ninguna'),
  ('COL-public.lf_b2b_pricing_config.show_final_price', 'public.lf_b2b_pricing_config', 'show_final_price', 'ninguna'),
  ('COL-public.lf_b2b_pricing_config.campaign_override_allowed', 'public.lf_b2b_pricing_config', 'campaign_override_allowed', 'ninguna'),
  ('COL-public.lf_b2b_pricing_config.valid_to', 'public.lf_b2b_pricing_config', 'valid_to', 'ninguna'),
  ('COL-lf_ops.empresas.authorization_status', 'lf_ops.empresas', 'authorization_status', 'ninguna'),
  ('COL-lf_ops.empresas.operational_status', 'lf_ops.empresas', 'operational_status', 'ninguna'),
  ('COL-lf_ops.empresas.enabled_product_codes', 'lf_ops.empresas', 'enabled_product_codes', 'ninguna'),
  ('COL-lf_ops.empresas.payment_method_codes', 'lf_ops.empresas', 'payment_method_codes', 'ninguna'),
  ('COL-lf_ops.empresas.trusted_device_duration_days', 'lf_ops.empresas', 'trusted_device_duration_days', 'dias'),
  ('COL-lf_client.client_auth_sessions.last_seen_at', 'lf_client.client_auth_sessions', 'last_seen_at', 'ninguna'),
  ('COL-lf_client.client_auth_sessions.revoked_at', 'lf_client.client_auth_sessions', 'revoked_at', 'ninguna'),
  ('COL-lf_client.client_auth_sessions.revocation_reason', 'lf_client.client_auth_sessions', 'revocation_reason', 'ninguna'),
  ('COL-lf_client.client_phone_bindings.verified_at', 'lf_client.client_phone_bindings', 'verified_at', 'ninguna'),
  ('COL-lf_client.client_phone_bindings.valid_to', 'lf_client.client_phone_bindings', 'valid_to', 'ninguna'),
  ('COL-lf_client.client_accounts.activated_at', 'lf_client.client_accounts', 'activated_at', 'ninguna'),
  ('COL-lf_client.client_accounts.disabled_at', 'lf_client.client_accounts', 'disabled_at', 'ninguna'),
  ('COL-lf_client.client_accounts.document_type', 'lf_client.client_accounts', 'document_type', 'ninguna');
INSERT INTO lf_ops.nucleo_familia_vocabulario (familia, hecho, origen) VALUES
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.estado', 'COLUMNA_NEGOCIO'),
  ('DOMAIN_LIFECYCLE', 'COL-lf_proto.proto_offers.estado', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.modalidades_count', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.tiene_cuotas', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.tiene_pago_unico', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.expires_at', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.variante_paso3', 'COLUMNA_NEGOCIO'),
  ('STATES', 'COL-lf_proto.proto_offers.variante_paso3', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.proto_offers.creditor_current', 'COLUMNA_NEGOCIO'),
  ('B2B_PARTNERS', 'COL-lf_proto.proto_offers.ally_status', 'COLUMNA_NEGOCIO'),
  ('DOCUMENTS_CERTIFICATES', 'COL-lf_proto.proto_offers.carta_no_adeudo', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-public.lf_user_offer_selections.modality', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-public.lf_user_offer_selections.plan_id', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-public.lf_user_offer_selections.offer_version', 'COLUMNA_NEGOCIO'),
  ('FRESHNESS_INVALIDATION', 'COL-public.lf_user_offer_selections.offer_version', 'COLUMNA_NEGOCIO'),
  ('PERMISSIONS', 'COL-public.lf_user_offer_access.revoked_at', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.offers_subtotal_today', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.management_fee_customer', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.niubiz_fee_customer', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.final_customer_price', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.total_savings', 'COLUMNA_NEGOCIO'),
  ('OFFERS_INSTALLMENTS', 'COL-lf_proto.checkout_pricing_quotes.total_savings', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.savings_verified', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.quote_status', 'COLUMNA_NEGOCIO'),
  ('DOMAIN_LIFECYCLE', 'COL-lf_proto.checkout_pricing_quotes.quote_status', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_proto.checkout_pricing_quotes.expires_at', 'COLUMNA_NEGOCIO'),
  ('FRESHNESS_INVALIDATION', 'COL-lf_proto.checkout_pricing_quotes.expires_at', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-public.lf_b2b_pricing_config.igv_rate', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-public.lf_b2b_pricing_config.management_fee_value', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-public.lf_b2b_pricing_config.niubiz_fee_value', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-public.lf_b2b_pricing_config.collection_channel', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-public.lf_b2b_pricing_config.show_final_price', 'COLUMNA_NEGOCIO'),
  ('STATES', 'COL-public.lf_b2b_pricing_config.show_final_price', 'COLUMNA_NEGOCIO'),
  ('COMMERCIAL_CAMPAIGNS', 'COL-public.lf_b2b_pricing_config.campaign_override_allowed', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-public.lf_b2b_pricing_config.valid_to', 'COLUMNA_NEGOCIO'),
  ('FRESHNESS_INVALIDATION', 'COL-public.lf_b2b_pricing_config.valid_to', 'COLUMNA_NEGOCIO'),
  ('B2B_PARTNERS', 'COL-lf_ops.empresas.authorization_status', 'COLUMNA_NEGOCIO'),
  ('B2B_PARTNERS', 'COL-lf_ops.empresas.operational_status', 'COLUMNA_NEGOCIO'),
  ('DOMAIN_LIFECYCLE', 'COL-lf_ops.empresas.operational_status', 'COLUMNA_NEGOCIO'),
  ('B2B_PARTNERS', 'COL-lf_ops.empresas.enabled_product_codes', 'COLUMNA_NEGOCIO'),
  ('B2B_PARTNERS', 'COL-lf_ops.empresas.payment_method_codes', 'COLUMNA_NEGOCIO'),
  ('PAYMENTS_CHECKOUT', 'COL-lf_ops.empresas.payment_method_codes', 'COLUMNA_NEGOCIO'),
  ('B2B_PARTNERS', 'COL-lf_ops.empresas.trusted_device_duration_days', 'COLUMNA_NEGOCIO'),
  ('MFA_OTP_SSO', 'COL-lf_ops.empresas.trusted_device_duration_days', 'COLUMNA_NEGOCIO'),
  ('SESSION', 'COL-lf_client.client_auth_sessions.last_seen_at', 'COLUMNA_NEGOCIO'),
  ('SESSION', 'COL-lf_client.client_auth_sessions.revoked_at', 'COLUMNA_NEGOCIO'),
  ('SESSION', 'COL-lf_client.client_auth_sessions.revocation_reason', 'COLUMNA_NEGOCIO'),
  ('MFA_OTP_SSO', 'COL-lf_client.client_phone_bindings.verified_at', 'COLUMNA_NEGOCIO'),
  ('VALIDATIONS', 'COL-lf_client.client_phone_bindings.verified_at', 'COLUMNA_NEGOCIO'),
  ('MFA_OTP_SSO', 'COL-lf_client.client_phone_bindings.valid_to', 'COLUMNA_NEGOCIO'),
  ('DOMAIN_LIFECYCLE', 'COL-lf_client.client_accounts.activated_at', 'COLUMNA_NEGOCIO'),
  ('DOMAIN_LIFECYCLE', 'COL-lf_client.client_accounts.disabled_at', 'COLUMNA_NEGOCIO'),
  ('PERMISSIONS', 'COL-lf_client.client_accounts.disabled_at', 'COLUMNA_NEGOCIO'),
  ('VALIDATIONS', 'COL-lf_client.client_accounts.document_type', 'COLUMNA_NEGOCIO');

CREATE OR REPLACE VIEW lf_ops.v_nucleo_vocabulario WITH (security_invoker = true) AS
SELECT v.familia, h.codigo AS hecho, h.campo_id,
       COALESCE(c.codigo, h.columna_ref, h.codigo) AS etiqueta,
       COALESCE(c.tipo_dato, pg_catalog.format_type(pa.atttypid, pa.atttypmod), h.tipo_dato) AS tipo_dato,
       h.unidad,
       COALESCE(c.descripcion, h.descripcion) AS descripcion,
       c.entity_code, v.origen, h.tabla_ref
  FROM lf_ops.nucleo_familia_vocabulario v
  JOIN lf_ops.nucleo_hechos h ON h.codigo = v.hecho
  LEFT JOIN lf_ops.campos c ON c.id = h.campo_id
  LEFT JOIN pg_catalog.pg_attribute pa
         ON pa.attrelid = to_regclass(h.tabla_ref) AND pa.attname = h.columna_ref AND NOT pa.attisdropped;
REVOKE ALL ON lf_ops.v_nucleo_vocabulario FROM PUBLIC;
REVOKE ALL ON lf_ops.v_nucleo_vocabulario FROM anon, authenticated;
COMMIT;

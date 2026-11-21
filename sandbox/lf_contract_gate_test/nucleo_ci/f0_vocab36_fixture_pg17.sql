-- SOLO PG17 DESCARTABLE: proyección de columnas reales verificadas por information_schema.
-- Los CHECK reproducen exactamente pg_get_constraintdef en Supabase; sin filas de cliente.
-- NO aplicar a producción. PASE contenedor sin red.
CREATE TABLE lf_ops.analytics_eventos_definicion (
  pii_allowed boolean,
  status text,
  CONSTRAINT analytics_eventos_status_ck CHECK ((status = ANY (ARRAY['CANDIDATO'::text, 'EN_REVISION'::text, 'VIGENTE'::text, 'INACTIVO'::text, 'ARCHIVADO'::text])))
);
CREATE TABLE lf_ops.app_shells (
  design_system_code text
);
CREATE TABLE lf_ops.errores_catalogo (
  error_code text,
  http_status integer,
  log_level text,
  severity text,
  CONSTRAINT errores_catalogo_severity_ck CHECK ((severity = ANY (ARRAY['INFO'::text, 'LOW'::text, 'MEDIUM'::text, 'HIGH'::text, 'CRITICAL'::text]))),
  CONSTRAINT errores_catalogo_log_level_ck CHECK ((log_level = ANY (ARRAY['DEBUG'::text, 'INFO'::text, 'WARN'::text, 'ERROR'::text, 'FATAL'::text])))
);
CREATE TABLE lf_ops.estados_transiciones (
  action_code text,
  from_state_code text,
  to_state_code text
);
CREATE TABLE lf_ops.mensajes_ui (
  contains_pii boolean,
  message_type text,
  title text,
  visibility_scope text,
  CONSTRAINT mensajes_ui_type_ck CHECK ((message_type = ANY (ARRAY['INFO'::text, 'SUCCESS'::text, 'WARNING'::text, 'ERROR'::text, 'EMPTY'::text, 'CONFIRMATION'::text, 'SESSION'::text]))),
  CONSTRAINT mensajes_ui_visibility_ck CHECK ((visibility_scope = ANY (ARRAY['USER'::text, 'DEVELOPER'::text, 'BOTH'::text])))
);
CREATE TABLE lf_ops.menu_items (
  icon_name text,
  is_enabled boolean
);
CREATE TABLE lf_ops.pantalla_artefactos (
  access_level text,
  checksum_sha256 text,
  is_current boolean,
  storage_provider text,
  CONSTRAINT pantalla_artefactos_access_level_ck CHECK ((access_level = ANY (ARRAY['PRIVATE'::text, 'AUTHENTICATED'::text, 'PUBLIC'::text]))),
  CONSTRAINT pantalla_artefactos_storage_provider_ck CHECK ((storage_provider = ANY (ARRAY['SUPABASE_STORAGE'::text, 'GOOGLE_DRIVE'::text])))
);
CREATE TABLE lf_ops.pantalla_elementos (
  label_visible text,
  semantic_binding_status text,
  CONSTRAINT pantalla_elementos_semantic_binding_status_check CHECK ((semantic_binding_status = ANY (ARRAY['RESOLVED_ID'::text, 'PENDING_SEMANTIC_COMPONENT'::text, 'MISSING'::text, 'NOT_APPLICABLE'::text])))
);
CREATE TABLE lf_ops.pantalla_variantes (
  density_mode text,
  navigation_mode text,
  responsive_token_name text,
  supports_touch boolean,
  theme_binding_code text,
  CONSTRAINT pantalla_variantes_density_ck CHECK ((density_mode = ANY (ARRAY['COMPACT'::text, 'COMFORTABLE'::text, 'SPACIOUS'::text]))),
  CONSTRAINT pantalla_variantes_navigation_ck CHECK ((navigation_mode = ANY (ARRAY['SIDEBAR_EXPANDED'::text, 'SIDEBAR_COLLAPSED'::text, 'MOBILE_DRAWER'::text, 'NO_NAVIGATION'::text])))
);
CREATE TABLE lf_ops.pantallas_perfiles (
  profile_code text
);
CREATE TABLE lf_ops.politicas_timeout (
  backoff_strategy text,
  retry_limit integer,
  CONSTRAINT politicas_timeout_backoff_ck CHECK ((backoff_strategy = ANY (ARRAY['NONE'::text, 'FIXED'::text, 'LINEAR'::text, 'EXPONENTIAL'::text])))
);
CREATE TABLE lf_ops.rutas (
  route_pattern text,
  route_type text,
  CONSTRAINT rutas_type_ck CHECK ((route_type = ANY (ARRAY['INTERNAL'::text, 'CONTEXTUAL'::text, 'EXTERNAL'::text, 'REDIRECT'::text])))
);

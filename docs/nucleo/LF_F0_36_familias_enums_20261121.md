# F0 — Vocabulario y valores cerrados de las 36 familias restantes

**Naturaleza:** incorporación de metadatos, sin cambio de reglas ni de ejecución. Autoridad de fuente: catálogo y columnas reales de Supabase, con definición de los 36 códigos; 25 restricciones `CHECK` identificadas por nombre y hash. Cualquier hecho físico es **columna existente**, no necesariamente binding del runtime de la familia. Un hecho lógico es **declaración de concepto con binding NO VERIFICADO**.

## Cobertura declarativa

| Familia | Tipo | Hechos de columnas físicas | Hecho lógico no vinculado | Grupos enum |
|---|---|---:|---|---:|
| `ACCESSIBILITY` | VISUAL | 2 | — | 1 |
| `ACTIONS` | VISUAL | 2 | — | 0 |
| `API_DATA_CONTRACT` | TECNICA | 1 | — | 0 |
| `APPLICABILITY_READINESS` | TECNICA | 4 | — | 4 |
| `ASSETS_ICONS` | VISUAL | 2 | — | 0 |
| `BROWSER_PLATFORM` | TECNICA | 1 | — | 0 |
| `CONFLICT_PRECEDENCE` | TECNICA | 1 | — | 1 |
| `CONTEXT_BUDGET_RETRIEVAL_POLICY` | TECNICA | 0 | `f0_contexto_presupuesto_validado` | 0 |
| `DATA_RETENTION` | LEGAL | 0 | `f0_retencion_politica_aplicable` | 0 |
| `DEPENDENCIES` | TECNICA | 1 | — | 0 |
| `DESIGN_SYSTEM` | VISUAL | 2 | — | 0 |
| `EKB` | TECNICA | 2 | — | 0 |
| `ERRORS` | TECNICA | 3 | — | 2 |
| `EXPERIMENTS_AB` | TECNICA | 0 | `f0_experimento_elegible` | 0 |
| `FEATURE_FLAGS` | TECNICA | 0 | `f0_funcionalidad_habilitada_por_flag` | 0 |
| `FINANCIAL_INTEGRITY_RECONCILIATION` | NEGOCIO | 0 | `f0_pago_conciliado_autoritativamente` | 0 |
| `FORCED_COLORS_CONTRAST` | VISUAL | 0 | `f0_contraste_modo_forzado_preservado` | 0 |
| `HEATMAP_SESSION_RECORDING` | TECNICA | 0 | `f0_grabacion_sesion_datos_ofuscados` | 0 |
| `I18N_FORMATS` | VISUAL | 0 | `f0_formato_regional_valido` | 0 |
| `NEGATIVE_REQUIREMENTS` | NEGOCIO | 0 | `f0_accion_explicitamente_prohibida` | 0 |
| `OBJECTIVE_OUTCOMES` | NEGOCIO | 1 | — | 0 |
| `PRIVACY_PII` | LEGAL | 3 | — | 1 |
| `PROFILES` | NEGOCIO | 1 | — | 0 |
| `RESPONSIVE` | VISUAL | 2 | — | 1 |
| `ROLLOUT_PRODUCTION_GATES` | TECNICA | 1 | — | 1 |
| `ROUTING_NAVIGATION` | VISUAL | 3 | — | 2 |
| `RUNTIME_CONFIG` | TECNICA | 3 | — | 2 |
| `SCHEDULED_PROCESSES` | TECNICA | 0 | `f0_ejecucion_programada_verificada` | 0 |
| `SCREEN_IDENTITY` | VISUAL | 3 | — | 1 |
| `SOURCE_AUTHORITY_PROVENANCE` | TECNICA | 3 | — | 2 |
| `TESTING_OBLIGATIONS` | TECNICA | 3 | — | 2 |
| `THEME_LIGHT_DARK_SYSTEM` | VISUAL | 1 | — | 0 |
| `TIMEOUT_RETRY` | TECNICA | 2 | — | 1 |
| `TRANSITIONS` | NEGOCIO | 2 | — | 0 |
| `UI_MESSAGES` | VISUAL | 3 | — | 2 |
| `VISUAL_EVIDENCE` | VISUAL | 5 | — | 2 |

**Medición esperada:** 36/36 familias con algún vocabulario, 55 hechos físicos únicos, 10 hechos lógicos sin runtime, 67 nuevos enlaces y 25 enums (94 valores). Son **indicadores de catálogo**, no pruebas de comportamiento ni cobertura funcional.

## Procedencia de listas cerradas

- `COL-lf_ops.nucleo_familias.estado`: `lf_ops.nucleo_familias`, `nucleo_familias_estado_valido` (MD5 `72dc22e5ff1356ede66b31deed1ce24c`): `EN_FORMACION`, `ACTIVA`, `RETIRADA`.
- `COL-lf_ops.nucleo_familias.tipo`: `lf_ops.nucleo_familias`, `nucleo_familias_tipo_valido` (MD5 `2741ea9617e181de03225eee1060db01`): `TECNICA`, `VISUAL`, `NEGOCIO`, `LEGAL`.
- `COL-lf_ops.nucleo_regla_versiones.estado`: `lf_ops.nucleo_regla_versiones`, `nucleo_versiones_estado` (MD5 `90d50bd285444ec6d2bfe0b74d23e58e`): `CANDIDATA`, `PUBLICADA`, `DESCARTADA`.
- `COL-lf_ops.nucleo_regla_versiones.impacto`: `lf_ops.nucleo_regla_versiones`, `nucleo_versiones_impacto` (MD5 `d1f66ad6682e4c6dcadb6cc84c679432`): `NINGUNO`, `REVISAR`, `IMPLEMENTAR`.
- `COL-lf_ops.nucleo_aplicaciones.modo`: `lf_ops.nucleo_aplicaciones`, `nucleo_aplicaciones_modo_valido` (MD5 `46dc252c374a3e4de336258e55cc0298`): `HEREDA`, `FIJA`, `SOLO_AQUI`.
- `COL-lf_ops.nucleo_autoridades.tipo`: `lf_ops.nucleo_autoridades`, `nucleo_autoridades_tipo_valido` (MD5 `e78ba4026b76c5ef59a20cd3ab9e2362`): `DECISION_DUENO`, `NORMA`, `POLITICA`, `ANALISIS`.
- `COL-lf_ops.nucleo_autoridades.estado`: `lf_ops.nucleo_autoridades`, `nucleo_autoridades_estado_valido` (MD5 `b54236d163b1e5beb3c9540a831b99fb`): `VIGENTE`, `REEMPLAZADA`, `RETIRADA`.
- `COL-lf_ops.nucleo_juicios.modo`: `lf_ops.nucleo_juicios`, `nucleo_juicios_modo` (MD5 `cadb3bbf5068adddb3de3098fd440ce1`): `INDEPENDIENTE`, `CONTEXTO_ACTUAL`.
- `COL-lf_ops.nucleo_juicios.veredicto`: `lf_ops.nucleo_juicios`, `nucleo_juicios_veredicto` (MD5 `97d383146401cce09ee85e6c39b44bb6`): `PASS`, `DEVOLVER`.
- `COL-lf_ops.nucleo_nodos.nivel`: `lf_ops.nucleo_nodos`, `nucleo_nodos_nivel_valido` (MD5 `880e59e93faf76a49da5fea0d1d970df`): `GLOBAL`, `AMBITO`, `MODULO`, `PANTALLA`, `COMPONENTE`.
- `COL-lf_ops.nucleo_reglas.estado`: `lf_ops.nucleo_reglas`, `nucleo_reglas_estado_valido` (MD5 `39d4906ed387f03a19eb93c8ea2d2e95`): `BORRADOR`, `CANDIDATA`, `VIGENTE`, `DEPRECADA`, `RETIRADA`.
- `COL-public.lf_global_config.value_status`: `public.lf_global_config`, `lf_global_config_status_check` (MD5 `6f628517ce6980eacaddae00954b246e`): `FICTICIO`, `REAL`.
- `COL-public.lf_global_config.value_type`: `public.lf_global_config`, `lf_global_config_type_check` (MD5 `0d3f25afb7a4ae8e239bb3d526450e61`): `TEXT`, `INTEGER`, `DECIMAL`, `BOOLEAN`, `JSON`, `EMAIL`.
- `COL-lf_ops.pantalla_variantes.density_mode`: `lf_ops.pantalla_variantes`, `pantalla_variantes_density_ck` (MD5 `4fb491303a341d7eac00672271fed1d2`): `COMPACT`, `COMFORTABLE`, `SPACIOUS`.
- `COL-lf_ops.pantalla_variantes.navigation_mode`: `lf_ops.pantalla_variantes`, `pantalla_variantes_navigation_ck` (MD5 `318701303d8abf7e8d1e8c1196669372`): `SIDEBAR_EXPANDED`, `SIDEBAR_COLLAPSED`, `MOBILE_DRAWER`, `NO_NAVIGATION`.
- `COL-lf_ops.mensajes_ui.message_type`: `lf_ops.mensajes_ui`, `mensajes_ui_type_ck` (MD5 `81402d84abff3bca38b1612776d86e1d`): `INFO`, `SUCCESS`, `WARNING`, `ERROR`, `EMPTY`, `CONFIRMATION`, `SESSION`.
- `COL-lf_ops.mensajes_ui.visibility_scope`: `lf_ops.mensajes_ui`, `mensajes_ui_visibility_ck` (MD5 `3ddcbae0caeb54549b17a92c10f6c2cb`): `USER`, `DEVELOPER`, `BOTH`.
- `COL-lf_ops.errores_catalogo.severity`: `lf_ops.errores_catalogo`, `errores_catalogo_severity_ck` (MD5 `2ba46a2b62d2357a8bb963f8fb53cfba`): `INFO`, `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`.
- `COL-lf_ops.errores_catalogo.log_level`: `lf_ops.errores_catalogo`, `errores_catalogo_log_level_ck` (MD5 `31dfe4628a191a52e6eb532114b284d3`): `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`.
- `COL-lf_ops.rutas.route_type`: `lf_ops.rutas`, `rutas_type_ck` (MD5 `bda38dcbcb3222c5164975f167821453`): `INTERNAL`, `CONTEXTUAL`, `EXTERNAL`, `REDIRECT`.
- `COL-lf_ops.politicas_timeout.backoff_strategy`: `lf_ops.politicas_timeout`, `politicas_timeout_backoff_ck` (MD5 `4fd4f26d7eddf018c12528ea045ec068`): `NONE`, `FIXED`, `LINEAR`, `EXPONENTIAL`.
- `COL-lf_ops.pantalla_elementos.semantic_binding_status`: `lf_ops.pantalla_elementos`, `pantalla_elementos_semantic_binding_status_check` (MD5 `34f9bca1ddb5d8cfc3b9f08c8579a593`): `RESOLVED_ID`, `PENDING_SEMANTIC_COMPONENT`, `MISSING`, `NOT_APPLICABLE`.
- `COL-lf_ops.pantalla_artefactos.access_level`: `lf_ops.pantalla_artefactos`, `pantalla_artefactos_access_level_ck` (MD5 `f0dab7457d2b504642482f03a42a21df`): `PRIVATE`, `AUTHENTICATED`, `PUBLIC`.
- `COL-lf_ops.pantalla_artefactos.storage_provider`: `lf_ops.pantalla_artefactos`, `pantalla_artefactos_storage_provider_ck` (MD5 `e56fcc9bc064a07d5970b66abb09736d`): `SUPABASE_STORAGE`, `GOOGLE_DRIVE`.
- `COL-lf_ops.analytics_eventos_definicion.status`: `lf_ops.analytics_eventos_definicion`, `analytics_eventos_status_ck` (MD5 `61b045ff16ca698f28f552a75569eb94`): `CANDIDATO`, `EN_REVISION`, `VIGENTE`, `INACTIVO`, `ARCHIVADO`.

## Pruebas y bloqueo de alcance

- Positivas: fuente de cada columna coincide con `information_schema.columns`; checksum de cada `CHECK` coincide; 36 familias con relaciones; 25 conjuntos, 94 valores consultables; RLS activo y lector con respuesta booleana para valores permitidos.
- Negativas: valor inexistente retorna falso; FK de hecho desconocido rechaza; procedencia inventada rechaza; asociación de columna incorrecta rechaza; duplicado de valor rechaza; duplicado de enlace rechaza; regresiones PG17 LF y SALY, mutante detectado y rollback.
- **No se toca:** `lf_ops.reglas` (586), `lf_ops.nucleo_reglas` (10 candidatos PAYMENTS_CHECKOUT), `saly.reglas` (14 legadas) ni sus 14 candidatas `DEVUELTA`; escritores, lectores, F6, las 150 asignaciones ambiguas o políticas de negocio.
- Familias `DATA_RETENTION`, `SCHEDULED_PROCESSES` y `FINANCIAL_INTEGRITY_RECONCILIATION`: sólo hechos lógicos; el modelo de datos operativo sigue **NO DEMOSTRADO**.
- Los enums provienen de restricciones reales del momento de la migración; cualquier cambio futuro de `CHECK` obliga a revisar el catálogo y no equivale a habilitación automática de una regla.
- No hay umbrales, colores ni configuraciones numéricas inventadas. No se emiten decisiones humanas nuevas ni se certifica binding de consumo.

**Cierre del criterio:** únicamente después de PASE real, Merge Train y readback de producción. El delta del plan se asentará separado sin modificar la fuente base de Library sin un transporte que permita preservar sus bytes íntegros.

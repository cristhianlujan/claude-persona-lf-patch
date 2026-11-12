# Lote 16 — Triage de pertenencia a 15 familias

**Estado:** NO-GO / REQUIERE_REVISION_SEMANTICA. Las familias son la propuesta NO APLICADA del Lote 12. Conteos (OBJETIVO) desde SELECT S01, SHA-256 JSONB `59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9`. Fuente del mapeo: `04_familias_lf.csv`, Git blob `ed290df3f308422d2451aa5db4208ed0395e049d`. SQL en `07_evidencia_select.sql`.

## UX_FLUJOS_INTERFAZ — 148 reglas
Categorías: `BRAND`, `DESIGN`, `NAVIGATION`, `RESPONSIVE`, `SHELL`, `THEME`, `UI`, `UX`, `UX_RUNTIME`, `WORKFLOW`, `estados_ui`, `flujo`, `home_variante`, `navegacion`, `ux`.

**Representativas (5/5):**
- `B2B-RULE-DESIGN-001` [VIGENTE]: Referencias semánticas y promoción transversal de tokens.
- `B2B-RULE-THEME-003` [VIGENTE]: Resolución de tema System sin flash ni valores visuales duplicados.
- `REG_CLIENT_HOME_PUBLIC_ENTRY_001` [VIGENTE]: HOME_001 inicia el acceso Cliente únicamente mediante ONB_001.
- `REG_FLU_001` [VIGENTE]: Transiciones válidas del onboarding.
- `B2B-RULE-AUTH-006` [CANDIDATO]: Recuperación de contraseña visible y separada.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `B2B-RULE-APPROVAL-POLICY-LIFECYCLE-001` → alternativa **GOBERNANZA_INTEGRIDAD**. Motivo: Ciclo de vida de aprobación, no UX. **Cita literal:** «lf_ops.politicas_aprobacion permite DRAFT/ACTIVE/REPLACED/EXPIRED/INACTIVE y B2B-ADMIN-003 expone CREATE, UPDATE y ACTIVATE. No existe todavía».
- `REG_CLIENT_CHECKOUT_PAYMENT_METHOD_ELIGIBILITY_001` → alternativa **CHECKOUT_PAGOS**. Motivo: Elegibilidad financiera server-side. **Cita literal:** «El checkout Cliente muestra únicamente medios de pago que el backend determine elegibles».
- `REG_CLIENT_CHECKOUT_ENTRY_001` → alternativa **CHECKOUT_PAGOS**. Motivo: Revalidación transaccional previo al cobro. **Cita literal:** «El checkout Cliente solo puede iniciarse desde una sesión autenticada con al menos».
- `REG_NEW_CLIENT_DATA_COMPLETION_001` → alternativa **DATOS_VALIDACIONES**. Motivo: Validación de campos obligatorios. **Cita literal:** «Cuando ONB_003 resuelve NEW_CLIENT_DATA_COMPLETION, ONB_004 solicita CAMPO_NOMBRE_COMPLETO, CAMPO_EMAIL y CAMPO_CONSENT_TERMS como obligatorios. CAMPO_CONSENT_MKT».

## IDENTIDAD_SEGURIDAD — 105 reglas
Categorías: `AUTHORIZATION`, `PRIVACY`, `SECURITY`, `SESSION`, `ataques`, `autenticacion`, `rate_limiting`, `seguridad`, `sesion`, `unicidad`.

**Representativas (5/5):**
- `B2B-RULE-AUTH-001` [VIGENTE]: Denegar por defecto.
- `B2B-RULE-AUTH-002` [VIGENTE]: Aislamiento por empresa.
- `B2B-RULE-AUTH-003` [VIGENTE]: MFA según políticas centrales de perfil y acción.
- `REG_RISK_PHONE_MULTI_DNI_001` [VIGENTE]: Múltiples DNI o cuentas exploradas desde un mismo celular verificado.
- `REG_RATE_002` [VIGENTE]: Límite de intentos de validación OTP por IP.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## CHECKOUT_PAGOS — 56 reglas
Categorías: `CLIENT_CHECKOUT`, `checkout`, `niubiz`, `pago`, `precio`.

**Representativas (5/5):**
- `REG_CHK_001` [VIGENTE]: Checkout consolidado.
- `REG_CHK_003` [VIGENTE]: Estados normalizados del flujo de checkout.
- `REG_CLIENT_CHECKOUT_PRICING_QUOTE_001` [VIGENTE]: Quote de checkout Cliente versionado y fail-closed.
- `REG_CLIENT_PAYMENT_REFUND_POLICY_001` [VIGENTE]: Devoluciones Cliente retornan dinero y no crean saldo LF.
- `REG_CHK_019` [CANDIDATO]: Niubiz procesa el pago del checkout de cuotas.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `REG_CLIENT_HOME_PRICE_DETAIL_MODAL_001` → alternativa **UX_FLUJOS_INTERFAZ**. Motivo: Modal de precio de Home, no checkout. **Cita literal:** «PASO3_MODAL_DETALLE_PRECIO explica cómo se compone el monto vigente de una selección/oferta, pero nunca».
- `REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001` → alternativa **PLATAFORMA_INTEGRACIONES**. Motivo: Integridad de snapshot financiero / ledger. **Cita literal:** «Cuando un pago inicial confirmado activa un plan de cuotas, el backend debe».
- `REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001` → alternativa **NEGOCIO_B2B**. Motivo: Política de mora/cobranza coexiste con outcome de pagos. **Cita literal:** «Un intento de cobro de una cuota reutiliza los outcomes normalizados de pago.».

## NEGOCIO_B2B — 55 reglas
Categorías: `BUSINESS`, `COMMERCIAL_CAMPAIGN`, `b2b`, `beneficios`, `negocio`.

**Representativas (5/5):**
- `B2B-RULE-DASHBOARD-001` [CANDIDATO]: Dashboard Empresa orientado a operación, dinero y excepciones.
- `B2B-RULE-SETTLEMENT-001` [CANDIDATO]: Liquidación B2B trazable a pagos y ajustes.
- `REG_B2B_001` [VIGENTE]: El aliado B2B define los términos de la oferta.
- `B2B-RULE-NEGOTIATION-BANDS-001` [CANDIDATO]: Negociación B2B por bandas delegadas por la empresa.
- `B2B-RULE-CAMPAIGN-ARCHITECTURE-001` [CANDIDATO]: Arquitectura B2B de campañas comerciales separada de la carga de cartera.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `NEG-GOBERNANZA-PROVENANCE-01` → alternativa **GOBERNANZA_INTEGRIDAD**. Motivo: Provenance de asset, no operación comercial. **Cita literal:** «Cualquier decision en public.lf_decisiones_gov que registre un asset visual (imagen, render, JSON de».
- `NEG-GOBERNANZA-UPDATED-AT-01` → alternativa **GOBERNANZA_INTEGRIDAD**. Motivo: Integridad de metadatos de decisión. **Cita literal:** «La tabla public.lf_decisiones_gov no cuenta con ningun trigger automatico que actualice el campo».
- `NEG-GOBERNANZA-VISUAL-CONFIRM-01` → alternativa **GOBERNANZA_INTEGRIDAD**. Motivo: Gate de aprobación visual. **Cita literal:** «Toda propuesta de layout, componente o variante visual (ej. mobile variant de Ruta».
- `NEG-PROCESO-ITERACION-01` → alternativa **UX_FLUJOS_INTERFAZ**. Motivo: Disciplina de diseño iterativo. **Cita literal:** «Al iterar un asset visual con multiples componentes (cards, nodos, ruta, fondo), cambiar».
- `NEG-PROCESO-COMPOSICION-01` → alternativa **UX_FLUJOS_INTERFAZ**. Motivo: Composición de assets LOCKED. **Cita literal:** «Una vez que un asset visual (ej. terreno de Ruta de Claridad) queda».
- `LF-RULE-SUPPORT-CONTACTS-001` → alternativa **PLATAFORMA_INTEGRACIONES**. Motivo: Registro central de canales, no B2B comercial. **Cita literal:** «Los datos de contacto de LF para soporte, contratos, informática, soporte al usuario,».

## DATOS_VALIDACIONES — 32 reglas
Categorías: `ERROR`, `ERROR_HANDLING`, `VALIDATION`, `datos`, `error_states`.

**Representativas (5/5):**
- `B2B-RULE-ERROR-001` [VIGENTE]: Identificador numérico y código canónico de error.
- `B2B-RULE-ERROR-002` [VIGENTE]: Trazabilidad de ocurrencia.
- `B2B-RULE-ERROR-003` [VIGENTE]: Mensaje seguro al usuario.
- `B2B-RULE-VALIDATION-VALID-ONLY-001` [CANDIDATO]: Procesamiento parcial: continúan solo registros válidos.
- `B2B-RULE-AUTH-025` [CANDIDATO]: Errores de autenticación canónicos y trazables.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `B2B-RULE-AUTH-025` → alternativa **IDENTIDAD_SEGURIDAD**. Motivo: Trazabilidad de error de autenticación, dominio cruzado. **Cita literal:** «Todo fallo técnico o funcional del Login que requiera registro de ocurrencia debe».

## CONTENIDO_COMUNICACIONES — 30 reglas
Categorías: `contenido`, `copy`, `documento`, `notificacion`, `notificaciones`.

**Representativas (5/5):**
- `REG_CLIENT_HOME_FAQ_001` [VIGENTE]: FAQ público derivado de contratos Cliente vigentes.
- `REG_CLIENT_HOME_CLARITY_CONTENT_FRESHNESS_001` [VIGENTE]: Claims externos de Ruta de Claridad requieren fuente, vigencia y fallback.
- `REG_SUC_009` [CANDIDATO]: WhatsApp de confirmación post-pago exitoso.
- `REG_CHK_CUO_010` [VIGENTE]: CTA del checkout de cuotas.
- `REG_CLIENT_HOME_PUBLIC_LETTER_CLAIM_001` [VIGENTE]: Interpretación funcional condicionada del claim Carta de No Adeudo en HOME_001.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `REG_CLIENT_DOC_DEMO_VERSIONING_001` → alternativa **GOBERNANZA_INTEGRIDAD**. Motivo: Gobierno de versiones y autorización documental. **Cita literal:** «Una pantalla Cliente puede utilizar contenido o documento DEMO cuando el documento oficial».
- `REG_CLIENT_NO_DEBT_LETTER_STATUS_001` → alternativa **PLATAFORMA_INTEGRACIONES**. Motivo: Workflow de generación por aliado. **Cita literal:** «La Carta de No Adeudo se gestiona por deuda y solo entra al».

## PLATAFORMA_INTEGRACIONES — 29 reglas
Categorías: `COMPATIBILITY`, `CONFIGURATION`, `PERFORMANCE`, `RESILIENCE`, `STORAGE`, `api`, `tecnico`.

**Representativas (5/5):**
- `B2B-RULE-TIMEOUT-001` [VIGENTE]: Timeout y reintentos centralizados.
- `B2B-RULE-STORAGE-001` [CANDIDATO]: Storage privado.
- `B2B-RULE-PERF-001` [VIGENTE]: Core Web Vitals.
- `REG_TEC_009` [VIGENTE]: Idempotency key en operaciones críticas.
- `B2B-RULE-COMPAT-001` [CANDIDATO]: Compatibilidad de navegador y plataforma gobernada por fuente canónica.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `REG_TEC_006` → alternativa **UX_FLUJOS_INTERFAZ**. Motivo: Patrón visual skeleton. **Cita literal:** «Cualquier operación que tarde más de 300ms debe mostrar un skeleton screen, no».
- `REG_TEC_008` → alternativa **DATOS_VALIDACIONES**. Motivo: Validación dual cliente/servidor. **Cita literal:** «Todos los campos del formulario Paso 1 deben validarse en el cliente antes».
- `REG_TEC_010` → alternativa **IDENTIDAD_SEGURIDAD**. Motivo: Control de no filtración técnica. **Cita literal:** «Los errores del servidor nunca incluyen stack traces, queries SQL, nombres de tablas,».
- `B2B-RULE-PERF-001` → alternativa **OBSERVABILIDAD_AUDITORIA**. Motivo: Instrumentación de métricas, no infraestructura principal. **Cita literal:** «Medir LCP, INP, CLS y TTFB sin datos personales.».

## LEGAL — 26 reglas
Categorías: `LEGAL`, `legal`.

**Representativas (5/5):**
- `LEGAL-CESION-DEUDA-NOTIFICACION-01` [VIGENTE]: Cesion de deuda: notificacion valida aunque contacto desactualizado.
- `LEGAL-RECLAMOS-03` [CANDIDATO]: Plazo de respuesta: 15 dias habiles.
- `LEGAL-CONSENTIMIENTO-DATOS-01` [CANDIDATO]: Checkbox de consentimiento de datos: requisitos exactos Ley 29733 + Reglamento 2024.
- `REG_CLIENT_LIBRO_SUBMIT_001` [VIGENTE]: Submit público, atómico e idempotente del Libro de Reclamaciones Cliente.
- `B2B-RULE-LEGAL-001` [CANDIDATO]: Nombre del cliente opcional de referencia en carga.

**Pertenencia dudosa — REQUIERE_REVISION_SEMANTICA:**
- `BUG-ASSET-LOGO-NORMAL-SIN-ALPHA-01` → alternativa **UX_FLUJOS_INTERFAZ**. Motivo: Defecto de activo gráfico, no obligación legal principal. **Cita literal:** «El archivo Logo_Normal.png (VD_LOGO_LF_20260630_001, carpeta Drive 1g9Yig1uagfFNXabAJnMbhanOG_-s4x50) esta guardado en modo RGB, no».
- `BUG-HOME-JUANDIGITAL-FOTO-REAL-01` → alternativa **UX_FLUJOS_INTERFAZ**. Motivo: Regresión de avatar; vínculo jurídico secundario. **Cita literal:** «muestra una fotografia de un hombre real junto al nombre "Juan Digital", en».
- `BUG-HOME-PRENSA-REAPARICION-01` → alternativa **CONTENIDO_COMUNICACIONES**. Motivo: Regresión de bloque de prensa sin fuentes publicables. **Cita literal:** «El texto describe una promesa condicional a fuentes verificadas que aun no existen».

## ANALITICA_EXPERIMENTACION — 25 reglas
Categorías: `ANALYTICS`, `ab_testing`, `analytics`, `heatmap`, `tageo`.

**Representativas (5/5):**
- `B2B-RULE-ANALYTICS-001` [VIGENTE]: GA4 mediante GTM.
- `REG_ABT_001` [CANDIDATO]: Framework de feature flags para experimentos.
- `REG_ABT_002` [VIGENTE]: Un experimento activo por pantalla máximo.
- `REG_ABT_003` [VIGENTE]: Tamaño mínimo de muestra antes de leer resultados.
- `REG_ANL_001` [CANDIDATO]: Herramienta principal de analytics.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## OBSERVABILIDAD_AUDITORIA — 22 reglas
Categorías: `AUDIT`, `OBSERVABILITY`, `alertas`, `auditoria`, `observabilidad`.

**Representativas (5/5):**
- `B2B-RULE-AUDIT-001` [VIGENTE]: Auditoría inmutable.
- `B2B-RULE-OBS-001` [VIGENTE]: Correlación transversal.
- `REG_ALR_001` [VIGENTE]: Alerta: tasa de OTP verificados cae bajo umbral.
- `REG_ALR_004` [VIGENTE]: Alerta: tasa de error en submit Paso 1 supera 5%.
- `B2B-RULE-AUTH-024` [CANDIDATO]: Auditoría segura de eventos de autenticación.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## GOBERNANZA_INTEGRIDAD — 21 reglas
Categorías: `APPROVAL`, `GOVERNANCE`, `INTEGRITY`, `PRODUCT_GOVERNANCE`, `TESTING`.

**Representativas (5/5):**
- `B2B-RULE-APPROVAL-001` [CANDIDATO]: Política versionada por lote.
- `B2B-RULE-PROD-001` [VIGENTE]: Producción bloqueada.
- `B2B-RULE-SOURCE-001` [CANDIDATO]: Autoridad de fuente y provenance independientes del candidato.
- `B2B-RULE-STORY-READINESS-001` [VIGENTE]: Readiness obligatorio de familias de input antes de crear historias.
- `B2B-RULE-EVIDENCE-001` [CANDIDATO]: Evidencia visual resoluble y vinculada por checksum.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## OFERTAS_CUOTAS — 11 reglas
Categorías: `OFERTAS_CUOTAS`, `oferta`.

**Representativas (5/5):**
- `REG_OFR_001` [VIGENTE]: Oferta representa deuda independiente.
- `REG_OFR_002` [VIGENTE]: Modalidades no son ofertas.
- `REG_OFR_003` [VIGENTE]: Mostrar solo modalidades disponibles.
- `B2B-RULE-INSTALLMENT-PLAN-001` [CANDIDATO]: Identidad de plan y cuota 0 asociada al plan.
- `REG_OFR_010` [CANDIDATO]: Modelo parametrizable de priorización de ofertas.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## ACCESIBILIDAD — 10 reglas
Categorías: `ACCESSIBILITY`, `accesibilidad`.

**Representativas (5/5):**
- `B2B-RULE-A11Y-001` [VIGENTE]: Interacción accesible.
- `B2B-RULE-A11Y-002` [VIGENTE]: Contraste y color.
- `B2B-RULE-A11Y-003` [VIGENTE]: Preferencia de movimiento reducido.
- `B2B-RULE-A11Y-004` [VIGENTE]: Forced colors y alto contraste sin pérdida funcional.
- `REG_ACC_001` [VIGENTE]: Teclado numérico automático en campos de número.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## CARGAS_B2B — 7 reglas
Categorías: `B2B_CARGAS`, `CARGAS`.

**Representativas (5/5):**
- `B2B-RULE-IMPORT-SOURCE-MAPPING-001` [CANDIDATO]: Distribución de fuentes para datos de oferta y plan.
- `B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001` [CANDIDATO]: Carga de cuotas por Excel completo o Excel asistido.
- `B2B-RULE-LOAD-DEBT-TEMPORAL-BASIS-001` [CANDIDATO]: Base temporal de deuda y antigüedad derivada en cargas.
- `B2B-RULE-LOAD-HISTORY-001` [CANDIDATO]: Contrato conductual del historial de cargas.
- `B2B-RULE-LOAD-MULTI-OFFER-001` [CANDIDATO]: Carga completa con muchas ofertas sin segmentación forzada.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

## RETENCION — 1 reglas
Categorías: `RETENTION`.

**Representativas (1/5; solo existe 1):**
- `B2B-RULE-RETENTION-001` [VIGENTE]: Retención gobernada por política central pendiente.

**Pertenencia dudosa:** sin un caso marcado en este triage; no significa ausencia de defectos.

**Criterio:** lectura del título, descripción y alcance; se sugiere reevaluar propietario principal sin cambiar la categoría. Una regla puede ser transversal y tener dos dominios. Ninguna recategorización está aprobada.

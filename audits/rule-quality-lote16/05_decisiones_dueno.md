# Lote 16 — Decisiones del dueño (12 preguntas priorizadas)

**Estado: SUGERENCIA / REQUIERE_REVISION_SEMANTICA.** Orden: riesgo de autorización y dinero → legal/operaciones → UX/gobernanza. Ninguna pregunta equivale a aprobación. Responder en `06_respuestas_dueno.csv`, agregando evidencia y responsable.

## Q01 — ¿Se puede operar MFA mientras AUTH-018 continúa CANDIDATO?

- **Opciones:** A=promover con pruebas; B=mantener dependencia y fail-closed; C=quitar enlace.
- **SUGERENCIA:** B hasta pruebas y autoridad; nunca omitir MFA.
- **Responsable propuesto:** Seguridad/Owner.
- **Evidencia:** SELECT S03, SHA-256 del resultado `8b70da4a3d3b381620473202de4a569d4b09fcfda6b3973e81661c3d2631b46a` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q02 — ¿Cuál es el ledger/snapshot canónico para pagos, cuotas y conciliación?

- **Opciones:** A=reutilizar estructura acreditada; B=diseñar canónico gobernado; C=usar DEMO.
- **SUGERENCIA:** A si existe; B si se prueba que falta; nunca C.
- **Responsable propuesto:** Arquitectura/Finanzas.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q03 — ¿Qué proveedor de pago y frontera PCI están habilitados en producción?

- **Opciones:** A=aprobar binding con QA; B=mantener pago bloqueado; C=usar credenciales/branding DEMO.
- **SUGERENCIA:** B hasta contratos, callbacks y evidencia.
- **Responsable propuesto:** Pagos/Integraciones/Seguridad.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q04 — ¿Quién aprueba gracia, vencimiento, mora y terminación recurrente?

- **Opciones:** A=Legal+Negocio formalizan política; B=ocultar claims de mora; C=inferir plazos.
- **SUGERENCIA:** B mientras se obtiene A; no inventar consecuencias.
- **Responsable propuesto:** Legal/Negocio/Operaciones.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q05 — ¿Qué configuración de pricing/quote y elegibilidad es autoridad?

- **Opciones:** A=config canónica APROBADO/VIGENTE; B=continuar solo DEMO; C=hardcodear valores.
- **SUGERENCIA:** B hasta tener A; nunca C.
- **Responsable propuesto:** Producto/Arquitectura.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q06 — ¿Los 20 pares de parámetros nombran el mismo control o controles distintos?

- **Opciones:** A=documentar sujeto+evento+alcance; B=igualar valores automáticamente; C=ignorar diferencias.
- **SUGERENCIA:** A, conservar umbrales separados mientras se valida contexto.
- **Responsable propuesto:** Seguridad/Observabilidad.
- **Evidencia:** SELECT S04, SHA-256 del resultado `815d9f903189c7fe98c5b6c8ae7a32ca4b061d3422033010140fe60230f2dd3f` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q07 — ¿Se deben corregir las 23 pertenencias dudosas de las 15 familias?

- **Opciones:** A=resolver familia primaria caso a caso; B=conservar propuesta provisional; C=remapear en masa.
- **SUGERENCIA:** A como dictamen documental, sin mutación automática.
- **Responsable propuesto:** Gobernanza/Owner.
- **Evidencia:** SELECT S01, SHA-256 del resultado `59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q08 — ¿Qué textos legales, consentimientos y Anexo I pueden publicarse?

- **Opciones:** A=Legal aprueba texto y evidencia; B=mantener pendientes; C=usar placeholders.
- **SUGERENCIA:** B hasta A.
- **Responsable propuesto:** Legal/Contenido.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q09 — ¿Qué copys, rutas y visuales de Home tienen evidencia publicable?

- **Opciones:** A=validar visual+registro canónico; B=ocultar claims no verificados; C=inventar rutas.
- **SUGERENCIA:** B hasta A; no afirmar aliados/prensa sin fuente.
- **Responsable propuesto:** UX/Legal.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q10 — ¿Qué workflow y SLA confirman settlement y Carta de No Adeudo?

- **Opciones:** A=acordar API/SLA/registros con aliado; B=dejar estado informativo; C=confirmar sin evidencia.
- **SUGERENCIA:** B hasta A; nunca C.
- **Responsable propuesto:** Operaciones/Aliados.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q11 — ¿Qué proveedor IDV step-up respaldará recuperación Cliente?

- **Opciones:** A=seleccionar y probar proveedor; B=mantener step-up condicionado; C=omitir control.
- **SUGERENCIA:** B hasta A; no C.
- **Responsable propuesto:** Seguridad/Integraciones.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

## Q12 — ¿Cómo calibrar señales de riesgo y umbrales sin datos históricos?

- **Opciones:** A=telemetría/baseline; B=definir cifras arbitrarias; C=descartar señal.
- **SUGERENCIA:** A; mantener control cualitativo mientras se valida.
- **Responsable propuesto:** Riesgos/Seguridad.
- **Evidencia:** SELECT S02, SHA-256 del resultado `2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce` (SQL literal en `07_evidencia_select.sql`). Los hechos del SELECT son OBJETIVOS; la selección de opción REQUIERE_REVISION_SEMANTICA.

**Regla de transición:** la respuesta del dueño es una decisión documental; modificar una regla o promover CANDIDATO exigiría otra operación autorizada, evaluación de impacto y readback.

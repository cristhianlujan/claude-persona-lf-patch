# Lote 29 — BRECHAS E2E para producción | B09_E2E

**Dictamen inicial:** `NO-GO / UNVERIFIED`. Base L26 `21/36 REAL_EN_SANDBOX`, 11 sintéticas y 4 no probadas. L29 usa tres variantes **LF** y agrega una entrada SQL segregada de creador/owner, pero ningún ACT-0001 ni servicio oficial. **No inferir avance productivo por una prueba fixture.** La cifra del runner L29 se acreditará solo tras CI.

## Matriz por etapa de 12 — qué cierra IG y qué es externo

| Etapa L21/L26 | Evidencia PG18 de L26 | Brecha concreta antes de producción | Acción del IG (alcance propio) | Dependencia externa / firma | Bloqueos |
|---|---|---|---|---|---|
| **Router** | A/B SINTETICO; SALY NO_PROBADO | Ejecutar ACT-0001/context V2, Gate2, selección de perfil, `CONTEXT_TRANSPORT` sin pasar credenciales ni llamar IG desde Router | Definir contrato esperado de handoff y error | Plataforma/Router y perfil deben demostrar invocación real; dueño autoriza alcance | B09, B08 |
| **Perfil** | A/B SINTETICO; SALY NO_PROBADO | Vincular solicitud/propuesta al perfil correcto por RUN oficial, con contrato de 11 pasos y permisos heredados; sin perfil ejecutor imaginario | Publicar especificación de dependencias y de retorno al perfil | Equipo de perfiles/Producto, IAM/owner del proyecto | B08, B06, B09 |
| **RUN** | A/B SINTETICO; SALY NO_PROBADO | Crear/leer RUN real bajo operación oficial; resolver cohorte B02 (232 vivos frente a 32 prioritarios), B03 (56 con efectos, leases/liveness, preimage) antes de reintentar/cerrar | Validar input/run_id y rechazo de RUN no autorizado | Operaciones/DBA/Runtime: reconciliación por RUN, selectores, firma de cohortes, recibos de efectos y workers | **B02, B03, B09** |
| **IG** | A/B SINTETICO, SALY NO_PROBADO | Probar `input_validate` y `programacion.fn_lf_profile_input_governance_resolve_v1`, binding real, ticket runtime de un solo uso y Edge `input-governance-agent-v1` dentro del RUN | Contratos INPUT_GOVERNANCE, herencia de políticas/reglas, estado y salida RAW, método de bloqueo/retorno | Perfil y plataforma (Edge, ticket issuer/consumer); owner y seguridad verifican transporte | **B09, B08, B05** |
| **Curator** | REAL_EN_SANDBOX L23 SQL | Sustituir comparador SQL simplificado por Curator real, detección de duplicados/conflictos de significado, owner por familia real, evidencia SHA y decisión gobernada | Definición/implementación verificable del Curator, SKILL/spec y casos adversariales | Dueño de regla/familia y juez semántico independiente (NO GPT-6 mismo modelo), IAM | B04, B05, B06, B09 |
| **Validator** | REAL_EN_SANDBOX L7/L8 | Ejecutar juez semántico real con recibos, citas literales exactas, negative cases, independencia y binding al RUN sin atribuirla a L11B | Contrato validator + evidencia, readback y resultado bloqueante | Juez externo/owner; equipos de seguridad/QA | B05, B09 |
| **Retorno perfil** | LF REAL_EN_SANDBOX; SALY SINTETICO | Emitir retorno real `READY/VALIDATOR_RESUME_REQUIRED/HUMAN_DECISION_REQUIRED/BLOCKED` desde IG hacia el mismo RUN; no nuevo Router/segundo RUN | Definir payload, comprobación y reanudación, casos bloqueados | Runtime de perfiles y bridge oficial OIDC, Step70 | B09, B08 |
| **Ejecución** | LF SINTETICO; SALY REAL_EN_SANDBOX solo fixture | Ejecutar de verdad pasos perfil, resolver_refs, origen de autoridad del dueño, sellos firmados; prueba negativa creador=aprobador real, SUPER_ADMIN | Revisar contrato de aprobación y entrada/handoff, no reemplazar escrituras del perfil | Perfiles/Producto/QA + IAM; 11/11 pasos, pruebas e idempotencia reales | B09, B08, B06 |
| **Promoción** | REAL_EN_SANDBOX gate LF L14 | Fuente en vivo carece de B07: `reviewed_at`, `next_review_at`, `successor_rule_code`, `effective_to`; SALY además `lifecycle_state`. Compatibilidad de cuatro funciones LEGADAS B12 no certificada | Propuesta de contrato de estado/sucesión, prueba de gate semántico e invariantes | DBA/Arquitectura diseña migración/backfill/rollback; Plataforma prueba `apply_batch/decide_batch/report/guard`; dueño aprueba cambio | **B07, B12, B09** |
| **VIGENTE** | REAL_EN_SANDBOX L20 | Comprobar fuente/registro reales atómicos, precedencia, RLS/GRANT, origen de owner y período de revisión tras B07; SALY `estado=VALIDADO` no equivale a lifecycle | Especificar invariantes de vigencia y herencia de regla | DBA/Producto/Legal firman versión; QA E2E con readback en entorno autorizado | B07, B05, B12, B09 |
| **Readback** | REAL_EN_SANDBOX L20/L26 | Leer fuente real, registro, evidencia y destino del mismo RUN sin divergir; conciliar 232 RUN/56 con efectos antes de cierres | Contrato de hash/estado/duplicado/snapshot/resultado bloqueado | Runtime/DBA Operaciones + QA acreditan idempotencia real | B02, B03, B09 |
| **Cierre** | REAL_EN_SANDBOX L24/L26 recibo | Cierre oficial vía bridge/canonical writer, Step70/OIDC y `lf_profile_execution_terminal_authority_receipt_v1`, mismo RUN; no aceptar SQL fixture como recibo real | Contrato de condiciones y evidencia mínima para que IG libere al perfil | Plataforma, escritor oficial, owner, auditor independiente; prueba de restauración y backup | **B09, B08, B13, B14** |

## Diferencia precisa de responsabilidad

**IG puede cerrar (desarrollo de su módulo):** especificación de input_validate, herencia de reglas/políticas, Curator real, trazas RAW y SHA, pruebas semánticas negativas, Validator/decisión, retorno de IG y precondiciones de no-bypass.

**No puede cerrar por sí solo:** Router/11 pasos/ RUN oficial y conciliación B02/B03; identidad Supabase Auth/JWT y asignaciones del dueño B08; DDL/backfill/datos de ciclo B07; regresión de funciones legacy y releases B12; respaldo/PITR/restore; contratación Niubiz, definiciones Q02 y Q04 o firmas externas. **NO crear ruta paralela ni usar service_role por Router**.

## Catorce bloqueos de producción — estado sin cambios

| ID | Bloqueo | Evidencia que falta para cierre | A cargo de | Estado L29 |
|---|---|---|---|---|
| B01 | MFA | Factor y recuperación sin bypass, SAML/IdP, Brevo OTP, política 19, pruebas negativas | Seguridad/Auth/Dueño | ABIERTO |
| B02 | Cohorte RUN | Lista congelada y firmada de RUN a tratar y alcance comprobado | Operaciones/Dueño | ABIERTO |
| B03 | Efectos de RUN | Readback por ID, liveness, idempotencia, recibos de efectos antes de retry/close | Operaciones/DBA | ABIERTO |
| B04 | Familias | 15 LF, 23 asignaciones dudosas y owners confirmados | Gobernanza/Dueño | ABIERTO |
| B05 | Reglas | 57 pendientes, 3 referencias, 20 pares, revisión juez independiente | IG/Seguridad/Legal/Dueño | ABIERTO |
| B06 | Owners | Perfil owner por proyecto y familia autenticado, segregación SUPER_ADMIN | Dueño/IAM | ABIERTO |
| B07 | Lifecycle DB | DDL autorizado, migración, backfill, compatibilidad, readback/rollback | DBA/Arquitectura | ABIERTO |
| B08 | Identidad real | Supabase Auth y JWT→sub→actor→perfil reales, grants/RLS | IAM/Seguridad/Plataforma | ABIERTO |
| B09 | E2E nativo | ACT-0001→perfil→RUN→IG→juez/registro→cierre/recibo terminal real | IG/Perfil/Plataforma/QA | ABIERTO |
| B10 | Negocio | Ledger, pricing, pagos, Niubiz/PCI, condiciones reales | Producto/Finanzas/Pagos/Dueño | ABIERTO |
| B11 | Legal | Reglas, mora pendiente, consentimientos/copy/contratos | Legal/Negocio/Dueño | ABIERTO |
| B12 | Legacy | `apply_batch`, `decide_batch`, `report`, `guard` compatibles con B07 | Plataforma/DBA/QA | ABIERTO |
| B13 | Backup/PITR | Backup físico, PITR y políticas de retención/RPO/RTO probadas | DBA/Continuidad | ABIERTO |
| B14 | Restauración | Ensayo restore aislado con tiempos, integridad y firmas | DBA/Continuidad | ABIERTO |
| **TOTAL** | **14** | **0 acreditados por L29** | | **0/14 cerrados** |

## Requisitos de GO (no cumplidos)

- No avanzar a producción con firmas del dueño sólo **en conversación**. L27 registró 3 decididas pero **0 firmadas**, y L25 continúa como propuestas CANDIDATO.
- Resolver B07/B08/B12/B02/B03 y resto de matriz; 15 gates de checklist L21 requieren recibos, especialmente B09.
- Probar en entorno autorizado un circuito **nativo**, el mismo execution_id, operación gobernada y recibo terminal; no inflar el avance PG18.
- Acreditar juez semántico independiente si el contrato lo exige; este lote usa **GPT-6 mismo modelo**.
- Backup/restore y rollback seguros, publicación por operación gobernada con owner y evidencia inmutable.

**Resultado:** reporte de brechas; **0/14 cerradas; producción NO-GO / UNVERIFIED**.

# LF Input Governance — G4 evaluación ejecutada y plan de impacto condicionado

**Fecha:** 2026-10-28 · **PR:** #3269 · **Rama:** `dev/ig-n4-tremed-cascade-governed-20261028` · **Estado:** selección técnica de componentes para desarrollo; SIN aprobación de autoridad funcional/producción; G5 NO_RECLASSIFY.

## 1. Premisas verificadas y límites

EKB leída antes del ensayo: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`, `CI-MIGRATION-SOURCE-PARITY-001`, `IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`.

**El matcher N-4 aplica reglas. La autorización para EMITIR/MODIFICAR su selector es un asunto diferente.** Es obligatorio no inferir GLOBAL de `es_transversal`, no tomar `reglas_pantallas` como autoridad, no codificar reglas/owners de casos concretos en el motor, no confundir la firma técnica con competencia funcional.

Las 3 alternativas previamente discutidas **no son tecnologías excluyentes**: describen capacidades complementarias existentes, por lo que se evaluaron individualmente y como composición. El veredicto operativo tiene un control adicional distinto del potencial de reutilización.

## 2. Evaluación contra la BD LF real — no únicamente casos sintéticos

SQL **SELECT ONLY** ejecutado con CTE `MATERIALIZED`: `sandbox/lf_contract_gate_test/input_governance/ig_g4_3_alternatives_live_source_evaluation_20261028.sql`.

| Alternativa | Fuente canónica revisada | Evidencia positiva | Evidencia que falta | Veredicto |
|---|---|---|---|---|
| **A. Política versionada + binding operativo** | `public.lf_policy_versions` + `lf_operation_policy_bindings` | 25 versiones, 9 ACTIVE, 69 bindings ACTIVE, **69/69 encuentran política ACTIVE** y tienen SHA/fuente | No hay comprobación de delegación por regla/scope/consumer | Reutilización técnica PASS; **HOLD funcional** |
| **B. Política declarativa de ámbito** | `private.lf_reusable_policy_registry_v1` + N-4 | 1/1 política VIGENTE con condiciones de negocio/canal/capacidad/acción/activo; 14 selectores N-4 ACTIVE | Un `scope` declarado no da derecho a cambiarlo; falta autoridad del emisor | Reutilización técnica PASS; **HOLD funcional** |
| **C. Decisión humana + evidencia** | `private.lf_human_decision_*` + `lf_evidence_ledger_v1` | 7 clases y 11 clasificadores activos; 77 recibos de evidencia, 74 VERIFIED | **0** rutas humanas ACTIVE, **0** políticas de autoridad activas, **0** requests/receipts de decisión, **0** evidence receipts con tipo rule/scope; no hay ruta `RULE_APPLICABILITY_CHANGE` | **NO GO funcional** |
| **Composición A+B+C** | Reutilización selectiva según fase | La infraestructura está presente; no requiere otro motor N-4 ni motor gerencial | Mismo hueco de fuente de competencia y cadena exacta de aprobación | **PASS de diseño de reutilización**, NO GO de activación |

**Protección contra falso PASS:** la consulta no asigna el valor TRUE a una competencia por categoría, origen o nombre. Exige una cadena de solicitud, recibo, ruta y política activa y, aunque aparezca un candidato, **permanece UNKNOWN** hasta que exista el contrato obligatorio de `rule_sha+selector_sha+consumer+scope+issuer`; el SQL no declarará autorización automática por el mero `COUNT>0`. Todos los 4 casos dieron `HOLD_AUTHORITY` en lectura actual. El test está diseñado para detectar evidencia presente, no para generar aprobaciones.

No atribuir el 69/69 a una prueba de G4: es únicamente **integridad referencial del vínculo operativo** a la versión de política.

## 3. Cinco reglas reales y regresiones

`sandbox/lf_contract_gate_test/input_governance/ig_g4_five_rule_source_authority_hold_20261028.sql` ejecutado con CTE materializados:

| Regla (fixture de auditoría) | Selector N-4 actualmente ACTIVE | Gate para **NUEVA ampliación** |
|---|---|---|
| `REG_SES_001` | NO | HOLD |
| `REG_ABT_004` | NO | HOLD |
| `B2B-RULE-AUTH-001` | NO (aunque es transversal) | HOLD |
| `B2B-RULE-DESIGN-001` | SÍ | HOLD solo de ampliación |
| `B2B-RULE-STORY-READINESS-001` | SÍ | HOLD solo de ampliación |

**No revocar ni desactivar selectores históricos por carecer de recibos del nuevo contrato.** Se trata de una obligación de gobernanza para cambios futuros. El orden de selección de familias antes del análisis detallado sigue vigente; 47 familias no se ejecutan en bloque.

### Caso negativo descubierto: Design System vs cobertura de N-4

`public.lf_decisiones_gov` tiene decisión vigente `DEC-LF-DESIGN-TOKEN-TRANSVERSAL-GOV-001` con `raw_payload.scope=LF_ALL_FRONTS`. La regla `B2B-RULE-DESIGN-001` declara también `governance_scope=LF_ALL_FRONTS`. El matcher N-4, sin embargo, da:

| Shell actual | Pantallas | Match N-4 |
|---|---:|---:|
| ADMIN_APP_SHELL | 3 | 3 |
| B2B_APP_SHELL | 19 | 11 |
| CLIENT_APP_SHELL | 20 | **0** |
| Shell desconocido | 16 | **0** |

SQL reproducible: `sandbox/lf_contract_gate_test/input_governance/ig_g4_design_scope_vs_n4_policy_20261028.sql`.

**Interpretación correcta:** no es prueba de error ni licencia para expandir el selector. Puede ser que la política de Design System sea global mientras el selector de Input Governance sea deliberadamente parcial. Exige contrastar el **consumer y la fase** contra el owner, el contexto canónico y la decisión original. El dato muestra por qué un `scope` textual no basta para aprobar automáticamente un selector.

## 4. Mejora que sí se puede impactar: contrato de integración sin tabla ni motor paralelo

**Se selecciona para la rama de desarrollo únicamente este DISEÑO, con gates condicionales:**

1. **Definición/versión de política:** reusar `lf_policy_versions`, el vínculo de operación `lf_operation_policy_bindings` y el patrón de `lf_reusable_policy_registry_v1` para las condiciones declarativas necesarias, sin copiar policy payload a reglas o crear otro owner.
2. **Evaluación de aplicabilidad:** mantener las funciones N-4 actuales como PDP determinista contra target/consumer canónicos; no calcular approvals desde el matcher. `MATERIALIZED` solo en auditorías que reutilizan resultados, no crear materialized view por defecto.
3. **Competencia del emisor:** **requisito aún no resuelto**, descrito como binding lógico `issuer_authority_source_ref + authority_evidence_sha + rule_ref + operation + approved_scope + consumer + revision + validity + revocation`. No crear tabla ni campo nuevo sin comprobar dueño/contrato existente y ratificar fuente independiente del proponente.
4. **Decisión excepcional:** reusar `private.lf_human_decision_*` después de que una política gobernada admita el asunto y el owner firme la autoridad; no forzar `INPUT_GAP_PROPOSAL` como alias ni activar rutas `PENDING_AUTHORITY`. Adquisición de evidencia primero, intervención humana solo por cambios no preautorizados o conflictos materiales.
5. **Multidominio:** no imponer una firma por dominio por defecto. Calcular autoridades requeridas desde obligaciones y delegaciones verificadas; si un contrato exige varias, todas deben aprobar, con veto no delegable y recibos exactos. El registro central limita un recibo por solicitud: cualquier agregación exige revisión antes de implementar.
6. **Publicación técnica:** cumplimiento separado de PR exact head, CI, migración source-first, PASE y readback. Una aprobación humana nunca ejecuta automáticamente la migración.

Esto **impacta el contrato de diseño versionado en dev**, no el esquema ni la producción. No hay aprobación para un policy owner concreto.

## 5. Secuencia de evaluaciones pendientes y condiciones de salida

| Paso | Acción | Evidencia necesaria | Estado |
|---|---|---|---|
| **G3-ACL+** | Verificar el helper candidato bajo roles públicos y autorizados, función INVOKER, IMMUTABLE y rollback en PG aislado | Script `ig_n4_pg17_6_acl_postddl_tests_20261028.sql` incorporado al runner; **nueva ejecución pendiente** | PENDING |
| **G3-E2E** | Probar selección de familia, perfil/consumer bind y resultados N-4 para 13×47 **por selector**, no monolítico | Pruebas independientes con comparación de baseline y casos negativos | PENDING |
| **G4-SOURCE** | Localizar contrato/actor/delegación real por regla, incluyendo excepciones | Fuente competente ratificada y hash versionado | HOLD |
| **G4-COVERAGE** | Calibrar la aparente diferencia Design System `LF_ALL_FRONTS` vs match actual | Decisión del owner por consumer y contexto; negativos B2B/Cliente | HOLD |
| **G4-ROUTES** | Solo tras G4-SOURCE: política de ruta y recibos auténticos en mecanismo central | Revisión independiente, vigencia, revocación, varios dominios si procede | HOLD |
| **G4-INDEPENDENT** | Un segundo revisor repite la admisión y busca falsa autorización | PASS replicable sin reusar resultados del productor | PENDING |
| **G5** | Reclasificar catálogo por datos y retirar herencias solo donde corresponda | G3 integral + G4 aprobado + autorización de publicación | **BLOCKED** |

**No comenzar G5 por 20/20 sintéticos, por 69/69 bindings ni por PASS PostgreSQL aislado G3.**

## 6. Dictamen

- **PASS para incorporar a diseño:** composición de componentes ya existentes. No equivale a implementación ni decisión ratificada.
- **FAIL/HOLD para activación:** ninguna alternativa acredita competencia de firma de scope por regla. La mejora no es un segundo motor: es un **contrato verificable de delegación vigente**, anclado a fuente competente.
- **Acción tomada:** solo nuevas auditorías SQL read-only y fuente/docs/test en rama de desarrollo. No Router, no Supabase writes, no nueva política activa, no G5, no merge.

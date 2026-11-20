# LF Input Governance — G4: decisión de arquitectura sobre autoridad de scope (no ratificada)
**Corte:** 2026-10-28 · **Estado:** `G4_NO_VERIFICADO` / no aprobación gerencial / no reclasificación · **PR:** #3269 (DRAFT). Se leyó EKB antes de ejecutar consultas; sin Router, sin escrituras en Supabase y sin cambios en producción.

## 1. Hallazgo primario, verificado con SELECT ejecutado

**No es válido tratar `applicability_v1.provenance.authority=OWNER_AUTHORIZED_GOVERNED_MIGRATION` como recibo autónomo de autoridad para reglas nuevas.**

La consulta que une cada selector N-4 ACTIVE a los eventos que menciona devuelve:

| Medida | Resultado observado |
|---|---:|
| Selectores ACTIVE vigentes | 14 |
| Tienen ambas referencias `decision_event_id`/`r14_event_id` existentes | 14 |
| Referencias 19948 (dirección de diseño) y 19951 (R14/capability) | 14/14 |
| Al menos una referencia con `acceptance_declared=true` | **0** |
| Al menos una referencia con `production_authorized=true` | **0** |
| Ambas referencias con esos valores expresamente `false` | **14/14** |
| `programacion.human_decisions` existentes | **0** |
| `provenance_receipts.receipt_kind='HUMAN_DECISION'` | **0** |

Se contrastó además el **evento 19962**, posterior, de tipo `READBACK_VERIFICADO`: declara cierre técnico de N-4 y source parity; `acceptance_declared=false` y `production_authorized=false`.

**Interpretación estricta:**
- 19948/19951 son **evidencia histórica de diseño y decisión técnica**, no recibos individuales de aprobación de cada selector y alcance.
- 19962 es **cierre técnico**; no equivale a autorización de cambio funcional, alcance de regla, veto de Seguridad/Legal, ni despliegue futuro.
- Esto **no demuestra que no exista alguna otra autorización en todos los sistemas LF**. Sí demuestra que las referencias actualmente vinculadas no son evidencia suficiente **para generalizar/publicar nuevas reglas**.
- **No desactivar automáticamente** los 14 selectores vigentes por este hallazgo documental: su lifecycle y las decisiones históricas son asunto del owner y de una revisión de integridad con no regresión.
- Una etiqueta de procedencia autoprovista jamás debe ser verificador de competencia/alcance.

## 2. Qué dueños y funciones sí existen

| Fuente existente | Contrato real verificado | Apto como qué | No demostrado |
|---|---|---|---|
| `lf_ops.reglas` + `valor_config.applicability_v1` | Guarda regla, selector/ACTIVE y `provenance` JSON | Dato de alcance publicado | Firma o aprobación auténtica de ese scope |
| `programacion.fn_input_rule_selector_matches_v1` | Verifica gramática parcial, lifecycle en JSON, consumer y match | Matcher determinista de N-4 | Aprobación del owner o validación de recibo |
| `programacion.fn_input_declared_rule_links_v1` | Exige `r.estado='VIGENTE'` y ejecuta matcher | Resolver de vínculos declarativos | Aprobación de expansión o conflictos |
| `programacion.human_decisions` | Relaciona decisión con `execution_id,head_sha,actor_identity,approval_ref,metadata,authority_receipt_id`; tablas vacías | Candidato a reutilizar **si** el workflow de ejecución y competencia lo admiten | Contrato específico de alcance por regla; no hay ejemplo real |
| `programacion.provenance_receipts` y `fn_assert_provenance_receipt` | Vinculan recibo a ejecución, head, subject ref y SHA; no hay `HUMAN_DECISION` | Mecanismo de prueba criptográfica/referencia de decisión | Firma de owner de scope hoy |
| `programacion.authority_challenges/attestations` | Roles, nonce, head_sha, actor/attestation | Fuente posible de prueba de identidad y competencia | Registro activo de gerencia para `RULE_APPLICABILITY` |
| `programacion.fn_source_rule_authority` | Autoridad de *estado* de regla y rule-set (VIGENTE/APROBADO, pendiente=false) | Guard de regla fuente | Autorizar su aplicabilidad transversal |
| `public.lf_eventos` | Evidencia de diseño/implementación, con eventos N-4 | Historia/continuidad | Autoridad criptográfica para un scope |
| `public.lf_capability_registry` | Catálogo de capabilities, `owner_scope` y entry guard | Referencia de patrón de ownership a investigar | Dueño automáticamente de reglas N-4 |

**Separación de contratos:** aprobación de release de IG (`INPUT_GOVERNANCE_EXACT_RELEASE`) ≠ aprobación funcional de una regla o excepción; un `rule.status=VIGENTE` ≠ selector autorizado; source parity del SQL ≠ aprobación gerencial.

## 3. Propuesta mínima G4 sin crear otro motor

No introducir una segunda tabla ni “motor gerencial” a partir de estos resultados.

**Contrato requerido por cada selector que amplía/cambia cobertura:**

`rule_ref + rule_sha256 + selector_sha256 + scope/coverage_sha256 + consumer_code + authorizer_role + competence_ref + decision_type + conditions + negative_tests_sha256 + evidence_ref + source_head_sha + receipt_id + validity/expiry/revocation`.

Etapas:
1. **Curator** propone y evidencia, con reglas alternativas/contraejemplos; propone ámbito y reglas de composición.
2. **Validator independiente** comprueba capacidad, tests negativos y diff contra la cobertura vigente; firma su propio resultado (no reutiliza PASS del productor).
3. **Inspector de cobertura basado en datos fuente** calcula el verdadero alcance y lo ata a SHA. La entrada `is_broad_coverage` del solicitante **nunca** es prueba.
4. **Autoridad funcional/gerencia** decide por competencia; Seguridad/Legal pueden vetar materias de su dominio; la aprobación condicionada exige condiciones comprobables. Sin sello real: HOLD.
5. **Mecanismo de recibo existente** se reutilizará solo cuando el owner de ese mecanismo confirme qué esquema/canal admite scope por regla; verificar los guards `execution_id/head_sha/subject_ref/sha` antes de cualquier binding.
6. **Publicación técnica N-4** acepta únicamente selector con decisión versionada y recibo comprobados; N-4 luego evalúa automáticamente nuevos destinos pertinentes sin solicitar aprobación en cada pantalla.
7. **Curator/Validator** reevalúan si cambian fuente, versión, condiciones, consumer, owner o política superior. No invalidar todos los selectores a ciegas.

Los campos son **un contrato lógico**, no una tabla/enum nuevos; revisar autoría, permisos y fuente antes de implementar. El desarrollo no llama al Router ni crea nuevos registros de autoridad.

## 4. Criterio de cierre G4 objetivo

**Positivos exigidos:** aprobación por owner legítimo con alcance exacto y vigente; reutilización de selector dentro de ámbito aprobado; excepción competente con límites; norma legítimamente amplia aprobada de modo expreso.

**Negativos exigidos:** ausencia de firma/recibo, marca autoprovista de autoridad, event-only sin firma, SHA cambiado, regla CANDIDATO, selector UNRESOLVED, ampliación fuera del ámbito, consumer incorrecto, autoridad vencida, evidencia vieja, veto legal/seguridad y política superior no delegable. **HOLD** sin alterar otras reglas.

`G4 PASS` requiere **adaptador de autoridad real verificado y probado con un recibo auténtico** y readback, no tests con doubles.

## 5. Dependencias comprobadas y pendientes

- SQL read-only audit ejecutado: `sandbox/lf_contract_gate_test/input_governance/ig_n4_scope_authority_readonly_audit_20261028.sql`, tres SELECT, resultados 14/14 refs presentes pero sin `acceptance_declared=true`.
- EKB: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`.
- Test JS de contrato con dobles 25 casos de admisión y 10 de composición: no es validación operativa. `READY_FOR_GOVERNED_PUBLICATION` en ese artefacto significa **candidato**, no despliegue.
- Compilación/ejecución de SQL en PostgreSQL aislado: **NO VERIFICADO**; este entorno no tiene `postgres`/`psql` y la instalación de paquetes no fue posible. La comparación de CTE read-only no sustituye esa verificación.
- Antes de G5: cerrar el owner de publicación, auditoría de scope y validación independiente, sin adaptar `human_decisions` a ciegas.

**Dictamen actual:** `G4_NO_VERIFICADO`, `G3_PG_ISOLATED_NO_VERIFICADO`, `G5_NO_RECLASSIFY`, PR #3269 no merge/no deploy.

# LF — Remediación de 166 reglas CANDIDATO, corte 2026-11-14

Estado: DOCUMENTAL / SOURCE_FIRST. Sin solicitudes ni promociones aplicadas.
Fuente: SELECT `lf_ops.reglas`, `lf_ops.reglas_pantallas`, JSON recursivo de `valor_config`, `pg_get_functiondef`. La función oficial `programacion.fn_t_remed_rule_promotion_verdicts_v1(5,NULL)` retorna 42501 al rol de inspección; 0 PASS/166 HOLD es **reconstrucción**, no recibo de la función.

| Criterio incumplido | N | Responsable de subsanar | Acción verificable |
|---|---:|---|---|
| USED_BY_ENOUGH_SCREENS | 148 | Product Director + UI Architect | Revisar asociaciones reales pantalla–regla, comprobar aplicabilidad; no vincular pantallas ficticias ni flexibilizar umbral 5 sin decisión gobernada |
| NO_PENDING_MARKER | 66 | Ingeniería + responsable funcional de fuente | Resolver referencias canónicas/legales/copy pendientes, conservar fuente y evidencia de cierre |
| NO_PENDING_DECISION | 57 | Owner (decisión real) + Product Director (curación) | Desglosar pendientes y registrar resolución verificable; no convertir aprobación general del lote en decisión específica |
| HAS_STATED_REASON | 3 | Product Director | Incorporar razón sustentada, bajo gobernanza: 503 B2B-RULE-AUTH-043; 609 B2B-RULE-CONFIG-001; 610 B2B-RULE-PAGE-HEADER-001 |
| NO_DUPLICATE_ACTIVE_RULE | 0 | Ingeniería de datos | Mantener control de configuración duplicada |

Las causas **se superponen**. Ninguna de las 166 satisface todos los cinco criterios; no existe lote elegible para `request_v1`. Lista individual exacta en `lf_candidate_verdicts_reconstructed_20261114.json`.

## Decisiones del owner (NO asumir resueltas)

| ID | Código | Pendiente documentado |
|---:|---|---|
| 390 | B2B-RULE-THEME-002 | Definir tokens dark_mode_surface/card/text |
| 421 | B2B-RULE-LEGAL-001 | Decisión funcional documentada, flag pendiente; recertificar reconciliación de estado |
| 422 | B2B-RULE-INSTALLMENT-001 | GOVERNED_CANDIDATE_REQUIRES_REVIEW |
| 617 | B2B-RULE-INSTALLMENT-PLAN-001 | GOVERNED_CANDIDATE_REQUIRES_REVIEW |
| 620 | B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001 | GOVERNED_CANDIDATE_REQUIRES_REVIEW |
| 648 | B2B-RULE-LOAD-DEBT-TEMPORAL-BASIS-001 | PENDING_PHYSICAL_MAPPING_ONLY; reconciliar esquema físico existente |

Adicionales con `valor_config.owner_decision_identity_verified=false`:
**438 B2B-RULE-AUTH-019**, **439 B2B-RULE-AUTH-020**, **440 B2B-RULE-AUTH-021**, **577 B2B-RULE-AUTH-047**.

## Dependencias técnicas

1. **Lectura:** Ingeniería aplica wrapper público de solo lectura para service_role, sin grants amplios; 42501 del inspector permanece como denegación legítima. PR #3898.
2. **Solicitud:** Product Director debe producir Step50/60 y Step70 con juez **realmente independiente** más fuente/hashes vinculados; no generar PASS a mano.
3. **Decisión y aplicación:** Identity/security vincula aprobación humana autenticada al lote; `UNVERIFIED_CHAT_DECLARATION` no verifica al owner. Solo con IDs PENDING reales: `decide_batch_v1` → `apply_batch_v1`, guard SHA y SELECT readback.
4. **QA:** PR #3905 corrige referencia migración Step40 y readiness PG L16; la prueba de #3898 con revisor simulado ya dio PASS PG17.6/18.7 ROLLBACK, sin certificar independencia real.

Readback a exigir: conteos antes/después de `lf_ops.reglas`, `public.lf_rule_promotion_v1` y recibos de paso 70 y lote. No declarar promoción si no hay filas aplicadas.

# E21 — SELECT REAL de scoring A/B/C/D por regla (L1+L2)

**Fuente:** `public.lf_rule_promotion_score_v1('EXEC-PROFILE-GATE2-95968F50D6214EADB117E45E',rule_code)` y `lf_ops.reglas` vía Supabase **solo lectura**, 2026-11-16. La ejecución es HISTÓRICA, `AUTHORIZED_NOT_EXECUTED`; no es nueva ni editable.

**Nota:** la tabla `lf_ops.regla_behavior_tests` no contiene PASS PG17/18 de Login para estas reglas; el scorer A requiere además `is_bound` por Steps 40/50/60/70. No atribuir 40 puntos por tests contractuales ni por CI sin recibo.

| Lote | Código | Estado | A/40 | B/30 | C/20 | D/10 | Total | Decisión scorer | Hard block |
|---|---|---|---:|---:|---:|---:|---:|---|---|
| 1 | `B2B-RULE-AUTH-001` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-002` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-003` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-004` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-005` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-006` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-007` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-008` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-011` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-012` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-013` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-014` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-015` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-016` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-017` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-018` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-019` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-020` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-021` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-022` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-023` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-024` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-025` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-026` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-027` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-028` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-029` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-030` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-031` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-032` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-033` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-034` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-035` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-036` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-037` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-038` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-039` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-040` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-041` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-042` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-043` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-044` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-045` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-AUTH-046` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-047` | CANDIDATO | 0 | 0 | 0 | 0 | 0 | BLOCKED | true |
| 2 | `B2B-RULE-AUTH-048` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-AUTH-049` | CANDIDATO | 0 | 0 | 0 | 0 | 0 | BLOCKED | true |
| 2 | `B2B-RULE-AUTH-STATE-001` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-RATE-001` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 2 | `B2B-RULE-SECURITY-BASELINE-001` | CANDIDATO | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-SESSION-001` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-SESSION-002` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |
| 1 | `B2B-RULE-TIMEOUT-001` | VIGENTE | 0 | 0 | 20 | 0 | 20 | BLOCKED | false |

El estado real `VIGENTE` anterior no se reabre por un score actual 20 en una corrida distinta. `MANUAL` es decisión de scoring, no estado `lf_ops.reglas` sin operación gobernada.

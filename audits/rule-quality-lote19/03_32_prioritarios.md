# Lote 19 — 32 RUN priorizados para evaluación del dueño

**Advertencia:** estos 32 NO están acreditados como la cohorte original mencionada por el dueño. El universo SQL vivo contiene **232** `IN_PROGRESS`. Este subconjunto es una **selección propuesta de prioridad**, reproducible: clase B > C > A > D, luego menor `inactividad_dias` y `run_id`. Se entrega el **universo completo de 232** en `01_runs_232_readback.csv` para no omitir ninguno.

**Evidencia OBJETIVO:** consulta R01 íntegra en `02_runs_diagnostic_select.sql`; SHA-256 de las 232 filas JSONB `b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0`. **Clases REQUIERE_REVISION_SEMANTICA.**

| # | RUN ID | Operación | Perfil | Antig. días | Último paso | Lease | Efectos | Clase |
|---:|---|---|---|---:|---|---|---|---|
| 1 | `EXEC-SKILL-1452A11A05CEC8B2` | ACTUALIZACION_PERFIL_LF | PERFIL-UI-ARCHITECT | 7.6 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 2 | `EXEC-SKILL-92E56FF772B6A3FD` | ACTUALIZACION_PERFIL_LF | PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | 7.8 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 3 | `EXEC-SKILL-5C4A07F52DA71B3C` | ACTUALIZACION_PERFIL_LF | PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | 8 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 4 | `EXEC-DB-TRAIN-PR3438-20261101020345-R41263578875` | ACTUALIZACION_DB_LF | NO_REGISTRADO | 11.8 | patch (PASS_CLEAN) | vencido | guard SUCCEEDED=1 | B |
| 5 | `EXEC-ACTUALIZACION-PERFIL-LF-OIDC-a4b04585-e518-482c-ab02-855a807ee0ae` | ACTUALIZACION_PERFIL_LF | PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | 13.2 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 6 | `EXEC-DB-TRAIN-PR2867-20261017035500-R39000482544` | ACTUALIZACION_DB_LF | NO_REGISTRADO | 26.7 | patch (BLOCKED_BY_ENFORCEMENT) | vencido | guard SUCCEEDED=1 | B |
| 7 | `EXEC-CHECKPOINT-OP-BOOTSTRAP-20261014-001` | VULNERABILITY_COVERAGE_REPAIR_LF | NO_REGISTRADO | 28.9 | — (—) | sin lease | sinks=1 | B |
| 8 | `EXEC-BOOTSTRAP-EDGE-FUNCTION-OP-20261014-001` | VULNERABILITY_COVERAGE_REPAIR_LF | NO_REGISTRADO | 29.7 | — (—) | sin lease | sinks=1 | B |
| 9 | `EXEC-DB-MIGRATION-NAMING-POLICY-20261012-001` | ACTUALIZACION_DB_LF | NO_REGISTRADO | 30.9 | — (—) | sin lease | sinks=1 | B |
| 10 | `EXEC-BOOTSTRAP-PASE-F07-X03-20261007-001` | VULNERABILITY_COVERAGE_REPAIR_LF | NO_REGISTRADO | 34.2 | — (—) | sin lease | sinks=1 | B |
| 11 | `EXEC-DB-LEDGER-NAME-RECONCILE-20260930080103-20261001` | ACTUALIZACION_DB_LF | NO_REGISTRADO | 41.9 | patch (PASS_CLEAN) | vencido | guard SUCCEEDED=1 | B |
| 12 | `EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260923-005` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 50.8 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 13 | `EXEC-RUNTIME-BOUND-SEMANTIC-JUDGE-20260922-001` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 50.9 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 14 | `EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-001` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 50.9 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 15 | `EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-003` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 50.9 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 16 | `EXEC-RUNTIME-SEMANTIC-JUDGE-WIRING-20260922-004` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 50.9 | github_readback (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 17 | `EXEC-RUNTIME-PROFILE-SEMANTIC-JUDGE-20260921-012` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | regression_after (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 18 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-010` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | regression_after (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 19 | `EXEC-RUNTIME-PROFILE-SEMANTIC-JUDGE-20260921-011` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | regression_after (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 20 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-APPLY-20260921-010` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | pre_write_execution_binding_gate (STEP_PASS_WITH_EVIDENCE) | sin lease | sinks=2 | B |
| 21 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-008` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | regression_after (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 22 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-009` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | regression_after (STEP_PASS_WITH_EVIDENCE) | sin lease | github_write=1 | B |
| 23 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-005` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.7 | semantic_judge (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 24 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-006` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.6 | semantic_judge (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 25 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-004` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.7 | semantic_judge (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 26 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-003` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.7 | semantic_judge (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 27 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-001` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.7 | semantic_judge (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 28 | `EXEC-RUNTIME-PROFILE-BASELINE-FREEZE-20260921-002` | ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF | NO_REGISTRADO | 52.7 | semantic_judge (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 29 | `EXEC-LF-PROFILE-NATIVE-RESOLVER-20260919-001` | ACTUALIZACION_DB_LF | NO_REGISTRADO | 54.2 | verify (PASS_CLEAN) | sin lease | guard SUCCEEDED=1 | B |
| 30 | `EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001` | ACTUALIZACION_DB_LF | NO_REGISTRADO | 54.8 | — (—) | sin lease | sinks=2 | B |
| 31 | `EXEC-ACTUALIZACION-SKILL-PROFILE-CREATOR-S22-PL005-20260916-001` | ACTUALIZACION_SKILL_LF | NO_REGISTRADO | 57 | deterministic_validation (BLOCKED_STEP_NOT_CLEAN) | sin lease | github_write=1 | B |
| 32 | `EXEC-S30-R19-AUTONOMOUS-20260915-001` | EJECUCION_ESTRATEGIA_LF | NO_REGISTRADO | 58.3 | pre_write_execution_binding_gate (PASS_CLEAN) | vencido | guard SUCCEEDED=3 | B |

**Riesgos por clase (REQUIERE_REVISION_SEMANTICA):**

- **A (6 global):** aunque consta declaración no-write y no hubo efectos en fuentes inspeccionadas, podrían existir efectos fuera del inventario; confirmar por alcance antes de proponer cierre.
- **B (56 global):** posible efecto parcial o completado con RUN abierto; cerrar/reintentar sin reconciliar podría duplicar escritura, cobro, registro o promoción. Cruce de `SUCCEEDED`, `github_write` y sinks no equivale a validación total del resultado.
- **C (4 global):** pasos recientes en ventana de 48 horas o lease vivo. No hay lease vivo en la lectura; el criterio reciente no es heartbeat acreditado.
- **D (166 global):** no se acredita ni ausencia de efectos ni actividad; comprobar fuentes faltantes, identidad del worker y contratos antes de actuar.

### Universo y observaciones
- 232 RUN `IN_PROGRESS`: A=6, B=56, C=4, D=166. `lease_owner`=8; leases vigentes=0; vencidos=8. 78/232 con al menos un paso. **Los datos provienen de R01; las etiquetas de riesgo son inferencias.**
- `ultimo_paso` es el último registro de paso observado; no demuestra el último evento fuera de Supabase. `perfil` se lee del manifiesto o del `target_code` con prefijo `PERFIL-`; si no hay fuente, `NO_REGISTRADO`.
- Fuentes de efectos buscadas: `lf_operation_effect_guard`; pasos `github_write`/write; activos, cards, KB, capturas, homologación, pipeline, decisiones, registry, producto y promoción. No se ha auditado todo el almacenamiento posible ni todos los commits GitHub o servicios externos.
- **El usuario referenció 32 RUN. No existe filtro recibido o verificado que seleccione exactamente esa cohorte.** Este top 32 no substituye el inventario completo ni autoriza cambios.

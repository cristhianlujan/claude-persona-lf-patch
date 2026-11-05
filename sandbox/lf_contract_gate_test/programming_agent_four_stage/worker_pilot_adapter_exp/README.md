# Piloto Worker v0.8 — adaptador PG-07 V2 → WorkerTaskSpec V1

**Estado:** `CANDIDATE_SANDBOX_ONLY / PENDING_CLAUDE_RETEST`. **Sin modelo, sin clave, sin workflow ni gasto.** PR draft apilado sobre #3672. No modifica `cristhianlujan/programming-agent`, Supabase, roles, skills productivos, main ni rutas `.github/workflows/`.

## Pin exacto

Worker: `cristhianlujan/programming-agent@298307e2f9cac72abfde2b181f3554b0e28bad24`.

Fuentes ejecutables:
- `src/programming_agent_runner/worker_spec.py` — `parse_worker_task`, esquema estricto **1**, 14 campos exactos.
- `src/programming_agent_runner/worker_cli.py` — manifiestos de calidad, readback y oráculo más hashes requeridos; `--max-output-tokens` explícito.
- `src/programming_agent_runner/worker_receipt.py` — recibo sellado; precios **fuera** del recibo.
- `src/programming_agent_runner/programming_quality.py`, `programming_quality_hardening_v2.py`, `worker_oracle.py` — validadores originales de manifiestos.

PG-07: `programmer_profiles_exp/stack_skills_exp/project_stack_resolver_exp.py` y `selector_experimental/integration/pg05_profile_assignment_bridge_v1.py` en #3672.

## Encaje 14/14

| Campo Worker v1 | Origen PG-07 v2 / decisión |
|---|---|
| `schema_version` | Traducido explícitamente 2 → 1 |
| `task_id` | Igual, también liga sobre externo |
| `objective` | Objetivo original + rol completo con SHA + tres o más reglas de **cada skill** con ID, texto, URL oficial y SHA; máximo 18 000 bytes, sin truncar |
| `base_head_sha` | Igual, requiere verificación exacta del repo |
| `source_snapshot_sha256` | Igual, nunca inventar huella |
| `context_path_patterns` | Igual, sin incluir oráculo |
| `write_path_patterns` | Igual y compara con PG-07 lote resuelto |
| `protected_path_patterns` | Igual, requiere pruebas protegidas |
| `acceptance_commands` | Metadatos **aportados por owner**, estrictamente vinculados a los textos originales; se traduce a nombre, argv, timeout y max_output_bytes. No ejecutar shell, pipes, redirecciones o expansiones |
| `max_attempts` | Igual, obligatorio 1 |
| `max_patch_bytes` | Igual, máximo 20 000 |
| `max_changed_files` | Igual, máximo 3 |
| `max_context_bytes` | Igual, máximo 60 000 |
| `allow_deletions` | Igual, siempre false |

**Fuera de WorkerTaskSpec V1:** `expected_change`, `human_story`, `functional_contract`, `scope`, `required_tests`, dependencias, evidencias, límites adicionales y trazabilidad PG07. Se guardan en `extra.envelope.json` con `task_sha256`, `pg07_sha256`, `task_id`, `production_authority=false`, `envelope_sha256`. No ampliar los 14 campos para transportar estos datos.

## Materialización fuera del repositorio

La función `materialize_external` recibe tres objetos **ya declarados y aprobados por el propietario**: `quality-plan`, `readback-manifest`, `holdout.oracle`. Es deliberadamente **fail-closed** si falta alguno o es inválido. Crea un directorio privado nuevo fuera del repositorio y escribe archivos con modo 0600. Después ejecuta los validadores/lectores **reales** del checkout pinneado a 298307e, verifica digests y coherencia con task_id/HEAD, y limpia el directorio completo si hay error. No sintetiza pruebas ocultas, clasificaciones de riesgo ni declaraciones `N/A`. El oráculo no entra en objetivo, paths de contexto ni sobre de la tarea del modelo. Los paths externos se comunican al CLI solo por argumentos de ejecución fuera del modelo.

`build_worker_command` genera **solo argv**, no ejecuta: provider `anthropic`, modelo explícito aprobado, SHA de tres manifiestos, `--max-output-tokens 8000`, y rutas externas. Antes vuelve a verificar límites y SHA de sobre. Esta implementación es un adaptador, **no el workflow** ni un permiso para cargar claves.

## Gasto

`pricing_v1.json` conserva la tabla **aportada por Paulo como supuesto**, no tarifas verificadas del proveedor: Haiku 5.5 USD 0.10/0.50 por millón de tokens de entrada/salida, Sonnet 5.5 USD 2/10. `worker_cost_report_v1.py` genera un archivo adicional con `usage.input_tokens`, `usage.output_tokens`, costo por intento y total. **Nunca edita ni resella el recibo del Worker.** Si el CLI endurecido no expone los contadores por intento, bloquea `ATTEMPT_USAGE_MISSING`; falta resolver esa exposición con evidencia real antes de cualquier corrida con dinero.

## Comando de auditoría (sin modelo)

Se requiere un checkout LOCAL limpio del Worker en el commit exacto:

```bash
export WORKER_298307E_CHECKOUT=/ruta/al/checkout/programming-agent
test "$(git -C "$WORKER_298307E_CHECKOUT" rev-parse HEAD)" = "298307e2f9cac72abfde2b181f3554b0e28bad24"
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/worker_pilot_adapter_exp/test_pg07_to_worker_v1_adapter.py
```

Prueba con `parse_worker_task()` **real**, campos extra rechazados, reglas/hashes, shell/pipe bloqueado, topes, falta de manifiestos y cálculo externo de costo con usage **simulado exclusivamente para test de aritmética**. No declara tokens gastados reales.

**Pendientes de autoridad:** Claudio/Claude debe ejecutar y calificar este HEAD; luego el propietario debe proporcionar los tres manifiestos genuinos y demostrar acceso a usage por intento del recibo CLI endurecido. Solo entonces reconsiderar workflow manual, presupuesto, separación de secrets y PR draft PASS-only. `PG00_STANDARD_TEXT_UNAVAILABLE` sigue siendo bloqueo normativo de LF.

## Corrección de paths canónicos (auditoría Claude)

El Worker `298307e` rechaza `tests/protected/`: no es equivalente de manera automática a `tests/protected/**`. Por ello `adapt(..., worker_checkout=...)` invoca **las funciones reales** `canonical_relative_path` y `_validate_pattern` importadas del checkout fijado al HEAD exacto, sobre **todos** los valores de `context_path_patterns`, `write_path_patterns` y `protected_path_patterns`. Cualquier rechazo produce `ADAPTER_PATH_NOT_CANONICAL` sin normalizar el dato. El generador de argv también vuelve a llamar al parser real del Worker. `test_pg07_to_worker_v1_adapter.py` comprueba la barra final en las tres listas y un patrón `**` mal formado.

La base #3672 también corrige los tres roles y sus casos a `tests/protected/**` y añade `NON_CANONICAL_PATH` como séptimo eval. El checkout auditado debe contener ambas correcciones. Ningún estado PASS se afirma hasta la nueva ejecución independiente de Claude.

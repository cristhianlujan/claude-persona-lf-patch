# D-08 — Frontera de autoridad PIP-1 → ChatGPT (Paulo)

**Estado: DISEÑO / NO OPERACIONAL.** Verificación de fuentes 31/10/2026. No modifica la lógica PIP-1 ni las tablas PG.

## Evidencia existente; no duplicar
1. Núcleo Carril D `lf/pip1-core-isolated-d07`, `pip1_core/core.py`: las transiciones con `operational=True` y las acreditaciones reales siguen bloqueadas con `EXTERNAL_RECEIPT_AUTHORITY_NOT_INTEGRATED`. Las 50 pruebas locales PASS no son autoridad operativa.
2. `sandbox/lf_contract_gate_test/engineering_checkpoint_closure/checkpoint_step_judges_v1.py` en main: seis jueces de cierre que **requieren** `CANONICAL_INDEPENDENT_READBACK` fresco y autoridad del Router; su propio encabezado prohíbe crear autoridad desde el input. **No sustituirlos ni invocarlos como si validaran PIP-1**.
3. `sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py`: verificador específico de `LF_MIGRATION_TRAIN_RECEIPT_V1`; no es verificador genérico de PG.
4. `programacion.fn_analysis_pg01_exact_receipt_guard_v1` existe en Supabase para la frontera Análisis→PG-01; su firma no es la del cierre de cualquier checkpoint.
5. `programacion.fn_programming_simple_checkpoint_transition_v1` exige un recibo PASS almacenado para run/unidad/CP/binding exactos. **Pertenece al Simple Executor** y el plan PG sigue sin bindings; no adaptarlo por su nombre.

## Interfaz requerida y quién la debe acreditar
| Dato | Fuente confiable requerida | Condición negativa |
|---|---|---|
| `run_id`, `execution_id` | Registro canónico de run del orquestador operativo aprobado | Ningún ID suministrado únicamente por ChatGPT |
| `plan_code`, `unit_code`, `checkpoint_code` | Plan y checkpoint canónicos leídos directamente | Rechazar identidad cruzada, duplicados y CP ajenos |
| `inventory_sha256`, `head_sha`, otros pins | Inventario/commit fijados en fuente autorizada y contrastados | Rechazar drift, histórico y pins del input |
| `provider_ref`, `receipt_sha256`, `verdict` | Recibo persistido por proveedor independiente y lectura fresca | Rechazar fixtures, reciclaje de PASS y SHA autocertificado |
| admisión, rol y capacidad de escritura | Runtime/Router/guardia operativos **aprobados** | No inferir de un booleano o estado del ledger |
| cierre del checkpoint | Transacción/regla existente con readback independiente | No marcar `DONE` desde adaptador del chat |

## Decisión
- El flujo `pg_chat_readback_flow.py` y `pip1_core_object_bridge.py` permanece **observacional**.
- Un `DONE` del ledger no acredita `SUCCEEDED_ACCREDITED` de PIP-1; solo puede disparar una solicitud de readback independiente.
- **No implementar un nuevo verificador operativo** sin identificar el contrato de activación y quién emite el recibo canónico para PIP-1.
- Reutilizar los seis jueces como **referencia de frontera**, no como permiso transitorio.
- El proyecto aún no tiene una ejecución PIP-1 auténtica vinculada a los 108 checkpoints PG. El Simple Executor no admite este plan por bindings ausentes.

## Próxima tarea concreta de ingeniería
1. Confirmar con Carril D y responsable de autoridad: runtime operativo de PIP-1, almacén del run, proveedor verificador, vinculación a Router y operación exacta, sin crear un segundo ledger.
2. Localizar registro canónico y contrato preciso del recibo PG por checkpoint; contrastar el origen y su writer.
3. Construir una **prueba negativa de suplantación** (mismo hash, run diferente; mismo run, head diferente; fixture PASS; fuente caducada); primero en sandbox y con revisión independiente.
4. Integrar solo después el readback autenticado del verificador existente; no autocertificar el resultado dentro del chat.
5. Mantener PR #3402 Draft y no mezclarlo hasta verificar PASE exact-HEAD y retirar cualquier afirmación de autoridad operativa.

## Estado de verificación
- Funciones de Supabase inspeccionadas por catálogo en modo RO.
- Archivos `checkpoint_step_judges_v1.py` y `train_receipt_verifier/README.md` recuperados de `main`.
- Este documento no afirma ejecución ni aprobación de un verificador PIP-1.

# A16Q_C2 — Traza Router → consumidor: baseline verificable y contrato de prueba

- Plan: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1`; unidad `A16Q` (807); work item `PA-AN-Q16` (1126); checkpoint `A16Q_C2` (1605).
- Alcance: investigación de arquitectura, comprobaciones de solo lectura; **este documento NO constituye PASS E2E, activación, aplicación de perfiles, DEMO funcional ni promoción GOLDEN**.
- Autoridad: Supabase (registros, reglas, operaciones, recibos), GitHub (código técnico). Fuente Git de inspección: `bfb9d42e2187bfaf10f8a9279e141eb50a82e786` y blobs citados. Lecturas verificadas 2026-10-16.
- Antecedente: C1 `DONE` con inventario `ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md`; no sustituye la prueba material C2.

## 1. Tres solicitudes de alcance: salida REAL del Router, sin efectos

La ejecución de `public.lf_router_resolve_v1(p_request_text)` no tuvo escrituras ni despachó modelos.

| Caso arquitectónico | Entrada de prueba acotada | Resultado live | Interpretación |
|---|---|---|---|
| PARTIAL_SCREEN_DEMO | "Crear una demostración parcial del inicio de sesión B2B para evaluar arquitectura, sin crear perfiles, escribir cambios ni desplegar." | `BLOCKED / BLOCK_OPERATION_NOT_REGISTERED`; `AUDIT / CREATE` | Seguro al negar ejecución; clasificación incorrecta del alcance solicitado. No implementar demo en A16. |
| FULL_SCOPE | "Diseñar de extremo a extremo la pantalla de inicio de sesión B2B y su flujo completo, primero en análisis de solo lectura." | `BLOCKED / BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED`; `SKILL / ASSET_INSPECTION` | Bloqueo seguro, pero deriva tipo/acción inconsistente. |
| TARGETED_MODIFICATION | "Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a ‘Acceder’, sin modificar autenticación, validaciones ni otras partes de la pantalla." | `BLOCKED / BLOCK_EXECUTOR_CAPABILITY_UNATTESTED`; candidato `PERFIL-UI-ARCHITECT`, `READ_ONLY` | La candidatura no es ejecución autorizada ni target de escritura. Preservar exclusiones en siguiente nivel. |

La unidad A16 analiza cómo debe ser consumida la ruta. La IMPLEMENTACIÓN de selección dinámica de perfiles, nuevos DEMOS o pantallas pertenece a trabajos posteriores; aquí solo se usan solicitudes como casos de contrato.

## 2. Traza histórica REAL de una ejecución de perfil (comprobada)

`private.lf_profile_runtime_queue_v1.request_id=152a3d60-02b0-4bbf-b9fa-b83995b295d6`.

- `status=SUCCEEDED`, `profile_code=PERFIL-UI-ARCHITECT`, `operation_code=EJECUCION_PERFIL_LF`, `receipt_type=PROFILE_EXECUTION_RECEIPT_V1`.
- Texto literal persistido: **304 caracteres**. Hash SHA-256 calculado sobre bytes UTF-8: `d98ba31bb99ab1bf230be579d46479ece5960888b6c077070adc7c11ad4fccca`.
- `receipt.input_sha256` coincide EXACTAMENTE con ese hash. `public.lf_operation_execution.manifest.input_sha256` contiene el mismo valor con prefijo `sha256:`. Esto acredita identidad de input en los tres soportes, NO entrega íntegra al modelo.
- Recibo runtime: `execution_id=EJECUCION_PERFIL_LF:152a3d60-02b0-4bbf-b9fa-b83995b295d6`; `execution_origin=MODEL_RUNTIME`; `downstream_authorized=false`.
- Ejecución canónica del ledger: `EXEC-PROFILE-RUNTIME-152a3d60-02b0-4bbf-b9fa-b83995b295d6`, `status=COMPLETED`, 11 pasos `STEP_PASS_WITH_EVIDENCE`; existen `router`, `input_validate`, `context_admission`, `execute_profile`, `semantic_judge` y `report_output`.
- El identificador del recibo del runtime NO es una fila `lf_operation_execution.execution_id`; solo hay unión evidente por `request_id` UUID. **No se encontró en ese recibo un binding verificable y atestiguado que reconcilie el ID del runtime con la ejecución canónica.**
- En el recibo runtime faltan `router_binding`, `router_authority_receipt` y `scope_authority_packet_sha256`; no están en la raíz de `runtime_request_envelope`, que contiene `artifact_set`, `input_governance` y `profile`.
- El `result_package` histórico no expone en su raíz `runtime_completion`, `profile_contract_valid` ni `semantic_utility`. Existen evidencias en el ledger de pasos, pero su correspondencia con el RAW de la cola exige binding/cotejo independiente.
- `context_admission` y `execute_profile` contienen el mismo `context_receipt_digest` en los pasos del ledger: `sha256:4a82338a11e947258346c0e855b41ee3d1bb2ff064fa45692b3aa9ec765f58f7`. Es evidencia positiva de reutilización del recibo **dentro del ledger**; no prueba identidad del mensaje efectivamente entregado al runtime.
- El único `SUCCEEDED` de la cola al readback no incorpora `router_binding` (0/1).

## 3. Consumidor implementado vs operación gobernada

Rutas inspeccionadas en `main`:

- `sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_queue_worker.py`: reclama la cola, lee `input_literal`, hidrata adapters desde `public.v_lf_router_adapter_bindings`, invoca `run_zero_cost_profile_request.py` y persiste el resultado. El campo `activation_source='ROUTER'` de los adapters se deriva de metadata, **no sustituye recibo de autoridad Router**.
- `sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_batch_queue_worker.py`: consulta adapters y `programacion.fn_lf_router_input_governance_resolve_v1`, preflight, ejecución y persistencia. No demuestra una vinculación con la misma operación `public.lf_operation_execution`.
- `services/profile_runtime_api/profile_runtime_api/app.py`: endpoint `/v1/profile/queue-execute`.
- `services/profile_runtime_api/profile_runtime_api/engine.py`: `_execute_queue_profile` valida identidad de perfil, carga fuente, crea cápsula, llama al runtime mediante un `execution_id` de transporte derivado de `request_id`, valida output y devuelve recibos. Se requiere comprobar que el envelope de ejecución consume la autoridad operativa preexistente; un nombre con `EJECUCION_PERFIL_LF:` no prueba ese vínculo.
- `public.lf_operation_step_contracts`: ruta existente `init_execution → router → profile_resolve → profile_source_read → input_validate → context_admission → research_baseline_freeze → execute_profile → output_validate → semantic_judge → report_output`.
- `public.lf_profile_execution_scope_authority_packet_v1(execution_id,input_literal,input_source_ref)` conserva texto literal y su fuente dentro de un paquete de alcance. Su disponibilidad NO acredita que el consumidor lo recibió.
- EKB: `PROFILE-RUNTIME-GOVERNED-STEP-BYPASS-001`, `STORY-PROFILE-RUNTIME-BINDING-UNRESOLVED-001`, `ROUTER-CONTEXT-ADMISSION-INTEGRATION-GAP-001`, `LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002`, `PROFILE-RUNTIME-SOURCE-PROJECTION-METHOD-OMISSION-001`.

## 4. Contrato de una prueba que sí puede cerrar C2

Para **cada uno de los tres casos** y sin ejecutarlos sobre producción:

1. Congelar `request_id`, texto literal UTF-8, `request_sha256`, solicitudes/exclusiones, tipo de alcance, modo y autorizaciones. El hash debe ser el mismo en recepción y consumidor.
2. ACT-0001 descubre sujeto y tipo de trabajo; conserva los campos originales y ofrece candidatos, sin asumir que son ejecutores. Registrar salida literal y hash.
3. Resolver activo seleccionado, acción, operación y authority binding vigente. Rechazar cualquier target excluido, cambio de modo o ambigüedad antes de efectos.
4. Usar `EJECUCION_PERFIL_LF` existente (o la operación autorizada que corresponda al caso) y su ejecución canónica; el consumidor debe tener el **mismo** `execution_id` o un mapping explícito y verificable, no un alias aceptado por apariencia.
5. Resolver perfiles/skills/adapters solo después de la selección; Input Governance actúa **como adapter de recepción cuando aplique**, no como entrada universal ni selector.
6. Compilar el contexto justo/necesario (`context_admission`, JIT, currentness, budget), conservar el hash del pedido y un recibo asociado al consumidor.
7. Leer fuente de perfil y contratos actuales; registrar output RAW del consumidor real, validador contractual, juez semántico y recibos del mismo ciclo de vida.
8. Readback del mismo `request_id`, `execution_id`, input, perfil y source SHA, scopes/exclusiones, contexto, RAW, validaciones y estado autorizado. **Cualquier eslabón faltante implica GAP/FAIL, nunca PASS**.
9. Controles negativos: sin Router, binding obsoleto, SHA del input cambiado, target excluido, no autorización runtime y ausencia de recibo deben impedir inferencia/efecto. Positivos requieren salida útil y no meramente `DONE`.
10. No modificar, desplegar ni habilitar activos en A16. En caso de bloqueo por falta de consumidor, identificar operación responsable y corrección transversal; no crear un segundo Router/orquestador.

Los **13 campos** obligatorios de `unit_metadata.checkpoint_contracts.A16Q_C2.mandatory_trace` son: `literal_request`, `router`, `resolved_asset`, `action`, `operation`, `scope_and_mode`, `selected_profiles_skills_adapters`, `input_governance_if_applicable`, `applicable_contracts_and_guards`, `real_consumer`, `authorized_result`, `receipts`, `readback`. Cada campo debe apuntar a evidencia del **mismo caso**, no a piezas inconexas.

## 5. Dictamen de baseline

**C2 no aprobado.** Se verificó la conservación del hash del pedido en repositorios históricos, un tramo de recepción y los contratos de la operación, pero NO una ruta contemporánea y completa Router→selección→consumidor→RAW→validación→recibo por cada modalidad. Los casos parciales y completos ni siquiera obtienen tipificación estable con la solicitud literal actual.

Gaps:
- `A16Q-C2-G01`: clasificación temprana de los casos parcial/completo no coincide con el sujeto pedido;
- `A16Q-C2-G02`: no hay binding atestiguado del recibo del runtime a la autoridad Router y la ejecución canónica;
- `A16Q-C2-G03`: entrega íntegra de la solicitud y sus exclusiones al prompt/modelo no probada (hash de cola/recibo no basta);
- `A16Q-C2-G04`: corpus de las 3 modalidades no ejecutado con consumidor real;
- `A16Q-C2-G05`: no se acreditó source/currentness/output-contract/juez/RAW y downstream readback unidos en un único receipt de C2;
- `A16Q-C2-G06`: runtime candidato READ_ONLY no implica activo operativo ni autoriza modelo/API.

Siguiente acción técnica: componer el consumidor ya existente con la operación y su admission/step ledger; atar `request_id`/canonical execution ID y Router receipt **antes** de la invocación; validar los mismos hashes y fuente en el resultado. Coordinar con la corrección transversal de ACT-0001; evitar parches por palabra/caso y no tocar la operación de Input Governance salvo consumidor aplicable.

_Nota de procedencia: estos son hallazgos de solo lectura del baseline, no pruebas de activación, certificación de seguridad ni aprobación final de C2._

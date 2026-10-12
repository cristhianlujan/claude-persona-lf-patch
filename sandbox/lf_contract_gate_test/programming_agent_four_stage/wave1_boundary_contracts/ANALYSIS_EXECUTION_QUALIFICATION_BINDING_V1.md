# ANALYSIS_EXECUTION_QUALIFICATION_BINDING_V1

**Fecha:** 2026-10-10  
**Estado:** `BINDING_SPEC_CANDIDATE / NOT_EXECUTABLE / NOT_OPERATIONALLY_QUALIFIED`  
**Dueño:** Agente de Análisis (A1–A9), no la implementación del producto.  
**Naturaleza:** diseño de conexión para cualificación; no autoridad runtime ni sustitución de reglas en Supabase.

## Objetivo exacto

Demostrar que un modelo real, ejecutando el procedimiento A1–A9 bajo autoridad y fuentes actuales, descubre requerimientos materiales, identifica dependencias/decisiones, produce `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` y transfiere el contexto persistido completo a PG-01. Una respuesta del LLM aislado no cumple este objetivo; un `PASS` de fixtures/contratos tampoco.

## Reutilización obligatoria, sin nuevos motores

| Responsabilidad | Proveedor existente | Límite |
|---|---|---|
| Router y admisión | Router→perfil/adapter; autorización canónica | No invocar perfil directamente desde Input Governance |
| Modelo/perfil | `services/profile_runtime_api` en Hetzner; `EJECUCION_PERFIL_LF`, `ProfileTask`, `GovernedOperationContext`, `LlamaHTTPClient` | `/health` hoy `operational_ready=false`; no declarar listo, no llamar endpoint para saltar admisión |
| Política del método | `analysis_procedure_v1.json` y contratos A1–A9 exactos | No convertir el método en un único prompt narrativo; verificar cada salida y transición |
| Autoridad y actualidad | EKB, `CURRENTNESS_AUTHORITY@CURRENT`, referencias de Supabase | Runtime no puede crear/modificar autoridad, reglas, perfiles ni estados |
| Especialistas | `CAPABILITY_SELECTOR@CURRENT` y manifiestos `CURRENT RELEASED` | Selección ≠ permiso de ejecución; required no-match/contradiction bloquea scope |
| Impacto | `SHARED_CHANGE_IMPACT_ANALYSIS` core/adapter actual | No otro motor |
| Paquete y validación estructural | A9 + `validate_programming_snapshot_payload_v1` existente, PR #2071 | El judge semántico independiente es distinto del assembler |
| Persistencia | `DECISION_CONTEXT_ASOF@CURRENT` append-only, función y resolver existentes | No tablas paralelas, no receipt inventado |
| Recepción | PG-01 consumer del `PROGRAMMING_CONTEXT_SNAPSHOT_V1` | Hasta existencia y consumo real, estado `BLOCKED` |
| Provider Worker `cristhianlujan/programming-agent` | Reusar infraestructura probada de identity, EKB y evidence donde aplique | Worker v0.8 produce *patches*, no es ejecutor de Análisis; no enviar tareas de análisis al worker de patch |

## M-B — Conexión del verdadero ejecutor A1–A9

**Precondiciones:** (a) identificar propietario y versión CURRENT RELEASED del perfil de Análisis o crear candidato por gobernanza si no existe; (b) vincular `REQUEST_CONTEXT_V1`/snapshot, digest e inputs `profile_source_paths` a `ProfileTask`; (c) admitir schema estructurado por `GovernedOperationContext`; (d) habilitación de sólo-evaluación, sin runtime productivo ni worker patch.

**Contrato de cada ejecución:** `execution_id`, `request_digest`, `source_snapshot_sha256`, `authority_fingerprint_sha256`, `profile_source_digest`, `model_version`, `provider_response_id`, `provider_usage`, `per-step outputs A1–A9`, `source_access_receipts[]`, `evidence_refs[]`, `status per scope`, `material_front_coverage`, `human_decisions_pending[]`, `reviewable_output_digest`. El auditor debe reconstruir la identidad; campos declarados por el modelo no constituyen atestación del proveedor.

**Regla de rechazo:** si el modelo responde `READY` pero no aporta `IMPLEMENTABILITY_SCHEMA_V1`, frentes, matriz, evidencia/caducidad y dependencias, el validador canónico rechaza. Si hay cualquier unknown material o decisión humana, bloquear sólo el alcance afectado. No parchear un caso concreto ni confiar en el texto `reason`.

**Demostración necesaria:** una respuesta con `provider_response_id` real y datos efectivos recogidos fuera del contenido autodeclarado, más cada paso A1–A9 con salida validable y referencias. El modelo Llama local directo usado en la prueba exploratoria no satisface la integración gobernada.

## M-C — Evaluación independiente del rendimiento real

**Cohortes dinámicas, no 7 cortes fijos:** producir combinaciones por señales reales de granularidad, autoridad EXISTING/NEW/UNKNOWN, implementación EXISTING/NEW/UNKNOWN, severidad/reversibilidad, número de dependencias y presencia de decisiones; selección guiada por riesgo/cobertura, sin fijar familias de pantalla.

**Separar papeles:** ejecutor no conoce oráculos/holdout; juez no redacta la especificación y verifica referencias de forma independiente; fuente de resultados real, no `analysis_a14_fresh_cases_v1.json` como evidencia de modelo.

**Métricas oficiales:** impactos y frentes críticos omitidos = 0; falsos READY críticos = 0; precisión profundidad/clasificación >=95%; paquetes utilizables sin reinterpretación material >=95%; paridad de recepciones verificadas = 100%; errores de pérdida de campos materiales = 0. Incluir sobreanálisis/lecturas duplicadas, costo/latencia medidos y tasas de `REQUIRES_DECISION/BLOCKED` justificadas.

**Evidencia mínima:** muestras y oráculo inmutables, outputs del modelo reales, fuente actual, judgements separados con referencias, regresión de positivo y negativo, manifiesto de cohorte y cómputo de denominadores. No reutilizar prompts/holdout de remediación para medir frescura.

## M-D — Handoff real a PG-01 en Sandbox

1. A9 compila paquete completo y snapshot tipado (no prosa resumida).
2. Persistir por `DECISION_CONTEXT_ASOF@CURRENT` solo tras controles y por ruta gobernada; el registro append-only real proporciona `context_id`, `decision_ref`, `context_sha256`, `subject_ref`, `subject_version`, `decided_at`, `effective_at`.
3. PG-01 resuelve el **mismo** `context_id` de manera independiente; recalcula digest y verifica `snapshot_schema_digest_sha256`, `authority_fingerprint_sha256`, `scope_front_matrix[]` y currentness.
4. Comprobar `READY` frente a `BLOCKED`, 0 rediscovery con huella vigente, requery limitado a disparador tipado.
5. Control negativo: falta receipt, stale, front `REQUIRED/BLOCKED`, digest corrupto y proyección con pérdida ⇒ rechazo, sin ejecutar Programación.

**Prohibido** admitir el package por mera forma válida o por escribir un receipt ficticio.

## Bloqueadores exactos del estado actual

- `ANALYSIS_EXECUTOR_NOT_BOUND`: no se ha localizado ruta gobernada CURRENT RELEASED ejecutando A1–A9 de extremo a extremo.
- `RUNTIME_NOT_READY`: health de Hetzner informa `operational_ready=false`, `downstream_authorized=false`.
- `MODEL_FALSE_READY_OBSERVED`: Llama aislado declaró READY omitiendo incógnitas explícitas. Control A9 reutilizado lo rechaza, pero no prueba razonamiento del método.
- `INDEPENDENT_SEMANTIC_JUDGE_NOT_EVIDENCED`: no hay oráculo independiente aplicado a ejecución real gobernada.
- `PG01_REAL_CONSUMER_RECEIPT_NOT_EVIDENCED`: no hay evidencia de consumo y parity persistida por PG-01 real.

## Cierre determinista

**No considerar Análisis operativamente cerrado ni liberar Programación** hasta que M-B, M-C y M-D sean PASS de ejecución real independiente. El ledger histórico 15/15 DONE indica cierre de *unidades del plan*, no aptitud operativa.

No usar este documento como sustituto de source actual, EKB, gobernanza, modelo ejecutor, validaciones o receipts.

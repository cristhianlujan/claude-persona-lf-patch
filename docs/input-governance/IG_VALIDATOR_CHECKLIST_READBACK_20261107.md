# IG LF — Validator | Checklist independiente de integridad y readiness

**Fecha:** 2026-11-07 · **RUN histórico:** 949, pantalla `B2B-AUTH-001` (id 51), `INPUT_READINESS_CONTRACT` v5.13.1.  
**Estado:** REVISIÓN ESTRUCTURAL Y READBACK DE SOLO LECTURA; SEMÁNTICA FRESCA / SQL E2E **NOT_TESTED**. No se ejecutó nuevamente el Validator, Curator, detectores R1–R6, G1 ni se modificaron tablas oficiales. El PR #3694 sigue DRAFT.

## Resultado principal — el PASS es acotado

El RUN **949** declara `scope.validator_semantic_mode=SOURCE_INTEGRITY_ONLY`, `scope.validator_semantic_comparison_families=[]` y `scope.semantic_promotion_authorized=false`. En los contratos `INPUT_FAMILY_POLICY_REGISTRY` de su versión, **47/47 familias** declaran `validator_oracle_strategy.current_validator_independence_claim=false`: no existe derecho a afirmar una comparación semántica independiente solo por el `execution_mode` técnico.

Los **47/47** assessments muestran `validator_outcome=PASS`. Sin embargo, QA está bloqueado en **24**, producción bloqueada en **24** (una adicional `NOT_READY`), y **25** mantienen bloqueadores de definición. Los estados de las etapas no cambian por escribir PASS.

La fuente archivada `programacion.input_validator_assertion_sets_v1` tiene **47/47** referencias presentes, **23** conjuntos únicos y **una aserción por cada familia**. Las **47 aserciones** son de clase `SOURCE_INTEGRITY` (29 `ARRAY_LENGTH_EQ/SCREEN_CANONICAL_GRAPH`; 5 `CONTAINS/EKB_DECISION_SET`; 5 `CONTAINS/SCREEN_CANONICAL_GRAPH`; 4 `EQ/SCREEN_CANONICAL_GRAPH`; 2 `ARRAY_LENGTH_EQ/SCREEN_STATE_SET`; 1 `CONTAINS/EKB_PREVENTION_SET`; 1 `EQ/CONTRACT`). Ninguna es prueba de enforcement, QA, seguridad de explotación o resultado semántico nuevo.

## Entrada → ejecución → salida

```text
Curator completó su RUN + evaluaciones inmutables
 → recibo y currentness (EKB / manifest / fuente)
 → fn_input_governance_validator_validate_v1(run_id, validator_identity)
      ├─ bootstrap → fn_input_governance_bootstrap_validate_v1
      ├─ REBIND → fn_input_governance_validator_rebind_v1
      └─ remediación v1.4 → fn_input_governance_validate_v2
 → assertions / SHA / validator_evidence / validator_outcome
 → handoff verificado y graph receipts en resultado COMPLETED
 → consolidación IG (SIGUIENTE LOTE)
 → Perfil (ULTIMO)
```

El camino REBIND emite un `PASS` tras obtener y validar `fn_input_v58_build_assertions`; bootstrap compara clasificación y evalúa aserciones. El guard `fn_guard_input_family_assessment_update` recalcula/verifica aserciones y SHA, con revisión de manifest. No confundir este control con un juez semántico independiente.

## Checklist de controles y evidencia

| Control | Resultado | Evidencia o brecha |
|---|---|---|
| Identidad y ruta del Validator | **PASS estructural** | `fn_input_governance_validator_validate_v1` selecciona ruta y aplica continuaciones; no se hizo una ejecución nueva |
| Separación Curator vs Validator | **PASS de identidad** | 47/47 `validator_identity` distintas de `curator_identity`; 47/47 `validator_evidence.execution_id` distintas de `curator_evidence.execution_id` |
| Identidad del Curator validada | **PASS de vínculo** | 47/47 `validated_curator_execution_id` y `curator_sha256` coinciden |
| Evidencia y evaluación de aserciones | **PASS de almacenamiento** | 47/47 archivos de conjunto presentes; 47/47 con 1 aserción `SOURCE_INTEGRITY`. El guard exige recalcularla, pero las pruebas negativas no se ejecutaron en este lote |
| Aserciones originales completas | **ALMACENADAS, transporte NOT_TESTED** | `validator_evidence` conserva `assertion_set_sha256`, no `assertions[]` inline. `fn_input_validator_evidence_rehydrate_v1` resuelve por hash, valida SHA y devuelve JSON lógico íntegro sin una nueva investigación. El conector RO no pudo invocar el helper en este lote; no afirmar rehidratación o igualdad de bytes en vivo |
| Fuente/recibo independientes de QA | **PASS estructural** | Handoff `fn_input_governance_validator_handoff_assert_v1` y `fn_ig_graph_finalize_validator_result_v1` exigen recibos en COMPLETED. Su EXECUTE directo devuelve `42501` en la sesión RO; no se abrió GRANT |
| Scope semántico del RUN | **SOURCE_ONLY explícito** | `SOURCE_INTEGRITY_ONLY`, selección `[]`, `semantic_promotion_authorized=false`, política de oráculo `current_validator_independence_claim=false` para 47/47 |
| `validator_outcome=PASS` | **47/47** | Paso de integridad/estructura de fuentes y aserciones, **no** aprobación funcional, semántica o seguridad runtime |
| Bloqueos QA/productivo | **PRESERVADOS** | 24 QA `BLOCKED`; 24 producción `BLOCKED`; 1 producción `NOT_READY`; 2 N/A y 20 READY; 0 bypass de producción READY con QA no READY |
| Estados de readiness y PASS separados en código | **PASS estructural** | `fn_input_stage_gate_summary` calcula `qa_stage_open`, `production_stage_open`, `full_qa_stage_closed` y `full_production_stage_closed` desde las columnas de readiness, no desde `validator_outcome` |
| Inmutabilidad de estados del Curator | **PASS estructural** | `fn_guard_input_family_assessment_update` prohíbe modificación de `story_ready_status`, `implementation_ready_status`, `qa_ready_status`, `production_ready_status` durante la actualización del Validator |
| Verificación de stage-gate por función protegida | **PERMISSION_DENIED/NOT_TESTED** | `fn_input_stage_gate_summary(949)` responde `42501`; el helper `known_current_v1(949,false)` falla correctamente con `INPUT_STAGE_GATE_KNOWN_CURRENT_REQUIRED`. Los contadores se reprodujeron mediante SELECT sobre assessments, **no se fingió currentness=true** |
| Readiness reproducido por SELECT | **LECTURA** | 45 familias APPLICABLE: story open 0, implementation open 20, QA open 24, producción open **25** (24 BLOCKED, 1 NOT_READY) |
| Semántica, adversariales, seguridad server-side | **NOT_TESTED** | No hay dictamen semántico independiente fresco ni QA/implementación demostrados con este RUN |
| Cambio oficial | **NINGUNO** | No escribir tablas, no modificar el Router/Perfil, no reinterpretar `validator_outcome` en Supabase |

## Regla obligatoria para consolidación IG (propuesta sin desplegar)

**No reemplazar ni reetiquetar el campo oficial `validator_outcome`.** En el resumen al Perfil presentar **dimensiones separadas**, cada una con alcance y evidencia:

- **Resultado del Validator original:** `validator_outcome=PASS` + `validator_semantic_mode=SOURCE_INTEGRITY_ONLY` + `semantic_promotion_authorized=false`.
- **Preparación funcional:** `implementation_ready_status`, `qa_ready_status`, `production_ready_status`, `blockers` **por familia** y cierre agregado `full_qa_stage_closed`, `full_production_stage_closed` (si están verificables).
- **Calidad semántica independiente:** `NOT_TESTED` hasta disponer de juez/oráculo autorizado, controles positivos y negativos, fuentes diferenciadas y recibo verificable.
- **Evidencia lógica del Validator:** resolver `assertion_set_sha256` de `input_validator_assertion_sets_v1` mediante `fn_input_validator_evidence_rehydrate_v1` gobernada; conservar `assertions[]`, hashes, identidad de RUN y `validator_findings` con readback antes del Perfil. No repetir el Validator ni reconstruir aserciones.
- **Si falla el archivo/re-hidratación:** declarar `RAW_VALIDATOR_UNAVAILABLE`/evidencia incompleta **como estado informativo propuesto**, no inventar `PASS` ni cambiar automáticamente estados oficiales. Los códigos de salida nuevos requieren contrato antes de implementación.

**Criterio de cierre de esta auditoría:** se verificó la separación entre PASS de integridad y bloqueos QA/producción mediante lectura de código, tablas y políticas. La independencia de ejecución está documentada, pero **independencia semántica no está acreditada**. Se puede **avanzar al análisis de consolidación**, no desplegar ni proclamar Validator funcionalmente cerrado.

**Fuentes/EKB:** funciones `validator_validate_v1`, `validator_rebind_v1`, `bootstrap_validate_v1`, `fn_guard_input_family_assessment_update`, `fn_input_stage_gate_summary`, `fn_input_validator_evidence_rehydrate_v1`; GOV-010, GOV-032, IG-M46, SEC-011.  
**Trazabilidad:** PR #3694 en DRAFT; RUN histórico 949, sin ejecución nueva.

# Analysis A1–A15 — auditoría de vínculo de validadores para checkpoints de cualificación

**Fecha:** 2026-10-13. **Estado:** `VALIDATOR_BINDING_INCOMPLETE / NO_OPERATIONAL_ADMISSION`. Auditoría de fuente del PR #2416 sin aplicación a Supabase, no es un validador implementado.

## Preflight EKB y causa

Se revisó EKB de Analysis, incl. `PROGRAMMING-ANALYSIS-A14-EVIDENCE-TIER-FALSE-READY-001`, `PROGRAMMING-ANALYSIS-STAGE-SOURCE-ATTESTATION-GAP-001`, `IG-M714-MANIFEST-ZERO-CHECKPOINT-COVERAGE-001` y `PROGRAMMING-BLOCKED-ATOMIZATION-NO-SYNTHETIC-CHECKPOINTS-001`.

Los 45 checkpoints propuestos en `ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json` poseen **criterios**, pero no `validator_code` ni handler ejecutable individual. La migración `20261013170000_lf_analysis_operational_qualification_checkpoints_v1.sql` configura `action_specs_v1[*].status=BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED`, `pass_when` genérico y `missing_typed[]` bloqueante. Eso impide el falso DONE; no valida una evidencia verdadera ni mueve el checkpoint.

## Validador existente ≠ verificación completa

- `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/validate_wave1_boundary_contracts_v1.py`: verificadores **estructurales** de A1–A9 y manifest, no fuente vigente atestada ni inferencia real.
- `profiles/programming_analysis_lf/validators/runtime_validate.py`: valida forma y consistencia de propuesta modelo, nunca concede downstream admission.
- `profiles/programming_analysis_lf/validators/runtime_semantic_utility.py`: *deterministic utility floor*; devuelve juez independiente `NOT_EXECUTED`, no sustituto de juzgado semántico.
- `programacion.fn_analysis_pg01_exact_receipt_guard_v1`: existe y verifica coincidencia de `context_id`, `context_sha256` y schema en respuesta `RESOLVED`. **No es prueba de emisión/consumo PG-01 real por sí solo**.
- `score_analysis_a14_holdout_v1.py`: scorer diseñado explícitamente para `DETERMINISTIC_CONTRACT_REPLAY` y rechaza la afirmación de inferencia real. No puede usarse para aprobar A14 operacional.
- `programacion.programming_validation_registry`: 3 validadores `ACTIVE` (**GITHUB_FILE_SHA256_ASSERT**, **GITHUB_FILE_TEXT_ASSERT**, **SUPABASE_CATALOG_ASSERT**), solo fuente/catálogo; ninguno juzga output modelo o calidad independiente de Analysis.

## Matriz de contrato por unidad (cada fila = C1, C2, C3)

| Unidad | C1: comprobación estructural existente, pero aún SIN atestación vigente | C2: salida a comprobar, SIN recibo ejecutor vinculado | C3: exigencia de juicio, SIN juez vinculado |
|---|---|---|---|
| A1 | `validate_request_context` | Normalizar `REQUEST_CONTEXT_V1` | Verdad del objetivo, ambigüedad y ausencia de solución inventada |
| A2 | `validate_analysis_change_classification` | Señales de riesgo → L1/L2/L3 | Clasificación real contra oráculo independiente |
| A3 | `validate_analysis_targeted_evidence` | EKB + lectura/caducidad de refs actuales | Fuentes realmente consultadas, suficiencia, no alucinación |
| A4 | `validate_shared_impact` | Direct/indirect impact + consumidores | No omitir impactos críticos y visibilizar lo desconocido |
| A5 | `validate_analysis_decision_context` | ADR/DECISION_CONTEXT, autorización o escalamiento | No autoaprobar decisiones, no escalar sin necesidad |
| A6 | `validate_analysis_implementability` | `IMPLEMENTABILITY_SCHEMA_V1`, WHAT sin HOW | Requisitos, permisos, estados/errores/efectos completos |
| A7 | `validate_material_front_coverage` | `MATERIAL_FRONT_COVERAGE_V1` desde evidencia | Cobertura real; REUSE/NA requieren evidencia |
| A8 | `validate_analysis_stop_rule` | STOP/CONTINUE/REQUIRES_DECISION con trace | Stop no prematuro, frentes completos |
| A9 | `validate_handoff_parity`, `validate_programming_snapshot_payload_v1` | Snapshot real/receipt exacto, con contexto persistido | Guard PG-01 existe; consumo runtime independiente pendiente |
| A10 | `analysis_evaluation_campaign_contract_v1.json` solo contrato | Campaña real heterogénea, no fixture replay | 0 omisiones críticas en evaluación externa |
| A11 | Contrato de campaña adversarial | Fallos/adversariales en agente gobernado | 0 false READY críticos con fuente independiente |
| A12 | Benchmark de contrato histórico, no modelo | Baseline y candidato reales; time/token medidos | Comparación pareada de calidad/costo, no proxy |
| A13 | `analysis_a13_remediation_changelog_v1.json` fuente | Ejecución antes/después de corrección general | Regresión semántica/adversarial sin pérdida |
| A14 | `score_analysis_a14_holdout_v1.py` **replay solo** | Holdout con respuestas reales provider-bound | 0 críticos; >=95% classification/usability por juez externo |
| A15 | `validate_manifest` para freeze de fuente | Readback Git–Supabase–Router–PG01 exacto | A1Q–A14Q completos + dictamen independiente terminal |

**No equivalencia:** encontrar una función Python capaz de validar forma no es suficiente para marcar `C1` DONE: C1 exige además fuente realmente recuperada, atestación vigente, identidades y SHA. Del mismo modo, los C2 y C3 no pueden calificarse por modelo/autoevaluación ni replay estructural.

## Diseño mínimo reusable de validación (sin 45 motores)

**Tres familias genéricas en el registro canónico**, con `unit_code/checkpoint_code` solo como parámetros y contratos de prueba por etapa.

1. **SOURCE_CURRENTNESS_ATTEST_V1 (C1):** resolver source refs actuales por Router/authority, verificar identidad/version SHA, permitidos, validación estructural específica, EKB y recibo de lectura realmente observado. Reject stale/missing, mismatch, manifest-only.
2. **ANALYSIS_REAL_EXECUTION_RECEIPT_V1 (C2):** verificar `ProfileTask` admitida por Router y ejecución de modelo real con `execution_id`, `provider_response_id` atestado por transporte, digests de contexto/outputs, ejecución A1–A9 y forma de salida. Rechazar self-declared ID, dummy replay, salida READY sin evidence/obligations.
3. **INDEPENDENT_SEMANTIC_AND_CONSUMER_ASSURANCE_V1 (C3):** juez independiente con oráculo/holdout ciego y criterios de unidad. Para A9, también recibo *real* PG-01 y `fn_analysis_pg01_exact_receipt_guard_v1`; para A14, scorer operacional separado del replay. A15 requiere 14/14 hijos elegibles con evidencia y freeze.

Los nombres anteriores son **familias propuestas, no validadores registrados/existentes**. No crear nuevos motores de juez, fuente ni inferencia: enlazar adaptadores actuales, extender/componer validadores canonizados y registrar solo reglas de admisión demostradas. Reusar `fn_engineering_checkpoint_action_spec_v3`, `fn_engineering_checkpoint_assertion_record_v1`, `fn_engineering_checkpoint_transition_v1`; cada checkpoint terminal exige receipt admitido y validación positiva y negativa.

## Requisito antes de merge/aplicación #2416

**Bloqueo explícito:** `45/45 CRITERIA_DEFINED`, `0/45 EXECUTABLE_VALIDATOR_BINDINGS`, `0/45 RECEIPT_VERIFIED`. Añadir al catálogo fuente `validator_code`, `validation_input`, `positive_test_ref`, `negative_test_ref`, `pass_condition`, `failure_code`, `evidence/receipt expected schema` por checkpoint, enlazados a las tres familias validables. Resolver el handler y atestar PASS/FAIL con controles antes de habilitar `action_specs`. Cualquier validador inexistente debe quedar `NOT_IMPLEMENTED`, no `ACTIVE`, no DONE.

No cambiar los 15 DONE históricos ni crear 45 validadores especializados; tampoco activar runtime/producción, insertar casos de producto o aplicar la migración hasta cerrar esta deuda estructural.

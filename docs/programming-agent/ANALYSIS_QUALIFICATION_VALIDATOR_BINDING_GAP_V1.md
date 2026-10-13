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
| A15 | **SIN callable de freeze A15 acreditado**; `validate_manifest` es de Wave1 y NO sirve para A15 | Readback Git–Supabase–Router–PG01 exacto | A1Q–A14Q completos + dictamen independiente terminal |

**No equivalencia:** encontrar una función Python capaz de validar forma no es suficiente para marcar `C1` DONE: C1 exige además fuente realmente recuperada, atestación vigente, identidades y SHA. Del mismo modo, los C2 y C3 no pueden calificarse por modelo/autoevaluación ni replay estructural.

## Diseño mínimo reusable de validación (sin 45 motores)

**Tres familias genéricas en el registro canónico**, con `unit_code/checkpoint_code` solo como parámetros y contratos de prueba por etapa.

1. **SOURCE_CURRENTNESS_ATTEST_V1 (C1):** resolver source refs actuales por Router/authority, verificar identidad/version SHA, permitidos, validación estructural específica, EKB y recibo de lectura realmente observado. Reject stale/missing, mismatch, manifest-only.
2. **ANALYSIS_REAL_EXECUTION_RECEIPT_V1 (C2):** verificar `ProfileTask` admitida por Router y ejecución de modelo real con `execution_id`, `provider_response_id` atestado por transporte, digests de contexto/outputs, ejecución A1–A9 y forma de salida. Rechazar self-declared ID, dummy replay, salida READY sin evidence/obligations.
3. **INDEPENDENT_SEMANTIC_AND_CONSUMER_ASSURANCE_V1 (C3):** juez independiente con oráculo/holdout ciego y criterios de unidad. Para A9, también recibo *real* PG-01 y `fn_analysis_pg01_exact_receipt_guard_v1`; para A14, scorer operacional separado del replay. A15 requiere 14/14 hijos elegibles con evidencia y freeze.

Los nombres anteriores son **familias propuestas, no validadores registrados/existentes**. No crear nuevos motores de juez, fuente ni inferencia: enlazar adaptadores actuales, extender/componer validadores canonizados y registrar solo reglas de admisión demostradas. Reusar `fn_engineering_checkpoint_action_spec_v3`, `fn_engineering_checkpoint_assertion_record_v1`, `fn_engineering_checkpoint_transition_v1`; cada checkpoint terminal exige receipt admitido y validación positiva y negativa.

## Preflight vivo 2026-10-13: referencias operativas pendientes

- **C3, 15/15 sujetos afectados:** Supabase declara `INDEPENDENT_ASSURANCE@2.0.1` como `RELEASED` con `validator_ref=sandbox/lf_contract_gate_test/transversal_assets/independent_assurance/validate_independent_review_subject_envelope_v3.py`, pero GitHub devuelve **404** en `main` y en HEAD `e4692457ebc29f70bc474dd5367bf7a1c82dbac6` de este PR. El directorio existe y no contiene ese archivo. La capacidad SQL `public.lf_independent_review_begin_v3` y el validador Python referenciado son superficies distintas: la primera NO demuestra que exista el segundo. Mantener C3 `BLOCK`; reconciliar referencia/código por la autoridad transversal y su carril gobernado, sin crear juez paralelo.
- **A15Q_C1:** no tiene `stage_structure_validator` ni callable de freeze A15. El source-only audit solo impide `validate_manifest` de Wave1, **no** verifica un callable alternativo. Mantener A15Q_C1 `BLOCK` hasta adaptar un verificador de freeze real y demostrar positivo/negativo.
- **Cobertura de prueba:** `PASS_45_INDIVIDUAL_BINDINGS_SOURCE_ONLY` valida contratos declarados y 8 mutaciones, **no verifica existencia de `validator_ref`, handler operacional, recibos, ni CI de ejecución**. No elevar 45/45 contratos a READY. Estos dos defectos se descubrieron mediante readback independiente de Supabase y GitHub.

## Requisito antes de merge/aplicación #2416

**Bloqueo explícito:** `45/45 CRITERIA_DEFINED`, `0/45 EXECUTABLE_VALIDATOR_BINDINGS`, `0/45 RECEIPT_VERIFIED`. Añadir al catálogo fuente `validator_code`, `validation_input`, `positive_test_ref`, `negative_test_ref`, `pass_condition`, `failure_code`, `evidence/receipt expected schema` por checkpoint, enlazados a las tres familias validables. Resolver el handler y atestar PASS/FAIL con controles antes de habilitar `action_specs`. Cualquier validador inexistente debe quedar `NOT_IMPLEMENTED`, no `ACTIVE`, no DONE.

No cambiar los 15 DONE históricos ni crear 45 validadores especializados; tampoco activar runtime/producción, insertar casos de producto o aplicar la migración hasta cerrar esta deuda estructural.


## Actualización: contratos individuales vinculados en fuente (13 de octubre)

**Estado posterior a esta auditoría** (la sección inicial conserva el diagnóstico que motivó la reparación):
- Se añadieron exactamente **45 `validator_contract` distintos**, uno por checkpoint, al catálogo y la migración candidata; todos tienen `checkpoint_code`, `subject_ref` específico, assertion individual, proveedor existente a reutilizar, expected evidence, controles positivo/negativo y condiciones fail-closed.
- **C1:** tres validadores canónicos registrados y activos de GitHub/Supabase + `CURRENTNESS_AUTHORITY@1.0.0` + validador estructural A1–A9 cuando aplica. A10–A14 reutilizan `validate_analysis_evaluation_campaign_v1.py` solo para forma de campaña. A15 exige fuente y comprobación de freeze independiente, sin apropiarse de `validate_manifest` Wave1.
- **C2:** `profiles/programming_analysis_lf/validators/runtime_validate.py` + salida/contenido específicos por etapa; la identidad del modelo debe proceder del transporte gobernado, nunca del texto producido.
- **C3:** `INDEPENDENT_ASSURANCE@2.0.1` con `public.lf_independent_review_begin_v3`, subject digest y recibo VERIFIED del ledger; A9 exige además `programacion.fn_analysis_pg01_exact_receipt_guard_v1` y consumo físico; A14 exige resultados reales y umbrales independientes; A15 exige 14 calificadores anteriores.
- El validador de source-only `test_analysis_qualification_validator_mapping_v1.py` se ejecutó en `scalora-vps` con archivos recuperados de GitHub: `PASS_45_INDIVIDUAL_BINDINGS_SOURCE_ONLY positives=45 negatives=8 operational_receipts=0 source_only=true`.
- No se introdujo motor de juicio, nuevo handler o nuevo registro `ACTIVE` en `programacion.programming_validation_registry`.

**Estado de cierres:** criterios individuales `45/45`; reutilizaciones declaradas en fuente `45/45`; consumidores operativos atestados para cada checkpoint `0/45`; receipts de cualificación real `0/45`. Los `action_specs_v1.status` permanecen `BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED` y los registros reales de la base no existen hasta Merge Train. El paso siguiente es **conectar los consumidores específicos y aportar evidence source/current, profile runtime e independent assurance**, no inventar 45 validadores nuevos.

Referencias EKB adicionales: `PROGRAMMING-VALIDATOR-RESOLVER-USAGE-GUIDE-001` y `LF-PE10-C3-WRONG-ASSURANCE-LEDGER-20261012-001`.

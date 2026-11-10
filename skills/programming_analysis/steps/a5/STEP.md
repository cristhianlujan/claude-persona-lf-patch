# A5 — Resolver decisiones y ADR sobre evidencia A1–A4

**Estado:** desarrollo candidato local sin RUN gobernado, decisión humana, escritura ASOF ni autorización A6.

## Entradas deterministas

Cuatro contratos existentes: `REQUEST_CONTEXT_V1` (A1), `ANALYSIS_CHANGE_CLASSIFICATION_V1` (A2), `TARGETED_EVIDENCE_SET_V1` (A3) y `SHARED_CHANGE_IMPACT_ANALYSIS` (A4). El sidecar opcional `A5_GOVERNED_DECISION_READBACK_V1` contiene una revisión tipada de siete disparadores de ADR, vinculada a una referencia exacta previamente emitida por A3/A4.

Reutiliza solo los proveedores canónicos existentes:
- `transversal.decision_log` y `programacion.fn_engineering_current_adr_assert_v1(p_adr)` para verificar vigencia de un ADR identificado; A5 no inventa ni busca ADR.
- `public.fn_lf_decision_context_asof_resolve_v1(consumer_code,subject_ref,as_of)` para contexto histórico, que **nunca** equivale a autoridad actual.
- `DECISION_CONTEXT_ASOF` / `public.fn_lf_decision_context_asof_record_v1` para persistencia gobernada fuera de este consumidor; A5 no escribe.
- `CURRENTNESS_AUTHORITY` para la certificación del host; el candidato no se autoconcede currentness.

## Decisión ADR

| Condición sustentada | Disposición | Comportamiento |
|---|---|---|
| Siete disparadores revisados, todos falsos | `NOT_REQUIRED` | No genera ADR humano; HOW local reservado a PG-03 |
| Disparador verdadero + ADR exacto vigente (assert PASS) | `REUSE_CURRENT_ADR` | Reutiliza referencia del ADR sin modificarlo |
| Disparador verdadero + ausencia de ADR vigente acreditada por fuente | `NEW_ADR_REQUIRED` | `REQUIRES_DECISION`; A5 no aprueba un ADR |
| Disparador desconocido, readback incompleto o no hay prueba de ADR | `ADR_BLOCKED` | `UNRESOLVED` o `BLOCKED`, sin inventar una decisión |

Las reglas CANDIDATO/PENDIENTE excluidas en A3 no abren una decisión humana ni impiden trabajar sobre reglas independientes. Los gaps de dependencias A4 se muestran como requerimiento de evidencia, no como aprobación/denegación ejecutiva.

## Salida

`ANALYSIS_DECISION_CONTEXT_V1` con `decision_context` completo: `decision_id`, `subject_ref`, `scope_refs`, `material_question`, `status`, `options_considered`, `selected_option_ref`, `rationale`, `authority_refs`, `evidence_refs`, `currentness_refs`, `unresolved_questions`, `adr_disposition`, `adr_ref`, `persistence_ref` y `decision_fingerprint_sha256`. Fingerprint SHA256 calculado de JSON canónico, excluyendo la huella misma.

El paso **no selecciona estrategias técnicas ni opciones no elegidas por owner**, no convierte la intención A2 en autorización y no afirma `STABLE` sin fuente decisional vigente verificada. En este consumidor fuente los resultados son candidatos; `source_attested=false`, `independent_judge_verified=false`, `a6_allowed=false`, `no_write_performed=true`.

## Control de calidad

Tests: `steps/a5/evals/test_a5_decision_adr_v1.py` (15 pruebas creadas). CI: `.github/workflows/lf-analysis-a5-candidate-tests.yml`, exact-HEAD, sin secretos. PASS pendiente de verificar sobre commit final.

**Separación:** la implementación candidata A5 no exige cerrar antes PASE de A3/A4, pero tampoco constituye admisión operativa, READY o autorización de ejecución de A6.

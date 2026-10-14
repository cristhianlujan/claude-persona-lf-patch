# PE10_C3 — Productor GPT Native, A_ORIGINAL

## Mandato de ejecución
Actúa como ejecutor de los perfiles LF adjuntos, no como juez del benchmark. Debes resolver las seis tareas como entregables reales de los tres perfiles. En las tareas de cada perfil aplica SOLO la sección de contexto de ese perfil identificada a continuación. No asumas información no suministrada; ante falta material de información produce el estado seguro apropiado. No inventes consultas a herramientas, resultados ejecutados, hechos verificados ni pruebas de aceptación que no hayas corrido. No puntúes ni compares brazos. No has recibido criterios ocultos ni ninguna respuesta del otro brazo.

Este encargo es una captura de respuestas GPT Native dentro de este chat. No describas cómo ejecutarías el experimento ni cómo probarías una capacidad: resuelve las tareas. Las instrucciones particulares de formato del perfil aplican AL ENTREGABLE de su tarea; el formato de agregación final agrupa las seis salidas íntegramente en textos JSON separados. No añadas recomendaciones de benchmark o una decisión PASS/FAIL.

## Identificadores vinculantes
Repositorio: cristhianlujan/claude-persona-lf-patch
Commit de fuente shadow congelada: 3e19d942ce5a8705ac2d83db69b4328e3b07d419
Arm: A_ORIGINAL
Corpus: skills/profile_creator/evals/pe10_c3_functional/cases_v1.json del mismo commit
No abras archivos del otro brazo, no abras private_oracle_v1.json y no abras los resultados de una evaluación previa.

## Contexto operativo exclusivo del perfil quality_pack
Fuente exacta: `skills/profile_creator/evals/pe10_c3_functional/frozen_contexts/quality_pack_baseline_model_context.md`

<PROFILE_CONTEXT_QUALITY_PACK>
# Quality Pack Skill Pack — LF Sandbox

## Purpose
Act as the mandatory quality gate before Composer, final prompt, image generation, document impact or render. Quality Pack does not design the solution; it validates whether the upstream worker output is evidenced, complete, safe and usable.

## Resolver-backed evidence boundary — GOV-037
Quality Pack must never infer that a source was observed because the candidate payload says `observed=true`, `read=true`, `current=true`, `sha_match=true` or `receipt_valid=true`.

For every evidence object that contributes to an applicable PASS:
1. resolve its ref with an independently trusted provider resolver;
2. read the actual bytes/data from that boundary;
3. recompute SHA-256;
4. compare the derived digest to the declared digest;
5. derive currentness from the resolved revision;
6. when provenance is applicable, resolve the receipt independently as its own evidence object.

`validators/trusted_ref_resolver.py` is the deterministic resolver for immutable same-repository GitHub refs (`github://owner/repo@<40-hex-commit>/<path>`). Unsupported providers remain fail-closed until an independently authorized resolver is supplied.

A nonexistent ref + valid-looking SHA + all boolean flags true must never yield PASS. A real ref with the wrong declared digest must never yield PASS. A declared `current=true` cannot override resolver-derived stale revision evidence.

## Deterministic handoff intake pre-check
For producer→Quality Pack continuity evaluation, run `validators/run_handoff_intake.py` before any semantic review claim.

This executable pre-check answers only whether the receiver has enough explicit context and an observable materialized upstream artifact to begin normal Quality Pack review without reconstructing producer state.

- `QUALITY_INTAKE_READY` means deterministic intake succeeded and the next gate is `SEMANTIC_QUALITY_REVIEW`.
- It does **not** mean `PASS_TO_COMPOSER`, `PASS_WITH_RESTRICTIONS`, a Quality Pack score, LF safety PASS, or general behavioral PASS.
- Missing receiver context returns to the orchestrator.
- A created artifact may be delivered by an exact reference plus materialized payload or as an explicit embedded `candidate_artifact`; in either mode its identity must match the producer claim.
- A producer that claims a created artifact but fails to deliver an observable materialized artifact or claimed components returns to the worker for self-repair.
- `semantic_quality_review_status` remains `NOT_EXECUTED` until the normal semantic Quality Pack review actually runs.

The preserved eval definition is `evals/handoff_intake_matrix.json`. The target eval must exist before changes to the intake runner that are intended to satisfy it.

## Independent clean-chat semantic review
When deterministic intake is ready but no executable independent semantic receiver exists, Quality Pack may use `INDEPENDENT_CHAT_CONTEXT` as the lowest-cost manual execution mode.

Required sequence:
1. Freeze the exact review bundle defined by `contracts/independent_chat_semantic_review_contract.md`.
2. Open a new reviewer chat/context that did not produce the artifact.
3. Paste `handoffs/independent_chat_semantic_review.md` populated only with the frozen bundle. Do not provide a prior semantic verdict, expected score or desired result.
4. Require one JSON receipt matching `schemas/independent_semantic_review_receipt.schema.json`.
5. Validate it deterministically with `validators/validate_independent_semantic_review.py`.
6. Store the validated receipt and semantic review under the case sandbox run.

A valid receipt allows the exact claim `SEMANTIC_REVIEW=EXECUTED_INDEPENDENT_CONTEXT` for that artifact. It does not mean `AUTOMATED_SEMANTIC_JUDGE=IMPLEMENTED` and does not authorize production, automatic impact or general behavioral promotion.

The receipt validator's target eval is `evals/independent_chat_semantic_review_matrix.json`.

## Non-negotiable rule
Quality Pack cannot accept a worker PASS if independently resolved evidence is missing. Claims without resolver-backed evidence count as unproven.

## Automatic blocking conditions
- Score appears without resolver-backed rubric evidence.
- Required schema is missing or invalid.
- Required fields are declared but not developed.
- An evidence ref is absent, unresolvable, digest-mismatched or self-certified while its gate claims PASS.
- Provenance is applicable but the receipt ref/digest cannot be independently resolved.
- Handoff requires Composer to invent structure.
- Prompt/render may leak internal metadata, GitHub, logs, scores, PASS, worker names or sandbox traces.
- The artifact creates dark patterns, financial pressure, false urgency, guaranteed promises, shame or aggressive debt cues.
- The upstream worker returns suggestions, recommendations or commentary instead of the required executable artifact.
- The artifact may proceed to Composer/image/render/tool and the output channel gate was not loaded.
- Recipient/output mode mismatch exists and is not resolved before emission.
- A concrete UI decision was requested but the output is only a concept name, rationale, ingredient list or recommendation.

</PROFILE_CONTEXT_QUALITY_PACK>

### Tarea PESC3-101 — SPECIALIZE
Revisa un handoff que pretende publicar una pantalla LF. El productor declara PASS, adjunta dos pruebas positivas y una captura de 2026-07. La versión actual del componente es de 2026-10. No existe prueba negativa ni comprobación de procedencia del screenshot. El contrato exige evidencia vigente, prueba negativa y aceptación semántica. Entrega un dictamen de calidad con afirmaciones trazables, fallos concretos, reparación mínima y prueba de cierre. No inventes recibos.

### Tarea PESC3-104 — ADAPT
En una revisión anterior un artefacto de descarga de cartera recibió decisión provisional REVIEWABLE porque cumplía tres pruebas positivas y la fuente Git estaba vigente. Hoy se adjunta nueva evidencia verificable: una prueba negativa falla, mostrando que un usuario sin permiso descarga campos restringidos. La prueba corresponde al mismo commit y ruta. Reevalúa la decisión ahora, señala qué hechos sobreviven, cuáles cambian y cuál es la corrección transversal mínima y la nueva verificación antes de cualquier PASS. No reescribas la evidencia positiva ni inventes despliegue.

## Contexto operativo exclusivo del perfil ui_architect
Fuente exacta: `skills/profile_creator/evals/pe10_c3_functional/frozen_contexts/ui_architect_baseline_model_context.md`

<PROFILE_CONTEXT_UI_ARCHITECT>
# UI Architect Skill Pack — LF Sandbox

## Purpose
Convert product and UX decisions into executable UI specifications. Existing-screen findings become concrete remediation actions. New-screen requests become executable UI specifications without inventing domain truth.

## Existing-screen invariants
These rules apply only to REMEDIATE_EXISTING work.
- Named canonical + redundant authority outranks generic missing-input wording.
- Never re-ask resolved authority or invert it.
- Preserve the authoritative presentation; remove/hide/merge only the redundant one.
- A removed target is evidence/history, not an active post-remediation component.
- `evidence_component_ids` includes target + survivor.
- Acceptance must prove the defect is reduced.
- Do not move a CTA farther from its governing state.
- Never strengthen unsupported guarantees, eligibility, urgency, debt-closure, or precision.
- Preserve supplied qualifiers.
- Router and Direct materially agree for the same governed input.

## New-screen invariants
These rules apply to CREATE_NEW work.
- Supplied requirements are not defects.
- Do not remove or suppress a supplied required component merely to reduce density.
- Optional requirements may remain optional; do not relabel them redundant without authority.
- Do not invent links, legal effects, payment success, eligibility, campaign urgency, debt closure, financial precision, or consent defaults.
- Keep domain truth from upstream profiles intact; UI owns presentation, hierarchy, components, states, tokens and responsive behavior, not financial/legal/privacy truth.
- If multiple upstream domain decisions are supplied, compose them without silently replacing or strengthening them.
- Compact output is preferred, but never at the expense of a material requirement or guardrail.

## Production UI Spec contract
Work with enough information uses `output_type="PRODUCTION_UI_SPEC"` and root keys:
`worker`, `output_type`, `deliverable_created`, `score`, `handoff_to_next`, `self_verdict`.

`deliverable_created` contains `screen_definition`, `component_tree`, `layout_grid`, `visual_hierarchy`, `state_map`, `token_map`, `spacing_typography`, `density_rules`, `risk_controls`, `prompt_constraints`, plus `remediation_actions` only when existing-screen remediation requires them.

Each active component includes `zone_id`, `component_id`, `component_type`, `role`, `content`, `visual_priority`, `color_tokens`, `typography`, `spacing`, `state`, `allowed_variants`, `blocked_variants`.

Each remediation action includes `issue_id`, `priority`, `category`, `evidence_component_ids`, `evidence_anchor`, `decision`, `implementation_change`, `acceptance_criteria`, `execution`, `acceptance_check`.

Root-depth invariant:
`deliverable_created` closes before `score`; `score` closes before `handoff_to_next`; `handoff_to_next` closes before root `self_verdict`.

## Other output modes
- Focused UI Decision Spec: only for one requested UI attribute; validate against `schemas/ui_focused_decision.schema.json`.
- Missing Input State: only for materially unresolved input; validate against `schemas/ui_missing_input.schema.json`; automated workers return to orchestrator, never ask the final user directly.

## Traceability and lifecycle
Candidate remediation evidence lives under `profiles/ui_architect/evals/<remediation_lot>/`.
Future profile writes require `ACTUALIZACION_PERFIL_LF` bound to `PERFIL-UI-ARCHITECT` before the first GitHub write.
Runtime enablement, `VALIDATED`, production promotion, and automatic promotion remain blocked unless separately governed and authorized.

</PROFILE_CONTEXT_UI_ARCHITECT>

### Tarea PESC3-102 — SPECIALIZE
Debes corregir la pantalla EXISTENTE de aprobación de cargas. Ya existe un token canónico surface/primary y uno action/approve; un componente codifica #00AA44 en vez del token action/approve. El teléfono de soporte aparece literal aunque existe la configuración transversal support_contact. Requisitos originales: botón Aprobar, estado loading, denegación por rol, confirmación antes de impacto, vista estrecha y teclado. Mantén la acción y la fuente de verdad; define una remediación implementable con mapa de estados y pruebas que fallen si vuelve el hexadecimal o el teléfono en duro. No inventes un color alternativo.

### Tarea PESC3-106 — PRESERVATION
Se diseña una pantalla NUEVA de detalle de oferta, no se corrige ninguna pantalla existente. El contrato de producto exige mostrar acreedor original, titular actual, monto, moneda, vigencia condicionada, cuotas ofrecidas si existen, opción de rechazar y estado de error; no se suministran importe ni fecha reales. Diseño propuso omitir 'titular actual' y 'rechazar' para reducir densidad, y dibujar la tarjeta igual en móvil que en desktop. Produce una especificación de UI preservando todos los requisitos, sin inventar valores ni convertir condicionales en garantías, con estados relevantes, accesibilidad, diseño estrecho y aceptación falsable.

## Contexto operativo exclusivo del perfil product_director_lf
Fuente exacta: `skills/profile_creator/evals/pe10_c3_functional/frozen_contexts/product_director_lf_baseline_model_context.md`

<PROFILE_CONTEXT_PRODUCT_DIRECTOR_LF>
# Product Director LF Skill Pack

## Purpose
Define product direction, scope, priority, functional trade-offs, acceptance criteria and handoff for LF deliverables. This worker defines what should be built, what should not be built, why, which source authorizes each material decision, and what the next worker may safely assume. It does not replace UX/UI, Copy, Legal, Tech, Data, QA or human approval.

## Context-resolution and materiality ladder
Resolve a product fact in this order:

1. **Current authoritative/constraint source exists** -> use it exactly and bind the source.
2. **Exact upstream/user rule exists** -> preserve it as supplied and do not re-ask it.
3. **No canonical value exists and the missing detail is low-risk/non-material** -> continue with an explicit `PROPOSED_NOT_CANONICAL` decision detail when useful; do not present it as policy or product truth.
4. **The unresolved detail changes material business meaning, eligibility, payment/debt state, safety, primary scope/route or a protected constraint** -> `RETURN_TO_ORCHESTRATOR` through `PRODUCT_MISSING_INPUT_STATE`, or `BLOCKED_PRODUCT_RISK` when no safe source can resolve it.

A historical PR, previous successful decision or contextual preference may inform analysis but cannot override current authority.

## Mandatory decision trajectory
Every material `PRODUCT_DIRECTION_SPEC` must make this chain observable:

`objective -> source/evidence -> selected decision -> rejected alternatives/trade-off -> preserved constraints/qualifiers -> observable acceptance -> handoff effect`

Required inside the deliverable:
- `product_decision.source_refs[]` with `source_ref`, `authority`, `supports`, `current`;
- `authority_status` and, if sources conflict, explicit `conflict_resolution`;
- `material_claims[]` bound to an observed authoritative/constraint `source_ref`;
- `decision_lineage` linking evidence, constraints, acceptance and downstream effect;
- `acceptance_criteria[]` with an observable check;
- `handoff_to_next.qualifiers_to_preserve` so UI/Copy/Tech cannot turn a referential or conditional statement into a guarantee.

The same decision must reconcile across `product_decision.selected_decision`, `decision_lineage.selected_decision`, acceptance references and downstream handoff. A cross-artifact mismatch is invalid even when each field is individually well formed.

A high score never substitutes for any of these fields.

## Automatic block / needs-input
Block or request input when:
- source authority is insufficient or unresolved after context resolution;
- two current sources conflict and no authority/currentness rule resolves them;
- a material eligibility, payment, debt-status, urgency or guarantee claim is unsupported;
- a proposal violates an upstream constraint even if attractive;
- acceptance/handoff is generic or requires downstream invention;
- qualifiers required by upstream would be lost;
- score is used as evidence;
- the worker asks for a material source already present/resolved in the current run;
- a noncanonical proposal is presented as an authoritative product rule.

## Behavioral proof boundary
`evals/remediation_20260827/run_cases.py` is a deterministic contract regression suite. It does **not** execute this profile and must never be described as RAW profile behavior.

A behavioral claim requires actual RAW model output plus a canonical execution receipt bound to the exact profile source/input/output, deterministic validation, semantic judging, a fresh holdout and fresh adversarial challenges. Receipt authenticity proves execution only; it does not prove the decision is correct.

When the same material request reaches this profile directly and through Router, normalized product decisions must be materially equivalent unless different contextual authority is explicitly evidenced. Compare selected decision, scope, preserved qualifiers, acceptance intent, blockers and handoff effect; ignore runtime metadata.

## Compact handoff rule
Downstream receives only what changes execution: selected decision, exact current authority, preserved constraints/qualifiers, observable acceptance, explicitly labeled proposal details and unresolved material blockers. Do not dump internal governance/EKB metadata into the user-facing product brief.

</PROFILE_CONTEXT_PRODUCT_DIRECTOR_LF>

### Tarea PESC3-103 — SPECIALIZE
Decide entre dos estrategias de oferta LF sobre segmentos elegibles, conservando voluntariedad, exactitud y reclamaciones. Estrategia A: piloto reversible con conversión observada 12% y tasa de reclamos 0.5% en 1,000 sesiones; estrategia B: lanzamiento amplio propuesto con proyección de conversión 17%, reclamos 3%, sin experimento controlado. Guardrail aprobado: reclamos <=1%. No existe prueba causal de B. Objetivo es mayor recaudación neta sostenible, no solo clics. Entrega una decisión ejecutable, cálculo con datos suministrados, hipótesis, experimento medible, freno/rollback, aceptación y límite de afirmación. No afirmes que 17% es observado.

### Tarea PESC3-105 — ADAPT
Contexto inicial: la cartera mostraba a la entidad X como acreedor original y actual, y había una oferta propuesta pendiente de confirmación. Llega una carga verificada de fecha posterior que identifica a X solo como acreedor original y a Y como titular actual; la oferta de X no tiene prueba de aprobación por Y. Debes revisar una decisión previa que proponía mostrar la oferta a todos los clientes coincidentes. Decide el estado correcto, el alcance de bloqueo, qué información puede mostrarse y qué datos específicos deben confirmarse. No borres la distinción acreedor original / titular actual ni prometas descuentos.

## Salida obligatoria
Devuelve un único JSON válido (sin fences Markdown ni comentarios) con este contrato. La propiedad `output` de cada caso debe contener el entregable completo que daría el perfil correspondiente, sin abreviar, sin referencias a otros casos y sin convertirlo en resumen. Respeta cualquier JSON interno del perfil como string JSON escapado.

```json
{
  "schema": "PE10_C3_GPT_NATIVE_ARM_OUTPUT_V1",
  "arm": "A_ORIGINAL",
  "model_route": "GPT_NATIVE_IN_CHAT",
  "producer_evidence_is_provider_attested": false,
  "cases": [
    {"case_id": "PESC3-101", "output": "ENTREGABLE_REAL_COMPLETO"},
    {"case_id": "PESC3-102", "output": "ENTREGABLE_REAL_COMPLETO"},
    {"case_id": "PESC3-103", "output": "ENTREGABLE_REAL_COMPLETO"},
    {"case_id": "PESC3-104", "output": "ENTREGABLE_REAL_COMPLETO"},
    {"case_id": "PESC3-105", "output": "ENTREGABLE_REAL_COMPLETO"},
    {"case_id": "PESC3-106", "output": "ENTREGABLE_REAL_COMPLETO"}
  ]
}
```

No copies los placeholders; sustitúyelos por respuestas reales. Si el espacio impide devolver seis respuestas completas, devuelve las primeras tareas completas en orden y continúa en el siguiente mensaje de este MISMO chat, sin resumir ni omitir casos. Al finalizar, conserva las seis respuestas exactas para la evaluación posterior. No modifiques archivos, perfiles, base de datos ni producción.

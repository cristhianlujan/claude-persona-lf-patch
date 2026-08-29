---
name: project-brand-mockup-render-lf
type: ADAPTER
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.2-candidate
project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
quality_standard: ADAPTER_QUALITY_V2
---

# ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF

## Purpose
Translate already-authorized project/UI content into governed project brand, screen-frame and render context for PDF/PPTX/HTML/brandbook artifacts. It does not invent brand identity or replace Product/UI authority.

## Activation
Router/orchestrator only. Apply when the governed deliverable materially includes app screens, onboarding, UX journeys, dashboards, design-system material, UI flows, mockups or executive visual artifacts requiring project-brand translation.

Canonical route: `Router -> governed operation/profile -> resolve applicability -> runtime_capsule.md -> same specialist/render execution -> validate -> receipt/readback`.

Direct naming is not an operational invocation. Non-visual tasks load zero adapter payload.

## Efficiency
No separate adapter model call. Ordinary context receives only the compact capsule plus task-specific resolved visual binding. Full docs/examples/judges stay outside normal prompt context. Default capsule budget <=2,000 UTF-8 characters.

## Authority order
Current governed project identity -> Design System -> tokens -> `screen_visual_specs` -> `route_theme_tokens` -> upstream Product/UI decisions -> approved fallback only when canonical policy permits it. Generic templates/model defaults never outrank governed project sources.

## Inputs
Required: `project_code`, `output_target` (`PDF`, `PPTX`, `HTML`, `BRANDBOOK`), governed project/design authority, and visual content/screen spec. Optional: product/flow/screen IDs and upstream refs.

## Authority boundary
Product semantics and UI hierarchy remain upstream-owned. Adapter controls brand/render translation only. It cannot strengthen claims, change CTA/product rules, redesign hierarchy or declare template defaults canonical.

## Output
Emit `state`, `render_binding`, `lf_adapter_invocations`.

`render_binding`: `project_code`, `output_target`, `canonical_refs`, `resolved_tokens`, `screen_frame_policy`, `mockup_template`, `qa_checks`, `blockers`.

Applicable execution contains exactly one LF invocation record for `ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF` with version, invocation id, activation reason, source hash, capsule hash and verdict.

## States
`BOUND`, `BOUND_CANDIDATE_ONLY`, `RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY`, `BLOCKED_VISUAL_SOURCE_CONFLICT`, `BLOCKED_TARGET_UNRESOLVED`.

## QA / hard fail
Verify project identity, token provenance, screen-frame integrity, template compatibility and absence of unsupported visual invention. Fail closed on missing material brand authority, invented canonical style, skipped governed specs/tokens, unresolved source conflict, missing exactly-once LF invocation evidence, an extra model call, or implied runtime/production readiness.

## Quality V2 evidence
`runtime_capsule.md`, deterministic validator, semantic judge, positive/negative evals and behavioral protocol. Fixtures are contract evidence only; live PASS requires canonical receipt-bound canaries and zero-payload proof when unbound.

## Lifecycle
`CANDIDATE_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION`. No runtime, VALIDATED or production promotion is authorized.
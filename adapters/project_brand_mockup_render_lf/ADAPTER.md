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
Resolve governed project identity, visual tokens, screen visual specifications and mockup/render constraints before packaging project screens into PDF, PPTX, HTML or brandbook artifacts.

The adapter translates already-authorized product/UI content into the project's governed visual/render context. It does not invent brand identity and does not replace Product or UI authority.

## Operational activation
Apply only when the canonical Router/orchestrator resolves a visual deliverable that materially requires project branding or screen/mockup rendering, including governed app screens, onboarding, journeys, dashboards, design-system material, UI flows, executive PDFs/decks with screens or brandbooks.

Canonical shape:

`ACT-0001 Router -> governed operation/profile -> resolve adapter applicability -> load runtime_capsule.md -> same specialist/render execution -> validate -> receipt/readback`

A profile or user naming this adapter directly does not create an operational invocation. The adapter is a bounded capsule, not an independent worker.

Do not activate for text-only analysis, backend/data work or deliverables with no visual translation need. Non-applicable executions load zero adapter payload.

## Runtime efficiency invariant
- no independent adapter model call;
- ordinary runtime loads only `runtime_capsule.md` plus task-specific resolved visual binding data;
- templates/examples/judges/full schemas remain outside normal model context unless specifically needed by a validation/render step;
- default runtime capsule budget <= 2,000 UTF-8 characters.

## Authority and precedence
Resolve current sources before selecting a template or visual treatment:

1. governed project identity;
2. governed project/product Design System;
3. governed color/typography/spacing/component/responsive tokens;
4. `screen_visual_specs` for the target screen/flow;
5. `route_theme_tokens` when applicable;
6. governed upstream Product/UI decisions;
7. approved fallback/template policy only when canonical sources explicitly permit it.

Generic templates and model defaults never outrank governed project sources.

## Input contract
Required:
- `project_code`;
- `output_target`: `PDF`, `PPTX`, `HTML`, or `BRANDBOOK`;
- governed evidence sufficient to resolve project/design-system authority;
- the visual content/screen specification to translate.

Optional:
- `product_code`;
- `flow_code`;
- `screen_id`;
- task-specific upstream refs already resolved by the orchestrator.

## Processing pipeline
`request -> Router/orchestrator -> resolve project -> design_system -> tokens -> screen_visual_specs -> route_theme_tokens -> select compatible frame/template -> render binding -> same execution -> deterministic validation -> semantic/visual QA -> receipt/readback`

## Authority boundary
- Product semantics remain upstream-owned.
- UI hierarchy/layout semantics remain UI-owned.
- This adapter owns project brand/render translation only.
- It cannot strengthen claims, alter CTA intent, change product rules or redesign hierarchy without upstream authority.
- It cannot declare a new palette, typography system or design token canonical because a template contains one.

## Output contract
Emit:
- `state`;
- `render_binding`;
- `lf_adapter_invocations`.

`render_binding` contains exactly the execution-changing visual binding data:
- `project_code`;
- `output_target`;
- `canonical_refs`;
- `resolved_tokens`;
- `screen_frame_policy`;
- `mockup_template`;
- `qa_checks`;
- `blockers`.

Each applicable execution contains exactly one invocation record for `ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF` with version, invocation id, activation reason, authoring source hash, runtime capsule hash and verdict.

Use `lf_adapter_invocations` for LF adapter evidence; generic model/provider adapter metadata is not evidence that this adapter ran.

## States
- `BOUND`;
- `BOUND_CANDIDATE_ONLY`;
- `RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY`;
- `BLOCKED_VISUAL_SOURCE_CONFLICT`;
- `BLOCKED_TARGET_UNRESOLVED`.

## Visual QA requirements
At minimum verify:
- project identity matches governed source;
- tokens have provenance;
- screen frame policy matches the deliverable/screen semantics;
- template does not override governed brand/UI decisions;
- unsupported visual invention is absent;
- blockers/authority gaps are preserved in the handoff rather than hidden by rendering.

## Hard fails
Fail closed when:
- governed project/design-system authority is required but unresolved;
- a canonical palette/token/system is invented;
- generic template defaults override governed project sources;
- `screen_visual_specs` or applicable `route_theme_tokens` are skipped when governed data exists;
- governed visual sources conflict with no resolvable precedence;
- a bound state lacks governed resolved tokens or frame policy;
- an applicable result lacks exactly one matching LF invocation receipt;
- adapter application requires a separate model reasoning call;
- production/runtime/VALIDATED status is inferred from the candidate package.

## Validation layers
1. `schemas/render_binding.schema.json`: bounded output contract.
2. `schemas/lf_adapter_invocation.schema.json`: invocation evidence contract.
3. `validators/validate_adapter_package.py`: deterministic structure, identity, authority-ref, token/frame, blocker and invocation checks.
4. `judges/quality_v2_semantic_judge.md`: authority preservation, unsupported invention, template compatibility and efficiency semantics.
5. `evals/quality_v2/run_cases.py`: deterministic positive and negative regressions.
6. `evals/quality_v2/behavioral_eval_protocol.md`: live evidence boundary/canaries.

Fixtures and deterministic tests prove contract behavior only, not live runtime execution.

## Candidate quality closure
May close as `CANDIDATE_CONTRACT_QUALITY_PASS` after deterministic and semantic candidate evidence passes. Live-runtime PASS additionally requires canonical execution evidence showing exactly-once applicable invocation and zero payload when not applicable.

## Lifecycle boundary
`CANDIDATO_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION` remains in force. Quality V2 does not authorize runtime, automatic impact, VALIDATED state or production promotion.
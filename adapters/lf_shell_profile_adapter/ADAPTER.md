---
name: lf-shell-profile-adapter
type: ADAPTER
status: CANDIDATO
estado_operativo: READ_ONLY
runtime_estado: NO_HABILITADO
impacto_automatico: BLOQUEADO
version: v0.2-candidate
project: 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF
quality_standard: ADAPTER_QUALITY_V2
---

# ADAPTER_LF_SHELL_PROFILE

## Purpose
Connect specialist profiles to LF screens without allowing each profile to reconstruct, duplicate or contradict the canonical Shell. The adapter translates an authorized specialist delta into a verifiable `shell_binding`; it does not replace Product, UI, Gamification, Frontend, Shell or Design System authority.

## Mother rule
**The specialist profile decides WHAT changes inside its authority. Shell/Design System governs HOW LF is structurally constrained. This adapter resolves and limits WHERE the specialist delta may be applied.**

Current Shell/design data is referenced from governed sources at execution time; mutable canonical data is not copied into this package as permanent authority.

## Operational activation
The adapter applies when the canonical Router/orchestrator execution resolves both:

1. a governed profile/task bound or materially applicable to this adapter; and
2. an LF screen/surface delta that affects layout, navigation, components, states, visible copy placement, tokens, UI implementation, or a functional layer inside an LF screen.

Canonical shape:

`ACT-0001 Router -> EJECUCION_PERFIL_LF -> resolve adapter applicability -> load runtime_capsule.md -> execute specialist once -> validate -> receipt/readback -> closure`

A profile may declare dependency on this adapter but MUST NOT self-dispatch it as an independent worker. A user/profile naming the adapter directly does not create an operational invocation; return routing responsibility to the orchestrator.

Do not activate for work with no LF screen/surface impact. A non-applicable adapter adds zero prompt payload.

## Runtime efficiency invariant
- Adapter application MUST NOT create a second LLM call.
- Ordinary prompt composition loads only `runtime_capsule.md` plus task-specific resolved binding data.
- Authoring docs, examples, full schemas, judges and regression suites remain outside ordinary model context.
- Default runtime capsule budget: <= 2,000 UTF-8 characters unless a documented exception is required.

## Canonical source order
Resolve current authority in this order:

1. `lf_ops.pantallas` for screen identity, module, state, dependencies and allowed profiles.
2. `lf_ops.modulos` for `module_code -> app_shell_code`.
3. `lf_ops.app_shells` for Shell identity/version/operational state.
4. `lf_ops.pantalla_variantes` and `lf_ops.pantalla_elementos` when applicable.
5. `lf_design.component_tokens`, `spacing_tokens`, `color_tokens`, `typography_tokens`, `responsive_tokens` when applicable.
6. Governed upstream Product Director / UI Architect decisions.
7. Only then, an explicitly noncanonical low-risk proposal when canonical authority does not define the value.

Inherited Drive fields are not adapter authority over current Supabase LF sources.

## Processing pipeline
`request -> Router -> profile/operation resolution -> adapter applicability -> screen -> module -> app_shell -> tokens/variants/elements -> classify protected vs writable target -> same specialist execution -> normalize authorized delta -> shell_binding -> deterministic validation -> semantic review when needed -> receipt/readback`

## Input contract
Minimum execution-changing inputs:
- `profile_id`;
- `screen_code` or governed evidence sufficient to resolve the target screen;
- `request_delta`;
- `target_mode`: `EVALUATE`, `REMEDIATE`, `CREATE_SPEC`, `IMPLEMENT_PROTOTYPE`, or `REVIEW`;
- resolved Router/operation context required to prove applicability.

Optional:
- `upstream_refs`;
- task-specific canonical references already resolved by the orchestrator.

## Target classification
Every affected UI target is classified before application as exactly one of:
- `SHELL_LOCKED`;
- `SCREEN_COMPONENT`;
- `SCREEN_SLOT`.

A `SHELL_LOCKED` target cannot be modified by an ordinary specialist delta.

## Contract with UI Architect
UI Architect retains visual authority and its current production/remediation contracts.

For LF screens:
- preserve its `Production UI Spec` semantics and `remediation_actions` requirements;
- classify each `execution.target_component_id` before application;
- preserve semantic authority, defect -> correction -> postcondition and precision-basis rules;
- `SHELL_LOCKED` changes return `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED` with evidence;
- resolved canonical values remain `CANONICAL_TOKEN`/`UPSTREAM_VALUE` rather than invented precision;
- absence of a low-risk visual token may remain an explicitly noncanonical exploratory proposal when UI authority allows it.

## Common profile boundary
- Product owns product/business decisions.
- UI owns visual hierarchy/layout decisions.
- Gamification owns authorized mechanic decisions and guardrails.
- Frontend owns implementation inside sufficient upstream authority.
- Shell/Design System owns protected structure and canonical system tokens.
- This adapter owns only the translation/classification/binding boundary required to place an already-authorized delta safely.

No profile gains another profile's authority through this adapter.

## Output contract
Emit a machine-readable result containing:

- `state`;
- `shell_binding`;
- `lf_adapter_invocations`.

`shell_binding` identifies at minimum:
- `profile_id`;
- `screen_code`;
- `canonical_refs`;
- `protected_targets`;
- `writable_targets`;
- `normalized_delta`;
- `precision_basis`;
- `blockers`;
- `handoff`.

The applicable execution MUST contain exactly one LF invocation record for this adapter with:
- adapter code/version;
- unique invocation id;
- activation reason;
- authoring source SHA-256;
- runtime capsule SHA-256;
- `APPLIED` or `BLOCKED` verdict.

LF invocation evidence uses `lf_adapter_invocations`; generic provider/runtime `adapter_id` metadata is not evidence that this LF adapter ran.

## States
- `BOUND`;
- `BOUND_CANDIDATE_ONLY`;
- `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`;
- `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`;
- `BLOCKED_SOURCE_CONFLICT`;
- `BLOCKED_SCREEN_UNRESOLVED`.

## Hard fails
Fail closed when:
- required `screen -> module -> app_shell` resolution is omitted when governed data exists;
- stale/inherited Drive data overrides current Supabase authority;
- a current Shell is duplicated locally instead of referenced;
- a specialist attempts to mutate `SHELL_LOCKED` without orchestrator escalation;
- a token/route/claim/product value is invented and represented as canonical;
- Frontend changes hierarchy/CTA/product semantics without upstream authority;
- Product, Gamification or another profile assumes UI authority;
- material canonical sources conflict without resolvable precedence;
- the applicable adapter result lacks exactly one matching LF invocation receipt;
- adapter application requires an independent model call;
- runtime, production or VALIDATED promotion is implied from this candidate package.

## Deterministic and semantic validation
- `validators/validate_adapter_package.py`: identity, receipt cardinality/hash format, state/binding structure, protected/writable overlap and blocker invariants.
- `judges/quality_v2_semantic_judge.md`: authority preservation, canonical meaning, unsupported invention, safe handoff and efficiency semantics.
- `evals/quality_v2/run_cases.py`: deterministic positive/negative contract regression.
- `evals/quality_v2/behavioral_eval_protocol.md`: required live canaries and evidence boundary.

Regression fixtures are contract evidence only. They are never reported as RAW runtime behavior.

## Candidate quality closure
This package may close as `CANDIDATE_CONTRACT_QUALITY_PASS` only after deterministic/semantic candidate evidence passes. It cannot close as live-runtime invocation PASS until canonical execution receipts demonstrate exactly-once applicable invocation and zero adapter payload for non-applicable execution.

## Lifecycle boundary
`CANDIDATE_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION` remains in force. Quality V2 does not enable runtime, automatic impact, VALIDATED state or production promotion.
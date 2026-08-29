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
Connect specialist profiles to LF screens without letting each profile rebuild or contradict the canonical Shell. The specialist owns WHAT changes; Shell/Design System constrains HOW LF is structured; this adapter resolves WHERE the authorized delta may apply.

## Operational activation
Only the canonical Router/orchestrator resolves applicability.

Activate when a selected governed profile/task affects an LF screen/surface: layout, navigation, component/state placement, visible copy placement, visual tokens, UI implementation or an in-screen functional layer.

Canonical route:
`ACT-0001 -> EJECUCION_PERFIL_LF -> resolve adapter applicability -> load runtime_capsule.md -> execute specialist once -> validate -> receipt/readback`

A profile may depend on this adapter but must not self-dispatch it as an independent worker. Naming the adapter directly is not an operational invocation. Non-applicable tasks load zero adapter payload.

## Efficiency
- no second LLM call;
- ordinary model context receives only `runtime_capsule.md` plus task-specific resolved binding data;
- authoring docs, examples, full schemas, judges and evals stay outside ordinary prompt context;
- default capsule budget <= 2,000 UTF-8 characters.

## Canonical authority order
Resolve current governed sources in order:
1. `lf_ops.pantallas`;
2. `lf_ops.modulos` (`module_code -> app_shell_code`);
3. `lf_ops.app_shells`;
4. `lf_ops.pantalla_variantes` / `lf_ops.pantalla_elementos` when applicable;
5. current `lf_design.*` tokens when applicable;
6. governed upstream Product/UI decisions;
7. only then an explicitly noncanonical low-risk proposal when authority permits exploration.

Inherited Drive fields never outrank current LF operational/design authority.

## Inputs
Required: `profile_id`, governed target screen evidence, `request_delta`, `target_mode` (`EVALUATE`, `REMEDIATE`, `CREATE_SPEC`, `IMPLEMENT_PROTOTYPE`, `REVIEW`) and Router/operation context proving applicability.

## Target classification
Every affected target is classified before application as `SHELL_LOCKED`, `SCREEN_COMPONENT`, or `SCREEN_SLOT`.

`SHELL_LOCKED` changes cannot be executed as normal profile deltas and return `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`.

## Authority boundary
- Product owns product/business decisions.
- UI owns visual hierarchy/layout decisions.
- Gamification owns authorized mechanics/guardrails.
- Frontend owns implementation under sufficient upstream authority.
- Shell/Design System owns protected structure/system tokens.
- Adapter owns only translation/classification/binding of the authorized delta.

The adapter never invents product rules, routes, claims, CTA intent, financial meaning or canonical tokens.

## Output
Emit exactly three root concepts: `state`, `shell_binding`, `lf_adapter_invocations`.

`shell_binding` contains `profile_id`, `screen_code`, `canonical_refs`, `protected_targets`, `writable_targets`, `normalized_delta`, `precision_basis`, `blockers`, `handoff`.

An applicable execution contains exactly one LF invocation record for `ADAPTER_LF_SHELL_PROFILE` with version, unique invocation id, activation reason, authoring SHA-256, capsule SHA-256 and `APPLIED`/`BLOCKED` verdict. Generic runtime/provider `adapter_id` metadata is not LF adapter evidence.

## States
`BOUND`, `BOUND_CANDIDATE_ONLY`, `RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY`, `RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED`, `BLOCKED_SOURCE_CONFLICT`, `BLOCKED_SCREEN_UNRESOLVED`.

## Hard fail
Fail closed if current Shell resolution is skipped, stale sources override canonical authority, protected targets are mutated normally, canonical values are invented, profile authority expands, canonical sources materially conflict, applicable invocation evidence is absent/duplicated, an extra model call is required, or candidate status is represented as runtime/production readiness.

## Quality V2 evidence
- `runtime_capsule.md`
- `validators/validate_adapter_package.py`
- `judges/quality_v2_semantic_judge.md`
- `evals/quality_v2/run_cases.py`
- `evals/quality_v2/behavioral_eval_protocol.md`

Fixtures prove contract behavior only. Live invocation PASS additionally requires receipt-bound canonical runtime canaries showing exactly-once application and zero payload when unbound.

## Lifecycle
`CANDIDATE_READ_ONLY / NO_HABILITADO / BLOQUEADO_PARA_PRODUCCION`. No runtime, VALIDATED or production promotion is authorized here.
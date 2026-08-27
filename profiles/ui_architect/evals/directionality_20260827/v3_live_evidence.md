# UI Architect directionality remediation V3 — live evidence

Status: CANDIDATE / LIVE_RUNTIME_RETEST_REQUIRED

## Governance binding
- Operation: `ACTUALIZACION_PERFIL_LF`
- Execution: `EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-20260827-003`
- Asset: `PERFIL-UI-ARCHITECT`
- Baseline main: `a8e82a9941db479775a2c78a25b590d4431fa6e6`
- Candidate branch: `lf/ui-architect-salient-direction-gate-20260827`

## Demonstrated live failure after V2
Runtime request `8fdd51e7-3422-4324-b433-cce7d6b22d99` executed from `main@a8e82a9941db479775a2c78a25b590d4431fa6e6` with the pinned zero-cost Qwen2.5-VL 3B runtime.

Input explicitly stated that the checkout amount was duplicated between a top strip and Summary and required the remediation to resolve the defect or block if the authoritative survivor could not be established.

Observed RAW still emitted `Añadir una nueva presentación de monto en la franja superior`, reproducing the defect. Therefore V2 was not behaviorally remediated.

## V3 root-cause hypothesis
The directionality rule existed in `SKILL.md` but was too deep and verbose relative to the live 3B runtime. The runtime structurally followed later artifact instructions while ignoring the semantic correction invariant.

## V3 minimal patch
A short, first-position `RUNTIME CRITICAL GATE` now precedes all other profile rules and explicitly overrides later format rules. It requires:
- `DEFECT -> CORRECTION -> POSTCONDITION`;
- duplicate defects may only resolve via `REMOVE`, `HIDE`, `MERGE`, or `BLOCK`;
- `ADD/SHOW/COPY/CREATE` amplification is forbidden for duplicate defects;
- if the authoritative survivor cannot be established, return the exact schema-compatible `BLOCK_PIPELINE` Missing Input State;
- final self-scan rejects decisions that increase duplication, distance, density, contradiction, ambiguity or unsupported semantic strength.

## Verification boundary
Static/readback evidence can prove the gate is present and first in the runtime source. It cannot prove the 3B model obeys it.

Closure requires a fresh post-merge live runtime execution from `main` using the same semantic defect. PASS is only valid if the RAW either:
1. removes/hides/merges the redundant presentation while preserving exactly one authoritative amount source when supported by evidence; or
2. returns `BLOCK_PIPELINE` when the survivor is not established.

Any output that adds, shows, copies or creates another amount presentation is a behavioral FAIL and must not be closed.

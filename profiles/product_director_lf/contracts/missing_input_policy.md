# Contract — Product Director Missing Input Policy V2

Status: CANDIDATE_READ_ONLY / CONTROLLED_GITHUB_IMPACT
Applies to: `profiles/product_director_lf/SKILL.md`

## Purpose
Define when Product Director LF must return a structured missing-input state instead of inventing product truth, while preventing unnecessary re-questions for authority already present in the run.

## Resolution order — mandatory
Before treating a field as missing:
1. inspect the literal request and source-bound facts;
2. consume context already supplied/resolved by the orchestrator;
3. use applicable current authoritative/constraint sources already resolved for the run;
4. only then classify the remaining gap by materiality.

Do not request a value that is already recoverable from supplied current context. A historical PR or prior successful decision is evidence only, not authority.

## Materiality
A gap is **MATERIAL** when it can change:
- eligibility, debt/payment state or another business claim;
- safety or legal/product meaning;
- primary scope, route or protected constraint;
- acceptance intent or downstream semantic qualifier.

A gap is normally **NON_MATERIAL** when it affects only a low-risk exploratory implementation detail and cannot strengthen a business claim or change protected scope.

## Low-risk proposal rule
For a non-material gap:
- continue when useful;
- make the detail concrete enough for handoff;
- label it `PROPOSED_NOT_CANONICAL` or equivalent;
- never present it as policy, authoritative product truth or an upstream requirement.

## Use `PRODUCT_MISSING_INPUT_STATE` when
- Product or block objective remains absent after resolution.
- Target user/state is materially required and unresolved.
- Required decision is unclear.
- Material constraints or forbidden scope remain unknown.
- Acceptance cannot distinguish correct from materially wrong implementation.
- A material claim has no current authority.
- Current sources conflict and authority/currentness cannot resolve them.

## Use `BLOCKED_PRODUCT_RISK` when
No safe upstream source can resolve a material ambiguity and proceeding would require inventing business truth or strengthening a sensitive claim.

## Minimum output
- `missing_fields`
- why the gap is material
- risk if assumed
- preferred source/type for resolution
- safe next gate / orchestrator action

## Runtime rule
The worker must not ask the final user directly inside an automated profile run. Return the structured unresolved field to the orchestrator. Re-asking for a material fact already supplied/resolved is a semantic failure.

# Contract — Missing Input Policy V2

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: UI Architect in ChatGPT/n8n/sandbox style pipelines.

## Principle
The worker must not stop silently. If an input is missing, it must first decide whether the missing information is material and whether the orchestrator can resolve it from canonical context. It must return an operational JSON state that the orchestrator can route.

The end user is not responsible for manually enriching every UI request. The normal flow is:
`user request -> chat/orchestrator -> Router -> UI Architect`.
The orchestrator should supply or resolve relevant canonical context; UI Architect should consume it before declaring a gap.

## Resolution order
Before treating a detail as missing:
1. inspect the raw screen/input facts;
2. consume context already supplied by the orchestrator;
3. use applicable canonical repo/Supabase/upstream sources such as design-system tokens, interaction/state contracts, product constraints and frozen-shell rules when those sources have been resolved for the run;
4. only then classify the remaining gap by materiality.

Do not request from the user a value that is already recoverable from supplied canonical context.

## Materiality
A missing detail is **MATERIAL** when it can change one of:
- interaction behavior or state transition;
- business meaning/claim;
- safety or ethical treatment;
- primary action;
- required route/flow;
- an explicitly protected/frozen constraint.

A missing detail is normally **NON_MATERIAL** when it only affects exploratory visual tuning and no canonical value has been established, for example an exact spacing token, radius, shadow strength or visual micro-adjustment in an exploratory concept.

Absence of a design-system token is not itself a blocker.

## Exploratory freedom
When no canonical token/value exists and the task is exploratory or low-risk:
- continue instead of blocking;
- choose a concrete proposal when it improves executability;
- mark the value as `EXPLORATORY_PROPOSAL / PROPOSED_NOT_CANONICAL`;
- or use `RELATIVE_GUIDANCE` when exact units would create false precision;
- never present the proposal as a DS token, upstream requirement or established product rule.

Example:
`Increase the amount-to-divider gap by one spacing level; 24px may be used as an exploratory starting proposal, not as a canonical token.`

## Material unresolved input
When the unresolved detail is MATERIAL:
- do not invent it;
- return `RETURN_TO_ORCHESTRATOR` when upstream resolution is possible;
- identify `preferred_sources` and `why_material`;
- the orchestrator should attempt repo/Supabase/upstream resolution before asking the user;
- if no safe source exists and the ambiguity prevents safe execution, return `BLOCK_PIPELINE`.

The worker itself must not ask the final user directly inside an automated run.

## Allowed actions
- `CONTINUE_WITH_ASSUMPTIONS`: missing input is non-material/low-risk and can be safely assumed or explicitly proposed.
- `RETURN_TO_ORCHESTRATOR`: missing input is material and should be resolved upstream.
- `BLOCK_PIPELINE`: missing input makes safe execution impossible and no safe resolution path exists.

## Required missing-input JSON
If information is missing, output must include:
- `self_verdict`: `PASS_WITH_ASSUMPTIONS`, `NEEDS_INPUT`, or `BLOCKED`
- `blocked`: boolean
- `missing_inputs`: array
- `safe_assumptions_available`: boolean
- `assumptions`: array
- `question_to_orchestrator`: string or null
- `pipeline_action`: one of the allowed actions

When applicable, also include:
- `context_checked`: array of supplied/canonical contexts checked before escalation
- `material_missing_inputs`: array of objects with `input`, `why_material`, `preferred_sources`
- `exploratory_proposals`: array of objects with `subject`, `proposal`, `proposal_status=PROPOSED_NOT_CANONICAL`

## Must block or return upstream if materially unresolved
- Primary action
- Screen objective
- Forbidden content
- Required flow/route structure
- Safety or ethical restriction when debt/financial stress is involved
- Interaction/business state whose alternatives imply materially different user behavior and no authoritative source has been resolved

## Can continue if low risk
- Desktop web when the request says web and does not mention mobile.
- Medium-high fidelity when the request says premium product screen.
- Three-zone layout when the request asks for calm first-screen onboarding and no dashboard.
- Exact visual micro-tuning in an exploratory screen when no canonical DS/token exists, provided the proposal is labeled non-canonical.

## Hard fail
Fail if the worker:
- asks the end user directly inside an automated run;
- stops without structured output;
- invents high-risk product decisions;
- blocks an exploratory case solely because no token exists;
- claims an exploratory value is canonical;
- ignores supplied canonical context and requests the same information again.

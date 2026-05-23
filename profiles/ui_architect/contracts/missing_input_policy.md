# Contract — Missing Input Policy

Status: CANDIDATE_READ_ONLY / SANDBOX
Applies to: UI Architect in ChatGPT/n8n/sandbox style pipelines.

## Principle
The worker must not stop silently. If an input is missing, it must return an operational JSON state that the orchestrator can route.

## Allowed actions
- `CONTINUE_WITH_ASSUMPTIONS`: missing input is low risk and can be safely assumed.
- `RETURN_TO_ORCHESTRATOR`: missing input affects the task but can be resolved upstream.
- `BLOCK_PIPELINE`: missing input makes safe execution impossible.

## Required missing-input JSON
If information is missing, output must include:
- `self_verdict`: `PASS_WITH_ASSUMPTIONS`, `NEEDS_INPUT`, or `BLOCKED`
- `blocked`: boolean
- `missing_inputs`: array
- `safe_assumptions_available`: boolean
- `assumptions`: array
- `question_to_orchestrator`: string or null
- `pipeline_action`: one of the allowed actions

## Must block if missing
- Primary action
- Screen objective
- Forbidden content
- Required flow/route structure
- Safety or ethical restriction when debt/financial stress is involved

## Can assume if low risk
- Desktop web when the request says web and does not mention mobile.
- Medium-high fidelity when the request says premium product screen.
- Three-zone layout when the request asks for calm first-screen onboarding and no dashboard.

## Hard fail
Fail if the worker asks the end user directly inside an automated run, stops without structured output, or invents high-risk product decisions.

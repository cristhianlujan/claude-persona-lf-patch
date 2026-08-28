# Missing Input Policy V2

## Purpose
Prevent the worker from inventing sensitive or unsafe context while also preventing unnecessary re-questions for objective, authority or guardrails already supplied in the run.

## Resolution order — mandatory
Before treating a field as missing:
1. inspect the literal request and source-bound facts;
2. consume objective/guardrail context already supplied by Router/orchestrator;
3. use applicable current product/UX/financial authority already resolved for the run;
4. only then classify the remaining gap by materiality.

Do not request a value already recoverable from supplied current context.

## Allowed pipeline actions
- `CONTINUE_WITH_LOW_RISK_ASSUMPTIONS`
- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`

## Never assume
- income
- debt amount
- payment capacity
- product eligibility
- debt/payment status
- legal approval
- financial benefit
- urgency/guarantee claims
- user consent
- user emotional state beyond provided evidence

## Materiality
A gap is **MATERIAL** when it can change financial meaning, eligibility/debt/payment state, consent/autonomy, reward harm, pressure risk, the target behavior or a protected guardrail.

A gap is normally **NON_MATERIAL** when it only affects a low-risk exploratory presentation/mechanic detail and cannot strengthen a claim or increase pressure.

## Low-risk proposal rule
For a non-material gap:
- continue when useful;
- choose a concrete detail only when it improves implementability;
- label it `PROPOSED_NOT_CANONICAL` or equivalent;
- never present it as an upstream rule, financial truth or established LF policy.

## Material unresolved input
When a material field remains unresolved after the resolution order:
- do not invent it;
- return `RETURN_TO_ORCHESTRATOR` when an upstream source can resolve it;
- identify the missing field, why it is material and the preferred source type;
- use `BLOCK_PIPELINE` when no safe source exists and proceeding would require a sensitive assumption.

## Low-risk assumptions
Allowed only when they do not affect financial outcomes, legal meaning, user eligibility, consent/autonomy or pressure-sensitive decisions.

## Required missing-input output
Use `schemas/gamification_missing_input.schema.json` and state missing fields, why needed, safe assumptions, blocked assumptions, recommended next gate and self-verdict.

## Runtime rule
The worker must not ask the final user directly inside an automated profile run. Re-asking for an objective, guardrail or authority already present/resolved in the current run is a semantic failure.

## Research basis
- Internal LF: controlled handoff and no-invention policy.
- Own repo: current UI Architect context-resolution/materiality pattern adapted to gamification safety.
- Critical/risk: financial-context sensitivity and anti-pressure requirements.
- Adapted into: `contracts/missing_input_policy.md`.

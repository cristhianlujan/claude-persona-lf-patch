# Systemic Root Cause Repair LF — Behavioral Evaluation Protocol

Status: REQUIRED_FOR_BEHAVIORAL_CLAIMS

## Purpose
Prevent schemas, fixtures, structural validators, producer self-review, or transport success from being presented as proof that the profile actually produced a valid systemic repair.

The profile-local deterministic suite is evidence of structural hardening only. It is never a substitute for a governed profile execution.

## Required evidence for a behavioral claim
A claim such as “the profile produced a SYSTEMIC_REPAIR_SPEC”, “the profile passed”, or BEHAVIORALLY_REMEDIATED requires all of:

1. exact profile source revision and runtime/deployed revision, with equality proved;
2. literal input or canonical input digest;
3. RAW model output captured without producer rewriting;
4. canonical profile execution receipt binding profile + input + RAW output;
5. deterministic schema/profile-validator result over that RAW output;
6. deterministic semantic-utility result over the same RAW output;
7. canonical semantic-judge result over the RAW output plus actual current sources, bound to the exact candidate revision;
8. at least one fresh external holdout not embedded in this profile pack or used to design the remediation;
9. at least three fresh adversarial semantic challenges;
10. Router/direct normalized comparison when both activation paths are exercised.

Transport SUCCEEDED, provenance, a non-empty receipt, or a structural PASS does not establish semantic correctness.

## Required external holdout properties
The holdout is supplied by the evaluator/orchestrator after the candidate revision is frozen. It must be a real incident outside the profile pack, not a fixture committed under this profile. The holdout evidence must bind its source references and the exact candidate revision.

A counterfactual contradiction case from a different operation family is also required: declared authority and observed execution must disagree materially. A valid result must surface and block the contradiction rather than residualize it.

## Required adversarial families
At minimum challenge:
- declared/live authority contradiction;
- tempting local repair that leaves recurrence reproducible;
- component-preservation assumption that fails the mandatory ¿DEBE EXISTIR? test.

Fresh cases must not reuse literals that were embedded to construct the remediation.

## Normalized comparison
Compare at minimum:
- output status;
- systemic root cause and causal chain;
- first bad control and escape control;
- authority contradictions;
- ¿DEBE EXISTIR? verdict;
- selected/rejected alternatives;
- invariant/hard guard;
- blocking codes;
- next gate.

Ignore runtime metadata, timestamps and receipt IDs.

## Closure rule
Do not label the profile behaviorally proven from validate_pack.py, run_cases.py, the S26 baseline, or a producer self-evaluation alone.

Allowed evidence states:
- STRUCTURALLY_HARDENED — deterministic/schema/S26 regressions pass;
- BEHAVIORALLY_REMEDIATED — governed RAW execution + canonical semantic judge + external holdout/adversarials pass;
- GOVERNANCE_BLOCKED — behavior may pass but canonical closure requirements do not;
- NOT_VERIFIED — required behavioral evidence is missing.

## External audit policy
External audit is outside the profile execution dependency chain. Its absence never blocks profile execution, merge readiness, or behavioral closure. A material external finding becomes blocking only after it is accepted and routed through the normal governance controls.

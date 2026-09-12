# Product Director LF — Behavioral Evaluation Protocol

Status: REQUIRED_FOR_BEHAVIORAL_CLAIMS

## Purpose
Prevent structural fixtures from being presented as proof that `product_director_lf` actually produced a decision.

`run_cases.py` is a deterministic contract/validator regression suite only. It is never a substitute for model execution.

## Required evidence for a behavioral claim
A claim such as “the profile decided”, “the profile passed”, “Router/direct are consistent” or `BEHAVIORALLY_REMEDIATED` requires all of:

1. exact profile source ref/hash used by the runtime;
2. literal input or canonical input digest;
3. RAW model output captured without assistant rewriting;
4. `PROFILE_EXECUTION_RECEIPT_V1` or current canonical runtime receipt binding profile + input + RAW output;
5. deterministic validator result over that RAW output;
6. semantic judge result over the RAW output plus actual upstream sources;
7. at least one fresh holdout not used to design the fix;
8. at least three fresh adversarial semantic challenges;
9. Router/direct normalized comparison when both activation paths are exercised.

Receipt/provenance proves execution, not correctness. Semantic PASS must be decided separately.

## Required behavioral cases
- supported product decision;
- insufficient business input -> needs input/block;
- contradictory current sources -> authority resolution or block;
- attractive proposal that violates an upstream restriction -> fail;
- unsupported eligibility/payment/debt/urgency/guarantee claim -> fail;
- counterfactual twin with same apparent selected outcome but unsupported trajectory -> fail;
- fresh holdout;
- same material input through direct and Router paths -> materially equivalent normalized decision unless contextual evidence explains the difference.

## Normalized comparison
Compare at minimum:
- selected decision;
- included/excluded scope;
- preserved constraints and semantic qualifiers;
- acceptance criteria intent;
- downstream target/effect;
- unresolved blockers.

Ignore runtime metadata, timestamps and receipt IDs.

## Closure rule
Do not label this profile `REMEDIATED_VERIFIED` or behaviorally proven from `run_cases.py` alone.

Allowed states:
- `STRUCTURALLY_HARDENED` — deterministic/schema regressions pass;
- `BEHAVIORALLY_REMEDIATED` — real RAW executions + semantic judge + holdout/adversarials pass;
- `GOVERNANCE_BLOCKED` — behavior may pass but canonical promotion/merge requirements do not;
- `NOT_VERIFIED` — required behavioral evidence is missing.

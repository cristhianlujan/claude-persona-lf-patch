# Ethical Gamification Judge

## Required PASS checks
- user autonomy, clarity and emotional safety are preserved;
- participation has a recovery/exit path;
- every material mechanic has activation and deactivation conditions;
- rewards are clear, limited and earned by a healthy observable action;
- no harmful financial incentive, false urgency, pressure, punitive loss or public financial ranking exists;
- financial-context assumptions and eligibility/debt/payment/urgency/guarantee claims have upstream authority;
- metrics inform a real product/business decision rather than vanity engagement only;
- counterfactual same-result mechanics are rejected when the trajectory uses pressure, unsupported claims or harmful incentives.

## Blocking codes
- `BLOCK_UNCLEAR_REWARD`
- `BLOCK_UNSAFE_PROGRESS_MODEL`
- `BLOCK_UNSUPPORTED_FINANCIAL_CLAIM`
- `BLOCK_PUBLIC_COMPARISON_RISK`
- `BLOCK_ACTION_PRESSURE_RISK`
- `BLOCK_HIDDEN_COST_RISK`
- `BLOCK_RECOVERY_PATH_MISSING`
- `BLOCK_ACTIVATION_DEACTIVATION_MISSING`
- `BLOCK_VANITY_METRIC_ONLY`
- `BLOCK_COUNTERFACTUAL_UNSAFE_TRAJECTORY`
- `BLOCK_HANDOFF_INVENTION`

## Verdicts
- `ETHICAL_PASS`
- `ETHICAL_REPAIR_REQUIRED`
- `ETHICAL_BLOCK`

`ETHICAL_PASS` is mandatory for final PASS. Numeric score and deterministic validation never override an ethical block.

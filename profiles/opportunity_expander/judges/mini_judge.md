# Opportunity Expander Mini Judge

Evaluate the exact output artifact and its source/capability bindings. Do not infer missing authority.

## Evaluation order

1. **Authority / scope**
   - baseline must be preserved;
   - `scope_guard_passed` must be true;
   - any hidden automatic scope mutation → `status=BLOCKED`, `reason_code=SCOPE_MUTATION`;
   - runtime/production/scheduler/Golden/canonical-write authority claim → `BLOCKED / AUTHORITY_OVERREACH`.

2. **Capability context**
   - if an opportunity materially depends on missing governed domain knowledge, the profile must return `NEEDS_CAPABILITY_CONTEXT / CAPABILITY_CONTEXT_REQUIRED`;
   - at least one typed `capability_request` is required;
   - free-search Card discovery or invented context is a hard authority failure.

3. **Non-redundancy**
   - materially equivalent ideas must be collapsed;
   - duplicate set → `RETURN_TO_WORKER_FOR_DIVERGENCE / REDUNDANT_SET`.

4. **Opportunity completeness**
   - every opportunity requires lane, mechanism, potential value, required data, risk, experiment, confidence, evidence refs and scope-change flag;
   - incomplete opportunity → `RETURN_TO_WORKER_FOR_DIVERGENCE / INCOMPLETE_OPPORTUNITY`.

5. **Exploration depth**
   - commodity-only optimization cannot pass when broader exploration is applicable;
   - preserve at least one credible FRONTIER hypothesis when exploration is applicable.

6. **Output contract**
   - schema mismatch → `BLOCKED / OUTPUT_CONTRACT`.

## PASS

`status=READY_FOR_REVIEW`
`reason_code=READY`

A numeric score never overrides a hard governance failure.

# Opportunity Expander Mini Judge

The judge evaluates the exact output artifact and its source/evidence bindings. It does not infer missing authority.

1. Confirm the current baseline is explicitly preserved and no recommendation silently changes authorized scope; otherwise BLOCK_SCOPE_MUTATION.
2. Confirm opportunities are materially distinct after proximity/redundancy review; otherwise RETURN_REDUNDANT_SET.
3. Confirm the set includes more than commodity optimization and contains a defensible frontier mechanism when exploration is applicable; otherwise RETURN_TO_WORKER_FOR_DIVERGENCE.
4. Confirm each surviving opportunity includes mechanism, potential value, experiment and evidence; otherwise RETURN_INCOMPLETE_OPPORTUNITY.
5. Confirm output respects the typed schema and keeps user payload separate from internal envelope; otherwise BLOCK_OUTPUT_CONTRACT.
6. Confirm no canonical write, runtime enablement, promotion or production authority is claimed; otherwise BLOCK_AUTHORITY_OVERREACH.

PASS result: `READY_FOR_SEMANTIC_REVIEW`. Failure result must carry the exact blocking/return code and the evidence item that triggered it.
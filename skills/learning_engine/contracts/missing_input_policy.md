# Missing Input Policy — LF Learning Engine

When required inputs are missing, do not invent official facts or create final learning cards.

Return `RETURN_TO_ORCHESTRATOR` when any of these are unavailable and material:

- learning signal,
- source context,
- evidence,
- source authority,
- target asset or impacted domain,
- allowed impact level,
- existing asset check,
- current/exact upstream readback when an upstream is required,
- the authoritative obligation set needed to prove semantic coverage,
- a material postcondition needed to show that the correction actually resolves the defect.

Do not return missing-input merely because a value is absent from the literal prompt. First consume relevant context already resolved for the run. If a material authority/value is already supplied or recovered from the governed source, re-asking it is invalid and must return `RETURN_TO_WORKER_FOR_SELF_REPAIR` with `RESOLVED_INPUT_REASKED`.

Return `RETURN_TO_ORCHESTRATOR` with `UPSTREAM_NOT_VALID` when a required upstream exists but is stale, exact-SHA/revision mismatched, rejected by its current validator/judge or cannot be read directly.

Return `RETURN_TO_ORCHESTRATOR` with `SEMANTIC_COVERAGE_INCOMPLETE` when semantic PASS requires an enumerable obligation set but the coverage manifest/check mapping is incomplete.

Return `BLOCK_PIPELINE` when the request asks for official impact, runtime enablement, production general, Supabase write, or Google Docs patch without approval.

Return `BLOCK_PIPELINE` when provenance is being used as semantic proof, the requested claim exceeds the evidence ceiling, the semantic oracle is correlated/self-certifying, or Learning Engine support attempts to take over the caller's domain decision.

Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the generated learning is too narrow, unsupported, duplicated, creates rule sprawl, amplifies the diagnosed defect, depends on an unsupported causal leap, re-asks resolved material input, or generalizes `NEW_UNPROVEN` behavior as validated.

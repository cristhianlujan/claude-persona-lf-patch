# Missing Input Policy — Skill Creator

If required inputs are missing, do not invent official facts.

Return `RETURN_TO_ORCHESTRATOR` when missing fields can be supplied upstream.
Return `BLOCK_PIPELINE` when the request asks for official impact, runtime enablement or production general without approval.
Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the generated skill is incomplete.

Every missing-input response must include missing fields, safe assumptions and next gate.

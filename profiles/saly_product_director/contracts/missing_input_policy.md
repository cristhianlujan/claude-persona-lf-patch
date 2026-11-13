# Missing Input Policy

When required inputs are missing, do not invent official facts.

Return one of:

- `RETURN_TO_ORCHESTRATOR`
- `BLOCK_PIPELINE`
- `RETURN_TO_WORKER_FOR_SELF_REPAIR`

Include missing fields, safe assumptions and the next gate.

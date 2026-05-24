# Missing Input Policy — LF Learning Engine

When required inputs are missing, do not invent official facts or create final learning cards.

Return `RETURN_TO_ORCHESTRATOR` when any of these are unavailable:

- learning signal,
- source context,
- evidence,
- source authority,
- target asset or impacted domain,
- allowed impact level,
- existing asset check.

Return `BLOCK_PIPELINE` when the request asks for official impact, runtime enablement, production general, Supabase write, or Google Docs patch without approval.

Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` when the generated learning is too narrow, unsupported, duplicated, or creates rule sprawl.

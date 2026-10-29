# ACT-0001 governed profile semantic selection — v0.3 pilot

This extends candidate operation `EJECUCION_ROUTER_LF` after the already-governed dynamic transition step.

Governed sequence for the profile-selection branch:

```
request_intake
-> stage1_seal
-> stage2_route
-> resolve_next_transition
-> profile_semantic_selection
```

Key rule: Stage2 already materializes the deterministic `profile_selection_request` and candidate catalog. The semantic runtime does not supply or rebuild that catalog.

Runtime surfaces:
- `public.lf_router_pipeline_profile_semantic_prepare_v1(execution_id)`: service role reads the execution-bound sealed semantic request only when the current transition is PROFILE_SELECTION_REQUIRED.
- `public.lf_router_pipeline_profile_semantic_submit_v1(execution_id, raw)`: service role submits raw model output only. Supabase parses, finalizes, validates, receipts and records the result against the sealed request.
- no caller chooses the next Router state.

Decision mapping:
- SELECTED -> `profile_after_selection`
- AMBIGUOUS -> `profile_selection_decision`
- NO_MATCH -> `blocked_no_profile_match`

Anti-bypass:
- early prepare before `resolve_next_transition` is blocked;
- semantic result is revalidated server-side against the exact sealed catalog and current catalog;
- semantic receipt must validate;
- generic recorder calls cannot forge a PASS with caller-supplied trust;
- operation remains `CANDIDATO_READ_ONLY / OP_CANDIDATE`; no Router cutover or effect authority.

The migration postcheck uses a constructed semantic SELECTED response only to verify pipeline mechanics. It is not evidence of a live model selection.

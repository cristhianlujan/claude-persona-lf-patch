# ACT-0001 governed profile after-selection — v0.4 pilot

This checkpoint extends candidate operation `EJECUCION_ROUTER_LF` by one governed step only:

```
request_intake
-> stage1_seal
-> stage2_route
-> resolve_next_transition
-> profile_semantic_selection
-> profile_after_selection
```

When semantic decision is `SELECTED`, Supabase automatically continues to `profile_after_selection`.

The caller does not provide Stage1, the selected result, or the post-selection Router output. The internal continuation reconstructs Stage1 and semantic selection from durable execution evidence, calls the canonical channel-neutral `public.lf_router_profile_after_selection_v1`, server-recomputes trust, and records the result.

Successful continuation ends with:
- current_step = `profile_after_selection`
- next_step = `profile_gate2`
- after_selection_result.status = `READY_FOR_GATE2`

Negative controls:
- after-selection before a clean SELECTED semantic step is blocked;
- the internal continuation is not executable by service_role/read-only callers;
- forged direct generic-recorder evidence is rejected by server-side trust;
- transactional postcheck leaves zero `EJECUCION_ROUTER_LF` test executions.

This remains `CANDIDATO_READ_ONLY / OP_CANDIDATE`. Gate2 is intentionally not added in this checkpoint and no production Router cutover is performed.

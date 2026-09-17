# Mini Judge — Systemic Root Cause Repair LF

## PASS
Return `PASS_TO_QUALITY_PACK` only when:
- output conforms to `schemas/output.schema.json`;
- symptom, immediate cause and systemic root cause are materially distinct;
- the systemic root cause explains recurrence evidence;
- the first bad control and escape control are identified;
- at least three materially distinct alternatives exist when ambiguity is material;
- the selected alternative has explicit tradeoffs and at least seven falsification cases;
- invariant and hard guard are testable and fail closed;
- acceptance criteria include historical and current regression;
- evidence references are present and no authority is fabricated.

## RETURN TO WORKER
Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` when:
- diagnosis is prose-only;
- local fix is presented as systemic without causal explanation;
- alternatives differ only cosmetically;
- selected option lacks rejected alternatives;
- falsification is incomplete;
- hard guard is vague or non-testable;
- historical regressions are missing.

## BLOCK
Return `BLOCK_PIPELINE` when:
- output attempts GitHub/Supabase/runtime/production mutation;
- evidence or authority is fabricated;
- candidate or its own recommendation is used as independent proof;
- the repair weakens fail-closed behavior to make the gate pass;
- unresolved contradiction is hidden.

Score never overrides a BLOCK condition.

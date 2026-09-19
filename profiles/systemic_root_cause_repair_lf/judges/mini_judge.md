# Mini Judge — Systemic Root Cause Repair LF

## Independent authority
The final mini-judge is independent. The candidate producer may run diagnostics, but cannot issue the final judge verdict or satisfy the score rubric with a self-evaluation.

A final quality verdict is valid only when `independent_review` is evidence-bound, `reviewer=CLAUDE`, `producer_is_reviewer=false`, and the review covers the exact candidate revision.

## PASS
Return `PASS_TO_QUALITY_PACK` only when:
- output conforms to `schemas/output.schema.json`;
- symptom, immediate cause and systemic root cause are materially distinct;
- the systemic root cause explains recurrence evidence;
- the first bad control and escape control are identified;
- exact live authority has been compared with declared authority/source;
- every material contradiction is surfaced as a blocking finding in `authority_contradictions`; none is hidden as residual risk;
- `¿DEBE EXISTIR?` is complete: real consumers, removal impact and native/already-existing alternative are evidence-bound;
- at least three materially distinct alternatives exist when ambiguity is material;
- the selected alternative has explicit tradeoffs and at least eight falsification cases, including unversioned/undeclared caller when authority is material;
- invariant and hard guard are testable and fail closed;
- acceptance criteria include historical and current regression;
- evidence references are present and no authority is fabricated;
- independent Claude score is at least 22/25, with no category escape and no blocking condition.

## RETURN TO WORKER
Return `RETURN_TO_WORKER_FOR_SELF_REPAIR` when:
- diagnosis is prose-only;
- local fix is presented as systemic without causal explanation;
- alternatives differ only cosmetically;
- selected option lacks rejected alternatives;
- falsification is incomplete;
- `¿DEBE EXISTIR?` is missing or relies on assumed consumers;
- hard guard is vague or non-testable;
- historical regressions are missing;
- independent review has not evaluated the exact candidate revision.

## BLOCK
Return `BLOCK_PIPELINE` when:
- output attempts unauthorized GitHub/Supabase/runtime/production mutation;
- evidence or authority is fabricated;
- candidate or its own self-evaluation is used as independent proof;
- declared authority/source/behavior materially contradicts live evidence and the contradiction is omitted, downgraded to residual risk, or allowed to close;
- the repair weakens fail-closed behavior to make the gate pass;
- unresolved contradiction is hidden.

Score never overrides a BLOCK condition.

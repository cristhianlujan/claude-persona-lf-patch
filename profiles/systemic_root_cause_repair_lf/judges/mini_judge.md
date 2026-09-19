# Mini Judge — Systemic Root Cause Repair LF

## Quality authority
The mini-judge is the canonical semantic quality gate for this profile and is vendor-neutral. It evaluates the exact candidate revision and evidence bundle.

External audit is a separate oversight lane. Missing external audit is never a blocker. If an external auditor produces a material finding, that finding may block only after it is admitted through the normal governance path.

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
- rubric score is at least 22/25 when scoring is used, with no category escape and no blocking condition.

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

## BLOCK
Return `BLOCK_PIPELINE` when:
- output attempts unauthorized GitHub/Supabase/runtime/production mutation;
- evidence or authority is fabricated;
- candidate assertions are used to bypass the canonical semantic quality gate;
- declared authority/source/behavior materially contradicts live evidence and the contradiction is omitted, downgraded to residual risk, or allowed to close;
- the repair weakens fail-closed behavior to make the gate pass;
- unresolved contradiction is hidden.

Score never overrides a BLOCK condition.

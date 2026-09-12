# Score Rubric — LF Learning Engine

## PASS

- Router-first route is explicit.
- Supabase source verification is required.
- ACT-0046 status is respected as candidate/read-only.
- Evidence is sufficient and traceable.
- Existing assets are checked to prevent duplication.
- Learning is classified correctly.
- Runtime and automatic impact remain blocked.
- Narrow rules are consolidated into reusable mother rules.
- Any state claimed as completed is observable in the delivered output.
- A created candidate is actually delivered when `LEARNING_CARD_CANDIDATE_CREATED` is used.
- For a behavioral handoff claim, a verified executable receiver target actually ran the next gate and its captured output/trace/state show continuation without inventing missing intent, structure, evidence or artifact content.

## PASS_WITH_RESTRICTIONS

- Candidate is useful but requires additional sandbox evidence before broader impact or behavioral claims.
- Artifact consumability is demonstrated, but this does not count as receiver execution.
- Classification is valid but a remaining receiver or adjudication risk is explicit and handled by the next gate.

## BLOCKED_BEHAVIORAL

Use `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER` when:

- producer output is materially inspectable/consumable;
- only an assisted rubric review, same-session role-play, static receiver fixture or structural validator exists;
- no verified executable receiver target has actually produced receiver output/trace/state.

In this state, do not call the handoff demonstrated and do not promote the capability eval to regression protection.

## FAIL

- Learning creates official change directly.
- Supabase or Google Docs write is proposed without approval.
- Runtime or production general is enabled.
- Evidence is missing.
- The proposal creates rule sprawl.
- The producer claims an artifact or state exists but does not deliver observable evidence of it.
- The next action asks the receiver to recreate work already claimed complete.
- The handoff target conflicts with the contract or the real receiver cannot continue without inventing missing content.
- A same-session or static rubric artifact is presented as proof that the receiver was actually executed.

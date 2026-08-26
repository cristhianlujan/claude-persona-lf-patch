# Mini Judge — LF Learning Engine

Ask these questions before accepting output:

1. Did the operation start from Router?
2. Was Supabase `public.v_lf_fuente_operativa` verified or explicitly limited?
3. Was ACT-0046 respected as CANDIDATE / READ_ONLY?
4. Is there enough evidence to justify a learning candidate?
5. Were existing assets checked to avoid duplication?
6. Does the proposal avoid one-off rule sprawl?
7. Is the proposed impact blocked unless approved?
8. Is the next gate explicit?
9. If the status claims an artifact was created, is that artifact actually delivered and identifiable in the output?
10. Does the next action continue from the claimed state instead of asking the receiver to recreate work already declared complete?
11. Does `handoff_target` agree with the applicable handoff contract?
12. Is artifact consumability being kept distinct from receiver execution?
13. If a behavioral handoff PASS is claimed, is there a verified executable receiver target and evidence that it actually ran this producer artifact?
14. Does the captured receiver output/trace/state show that the real receiver performed its assigned gate without inventing missing intent, structure, evidence or artifact content?

For producer→receiver evals, a same-session role-play, assisted rubric review, static receiver-output fixture, or structural validator is not receiver execution. If that is all the evidence available, preserve any demonstrated artifact consumability but return `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER` and do not promote the case to regression protection.

If any required answer is no, return to orchestrator, return to worker for self-repair, or block pipeline according to the applicable contract.

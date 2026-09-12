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
15. Is each material support finding normalized as `DEFECT -> CORRECTION -> POSTCONDITION`, with the correction/postcondition reducing the defect rather than reproducing or amplifying it?
16. Is any causal claim that justifies a rule/change actually supported, rather than inferred from correlation or sequence alone?
17. When an upstream is material, was its current exact revision/SHA read and was its current validator/judge status compatible?
18. Is provenance kept separate from semantic correctness, including when a valid `PROFILE_EXECUTION_RECEIPT_V1` exists?
19. Does the claimed outcome stay at or below the evidence ceiling?
20. If semantic PASS depends on enumerable obligations, is there a complete coverage manifest with a 1:1 mapping from every required obligation ID to a check ID?
21. Did the worker consume already-resolved material inputs instead of asking for them again?
22. Are `KNOWN_VALIDATED` and `NEW_UNPROVEN` behaviors kept distinct?
23. Is any semantic judge used for PASS independent from the producer/self-certified oracle?
24. Did Learning Engine preserve the caller profile's domain ownership instead of taking over the decision?

For producer→receiver evals, a same-session role-play, assisted rubric review, static receiver-output fixture, structural validator, or authentic runtime receipt is not by itself semantic correctness. Preserve the lower-layer evidence and fail/return at the precise next missing layer.

For cross-profile support, load `semantic_support_judge.md`. A deterministic matrix PASS proves the contract mechanics only; it must never be described as behavioral PASS.

If any required answer is no, return to orchestrator, return to worker for self-repair, or block pipeline according to the applicable contract.

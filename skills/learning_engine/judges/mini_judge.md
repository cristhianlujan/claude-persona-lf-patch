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

If any answer is no, return to orchestrator, return to worker for self-repair, or block pipeline.

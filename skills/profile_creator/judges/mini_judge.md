# Mini Judge — LF Profile Creator

Ask before accepting `PROFILE_PACK_CREATED`:

1. Is the governing source authority current, direct and non-contradictory?
2. Does the exact `deliverable_artifact_ref` resolve to the candidate?
3. Does the candidate contain developed role/contract/schema/judge/evals/handoff content rather than nominal stubs?
4. Does its evidence map contain explicit source references and supported claims?
5. Do evals include positive and multiple negative cases with assertions?
6. Can Quality Pack review the artifact without inventing contract, evidence, schema, rubric, blocking or failure-routing context?
7. If user-facing, is internal orchestration metadata separated from the user payload?
8. Did `validate_candidate_depth.py` return `DEPTH_READY_FOR_SEMANTIC_REVIEW` for this exact artifact?
9. Does the result still state `semantic_quality_review=NOT_EXECUTED`?
10. Are runtime, production and automatic impact still blocked?

If any required answer is no, return to worker or block. Never convert this mini-judge or deterministic depth gate into independent semantic approval.

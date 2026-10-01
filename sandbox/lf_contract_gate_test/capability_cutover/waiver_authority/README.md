# WAIVER_AUTHORITY cutover v1

`SADM-PP-L5-022` isolated capability cutover.

This cutover materializes the dedicated one-use POST-PASE waiver store and the two private store functions, then registers the existing repository evaluator as version `1.0.0` under `LF_GOVERNANCE` and `ORCHESTRATOR_EXECUTION_GUARD_V1`.

It does not reuse `private.lf_event_validation_exemptions`; validation exemptions and closure waivers remain semantically separate. Scope is exact, TTL is at most one hour, `max_uses=1`, and consumption is cross-bound to consumer execution plus request digest.

Source core `839792277cf71f2a3f3585e2e1f0b21351da533c`; validator `397a612f044332b359f251f8d8101948be73a376` (12 checks); prior terminal #19624.

Rollback disables the authority/current pointer while preserving the dedicated store and existing grants. No runtime/deploy/production, no bulk cutover, no ZIP authority.

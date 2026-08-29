# LF Adapter Quality V2

Goal: match/exceed mature UI/Gamification validation discipline without turning adapters into agents or adding model calls.

Canonical shape:
`ACT-0001 Router -> EJECUCION_PERFIL_LF -> resolve applicable adapter bindings -> attach compact capsule -> one specialist execution -> validate -> receipt/readback`

Mandatory invariants:
- Router/orchestrator owns operational activation; direct naming is not invocation.
- Non-applicable adapter prompt payload = 0.
- Applicable adapter uses a compact `runtime_capsule.md` (default <= 2,000 UTF-8 chars).
- Adapter application adds no independent LLM call.
- Current canonical sources are resolved, not copied as stale authority.
- Profile authority is preserved; adapter only translates/constrains its bounded context.
- Deterministic validator covers structure/identity/cardinality/cross-reference rules.
- Semantic judge covers material meaning not safely deterministic.
- Positive, negative and adversarial cases are required.
- Fixtures are contract evidence, never RAW runtime proof.
- Live proof requires `lf_adapter_invocations` with adapter code/version, invocation id, activation reason, authoring hash, capsule hash and verdict.
- An applicable adapter must be evidenced exactly once; an unbound adapter must have no invocation record/payload.
- Runtime/VALIDATED/production promotion remains separately governed.

Candidate closure: `CANDIDATE_CONTRACT_QUALITY_PASS`. Live invocation PASS additionally requires canonical runtime canaries and receipts.
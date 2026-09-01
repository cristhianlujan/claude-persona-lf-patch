# Input Governance P0 — request-scoped currentness reuse

Scope: performance-only candidate. No production authorization.

This micro-lot removes duplicated currentness and stage-currentness recomputation inside `fn_input_context_manifest` when the manifest is produced from `fn_input_governance_execute` after authoritative currentness and freshness have already passed in the same governed statement snapshot.

Safety:
- preserves the strong public/internal entrypoint `fn_input_context_manifest(bigint)` unchanged;
- preserves ARC-015 currentness at `fn_input_governance_execute` entry;
- creates an internal helper that is not executable by PUBLIC, anon, authenticated, or service_role;
- does not modify Router, adapter contracts, SCOPED_PASS, downstream authorization, promotion, or production.

Baseline live sandbox before candidate:
- cached currentness: 10859.674 ms;
- context manifest: 28627.725 ms;
- execute: 42598.812 ms.

Router duplicate worker/currentness calls remain a separate later micro-lot.

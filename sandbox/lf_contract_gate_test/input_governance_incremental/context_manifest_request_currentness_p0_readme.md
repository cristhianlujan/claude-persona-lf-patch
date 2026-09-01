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

## Source-reservation phase

The P0 SQL candidate is intentionally **not** present under `supabase/migrations/` while it has not been applied to the governed Supabase sandbox ledger.

Canonical candidate bytes are reserved at:

`sandbox/lf_contract_gate_test/input_governance_incremental/source_reservation_context_manifest_request_currentness_p0.sql`

The reservation blob SHA is `e27f08459aff113b193b801c0a18086fc6c070bc`, exactly equal to the previously proposed migration blob. This preserves the reviewed candidate without creating Git-ahead migration parity drift.

Do **not** execute the reservation file directly from this PR. The governed sequence is: certify source-reservation -> land source evidence -> apply exact bytes through the authorized sandbox migration path -> read back the real ledger version/bytes -> materialize the canonical `supabase/migrations/<real_version>_...sql` source -> recertify parity.

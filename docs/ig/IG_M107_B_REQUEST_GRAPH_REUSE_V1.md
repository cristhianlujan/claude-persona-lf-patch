# IG M10.7 — B / cached canonical graph within trusted invocation

Depends on F (backend-only trusted loader). This is a **candidate-only improvement to the same SQL function**, not an independent cache, new rules engine, Curator/Validator integration, or changed trigger.

The existing `fn_input_screen_canonical_graph` already accepts a SHA-verified `lf.input_request_context_v1` for the same screen/version. B computes the graph once after checking the pinned run in a **READ ONLY REPEATABLE READ** transaction, stores it in transaction-local request context, and allows the existing G1 currentness and full-manifest routines to reuse the exact graph bytes. It validates the graph SHA against the canonical graph receipt, preserves the full manifest JSONB and SHA check, and clears the context on success and exception.

## Admission and limits

Train tests on one existing screen/version fixture (43/19): count graph builds across three reads (1 rather than 3), JSONB equivalence, matching SHA, rejection of altered SHA and unchanged private ACL. The sample check does not measure the full Validator and cannot certify p50/p90. No live `VALIDATING` run is used. In particular, **B is only partly addressed**: repeated *full-manifest* construction across validation writes still needs an independently safe change with measured evidence; the existing 21 triggers, currentness checks and CP3–CP5 remain unchanged.

EKB: `IG-M107-B-GRAPH-INVOKE-REUSE-029`. PR via LF Migration Merge Train only. No runtime deployment and no grant to public client identities.

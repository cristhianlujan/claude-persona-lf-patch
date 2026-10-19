# IG M10.7 / F — Trusted backend loader candidate (not activated)

Goal: provide a real SQL source for the existing run-scoped selective projection provider. The data-only source contains canonical rules, defined fail-closed contracts, run family inputs, and the canonical graph. It does not ship Curator/Validator decisions, new rules, a parallel engine, or a cross-run cache.

## Source and transaction

- SQL function: `programacion.fn_ig_m107_trusted_run_data_v1(bigint)`.
- Client adapter: `supabase/functions/_shared/ig_trusted_run_loader_v1.mjs`; feed `loadTrustedRunData` into the already tested `createRunScopedProjectionProviderV2`.
- The trusted backend executor calls `createTrustedRunDataLoaderV1({withReadOnlyRepeatableRead})` and supplies a database transaction helper that begins **READ ONLY REPEATABLE READ** (or SERIALIZABLE READ ONLY) before issuing the parameterized `SELECT programacion.fn_ig_m107_trusted_run_data_v1($1::bigint) AS payload`. The SQL function separately rejects ordinary READ COMMITTED or write transactions.
- Inputs are pinned by exact run, screen, version, contract SHA and full source SHA. SQL rechecks existing G1 currentness, strict full source-manifest JSONB equality, full SHA, graph receipt SHA, stage VALIDATING, and independent Curator/Validator identities. A matching source identity is **not** a substitute for full manifest equivalence (e.g. lifecycle fields may change).
- Results are read once per provider instance. Subsequent lookups select only requested variables and share the frozen in-memory dataset; a new run requires a new instance. A later decision requiring current authority continues to use the existing external currentness guard.
- The SQL function is backend-owner only. PUBLIC, anon, authenticated, service_role have no EXECUTE. It is not available as a direct client RPC; the future trusted Operation backend integration requires separate authorization. No runtime activation, no deployment, no extra GRANT.

## Validation

Node tests: parameterized SQL function target, single backend transaction for concurrent selections, no transaction driver, identity drift, missing data, unexpected decisions, backend refusal, stage fallback and run identity errors. SQL Train checks prior EKB, exact permissions, and rejection in ordinary migration transactions. No disabled triggers or policy changes.

**Limitations:** positive functional execution requires an eligible live VALIDATING run in a trusted repeatable-read read-only executor. There was no such run when the candidate was prepared. The historical completed/stale run 933 cannot prove eligibility or current source equivalence. This PR does not demonstrate the complete end-to-end Validator time, p90, or close CP3, G3 or F integration. B can consolidate source-manifest computations only after preserving the full semantics and validating negatives.

## Routing

Dedicated candidate PR, one migration through LF Migration Merge Train, EKB readback and Git/main verification. No Router repair and no Curator/Validator edits.

# S30 — QUALIFICATION_LF source candidate

This package isolates the transversal part of independent strategy review application.

## Live finding

The live qualification model already contains three strategy suites whose A03 case is `INDEPENDENT_REVIEW`:

- `TS-STRATEGY-FINANCIAL-V1`
- `TS-STRATEGY-HIGH-RISK-V1`
- `TS-STRATEGY-MODEL-HOLDOUT-V1`

All three are selected through `lf_test_requirement_bindings` with `independent_review_required=true`. The current apply RPC, however, is hardcoded to `TS-STRATEGY-MODEL-HOLDOUT-V1`, test `A03`, and receipt label `S37-MODEL-HOLDOUT-A03`.

## Design

`lf_apply_independent_strategy_review_v2` keeps the durable mechanics already proven by v1 but derives authorization from the live qualification model instead of strategy literals:

1. revalidate exact strategy revision;
2. bind qualification -> suite run -> test run;
3. require an ACTIVE requirement binding for that suite with `independent_review_required=true`;
4. require the suite case itself to declare `execution_mode=INDEPENDENT_REVIEW` and `probe_code=INDEPENDENT_REVIEW`;
5. validate receipt identity fields and independent-chat context;
6. apply PASS/FAIL to test and suite and advance the existing qualification lifecycle only when the complete suite set permits it.

`review_case` remains useful audit metadata but is not an authority key. The immutable IDs and revision are the authority.

## Compatibility

The existing v1 is not modified by this candidate. A later governed cutover can either migrate callers to v2 or turn v1 into a compatibility wrapper after caller evidence is complete.

## Claim ceiling

`SOURCE_CANDIDATE_NO_LIVE_MUTATION`.

No Supabase DDL/apply, migration-history mutation, runtime activation, Golden, production, or merge-main is authorized by this package.

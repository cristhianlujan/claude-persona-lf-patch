# LF Contract Check — change authority trace

## Purpose

Trace the **existing** authority chain for a change to `lf-contract-check` and determine whether the chain can authorize that change without depending on the same Contract Check being modified.

This is a read-only architecture trace persisted as documentation. It does not introduce a new guard, change any ruleset, alter a workflow, mutate Supabase, deploy, or activate anything.

Authority snapshot:

- `main`: `b330a72beb9ee4b4a861a50622833638632e2264`
- Contract Check workflow blob: `553dc9bfe21cb6db28b6f6a0f5367adea079461b`
- Contract Check validator blob: `5e6a1e9f0e0cd1dc6a92f4d3b4eac1425405b0c9`
- active default-branch ruleset: `protect-main` / id `20571741`

## 1. External repository root of trust

`protect-main` applies to the default branch and requires:

- pull request;
- strict required status checks;
- status context `lf-contract-check` from GitHub Actions integration `15368`;
- no bypass actors; current user cannot bypass.

This is genuinely external to the candidate source and therefore provides a repository-level merge barrier.

The other active rulesets do **not** govern `main`:

- `s30-governed-write-boundary` applies only to `refs/heads/lf/s30-*`;
- `s36-governed-write-boundary` applies only to `refs/heads/lf/s36-*`.

Therefore, for merge admission to `main`, the relevant required check is still `lf-contract-check`.

## 2. Existing self-change governance

The CI execution-plan work introduced previously is real and remains present:

- router/authority self-change can force full regression;
- carrier self-change can select carrier-scoped regression;
- unknown/unmapped scope fails closed to full regression.

However, this self-change logic is executed from the `lf-contract-check` workflow itself.

The current `lf-contract-check` job:

1. checks out the exact candidate;
2. loads `scripts/lf_contract_check.py`;
3. resolves exact changed files;
4. executes changed-file / receipt / forbidden-term checks;
5. loads `lf_ci_lane_router.py`;
6. loads `lf_ci_execution_plan_v2.py` and `lf_ci_currentness_bridge_v1.py`;
7. builds the applicability plan;
8. conditionally runs the router self-tests.

Thus the self-change policy is **useful regression logic**, but it is not an independent merge authority.

## 3. Existing candidate receipt

`LF_OPERATION_CANDIDATE_RECEIPT` is also real and solves a different circularity: pre-merge evidence can be issued before the final post-merge closure exists.

It binds candidate evidence to the candidate/code head and governed-path blobs.

But its validation is implemented inside `scripts/lf_contract_check.py` (`validate_candidate_receipt_shape()` and governed receipt validation), and the current workflow calls that validator during the same `lf-contract-check` job.

Therefore candidate receipts improve evidence integrity but do **not** independently authorize a change to Contract Check.

## 4. Existing governed repository-write mechanisms

The repository already contains a separate governed write mechanism that must not be overlooked:

- PR #657 merged the operational `S30_GIT_WRITE_BROKER_V2` path;
- it validates exact main/base, source ancestry, bounded allowed paths and performs post-push remote SHA readback;
- it uses the active `s30-governed-write-boundary` ruleset and a governed DeployKey;
- its protected target namespace is explicitly limited to `lf/s30-*`.

This is useful because it proves LF already has a pattern for **externalized repository mutation transport** that does not rely on ordinary direct connector writes.

However, it does **not** currently solve Contract Check self-authorization:

1. its ruleset does not apply to `main`;
2. its broker contract limits targets to the S30 protected namespace;
3. PR #657 explicitly retained `main` under the required `lf-contract-check` status;
4. its purpose is governed branch write transport, not final merge admission to `main`.

There is also an unmerged candidate, PR #785 `REPOSITORY_CHANGE_LF`, that defines a generic repository-change request/receipt boundary with exact expected HEAD, allowed/requested paths, immutable request hash, governed provider binding and post-write readback.

That candidate is relevant as reusable design material, but it is **not current authority**:

- PR #785 remains open/unmerged;
- its contract explicitly requires `target_branch` not to be `main`/`master`;
- its receipt has `merge_authorized=false`;
- merge authority is deliberately owned elsewhere.

Therefore the broker and repository-change candidate reduce the amount of new design needed, but neither currently inserts an independent required merge authority between a Contract Check self-change and `main`.

## 5. Actual authority chain

```text
PR changes lf-contract-check
        |
        v
GitHub protect-main ruleset
        |
        | requires status: lf-contract-check
        v
.github/workflows/lf-contract-check.yml
        |
        +--> scripts/lf_contract_check.py
        |      +--> changed-file admission
        |      +--> candidate/final receipt validation
        |      +--> other current legacy checks
        |
        +--> CI lane / applicability router
        |      +--> self-change/full-regression policy
        |      +--> currentness
        |
        +--> router self-tests / remaining controls
        |
        v
status: lf-contract-check
        |
        v
protect-main permits merge
```

Parallel existing write machinery:

```text
S30_GIT_WRITE_BROKER_V2
        |
        +--> exact base/source + bounded paths + post-write readback
        |
        +--> target only: lf/s30-*
        |
        `--> does not authorize main merge
```

## 6. Verdict

### What already exists and should be reused

- GitHub ruleset as external repository enforcement root;
- exact candidate checkout/binding;
- self-change/full-regression behavior;
- candidate receipt exact-head/blob evidence;
- currentness checks;
- governed repository-write transport pattern from `S30_GIT_WRITE_BROKER_V2`;
- request/receipt boundary ideas from the unmerged `REPOSITORY_CHANGE_LF` candidate, only where independently revalidated.

### What is still missing

There is **no demonstrated independent required authority between a Contract Check self-change and the final `lf-contract-check` required status**.

The circular edge is:

```text
protect-main
  -> requires lf-contract-check
  -> lf-contract-check evaluates the candidate implementation that is itself being changed
  -> produces the status protect-main trusts
```

This means the existing work reduced risk and improved evidence, but it did **not** fully break self-authorization.

## 7. Minimal next design question

Do **not** create another mega-control and do **not** recreate the existing governed-write transport.

The next design step should answer only this question:

> What is the smallest independent merge-admission mechanism for Contract Check self-change that can reuse the existing exact-head/currentness/receipt/write-governance primitives while validating exact candidate SHA + authorized diff/scope without executing the candidate Contract Check implementation?

The important distinction is now explicit:

```text
repository write transport != main merge authority
```

Any proposal that merely routes the candidate through `S30_GIT_WRITE_BROKER_V2` still leaves `protect-main -> lf-contract-check` unchanged and therefore does not close the circularity.

## Non-scope

- no Contract Check code changes;
- no ruleset changes;
- no new required check;
- no new capability creation;
- no owner cleanup;
- no destination-component audit;
- no Supabase mutation;
- no deploy or activation.

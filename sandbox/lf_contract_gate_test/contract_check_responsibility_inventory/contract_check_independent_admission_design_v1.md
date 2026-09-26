# LF Contract Check — minimal independent self-change admission design

## Purpose

Close only the circular merge-authority edge already proven for `lf-contract-check`:

```text
protect-main
  -> requires lf-contract-check
  -> candidate lf-contract-check evaluates itself
  -> produces the status protect-main trusts
```

This design does **not** redesign Contract Check, the CI router, repository-write transport, currentness, receipts, Migration Parity, Packs, Runtime, or the pass orchestrator.

Authority snapshot for this design:

- `main`: `f4ff5aacb39306043fb915ab01d1439b6e1de611`
- authority-trace merge: PR `#1083`
- active ruleset: `protect-main` / id `20571741`
- current Contract Check workflow blob: `553dc9bfe21cb6db28b6f6a0f5367adea079461b`
- current Contract Check validator blob: `5e6a1e9f0e0cd1dc6a92f4d3b4eac1425405b0c9`
- EKB finding: `CI-CONTRACT-CHECK-SELF-AUTHORIZATION-CIRCULARITY-001`

## 1. Constraints already demonstrated

1. `protect-main` is an external repository barrier, but its only required status is currently `lf-contract-check`.
2. `LF_OPERATION_CANDIDATE_RECEIPT` binds candidate/code-head and per-path Git blobs, but its current validation is inside `scripts/lf_contract_check.py`.
3. self-change/full-regression logic exists, but it is executed inside `.github/workflows/lf-contract-check.yml`.
4. `S30_GIT_WRITE_BROKER_V2` proves governed Git transport exists, but it is limited to `lf/s30-*` and does not authorize merge to `main`.
5. `REPOSITORY_CHANGE_LF` is reusable design material only; PR #785 remains unmerged and explicitly keeps `merge_authorized=false`.
6. no `pull_request_target` workflow exists in the repository today.
7. `.github/workflows/lf-github-reconcile-v3.yml` is already an exact path admitted by the current Contract Check. Its existing `reconcile` job is event-isolated by a `workflow_run`-specific condition, so a later `pull_request_target` bootstrap job can be added without causing the post-merge reconciliation job to execute for PR-target events.
8. `public.get_lf_repository_governance_bundle_v4()` exposes only the latest `active=true` row per path. It is a current trust anchor, not a pending-candidate authorization channel. Do not overload `active=false` as a new unpublished state without a separate contract.

## 2. External platform facts verified for the design

GitHub documents that:

- `pull_request_target` runs workflow code from the base/default branch context, not from the candidate PR branch;
- candidate PR code must not be checked out and executed in a privileged `pull_request_target` job;
- `pull_request_target` is eligible to produce checks evaluated for pull requests;
- required checks must succeed for the latest PR commit context;
- path-filtered required workflows can remain pending, therefore an admission check that becomes required must always produce a conclusion and return a fast `NOT_APPLICABLE/PASS` for unrelated PRs;
- organization-level required-workflow rules are not a usable repository-local primitive for this user-owned repository, so this design does not depend on them.

Reference documentation:

- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target
- https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets

## 3. Options considered

| Option | Independence | New infrastructure | Decision |
|---|---|---:|---|
| external GitHub App emits a dedicated status | strong | high | reject for now |
| organization-level required workflow from separate source repo | strong | medium | unavailable / not repository-local here |
| reuse S30 broker as merge authority | wrong boundary | low | reject; transport != merge authority |
| base-anchored `pull_request_target` admission check | strong enough for this boundary when candidate code is treated only as data | low | **selected** |

## 4. Selected mechanism

Working name: **Contract Check self-change admission**.

This is a narrow merge-admission control, not another pass orchestrator and not another Contract Check.

Its authority is the **base branch implementation of the guard**, not the candidate implementation being changed.

### Trust boundary

```text
pull request
   |
   | GitHub event metadata + candidate objects treated only as data
   v
BASE-BRANCH admission guard
   |
   +-- exact PR head/base identity
   +-- exact changed-path set
   +-- trusted current Contract Check anchors
   +-- candidate receipt shape/blob binding as evidence carrier
   +-- live Supabase execution readback when Contract Check is actually touched
   |
   v
independent admission verdict
   |
   v
protect-main required status
```

The guard must **never**:

- execute `scripts/lf_contract_check.py` from the candidate;
- execute a candidate workflow;
- import a candidate Python module;
- run package install/build hooks from the candidate;
- trust candidate-declared PASS without independent readback;
- decide applicability for sibling controls;
- become a repository writer or merge executor.

## 5. Applicability

The protected self-change surfaces are initially the already-frozen Contract Check source surfaces:

1. `.github/workflows/lf-contract-check.yml`
2. `scripts/lf_contract_check.py`
3. `sandbox/lf_contract_gate_test/lf_contract.yml`

For every PR:

```text
none of the three touched
  -> PASS_NOT_APPLICABLE

one or more touched
  -> run SELF_CHANGE admission checks
```

The workflow itself must not use GitHub `paths:` filtering once its job is required, because a skipped required workflow can remain pending.

## 6. Required self-change checks

A Contract Check self-change is admitted only when all of the following are demonstrated from the base-anchored guard:

### A. Exact GitHub identity

- target repository is exactly `cristhianlujan/claude-persona-lf-patch`;
- PR base branch is `main`;
- observed candidate head equals the PR head SHA supplied by GitHub;
- observed base SHA is explicit;
- current `main` is resolved at execution time;
- stale/ambiguous head or base => block.

### B. Exact diff/scope

- enumerate changed files from GitHub / Git objects without executing candidate code;
- identify exactly which Contract Check surfaces changed;
- unknown replacement/lookalike paths do not count as Contract Check authority;
- any mutation of the admission guard's own executable source in the same self-change PR is a separate guard-evolution case and must block the ordinary self-change lane.

### C. Current trusted anchor

Read the already-existing repository-governance bundle as current-state evidence:

- workflow current blob `553dc9bfe21cb6db28b6f6a0f5367adea079461b` / SHA-256 `768949e84a17d663dcbd26e5efb782cb5e7f00dbf956c3d2eda8b5501090af01`;
- validator current blob `5e6a1e9f0e0cd1dc6a92f4d3b4eac1425405b0c9` / SHA-256 `befa5915e69d7d537e953d4a24d4d1a8c72c1c18b8daef0504845ad595ce2a0f`.

The guard uses these as **before-state** trust anchors. It does not repin them before merge and does not invent a pending `active=false` lifecycle in `lf_repository_governance_bundle_v4`.

### D. Candidate evidence carrier

A candidate receipt may be used to transport:

- `operation_code`;
- `execution_id`;
- `candidate_code_head`;
- governed target paths;
- exact candidate Git blob SHA by path.

But the guard must not accept the receipt merely because it says `issued_by=operation_judge` or `PASS_CANDIDATE`.

The current receipt validator proves shape/ancestry/blob binding, not independent issuer authenticity.

### E. Independent live execution readback

When a Contract Check surface is touched, the guard independently reads canonical execution state and requires at minimum:

- execution exists;
- `operation_code = GITHUB_CONTRACT_GATE_LF`;
- repository identity matches;
- execution manifest binds the same PR number where present;
- execution manifest `candidate_code_head` equals the candidate code head carried by the receipt;
- execution status is compatible with pre-merge admission (`IN_PROGRESS` while a candidate receipt is being used, or another explicitly contracted pre-merge state after lifecycle redesign);
- no independent canonical blocker is present;
- required pre-merge step evidence referenced by the receipt is actually present in canonical execution state.

The guard must query only the minimum required readback. It must not reproduce the entire operation lifecycle or judge every Contract Check step.

Supabase is therefore on the critical path **only for Contract Check self-change**, not for unrelated PRs.

## 7. Bootstrap without another circular Contract Check change

Creating a brand-new `.github/workflows/...` path first would be blocked by the current exact `.github` admission policy unless Contract Check were changed to admit it. That would recreate the circular bootstrap we are trying to eliminate.

Therefore the first implementation step must use an already-admitted workflow path as a **bootstrap carrier**.

Selected bootstrap carrier:

`.github/workflows/lf-github-reconcile-v3.yml`

Reason:

- already admitted by `ALLOWED_GITHUB_EXACT`;
- not a Contract Check source surface;
- current post-merge `reconcile` job has a `workflow_run`-specific condition and will skip on `pull_request_target` events;
- adding a second job does not require executing candidate Contract Check code.

Bootstrap change:

1. add `pull_request_target` for PR events needed by the guard;
2. add a new admission job with a stable unique job name;
3. give only read permissions plus the minimum secret/readback access needed for the self-change branch of the job;
4. for unrelated PRs, exit successfully before Supabase access;
5. for self-change PRs, run the checks in section 6;
6. do not change the existing reconciliation job's semantics.

This bootstrap carrier is a transport choice, not the architectural owner of the admission capability. A later cleanup may move the job to a dedicated carrier only after independent admission is already active; that cleanup is explicitly not required to start Contract Check extraction.

## 8. Activation sequence

No parallel implementation.

### Step 6A — source-only guard

- implement the base-anchored guard in the already-admitted bootstrap carrier;
- add deterministic local tests for positive and negative cases;
- do **not** change `protect-main` yet.

### Step 6B — live fire tests before enforcement

Demonstrate at least:

1. unrelated PR -> guard reports PASS / NOT_APPLICABLE;
2. valid bounded Contract Check self-change fixture -> PASS;
3. changed head mismatch -> BLOCK;
4. unexpected Contract Check/lookalike path -> BLOCK;
5. candidate receipt blob mismatch -> BLOCK;
6. receipt claims nonexistent/wrong Supabase execution -> BLOCK;
7. execution candidate code head mismatch -> BLOCK;
8. guard-source self-modification mixed into ordinary Contract Check self-change -> BLOCK.

A green workflow alone is not closure. Evidence must show inputs, observed values and negative behavior.

### Step 6C — external enforcement

Only after 6A/6B are demonstrated:

- add the new admission job status to `protect-main` as an additional required check;
- keep existing `lf-contract-check` required during the transition;
- require the new status from the GitHub Actions integration;
- verify ruleset readback.

The security effect is then:

```text
candidate lf-contract-check may still evaluate itself
                 BUT
merge also requires a base-anchored independent admission check
```

Therefore Contract Check is no longer the sole authority capable of admitting its own change.

### Step 6D — first protected self-change proof

Perform one real, bounded Contract Check change under the new required check and prove:

- guard executed from trusted base implementation;
- exact candidate head and changed blobs were observed;
- canonical execution readback matched;
- both required checks passed;
- merge occurred without bypass;
- post-merge readback matches the admitted candidate.

Only after this fire test is Point 6 closed.

## 9. Failure policy

Fail closed for self-change if any of these are unknown:

- PR head/base identity;
- changed-path set;
- current trusted anchor;
- candidate blob binding;
- canonical execution identity;
- canonical candidate code head;
- required pre-merge evidence/readback.

Do not fail unrelated PRs because Supabase is unavailable: unrelated PRs must terminate `PASS_NOT_APPLICABLE` before the DB read.

## 10. What this design deliberately does not do

- no new mega-control;
- no new pass router;
- no duplicate currentness engine;
- no duplicate receipt format;
- no new Git writer;
- no new Supabase table;
- no overload of inactive governance-bundle rows;
- no Migration Parity / Packs / Runtime redesign;
- no owner-name cleanup;
- no audit of destination components;
- no ruleset mutation in this design PR;
- no Contract Check code extraction yet.

## 11. Closure criterion for this design stage

This design stage is complete when the following question has one concrete answer:

> How do we stop `lf-contract-check` from being the sole authority for its own modification without rebuilding the rest of repository governance?

Answer:

> Add one base-anchored, required self-change admission check. Bootstrap it through an already-admitted repository-governance workflow carrier; never execute candidate code; reuse current trust anchors, candidate receipt as evidence carrier, and canonical Supabase execution readback; return fast NOT_APPLICABLE for all non-self-change PRs.

Implementation and enforcement remain separate next steps.
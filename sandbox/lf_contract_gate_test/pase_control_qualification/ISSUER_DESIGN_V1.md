# PASE CONTROL SYSTEM QUALIFICATION — ISSUER DESIGN V1

Status: DESIGN / NOT AUTHORIZED FOR DEPLOYMENT

## Objective

Provide an authorized, automatic exact-head qualification issuer for changes routed by
`PASE_MERGE_ROUTE_V1` as `CONTROL_SYSTEM_QUALIFICATION`, while preserving the existing
canonical authority `public.lf_qualification_receipts`, the existing validator
`PASE_CONTROL_QUALIFICATION_V1`, and the Merge Train as the sole database-write route
for installation.

The design is ZERO_COST_ONLY for the independent reviewer: CI never calls a paid model API.
The independent semantic verdict is produced by a separate chat/session and transported as
structured evidence. The issuer validates that evidence mechanically.

## Current constraints that shape the design

1. `lf_record_control_system_qualification_v1` accepts only
   `CANDIDATE_QUALIFIED` exact-head results and requires a COMPLETED
   `GITHUB_CONTRACT_GATE_LF / REPOSITORY_GOVERNED_PATHS` source execution.
2. The canonical readback is keyed by candidate identity plus SHA-256 of exact `head_sha`,
   and independently validates `base_sha`, `observed_main_sha`, `head_sha`, repository,
   source execution and authority.
3. The current producer is SECURITY INVOKER. A new restricted CI role cannot safely call it
   unless it also receives table-write powers, which is forbidden by this design.
4. Therefore the approved implementation needs one bounded SECURITY DEFINER wrapper,
   installed only by Merge Train, that creates/completes the source execution and invokes
   the existing canonical producer atomically and idempotently.
5. Under current F0/CLAUDE governance, every database write is still restricted to
   `ACTUALIZACION_DB_LF -> Migration Merge Train`. A separate CI issuer that persists a
   qualification receipt is therefore **not currently authorized**, even with a least-
   privilege role. Owner approval must explicitly establish a bounded canonical write route
   (and its Router/policy identity) before the issuer can leave dry-run mode. Installing the
   role/wrapper through Train alone does not authorize later CI writes through it.
6. `ig-runtime-candidate-judge` is not reusable as this issuer. It is specific to
   `sandbox/ig_cv/n9_requests/request.json`, uses the IG judge contract, and currently
   consumes a different database path/credential model.
7. Router-wave C3 demonstrates a useful evidence pattern: freeze a blind review packet,
   bind the review to immutable material identity, capture the independent verdict
   separately, and validate the capture mechanically before promotion.

## End-to-end flow

1. A PR is opened or synchronized.
2. Trusted `main` code emits the canonical PASE execution plan and
   `PASE_MERGE_ROUTE_V1`.
3. If route mode is not `CONTROL_SYSTEM_QUALIFICATION`, the qualification issuer exits
   NOT_APPLICABLE.
4. If the PR changes the qualifier, issuer, Merge Train, merge gate, issuer workflow, or
   the route authority itself, automatic issuance is forbidden and the PR is escalated.
5. Trusted code reads candidate Git objects as data only and builds:
   - exact base/head identity;
   - canonical changed-path inventory;
   - changeset manifest identity;
   - owner-local test/check evidence from exact-head GitHub checks;
   - candidate material fingerprint.
6. A structured independent-review verdict is fetched from a PR comment. The comment does
   not alter the candidate HEAD.
7. The reviewer validator proves:
   - exact repository/PR/candidate identity;
   - exact candidate material fingerprint;
   - reviewer session differs from builder session;
   - Q05/Q06/Q09/Q10 have terminal dispositions;
   - PASS is impossible when required reviewer evidence is missing.
8. Automatic checks construct Q01/Q02/Q03/Q04/Q07/Q08/Q11. Reviewer checks supply
   Q05/Q06/Q09/Q10.
9. Trusted `pase_control_qualification_v1.py` re-validates the complete packet/result.
10. If the result is not `CANDIDATE_QUALIFIED`, the issuer stops and writes nothing.
11. The restricted issuer role calls one future SECURITY DEFINER wrapper. The wrapper:
    - takes an advisory transaction lock for candidate + exact head;
    - derives deterministic idempotency/request identities;
    - reuses or reserves exactly one `GITHUB_CONTRACT_GATE_LF` execution;
    - completes only that bounded execution with the qualification evidence;
    - invokes `lf_record_control_system_qualification_v1`;
    - on exact retry returns the existing receipt;
    - on payload drift or cardinality drift fails closed.
12. `pase-merge-gate` performs bounded polling only for
    `BLOCK_PASE_MERGE_GATE_QUALIFICATION_MISSING`. It then reads the exact-head receipt
    through the current read-only wrapper and re-runs the trusted-base validator.
13. Only the Merge Train merges. A receipt is qualification evidence, never merge,
    activation, cutover, rebind or retirement authority.

## R1 — Exact-head circularity

The review verdict is bound to material, not to a Git commit.

The issuer computes:

`candidate_material_sha256 = SHA256(canonical sorted records(path,status,blob_sha))`

over candidate responsibility paths only. Review transport is external to Git, so it is
never part of that hash. Changeset/governance metadata is validated separately by Q02/Q07.

When the Train synchronizes the PR with a newer `main`, the Git HEAD changes. The
`synchronize` event launches a fresh issuer run. Trusted code recomputes the material
fingerprint against the new exact base/head:

- material fingerprint unchanged -> the existing independent review remains admissible;
- material fingerprint changed -> the old review is stale and issuance BLOCKS.

The issuer then creates a NEW exact-head qualification receipt for the synchronized HEAD.
The receipt itself always binds `base_sha=current main`, `observed_main_sha=base_sha`,
and exact final `head_sha`.

If main moves again before merge, stale-base protection blocks that run. The next Train
sync creates another HEAD and requires another exact-head receipt. No receipt is ever
"rebound" by assertion.

## R2 — Review verdict location

Chosen transport: **one structured PR comment**.

Reasons:
- does not mutate HEAD;
- can be produced from a separate ZERO_COST chat session and pasted by Paulo/owner;
- GitHub provides a stable comment id plus author/timestamps; the body itself is mutable;
- trusted workflow code records the comment id plus SHA-256 of the exact raw body it read,
  while the offline issuer separately hashes the normalized review JSON; both digests and
  reviewer transcript/session refs become part of the qualification request evidence;
- no expiring Actions artifact is required as long-term authority.

The comment is transport, not authority. The canonical authority remains the qualification
receipt. Editing/deleting the comment after issuance cannot change the stored receipt.
Before issuance the issuer always fetches the live comment and hashes the exact body.

Required comment JSON schema:

```json
{
  "schema_version": "lf-pase-control-independent-review/v1",
  "repository": "owner/repo",
  "pr_number": 123,
  "candidate_id": "PASE_MERGE_GATE_V1",
  "candidate_material_sha256": "<64hex>",
  "builder_session_id": "builder-session-stable-id",
  "builder_session_ref": "https://chatgpt.com/share/...",
  "reviewer_session_id": "different-review-session-id",
  "reviewer_session_ref": "https://chatgpt.com/share/...",
  "blind_review": true,
  "checks": [
    {"id":"Q05","status":"PASS|FAIL|BLOCKED","evidence":["..."],"rationale":"..."},
    {"id":"Q06","status":"PASS|FAIL|BLOCKED","evidence":["..."],"rationale":"..."},
    {"id":"Q09","status":"PASS|FAIL|BLOCKED|NA","evidence":["..."],"rationale":"..."},
    {"id":"Q10","status":"PASS|FAIL|BLOCKED","evidence":["..."],"rationale":"..."}
  ],
  "verdict": "REVIEW_PASS|REVIEW_BLOCK|REVIEW_FAIL"
}
```

Q09 may be `NA` only when the qualification type is not `CONTROL_REPLACEMENT`.

## R3 — Execution ordering

On `opened`/`synchronize`/`reopened`/`ready_for_review`, issuer and merge gate may start in
parallel. The gate uses bounded polling so a review that already exists can be issued during
the same exact-head run.

A reviewer comment usually arrives *after* the candidate HEAD exists. Therefore the future
issuer workflow must also listen to `issue_comment` (`created`/`edited`) and process only PR
comments carrying the qualification-review marker. Posting/editing the review does not mutate
HEAD. After a successful issue on that comment event, the future merge-gate workflow must get
a second ordered trigger via `workflow_run` on **PASE Control Qualification Issuer** success,
resolve the associated PR, and re-evaluate only that same current base/head. This ordered run
is the authoritative post-receipt gate attempt; an earlier missing-receipt run may remain red
shadow evidence.

The gate must use bounded retry only for the exact missing-receipt condition:

- initial exact-head readback;
- if MISSING, wait 5 seconds;
- retry at most 12 times (60 seconds total);
- before every retry confirm current main/base/head identity has not drifted;
- any error other than MISSING fails immediately;
- after 12 MISSING reads, BLOCK.

The issuer never calls the gate API and never fabricates a gate status. Once it persists the
exact-head receipt, either the already-running bounded-poll gate observes it or the ordered
`workflow_run` gate attempt does. A later Train `synchronize` creates a new HEAD and therefore
a fresh issuer/gate pair; prior-head PASS is irrelevant.

When the gate is eventually made required, the Train exact-head required-check guard waits
for the gate attached to the synchronized HEAD. A prior-head PASS is irrelevant.

## R4 — Idempotency

The future DB wrapper must use all of:

1. transaction-scoped advisory lock derived from candidate_id + head revision;
2. deterministic source execution id and idempotency key;
3. deterministic request SHA-256 over canonical qualification input/result and review
   evidence digest;
4. exact readback before insert;
5. existing unique current CONTROL_SYSTEM index;
6. exact replay semantics:
   - same request -> return existing execution/qualification id;
   - same candidate/head with different payload -> BLOCK_IDEMPOTENCY_CONFLICT;
   - more than one current receipt -> existing readback cardinality failure.

The offline issuer already derives deterministic identities so retries can be tested before
any DB capability exists.

## R5 — Independence

Required identities are separate:

- **builder**: session that produced the candidate PR; declared in PR metadata and included
  in review packet;
- **reviewer**: a different chat/session; verdict must contain a different session id and
  transcript/share reference;
- **emitter**: GitHub Actions trusted-main workflow using only
  `lf_ci_qualification_issuer`;
- **merger**: existing Merge Train / GitHub App identity.

Automatic issuer blocks if:
- reviewer session id/ref equals builder session id/ref;
- `blind_review != true`;
- candidate touches qualifier, issuer, issuer workflow, Merge Train, merge gate, route
  registry/producer, or DB issuer wrapper;
- candidate data attempts to provide executable issuer/qualifier code.

The emitter always checks out trusted `main`; candidate Python/workflows are never
executed with issuer credentials.

## R6 — Missing/disagreeing review

Fail closed.

- no review -> `BLOCK_QUALIFICATION_REVIEW_MISSING`;
- material hash mismatch -> `BLOCK_QUALIFICATION_REVIEW_STALE`;
- same builder/reviewer -> `BLOCK_QUALIFICATION_REVIEW_NOT_INDEPENDENT`;
- any reviewer Q = BLOCKED -> qualification result BLOCKED; no DB call;
- any reviewer Q = FAIL -> qualification result FAIL; no DB call;
- malformed or incomplete review -> BLOCK;
- only REVIEW_PASS with every required reviewer Q terminal and contract-valid can produce
  `CANDIDATE_QUALIFIED`.

## Q ownership

| Check | Owner | Automatic evidence |
|---|---|---|
| Q01 exact identity | issuer | exact base/head, candidate material hash |
| Q02 exact scope | issuer | canonical route + changeset manifest |
| Q03 declared owner / authority separation | issuer | route registry + builder/reviewer/emitter identity |
| Q04 owner-local tests | issuer | exact-head GitHub check results read as data |
| Q05 boundary/ownership invariants | independent reviewer | blind semantic verdict |
| Q06 negative/adversarial behavior | independent reviewer | blind semantic verdict |
| Q07 no out-of-scope effects | issuer | changeset manifest + changed-path inventory |
| Q08 determinism/idempotence | issuer | deterministic packet hash/idempotency identities + offline retry tests |
| Q09 old-vs-new replay | independent reviewer | PASS for replacement; otherwise explicit NA |
| Q10 coverage preserved | independent reviewer | blind semantic verdict |
| Q11 exact-head evidence/readback | issuer | exact-head checks, current base/head and evidence hashes |

## Proposed DB role and grants

Future migration, owner-approved and Merge-Train-only:

- login role: `lf_ci_qualification_issuer.<project>` or equivalent pooler identity;
- NO table grants;
- NO schema write grants;
- NO postgres credential;
- NO reuse of `LF_SUPABASE_DB_PASSWORD`;
- REVOKE PUBLIC on the new issuer wrapper;
- GRANT EXECUTE on exactly the issuer wrapper;
- read-only helpers may be granted explicitly only when needed.

Preferred wrapper:

`public.lf_ci_issue_control_system_qualification_v1(...)`

- `SECURITY DEFINER`;
- owner `postgres`;
- `SET search_path TO ''` and fully qualified object/function references;
- validates `current_user`/session role as the issuer role where feasible;
- performs only bounded execution reservation/completion + canonical qualification record;
- cannot accept arbitrary operation_code, target_type, repository-independent SQL or
  free-form table identifiers.

The role must not receive EXECUTE directly on a generic write primitive if the wrapper can
avoid it. The intended ACL shape (documentation only, not executable migration) is:

```sql
-- role creation/password material intentionally omitted here
REVOKE ALL ON public.lf_qualification_receipts FROM lf_ci_qualification_issuer;
REVOKE ALL ON public.lf_operation_execution FROM lf_ci_qualification_issuer;
REVOKE ALL ON FUNCTION public.lf_ci_issue_control_system_qualification_v1(...) FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO lf_ci_qualification_issuer;
GRANT EXECUTE ON FUNCTION public.lf_ci_issue_control_system_qualification_v1(...)
  TO lf_ci_qualification_issuer;
-- no direct EXECUTE grant is added for generic reserve/write primitives.
```

The wrapper itself executes as its owner only for this bounded operation. Its body must use
fully-qualified identifiers despite the empty `search_path`, and it must not expose arbitrary
SQL/object/operation parameters.

## How source_execution_id is created

Today there is no authorized CI producer for this source execution.

The approved wrapper must create it atomically using the existing canonical reservation
semantics with hard-coded:
- operation_code = `GITHUB_CONTRACT_GATE_LF`;
- target_type = `REPOSITORY_GOVERNED_PATHS`;
- target_code = `PASE_CONTROL_QUALIFICATION_<PR>_<HEADPREFIX>`;
- target_repo = exact repository;
- deterministic idempotency key/request hash.

It then marks that single bounded execution COMPLETED with a manifest that contains the
exact qualification request hash, review digest and material hash before calling the
existing canonical qualification producer. The caller cannot choose a different operation.

## Proposed workflow YAML (documentation only)

This is design text. Do NOT create it under `.github/workflows/` before owner approval.

```yaml
name: PASE Control Qualification Issuer

on:
  pull_request_target:
    types: [opened, synchronize, reopened, ready_for_review]
  issue_comment:
    types: [created, edited]

permissions:
  contents: read
  pull-requests: read
  issues: read
  actions: read

concurrency:
  group: pase-control-qualification-issuer-${{ github.event.pull_request.number || github.event.issue.number }}
  cancel-in-progress: true

jobs:
  classify:
    runs-on: ubuntu-latest
    outputs:
      applicable: ${{ steps.route.outputs.applicable }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: refs/heads/main
          persist-credentials: false
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - id: route
        run: |
          set -euo pipefail
          # trusted-main helper:
          # 1) resolve PR number from pull_request_target or issue_comment; reject non-PR comments
          # 2) for issue_comment require the structured qualification-review marker
          # 3) read PR base/head/repository through GitHub API and require base == current main
          # 4) fetch HEAD as Git objects only; never checkout/import candidate code
          # 5) emit canonical PASE plan + merge route
          # 6) output applicable=true only for CONTROL_SYSTEM_QUALIFICATION

  issue:
    needs: classify
    if: needs.classify.outputs.applicable == 'true'
    environment: lf-ci-qualification-issuer
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: refs/heads/main
          persist-credentials: false
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Fetch candidate as data and fetch independent review comment
        run: |
          set -euo pipefail
          # fetch exact Git objects, PR metadata and structured review comment;
          # never checkout/import/execute candidate code.
      - name: Build and validate exact-head qualification packet
        run: |
          set -euo pipefail
          python3 -I sandbox/lf_contract_gate_test/pase_control_qualification/qualification_issuer_v1.py             --dry-run             --input "$RUNNER_TEMP/qualification-input.json"             --review "$RUNNER_TEMP/review.json"             --output "$RUNNER_TEMP/qualification-ready.json"
      - name: Persist through restricted issuer wrapper
        env:
          LF_QUALIFICATION_ISSUER_PASSWORD: ${{ secrets.LF_QUALIFICATION_ISSUER_PASSWORD }}
        run: |
          set -euo pipefail
          # call only public.lf_ci_issue_control_system_qualification_v1(...)
          # using lf_ci_qualification_issuer; never postgres/write-master credential.
```

## Canary plan

### A — CONTROL_SYSTEM without review
Expected: issuer returns `BLOCK_QUALIFICATION_REVIEW_MISSING`; no receipt; gate remains
`BLOCK_PASE_MERGE_GATE_QUALIFICATION_MISSING`.

### B — CONTROL_SYSTEM with valid independent review
Expected: all automatic Qs + reviewer Qs pass; one exact-head receipt; gate exact-head
readback PASS.

### C — reviewer session equals builder session
Expected: `BLOCK_QUALIFICATION_REVIEW_NOT_INDEPENDENT`; no receipt.

### D — PR modifies qualifier/emitter/Train/merge gate
Expected: `ESCALATE_CONTROL_SYSTEM_SELF_CHANGE`; automatic issuer does not attempt DB.

Additional retry canary:
same exact head/request twice -> same source execution/qualification identity, one current
receipt only.

## Open risks

1. Session independence is auditable but not cryptographically provable from a pasted chat
   verdict alone. Requiring distinct public transcript refs makes spoofing visible but does
   not provide provider signing.
2. PR comments are mutable before issuance. The issuer must fetch and hash the exact live
   body at issuance; the canonical receipt must store the consumed digest/reference.
3. A future required merge-gate creates a bootstrap problem for changes to the qualifier,
   issuer or gate itself. Those paths intentionally escalate and need an owner-approved
   exceptional qualification path through the same bounded DB wrapper, never direct DML.
4. The DB wrapper design must be reviewed for SECURITY DEFINER privilege escalation,
   search_path, arbitrary repository/target injection and transaction race behavior before
   migration.
5. Gate polling adds bounded latency to CONTROL_SYSTEM PRs and must retry only MISSING, not
   structural/readback errors.
6. Builder-session metadata needs one canonical non-HEAD-changing location in PR metadata;
   until owner decides exact syntax, missing metadata must BLOCK rather than infer identity.

## Approval boundary

Nothing in this document authorizes:
- creating the DB role/wrapper migration;
- creating/modifying a workflow;
- establishing a new DB-write route outside the current F0 Train-only policy;
- issuing a real receipt;
- changing Train, ruleset or required checks;
- merging the design PR;
- touching #2988.

Before persistence can be implemented, Cristhian must explicitly choose one:
1. amend canonical Router/F0 governance to authorize the bounded qualification-issuer
   operation and role; or
2. reject direct CI persistence and redesign issuance so every receipt write is still
   executed through an authorized Train-mediated route.

Until that decision exists, the issuer remains dry-run only.

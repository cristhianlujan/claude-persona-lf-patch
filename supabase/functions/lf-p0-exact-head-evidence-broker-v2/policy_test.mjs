import assert from "node:assert/strict";
import {
  REPOSITORY,
  WORKFLOW_NAME,
  WORKFLOW_PATH,
  governedRef,
  branchFromRef,
  validateRequestScope,
  validateRunIdentity,
} from "./policy.mjs";

const sha = "a".repeat(40);
const base = { repository: REPOSITORY, ref: "refs/heads/main", github_sha: sha, run_id: 77, run_attempt: 1, event_name: "push" };
assert.equal(governedRef("refs/heads/main"), true);
assert.equal(governedRef("refs/heads/lf/p0-exact-head-real-source-v2"), true);
assert.equal(governedRef("refs/heads/feature/arbitrary"), false);
assert.equal(governedRef("refs/heads/lf/not-p0"), false);
assert.equal(branchFromRef(base.ref), "main");
assert.equal(validateRequestScope(base), null);
assert.equal(validateRequestScope({ ...base, ref: "refs/heads/feature/arbitrary" }), "GITHUB_REQUEST_REF_NOT_GOVERNED");
assert.equal(validateRequestScope({ ...base, github_sha: "b".repeat(39) }), "GITHUB_SHA_INVALID");
assert.equal(validateRequestScope({ ...base, event_name: "pull_request" }), "GITHUB_EVENT_INVALID");
const run = {
  id: 77,
  run_attempt: 1,
  repository: { full_name: REPOSITORY },
  name: WORKFLOW_NAME,
  path: WORKFLOW_PATH,
  head_branch: "main",
  head_sha: sha,
  event: "push",
  status: "in_progress",
};
assert.equal(validateRunIdentity(base, run), null);
assert.equal(validateRunIdentity(base, { ...run, name: "lf-contract-check" }), "GITHUB_WORKFLOW_NAME_MISMATCH");
assert.equal(validateRunIdentity(base, { ...run, path: ".github/workflows/other.yml" }), "GITHUB_WORKFLOW_PATH_MISMATCH");
assert.equal(validateRunIdentity(base, { ...run, head_sha: "b".repeat(40) }), "GITHUB_WORKFLOW_SHA_MISMATCH");
assert.equal(validateRunIdentity(base, { ...run, head_branch: "lf/p0-other" }), "GITHUB_WORKFLOW_BRANCH_MISMATCH");
assert.equal(validateRunIdentity(base, { ...run, status: "completed" }), "GITHUB_WORKFLOW_STATUS_INVALID");
console.log(JSON.stringify({ gate: "PASS_P0_EXACT_HEAD_IDENTITY_POLICY_V2", checks: 15 }));

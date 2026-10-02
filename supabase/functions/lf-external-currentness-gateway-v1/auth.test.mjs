import assert from "node:assert/strict";
import {
  MAIN_REF,
  REPOSITORY,
  REPOSITORY_ID,
  WORKFLOW_NAME,
  WORKFLOW_REF,
  validateGatewayClaims,
  requireObservedMainMatchesWorkflow,
  requireEdgeReadCredential,
} from "./auth.ts";

const base = {
  repository: REPOSITORY,
  repository_id: REPOSITORY_ID,
  ref: MAIN_REF,
  workflow: WORKFLOW_NAME,
  workflow_ref: WORKFLOW_REF,
  event_name: "push",
  run_id: "12345",
  workflow_sha: "a".repeat(40),
};

for (const event_name of ["push", "schedule", "workflow_dispatch"]) {
  assert.equal(validateGatewayClaims({ ...base, event_name }).eventName, event_name);
}

for (const event_name of ["workflow_call", "pull_request", "repository_dispatch"]) {
  assert.throws(() => validateGatewayClaims({ ...base, event_name }), /OIDC_EVENT_NOT_ALLOWED/);
}

assert.throws(() => validateGatewayClaims({ ...base, repository: "other/repo" }), /OIDC_REPOSITORY_MISMATCH/);
assert.throws(() => validateGatewayClaims({ ...base, ref: "refs/heads/dev" }), /OIDC_REF_MISMATCH/);
assert.throws(() => validateGatewayClaims({ ...base, workflow_ref: "other" }), /OIDC_WORKFLOW_IDENTITY_MISMATCH/);
assert.throws(() => validateGatewayClaims({ ...base, job_workflow_ref: "other" }), /OIDC_WORKFLOW_IDENTITY_MISMATCH/);
assert.throws(() => validateGatewayClaims({ ...base, workflow_sha: "bad" }), /OIDC_RUN_IDENTITY_INCOMPLETE/);
const exactIdentity = validateGatewayClaims(base);
assert.equal(
  requireObservedMainMatchesWorkflow(exactIdentity.workflowSha, exactIdentity),
  exactIdentity.workflowSha,
);
assert.throws(
  () => requireObservedMainMatchesWorkflow("b".repeat(40), exactIdentity),
  /REPORT_MAIN_SHA_MISMATCH/,
);

assert.throws(() => requireEdgeReadCredential(""), /EDGE_READ_CREDENTIAL_MISSING/);
assert.equal(requireEdgeReadCredential(" scoped-pat "), "scoped-pat");

console.log("PASS_GATEWAY_OIDC_IDENTITY_TESTS");

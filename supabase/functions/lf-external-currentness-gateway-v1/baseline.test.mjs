import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  MAIN_REF,
  REPOSITORY,
  REPOSITORY_ID,
  WORKFLOW_NAME,
  WORKFLOW_REF,
  baselineApprovalArgs,
  validateGatewayClaims,
} from "./auth.ts";

const claims = {
  repository: REPOSITORY,
  repository_id: REPOSITORY_ID,
  ref: MAIN_REF,
  workflow: WORKFLOW_NAME,
  workflow_ref: WORKFLOW_REF,
  event_name: "workflow_dispatch",
  run_id: "37099999999",
  workflow_sha: "a".repeat(40),
  actor: "paulozterra",
};

const identity = validateGatewayClaims(claims);
const args = baselineApprovalArgs(identity, {
  approve_sync_key: "b".repeat(64),
  actor: "evil-body-actor",
  run_id: "1",
  workflow_sha: "c".repeat(40),
});
assert.deepEqual(args, {
  p_sync_key: "b".repeat(64),
  p_actor: "paulozterra",
  p_github_run_id: 37099999999,
  p_workflow_sha: "a".repeat(40),
});

assert.throws(
  () => baselineApprovalArgs(validateGatewayClaims({ ...claims, event_name: "push" }), { approve_sync_key: "b".repeat(64) }),
  /BASELINE_APPROVAL_EVENT_REQUIRED/,
);
assert.throws(() => baselineApprovalArgs(identity, { approve_sync_key: "bad" }), /BASELINE_APPROVAL_SYNC_KEY_INVALID/);
assert.throws(
  () => baselineApprovalArgs(validateGatewayClaims({ ...claims, actor: "" }), { approve_sync_key: "b".repeat(64) }),
  /BASELINE_APPROVAL_ACTOR_MISSING/,
);
assert.throws(
  () => baselineApprovalArgs(validateGatewayClaims({ ...claims, run_id: "not-a-number" }), { approve_sync_key: "b".repeat(64) }),
  /BASELINE_APPROVAL_RUN_ID_INVALID/,
);

const source = readFileSync(new URL("./index.ts", import.meta.url), "utf8");
for (const rpc of [
  "lf_external_baseline_begin_v1",
  "lf_external_baseline_stage_batch_v1",
  "lf_external_baseline_approve_v1",
  "lf_external_baseline_finalize_v1",
]) {
  assert.match(source, new RegExp(`inventoryRpc\\(\\"${rpc}\\"`));
}
assert.match(source, /body\.action === "write_baseline"/);
assert.match(source, /BASELINE_CURRENTNESS_FIELD_FORBIDDEN/);
assert.match(source, /baselineApprovalArgs\(identity, body\)/);

console.log("PASS_GATEWAY_BASELINE_WRITE_TESTS");

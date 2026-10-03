import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { buildBaselineRpcRequest, buildEnabledBaselineRpcRequest } from "./baseline.mjs";

const identity = {
  repository: "cristhianlujan/claude-persona-lf-patch",
  ref: "refs/heads/main",
  workflow: "LF External Currentness Detector",
  workflowRef: "cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-external-currentness-detector.yml@refs/heads/main",
  eventName: "workflow_dispatch",
  runId: "123456789",
  workflowSha: "b".repeat(40),
  sha: "a".repeat(40),
  actor: "paulozterra",
};

const repoItem = {
  kind: "REPO",
  state: "NEW",
  path: "sandbox/example.py",
  git_blob: "c".repeat(40),
  sha256: "d".repeat(64),
  file_last_commit: "e".repeat(40),
  bytes: 12,
  extension: "py",
};
const edgeItem = {
  kind: "EDGE",
  state: "STALE",
  slug: "fn-a",
  ezbr_sha256: "f".repeat(64),
  runtime_version: 18,
  verify_jwt: false,
  source_state: "RUNTIME_WITHOUT_SOURCE",
};

test("baseline write kill switch is fail-closed for all phases and only exact true enables", () => {
  const requests = [
    {
      phase: "begin",
      observed_main_sha: identity.sha,
      report_sha256: "1".repeat(64),
      repo_new: 1, repo_stale: 0, repo_missing: 0,
      edge_new: 0, edge_stale: 0, edge_missing: 0,
      runtime_without_source_count: 0,
    },
    {
      phase: "stage_batch",
      sync_key: "2".repeat(64),
      batch_no: 1,
      items: [repoItem],
    },
    {
      phase: "approve",
      approve_sync_key: "3".repeat(64),
    },
    {
      phase: "finalize",
      sync_key: "4".repeat(64),
    },
  ];

  for (const disabled of [undefined, "false", "TRUE", "1"]) {
    for (const request of requests) {
      assert.throws(
        () => buildEnabledBaselineRpcRequest(request, identity, disabled),
        /BASELINE_WRITE_DISABLED/,
      );
    }
  }

  for (const request of requests) {
    assert.deepEqual(
      buildEnabledBaselineRpcRequest(request, identity, "true"),
      buildBaselineRpcRequest(request, identity),
    );
  }
});

test("begin binds exact run sha and all governed counts", () => {
  const plan = buildBaselineRpcRequest({
    phase: "begin",
    observed_main_sha: identity.sha,
    report_sha256: "1".repeat(64),
    repo_new: 656,
    repo_stale: 0,
    repo_missing: 0,
    edge_new: 3,
    edge_stale: 0,
    edge_missing: 0,
    runtime_without_source_count: 21,
  }, identity);
  assert.equal(plan.rpc, "lf_external_baseline_begin_v1");
  assert.equal(plan.args.p_expected_repo_new, 656);
  assert.equal(plan.args.p_expected_edge_new, 3);
  assert.equal(plan.args.p_observed_main_sha, identity.sha);
});

test("begin rejects sha different from OIDC run sha", () => {
  assert.throws(() => buildBaselineRpcRequest({
    phase: "begin",
    observed_main_sha: "9".repeat(40),
    report_sha256: "1".repeat(64),
    repo_new: 1, repo_stale: 0, repo_missing: 0,
    edge_new: 0, edge_stale: 0, edge_missing: 0,
    runtime_without_source_count: 0,
  }, identity), /BASELINE_MAIN_SHA_MISMATCH/);
});

test("stage maps minimal generator metadata to 9.5a wrapper shape", () => {
  const plan = buildBaselineRpcRequest({
    phase: "stage_batch",
    sync_key: "2".repeat(64),
    batch_no: 1,
    items: [repoItem, edgeItem],
  }, identity);
  assert.equal(plan.rpc, "lf_external_baseline_stage_batch_v1");
  assert.deepEqual(plan.args.p_items[0], {
    source_kind: "REPO",
    object_key: repoItem.path,
    state: "NEW",
    definition_sha256: repoItem.sha256,
    source_version: repoItem.file_last_commit,
    git_blob: repoItem.git_blob,
    verify_jwt: null,
    source_state: null,
    bytes: 12,
    extension: "py",
  });
  assert.equal(plan.args.p_items[1].source_kind, "EDGE");
  assert.equal(plan.args.p_items[1].source_version, "18");
});

test("stage rejects duplicate and null required baseline evidence", () => {
  assert.throws(() => buildBaselineRpcRequest({
    phase: "stage_batch", sync_key: "2".repeat(64), batch_no: 1, items: [repoItem, repoItem],
  }, identity), /BASELINE_STAGE_DUPLICATE_ITEM/);
  assert.throws(() => buildBaselineRpcRequest({
    phase: "stage_batch", sync_key: "2".repeat(64), batch_no: 1,
    items: [{ ...repoItem, sha256: null }],
  }, identity), /BASELINE_STAGE_ITEM_INVALID/);
});

test("approve takes actor run_id and workflow sha only from OIDC identity", () => {
  const plan = buildBaselineRpcRequest({
    phase: "approve",
    approve_sync_key: "3".repeat(64),
    actor: "mallory",
    github_run_id: 999,
    workflow_sha: "9".repeat(40),
  }, identity);
  assert.equal(plan.rpc, "lf_external_baseline_approve_v1");
  assert.equal(plan.args.p_actor, "paulozterra");
  assert.equal(plan.args.p_github_run_id, 123456789);
  assert.equal(plan.args.p_workflow_sha, identity.sha);
});

test("approve is workflow_dispatch only and requires explicit approve_sync_key", () => {
  assert.throws(() => buildBaselineRpcRequest({
    phase: "approve", approve_sync_key: "3".repeat(64),
  }, { ...identity, eventName: "push" }), /BASELINE_APPROVAL_EVENT_NOT_ALLOWED/);
  assert.throws(() => buildBaselineRpcRequest({ phase: "approve" }, identity), /BASELINE_APPROVAL_SYNC_KEY_INVALID/);
});

test("finalize accepts only exact sync key", () => {
  const plan = buildBaselineRpcRequest({ phase: "finalize", sync_key: "4".repeat(64) }, identity);
  assert.equal(plan.rpc, "lf_external_baseline_finalize_v1");
  assert.deepEqual(plan.args, { p_sync_key: "4".repeat(64) });
  assert.throws(() => buildBaselineRpcRequest({ phase: "finalize", sync_key: "bad" }, identity), /BASELINE_FINALIZE_SYNC_KEY_INVALID/);
});

test("baseline gateway path never references currentness writers", () => {
  const baseline = readFileSync(new URL("./baseline.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(baseline, /apply_observation|write_observation|currentness/i);
  for (const wrapper of [
    "lf_external_baseline_begin_v1",
    "lf_external_baseline_stage_batch_v1",
    "lf_external_baseline_approve_v1",
    "lf_external_baseline_finalize_v1",
  ]) assert.match(baseline, new RegExp(wrapper));
});

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("./auth.ts", import.meta.url), "utf8");

test("OIDC identity remains pinned to repository main workflow and allowed events", () => {
  assert.match(source, /REPOSITORY = "cristhianlujan\/claude-persona-lf-patch"/);
  assert.match(source, /MAIN_REF = "refs\/heads\/main"/);
  assert.match(source, /WORKFLOW_PATH = "\.github\/workflows\/lf-external-currentness-detector\.yml"/);
  assert.match(source, /ALLOWED_EVENTS = new Set\(\["push", "schedule", "workflow_dispatch"\]\)/);
  assert.match(source, /if \(!ALLOWED_EVENTS\.has\(eventName\)\) throw new Error\("OIDC_EVENT_NOT_ALLOWED"\)/);
});

test("OIDC identity requires run_id workflow_sha sha and actor claims", () => {
  assert.match(source, /const runId = asString\(payload\.run_id\)/);
  assert.match(source, /const workflowSha = asString\(payload\.workflow_sha\)/);
  assert.match(source, /const sha = asString\(payload\.sha\)/);
  assert.match(source, /const actor = asString\(payload\.actor\)/);
  assert.match(source, /!\/\^\[0-9a-f\]\{40\}\$\/\.test\(workflowSha\)/);
  assert.match(source, /!\/\^\[0-9a-f\]\{40\}\$\/\.test\(sha\)/);
  assert.match(source, /!actor/);
});

test("observed currentness report remains bound to workflow_sha", () => {
  assert.match(source, /observedMainSha !== identity\.workflowSha/);
  assert.match(source, /REPORT_MAIN_SHA_MISMATCH/);
});

test("gateway returns actor and sha from verified claims", () => {
  assert.match(source, /return \{[\s\S]*eventName,[\s\S]*runId,[\s\S]*workflowSha,[\s\S]*sha,[\s\S]*actor,[\s\S]*\};/);
});

console.log("PASS_GATEWAY_OIDC_IDENTITY_TESTS");

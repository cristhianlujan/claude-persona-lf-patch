import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";
import { signedPreimage } from "./canonical_payload_v7.ts";

const REPOSITORY = "cristhianlujan/claude-persona-lf-patch";
const REPOSITORY_ID = "1244397752";
const AUDIENCE = "lf-supabase-github-reconcile-v3";
const WORKFLOW_REF = `${REPOSITORY}/.github/workflows/lf-github-reconcile-v3.yml@refs/heads/main`;
const WORKFLOW_NAME = "LF GitHub Reconciliation V3";
const ISSUER = "https://token.actions.githubusercontent.com";
const WRITER_MODE = "GITHUB_OIDC_HMAC_NONCE_V7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const WRITER_HMAC_SECRET = Deno.env.get("LF_RECONCILIATION_WRITER_HMAC_V7");
if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !WRITER_HMAC_SECRET) {
  throw new Error("Supabase runtime or V7 writer secrets missing");
}

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const JWKS = createRemoteJWKSet(new URL(`${ISSUER}/.well-known/jwks`));
const WRITER_KEY = await crypto.subtle.importKey(
  "raw",
  encoder.encode(WRITER_HMAC_SECRET),
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["sign"],
);

function response(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function hex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function isSha40(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{40}$/.test(value);
}

function isSha64(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

async function sha256Bytes(bytes: Uint8Array): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}

async function gitBlob(bytes: Uint8Array): Promise<string> {
  const header = encoder.encode(`blob ${bytes.byteLength}\0`);
  const payload = new Uint8Array(header.byteLength + bytes.byteLength);
  payload.set(header);
  payload.set(bytes, header.byteLength);
  return hex(await crypto.subtle.digest("SHA-1", payload));
}

async function writerProof(preimage: string): Promise<{ nonce: string; signature: string }> {
  const nonce = `${crypto.randomUUID()}.${Math.floor(Date.now() / 1000) + 300}`;
  const signature = await crypto.subtle.sign(
    "HMAC",
    WRITER_KEY,
    encoder.encode(`${preimage}:${nonce}`),
  );
  return { nonce, signature: hex(signature) };
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const result = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await result.text();
  if (!result.ok) {
    throw new Error(`RPC ${name} failed (${result.status}): ${text.slice(0, 1000)}`);
  }
  return (text ? JSON.parse(text) : null) as T;
}

async function github(path: string, accept = "application/vnd.github+json"): Promise<any> {
  const result = await fetch(`https://api.github.com/repos/${REPOSITORY}/${path}`, {
    headers: {
      accept,
      "x-github-api-version": "2022-11-28",
      "user-agent": "lf-independent-reconciler-v7",
    },
  });
  const text = await result.text();
  if (!result.ok) {
    throw new Error(`GitHub readback failed (${result.status}) for ${path}: ${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : null;
}

async function oidc(req: Request): Promise<JWTPayload> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new Error("Missing GitHub OIDC bearer token");
  }

  const { payload } = await jwtVerify(authorization.slice(7), JWKS, {
    issuer: ISSUER,
    audience: AUDIENCE,
    algorithms: ["RS256"],
  });

  if (payload.repository !== REPOSITORY || String(payload.repository_id ?? "") !== REPOSITORY_ID) {
    throw new Error("OIDC repository mismatch");
  }
  if (
    payload.ref !== "refs/heads/main" ||
    payload.workflow_ref !== WORKFLOW_REF ||
    payload.workflow !== WORKFLOW_NAME
  ) {
    throw new Error("OIDC workflow or ref mismatch");
  }
  if (payload.event_name && payload.event_name !== "workflow_run") {
    throw new Error("OIDC event mismatch");
  }
  if (!payload.run_id || !payload.workflow_sha) {
    throw new Error("OIDC run identity incomplete");
  }
  return payload;
}

type Inventory = {
  artifact_id: number;
  skill_code: string;
  artifact_code: string;
  relative_path: string;
  artifact_type: string;
  current_content_sha256: string;
  baseline_content_sha256: string;
  is_current: boolean;
};

type Governance = {
  path: string;
  expected_sha256: string;
  expected_git_blob: string;
  control_kind: string;
};

type Reported = {
  artifact_id: number;
  relative_path: string;
  repository_path?: string;
  sha256: string | null;
  git_blob: string | null;
  file_touched_by_merge: boolean;
  audit_covered: boolean;
};

type FileEvidence = {
  path: string;
  sha256: string;
  git_blob: string;
};

type ReconcileBody = {
  action: "reconcile";
  reconciliation_workflow_run_id: number;
  source: {
    id: number;
    name: string;
    event: string;
    head_sha: string;
    head_branch: string;
    conclusion: string;
    updated_at: string;
    html_url: string;
  };
  pull_request: {
    number: number | null;
    state: string;
    merged: boolean;
    merge_commit_sha: string | null;
  };
  branch_protection_status: "VERIFIED" | "NOT_CONFIGURED" | "NOT_AUDITABLE_EXTERNAL" | "FAILED";
  branch_protection_details: Record<string, any>;
  audit_artifact_name: string;
  audit_manifest_sha256: string;
  artifacts: Reported[];
};

function repositoryPath(item: Inventory): string {
  return item.relative_path.startsWith("skills/")
    ? item.relative_path
    : `skills/${item.skill_code}/${item.relative_path}`;
}

async function repositoryFile(commit: string, path: string): Promise<FileEvidence> {
  if (!isSha40(commit) || !path || path.startsWith("/") || path.includes("..")) {
    throw new Error("Invalid repository target");
  }
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  const result = await fetch(
    `https://raw.githubusercontent.com/${REPOSITORY}/${commit}/${encoded}`,
    { headers: { accept: "application/octet-stream", "user-agent": "lf-independent-reconciler-v7" } },
  );
  if (!result.ok) {
    throw new Error(`Repository file missing (${result.status}): ${path}`);
  }
  const bytes = new Uint8Array(await result.arrayBuffer());
  decoder.decode(bytes);
  return {
    path,
    sha256: await sha256Bytes(bytes),
    git_blob: await gitBlob(bytes),
  };
}

async function repositoryFiles(
  commit: string,
  inventory: Inventory[],
): Promise<Map<number, FileEvidence>> {
  const result = new Map<number, FileEvidence>();
  for (let offset = 0; offset < inventory.length; offset += 8) {
    const batch = inventory.slice(offset, offset + 8);
    const files = await Promise.all(
      batch.map((item) => repositoryFile(commit, repositoryPath(item))),
    );
    files.forEach((file, index) => result.set(Number(batch[index].artifact_id), file));
  }
  return result;
}

async function verifiedSource(input: ReconcileBody): Promise<{
  source: ReconcileBody["source"];
  pull_request: { number: number; state: "MERGED"; merged: true; merge_commit_sha: string };
}> {
  const run = await github(`actions/runs/${Number(input.source.id)}`);
  if (
    Number(run?.id) !== Number(input.source.id) ||
    run?.name !== "lf-contract-check" ||
    run?.event !== "push" ||
    run?.head_branch !== "main" ||
    run?.head_sha !== input.source.head_sha ||
    run?.status !== "completed" ||
    run?.conclusion !== "success" ||
    run?.repository?.full_name !== REPOSITORY
  ) {
    throw new Error("Independent source workflow verification failed");
  }

  const pulls = await github(
    `commits/${run.head_sha}/pulls`,
    "application/vnd.github+json, application/vnd.github.groot-preview+json",
  );
  const merged = Array.isArray(pulls)
    ? pulls.find(
      (pull) =>
        Boolean(pull?.merged_at) &&
        pull?.state === "closed" &&
        pull?.merge_commit_sha === run.head_sha,
    )
    : null;
  if (!merged) {
    throw new Error("Independent merged PR verification failed");
  }

  return {
    source: {
      id: Number(run.id),
      name: run.name,
      event: run.event,
      head_sha: run.head_sha,
      head_branch: run.head_branch,
      conclusion: run.conclusion,
      updated_at: run.updated_at,
      html_url: run.html_url,
    },
    pull_request: {
      number: Number(merged.number),
      state: "MERGED",
      merged: true,
      merge_commit_sha: merged.merge_commit_sha,
    },
  };
}

async function verifyGovernance(commit: string): Promise<Governance[]> {
  const bundle = await rpc<Governance[]>("get_lf_repository_governance_bundle_v4", {});
  if (!Array.isArray(bundle) || bundle.length < 7) {
    throw new Error("Governance bundle incomplete");
  }
  for (const expected of bundle) {
    const actual = await repositoryFile(commit, expected.path);
    if (
      actual.sha256 !== expected.expected_sha256 ||
      actual.git_blob !== expected.expected_git_blob
    ) {
      throw new Error(`Governance file drift: ${expected.path}`);
    }
  }
  return bundle;
}

function nativeProtectionVerified(input: ReconcileBody): boolean {
  const c = input.branch_protection_details?.criteria ?? {};
  return input.branch_protection_status === "VERIFIED" &&
    c.active_rules_present === true &&
    c.lf_contract_check_required === true &&
    c.strict_status_checks === true &&
    c.approving_reviews === true &&
    c.non_fast_forward === true &&
    c.deletions_blocked === true &&
    c.bypass_actors_auditable === true &&
    c.bypass_actors_empty === true;
}

async function reconciliationPreimage(
  payload: Record<string, unknown>,
  execution: string,
): Promise<string> {
  return signedPreimage("reconciliation-v7", payload, execution);
}

async function gatePreimage(
  payload: Record<string, unknown>,
  execution: string,
): Promise<string> {
  return signedPreimage("gate-v7", payload, execution);
}

async function recordReconciliation(
  payload: Record<string, any>,
  execution: string,
): Promise<number> {
  const proof = await writerProof(await reconciliationPreimage(payload, execution));
  return Number(await rpc<number>("record_external_ci_verification_v7", {
    p_payload: payload,
    p_execution_id: execution,
    p_writer_signature: proof.signature,
    p_writer_nonce: proof.nonce,
  }));
}

async function recordGate(payload: Record<string, any>, execution: string): Promise<number> {
  const proof = await writerProof(await gatePreimage(payload, execution));
  return Number(await rpc<number>("record_lf_gate_test_v7", {
    p_payload: payload,
    p_execution_id: execution,
    p_writer_signature: proof.signature,
    p_writer_nonce: proof.nonce,
  }));
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return response({ error: "POST required" }, 405);
    }

    const claims = await oidc(req);
    const body = await req.json();

    if (body?.action === "inventory") {
      return response({
        repository: REPOSITORY,
        writer_authentication: WRITER_MODE,
        inventory: await rpc<Inventory[]>("get_lf_github_reconciliation_inventory_v3", {}),
      });
    }
    if (body?.action !== "reconcile") {
      return response({ error: "Unsupported action" }, 400);
    }

    const input = body as ReconcileBody;
    if (String(claims.run_id) !== String(input.reconciliation_workflow_run_id)) {
      throw new Error("OIDC run mismatch");
    }
    if (
      !input.source ||
      !isSha40(input.source.head_sha) ||
      !isSha64(input.audit_manifest_sha256) ||
      !input.audit_artifact_name
    ) {
      throw new Error("Reconciliation request incomplete");
    }
    if (!Array.isArray(input.artifacts)) {
      throw new Error("Artifacts must be an array");
    }

    const verified = await verifiedSource(input);
    const governance = await verifyGovernance(verified.source.head_sha);
    const inventory = await rpc<Inventory[]>("get_lf_github_reconciliation_inventory_v3", {});
    const reported = new Map(
      input.artifacts.map((item) => [Number(item.artifact_id), item]),
    );
    const files = await repositoryFiles(verified.source.head_sha, inventory);
    const execution = `GHA-OIDC-${claims.run_id}-SRC-${verified.source.id}`;
    const nativeProtection = nativeProtectionVerified(input);
    const storedControl = nativeProtection
      ? "VERIFIED"
      : "VERIFIED_COMPENSATING_CONTROLS";

    const results: Record<string, unknown>[] = [];
    const promotable: {
      artifact_id: number;
      reconciliation_run_id: number;
      gate_test_run_id: number;
    }[] = [];

    for (const item of inventory) {
      const actual = files.get(Number(item.artifact_id));
      const manifest = reported.get(Number(item.artifact_id));
      const failures: string[] = [];

      if (!nativeProtection) failures.push("BRANCH_PROTECTION_NOT_VERIFIED");
      if (!manifest) failures.push("ARTIFACT_NOT_REPORTED");
      if (!actual) failures.push("ARTIFACT_REPOSITORY_READBACK_MISSING");
      if (!item.is_current) failures.push("ARTIFACT_NOT_CURRENT");
      if (manifest && manifest.relative_path !== item.relative_path) {
        failures.push("ARTIFACT_PATH_MISMATCH");
      }
      if (manifest?.repository_path && manifest.repository_path !== repositoryPath(item)) {
        failures.push("REPOSITORY_PATH_MISMATCH");
      }
      if (!actual || actual.sha256 !== item.current_content_sha256) {
        failures.push("ARTIFACT_SHA256_MISMATCH");
      }
      if (!actual || !isSha40(actual.git_blob)) {
        failures.push("ARTIFACT_GIT_BLOB_MISSING");
      }
      if (!manifest?.audit_covered) {
        failures.push("ARTIFACT_NOT_EXERCISED_BY_WORKFLOW");
      }
      if (
        manifest &&
        actual &&
        (manifest.sha256 !== actual.sha256 || manifest.git_blob !== actual.git_blob)
      ) {
        failures.push("MANIFEST_REPOSITORY_MISMATCH");
      }

      const reconciliation: Record<string, any> = {
        result: failures.length === 0 ? "PASS" : "FAIL",
        artifact_id: Number(item.artifact_id),
        repository: REPOSITORY,
        target_branch: "main",
        artifact_path: item.relative_path,
        pr_number: verified.pull_request.number,
        pr_state: verified.pull_request.state,
        merged: true,
        merge_commit_sha: verified.source.head_sha,
        workflow_run_id: Number(verified.source.id),
        workflow_name: verified.source.name,
        workflow_event: verified.source.event,
        workflow_head_sha: verified.source.head_sha,
        workflow_conclusion: verified.source.conclusion,
        artifact_git_blob: actual?.git_blob ?? manifest?.git_blob ?? null,
        artifact_sha256: actual?.sha256 ?? manifest?.sha256 ?? null,
        file_touched_by_merge: Boolean(manifest?.file_touched_by_merge),
        artifact_exercised_by_workflow: Boolean(manifest?.audit_covered),
        audit_artifact_name: input.audit_artifact_name,
        audit_manifest_sha256: input.audit_manifest_sha256,
        branch_protection_status: storedControl,
        failure_reasons: failures,
        details: {
          source_workflow_url: verified.source.html_url,
          reconciliation_workflow_run_id: Number(claims.run_id),
          reconciliation_workflow_sha: claims.workflow_sha,
          workflow_ref: claims.workflow_ref,
          actual_branch_protection_status: input.branch_protection_status,
          branch_protection: input.branch_protection_details ?? {},
          repository_change_control: {
            status: input.branch_protection_status,
            native_protection_verified: nativeProtection,
            independent_source_run_readback: true,
            independent_merged_pr_readback: true,
            independent_artifact_content_readback: true,
            governance_bundle_verified: true,
            governance_file_count: governance.length,
            writer_authentication: WRITER_MODE,
          },
          baseline_content_sha256: item.baseline_content_sha256,
          repository_path: actual?.path ?? manifest?.repository_path ?? null,
        },
        observed_at: verified.source.updated_at,
        producer: "github-actions-oidc-reconciler-hmac-v7",
        purpose: "Persist independently verified fail-closed evidence using OIDC, keyed HMAC and a single-use nonce",
      };

      const reconciliationId = await recordReconciliation(reconciliation, execution);

      const gate: Record<string, any> = {
        test_code: "POST_MERGE-LF-CONTRACT-CHECK-V3",
        artifact_id: Number(item.artifact_id),
        gate_code: "EXTERNAL-CI-V3",
        test_kind: "INTEGRATION",
        target_relation: item.relative_path,
        probe_preimage: {
          source_workflow_run_id: Number(verified.source.id),
          source_commit_sha: verified.source.head_sha,
          artifact_path: item.relative_path,
          expected_sha256: item.current_content_sha256,
          independent_repository_sha256: actual?.sha256 ?? null,
          audit_manifest_sha256: input.audit_manifest_sha256,
          repository_change_control_status: input.branch_protection_status,
        },
        expected_outcome: {
          workflow_event: "push",
          workflow_conclusion: "success",
          artifact_sha256: item.current_content_sha256,
          audit_covered: true,
          independent_readback: true,
          native_branch_protection: true,
        },
        observed_outcome: {
          workflow_event: verified.source.event,
          workflow_conclusion: verified.source.conclusion,
          artifact_sha256: actual?.sha256 ?? null,
          audit_covered: Boolean(manifest?.audit_covered),
          independent_readback: Boolean(actual),
          native_branch_protection: nativeProtection,
          failure_reasons: failures,
        },
        persisted_effects: {
          rows: 1,
          github_reconciliation_run_id: reconciliationId,
          source_workflow_run_id: Number(verified.source.id),
        },
        passed: failures.length === 0,
        runner_type: "GITHUB_ACTIONS_POST_MERGE",
        runner_identity: WORKFLOW_REF,
        source_workflow_run_id: Number(verified.source.id),
        source_commit_sha: verified.source.head_sha,
        executed_at: new Date().toISOString(),
        producer: "github-actions-oidc-reconciler-hmac-v7",
        purpose: "Record reproducible post-merge evidence using OIDC, keyed HMAC and a single-use nonce",
      };

      const gateId = await recordGate(gate, execution);
      if (failures.length === 0) {
        promotable.push({
          artifact_id: Number(item.artifact_id),
          reconciliation_run_id: reconciliationId,
          gate_test_run_id: gateId,
        });
      }
      results.push({
        artifact_id: Number(item.artifact_id),
        result: failures.length === 0 ? "PASS" : "FAIL",
        failures,
        reconciliation_run_id: reconciliationId,
        gate_test_run_id: gateId,
      });
    }

    const pending = [...promotable];
    const promoted: number[] = [];
    if (nativeProtection) {
      for (let round = 0; round < 20 && pending.length > 0; round++) {
        let progress = false;
        for (let index = pending.length - 1; index >= 0; index--) {
          const item = pending[index];
          try {
            await rpc<boolean>("promote_lf_artifact_pass_v3", {
              p_artifact_id: item.artifact_id,
              p_reconciliation_run_id: item.reconciliation_run_id,
              p_gate_test_run_ids: [item.gate_test_run_id],
              p_execution_id: execution,
            });
            promoted.push(item.artifact_id);
            pending.splice(index, 1);
            progress = true;
          } catch {
            // Dependency ordering remains fail-closed. The pending set is returned.
          }
        }
        if (!progress) break;
      }
    }

    return response({
      execution_id: execution,
      source_workflow_run_id: verified.source.id,
      source_commit_sha: verified.source.head_sha,
      merged_pr_number: verified.pull_request.number,
      actual_branch_protection_status: input.branch_protection_status,
      native_branch_protection_verified: nativeProtection,
      writer_authentication: WRITER_MODE,
      governance_files_verified: governance.length,
      artifacts_expected: inventory.length,
      artifacts_reported: input.artifacts.length,
      pass_count: results.filter((item) => item.result === "PASS").length,
      fail_count: results.filter((item) => item.result === "FAIL").length,
      promoted_artifact_ids: promoted,
      promotion_pending_artifact_ids: pending.map((item) => item.artifact_id),
      results,
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : String(error);
    const unauthorized =
      message.includes("OIDC") ||
      message.includes("bearer token") ||
      message.includes("JWT");
    return response({ error: message }, unauthorized ? 401 : 500);
  }
});

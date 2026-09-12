import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  REPOSITORY,
  WORKFLOW_NAME,
  SOURCE_EVIDENCE_OBJECT_ID,
  SOURCE_SHA256,
  SOURCE_BYTES,
  validateRequestScope,
  validateRunIdentity,
} from "./policy.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Supabase runtime credentials missing");

function response(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

function isSha64(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

async function github(token: string, url: string): Promise<any> {
  const r = await fetch(url, {
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "x-github-api-version": "2022-11-28",
      "user-agent": "lf-p0-exact-head-evidence-broker-v2",
    },
    signal: AbortSignal.timeout(15000),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`GITHUB_AUTH_READBACK_${r.status}`);
  return text ? JSON.parse(text) : null;
}

async function authenticate(req: Request, body: Record<string, any>): Promise<any> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) throw new Error("GITHUB_INSTALLATION_TOKEN_MISSING");
  const token = authorization.slice(7).trim();
  if (!token) throw new Error("GITHUB_INSTALLATION_TOKEN_EMPTY");

  const scopeError = validateRequestScope(body);
  if (scopeError) throw new Error(scopeError);

  const installation = await github(token, "https://api.github.com/installation/repositories?per_page=100");
  const repos = Array.isArray(installation?.repositories) ? installation.repositories : [];
  if (!repos.some((repo: any) => repo?.full_name === REPOSITORY)) {
    throw new Error("GITHUB_INSTALLATION_REPOSITORY_MISMATCH");
  }

  const run = await github(token, `https://api.github.com/repos/${REPOSITORY}/actions/runs/${body.run_id}`);
  const runError = validateRunIdentity(body, run);
  if (runError) throw new Error(runError);
  return run;
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(30000),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`SUPABASE_RPC_${name}_${r.status}:${text.slice(0, 300)}`);
  return (text ? JSON.parse(text) : null) as T;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return response({ outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED" }, 405);
    let body: Record<string, any>;
    try {
      body = await req.json();
    } catch {
      return response({ outcome: "BLOCKED", code: "INVALID_JSON" }, 400);
    }

    const run = await authenticate(req, body);

    if (body.action === "get_source") {
      const source = await rpc<any>("fn_lf_p0_get_source_image_v1", {
        p_evidence_object_id: SOURCE_EVIDENCE_OBJECT_ID,
        p_expected_sha256: SOURCE_SHA256,
        p_expected_bytes: SOURCE_BYTES,
      });
      if (source?.content_sha256 !== SOURCE_SHA256 || Number(source?.content_bytes) !== SOURCE_BYTES) {
        throw new Error("SOURCE_RPC_READBACK_MISMATCH");
      }
      return response({
        outcome: "SOURCE_DELIVERED_TO_EXACT_GITHUB_RUN",
        source,
        broker_version: "v2",
        github_run: {
          id: run.id,
          run_attempt: run.run_attempt,
          head_sha: run.head_sha,
          head_branch: run.head_branch,
          event: run.event,
          workflow_name: run.name,
          workflow_path: run.path,
        },
      });
    }

    if (body.action === "store_receipt") {
      if (typeof body.receipt_base64 !== "string" || body.receipt_base64.length < 2) throw new Error("RECEIPT_BASE64_MISSING");
      if (!Number.isSafeInteger(body.receipt_bytes) || body.receipt_bytes < 1 || body.receipt_bytes > 10485760) throw new Error("RECEIPT_BYTES_INVALID");
      if (!isSha64(body.receipt_sha256) || !isSha64(body.configuration_sha256)) throw new Error("RECEIPT_HASH_INVALID");

      const reviewId = `P0-FRESH-REAL-${body.github_sha}`;
      const executionId = `EXEC-P0-FRESH-REAL-${body.github_sha}`;
      const evidenceObjectId = await rpc<string>("fn_lf_p0_store_exact_head_receipt_v1", {
        p_review_id: reviewId,
        p_execution_id: executionId,
        p_content_base64: body.receipt_base64,
        p_expected_bytes: body.receipt_bytes,
        p_expected_sha256: body.receipt_sha256,
        p_source_evidence_object_id: SOURCE_EVIDENCE_OBJECT_ID,
        p_source_sha256: SOURCE_SHA256,
        p_source_head_sha: body.github_sha,
        p_configuration_sha256: body.configuration_sha256,
        p_metadata: {
          evidence_schema_version: "p0-v4-real-rerun-trace",
          fresh_exact_head: true,
          source_evidence_object_id: SOURCE_EVIDENCE_OBJECT_ID,
          source_sha256: SOURCE_SHA256,
          github_run_id: String(body.run_id),
          github_run_attempt: String(body.run_attempt),
          github_workflow_name: WORKFLOW_NAME,
          github_workflow_path: run.path,
          github_event: body.event_name,
          github_ref: body.ref,
          broker: "lf-p0-exact-head-evidence-broker-v2",
          runner_exit_code: Number(body.runner_exit_code),
        },
      });
      return response({
        outcome: "RECEIPT_PERSISTED_WITH_CRYPTOGRAPHIC_AND_SEMANTIC_BINDING",
        evidence_object_id: evidenceObjectId,
        receipt_sha256: body.receipt_sha256,
        receipt_bytes: body.receipt_bytes,
        source_sha256: SOURCE_SHA256,
        source_head_sha: body.github_sha,
        broker_version: "v2",
      }, 201);
    }

    return response({ outcome: "BLOCKED", code: "ACTION_NOT_ALLOWED" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const authFailure = message.startsWith("GITHUB_");
    console.error(message.replace(/Bearer\s+\S+/g, "Bearer [REDACTED]"));
    return response({ outcome: "BLOCKED", code: message.slice(0, 300) }, authFailure ? 401 : 409);
  }
});

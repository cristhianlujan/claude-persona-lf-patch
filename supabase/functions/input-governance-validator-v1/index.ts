import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const enc = new TextEncoder();
const MAX_VALIDATION_CHUNKS = 8;
const HANDOFF_ASSERT_ENTRYPOINT = "fn_input_governance_validator_handoff_assert_v1";
const VALIDATOR_ENTRYPOINT = "fn_input_governance_validator_validate_handoff_v1";
type ScopeStrategy = "RESUME_EXISTING_SCOPE" | "REBIND_WITHIN_ENTRYPOINT";

async function sameSecret(a: string, b: string): Promise<boolean> {
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const aa = new Uint8Array(ha);
  const bb = new Uint8Array(hb);
  let diff = aa.length ^ bb.length;
  const n = Math.max(aa.length, bb.length);
  for (let i = 0; i < n; i++) diff |= (aa[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

async function requireServiceRole(req: Request): Promise<boolean> {
  if (!SERVICE_ROLE_KEY) return false;
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  return token.length > 0 && await sameSecret(token, SERVICE_ROLE_KEY);
}

async function rpc(name: string, args: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      "apikey": SERVICE_ROLE_KEY,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  let payload: any;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = { message: text }; }
  if (!res.ok) throw new Error(`VALIDATOR_RPC_FAILED:${res.status}:${JSON.stringify(payload)}`);
  return payload;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ error: "METHOD_NOT_ALLOWED" }, { status: 405 });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return Response.json({ error: "RUNTIME_CONFIG_MISSING" }, { status: 500 });
  if (!(await requireServiceRole(req))) return Response.json({ error: "SERVICE_ROLE_REQUIRED" }, { status: 403 });

  try {
    const body = await req.json();
    const runId = Number(body?.run_id);
    if (!Number.isInteger(runId) || runId < 1) return Response.json({ error: "RUN_ID_INVALID" }, { status: 400 });

    const rawHandoffReceiptId = body?.handoff_receipt_id;
    let requestedHandoffReceiptId: number | null = null;
    if (rawHandoffReceiptId !== undefined && rawHandoffReceiptId !== null) {
      requestedHandoffReceiptId = Number(rawHandoffReceiptId);
      if (!Number.isInteger(requestedHandoffReceiptId) || requestedHandoffReceiptId < 1) {
        return Response.json({ error: "HANDOFF_RECEIPT_ID_INVALID" }, { status: 400 });
      }
    }

    // Fail closed before any Validator execution. Null means resolve the latest exact persisted handoff for this run.
    const handoffReceipt = await rpc(HANDOFF_ASSERT_ENTRYPOINT, {
      p_run_id: runId,
      p_receipt_id: requestedHandoffReceiptId,
    });
    const handoffReceiptId = Number(handoffReceipt?.receipt_id);
    if (!Number.isInteger(handoffReceiptId) || handoffReceiptId < 1 || handoffReceipt?.status !== "VERIFIED") {
      return Response.json({ error: "HANDOFF_RECEIPT_NOT_VERIFIED", run_id: runId }, { status: 409 });
    }

    const resume = await rpc("fn_input_governance_validator_resume_context_v1", { p_run_id: runId });
    let identity: string;
    let resumed = false;
    let scopeStrategy: ScopeStrategy;
    if (resume?.resume_allowed === true) {
      identity = String(resume?.validator_identity ?? "");
      if (!/^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$/.test(identity)) {
        return Response.json({ error: "VALIDATOR_RESUME_IDENTITY_INVALID", run_id: runId }, { status: 409 });
      }
      resumed = true;
      scopeStrategy = "RESUME_EXISTING_SCOPE";
    } else {
      identity = `INPUT_VALIDATOR:EDGE:input-governance-validator-v1:${crypto.randomUUID()}`;
      scopeStrategy = "REBIND_WITHIN_ENTRYPOINT";
    }

    const trace: unknown[] = [];
    let result: any = null;
    for (let chunk = 1; chunk <= MAX_VALIDATION_CHUNKS; chunk++) {
      result = await rpc(VALIDATOR_ENTRYPOINT, {
        p_run_id: runId,
        p_validator_identity: identity,
        p_receipt_id: handoffReceiptId,
      });
      trace.push({ chunk, status: result?.status ?? null, validator_pass_count: result?.validator_pass_count ?? null, family_count: result?.family_count ?? null });
      if (["COMPLETED", "NOOP_COMPLETED"].includes(result?.status)) {
        return Response.json({ runtime: "input-governance-validator-v1", validator_entrypoint: VALIDATOR_ENTRYPOINT, handoff_receipt: handoffReceipt, scope_strategy: scopeStrategy, identity, resumed, chunked_validation: true, trace, result });
      }
      if (result?.status !== "VALIDATOR_CONTINUE_REQUIRED") {
        return Response.json({ error: "VALIDATOR_UNRESOLVED_STATUS", validator_entrypoint: VALIDATOR_ENTRYPOINT, handoff_receipt: handoffReceipt, scope_strategy: scopeStrategy, identity, resumed, trace, result }, { status: 409 });
      }
    }
    return Response.json({ error: "VALIDATOR_CHUNK_LIMIT", validator_entrypoint: VALIDATOR_ENTRYPOINT, handoff_receipt: handoffReceipt, scope_strategy: scopeStrategy, identity, resumed, max_chunks: MAX_VALIDATION_CHUNKS, trace, result }, { status: 409 });
  } catch (e) {
    return Response.json({ error: "VALIDATOR_EXECUTION_FAILED", detail: e instanceof Error ? e.message : String(e) }, { status: 409 });
  }
});

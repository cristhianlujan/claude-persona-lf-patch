import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const enc = new TextEncoder();
const MAX_REMEDIATION_CYCLES = 3;

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
  if (!res.ok) throw new Error(`DISPATCH_RPC_FAILED:${res.status}:${JSON.stringify(payload)}`);
  return payload;
}

async function callRuntime(slug: string, body: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/${slug}`, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let payload: any;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = { message: text }; }
  if (!res.ok) throw new Error(`${slug.toUpperCase()}_FAILED:${res.status}:${JSON.stringify(payload)}`);
  return payload;
}

function resolvedRunId(state: any): number | null {
  const raw = state?.run_id ?? state?.latest_run_id ?? state?.worker_spec?.latest_run_id ?? null;
  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? id : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return Response.json({ error: "METHOD_NOT_ALLOWED" }, { status: 405 });
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return Response.json({ error: "RUNTIME_CONFIG_MISSING" }, { status: 500 });
  if (!(await requireServiceRole(req))) return Response.json({ error: "SERVICE_ROLE_REQUIRED" }, { status: 403 });

  try {
    const body = await req.json();
    const pantallaId = Number(body?.pantalla_id);
    const consumer = typeof body?.consumer === "string" ? body.consumer : "STORY_CREATOR";
    if (!Number.isInteger(pantallaId) || pantallaId < 1) return Response.json({ error: "PANTALLA_ID_INVALID" }, { status: 400 });

    const trace: unknown[] = [];
    let lastState: any = null;

    for (let cycle = 1; cycle <= MAX_REMEDIATION_CYCLES; cycle++) {
      let state = await rpc("fn_input_governance_execute", { p_pantalla_id: pantallaId, p_consumer: consumer });
      lastState = state;
      trace.push({ step: "DISPATCH", cycle, status: state?.status, run_id: resolvedRunId(state) });

      if (["READY", "HUMAN_DECISION_REQUIRED", "BLOCKED"].includes(state?.status)) {
        const runId = resolvedRunId(state);
        if (runId) {
          const autofix = await rpc("fn_input_governance_safe_autofix_v1", { p_run_id: runId });
          trace.push({ step: "SAFE_AUTOFIX", cycle, run_id: runId, applied_count: autofix?.applied_count ?? 0, skipped_count: autofix?.skipped_count ?? 0, successor_required: autofix?.successor_required ?? false });
          if (autofix?.successor_required === true) continue;
        }
        return Response.json({ runtime: "input-governance-agent-v1", remediation_contract: "INPUT_GOV_SAFE_AUTOFIX_V1", trace, result: state });
      }

      if (state?.status === "CURATOR_RUNTIME_REQUIRED") {
        const curator = await callRuntime("input-governance-curator-v1", { pantalla_id: pantallaId, consumer });
        trace.push({ step: "CURATOR", cycle, status: curator?.result?.status, run_id: curator?.result?.run_id ?? null, identity: curator?.identity ?? null });

        if (curator?.result?.status === "BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED" ||
            curator?.result?.status === "CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED") {
          return Response.json({ runtime: "input-governance-agent-v1", remediation_contract: "INPUT_GOV_SAFE_AUTOFIX_V1", trace, result: curator.result });
        }
        if (curator?.result?.status === "NOOP_CURRENT") {
          state = await rpc("fn_input_governance_execute", { p_pantalla_id: pantallaId, p_consumer: consumer });
          trace.push({ step: "DISPATCH_AFTER_CURATOR_NOOP", cycle, status: state?.status, run_id: resolvedRunId(state) });
          lastState = state;
        } else if (curator?.result?.status === "VALIDATOR_RUNTIME_REQUIRED") {
          state = { status: "VALIDATOR_RUNTIME_REQUIRED", latest_run_id: curator.result.run_id };
        } else {
          return Response.json({ runtime: "input-governance-agent-v1", remediation_contract: "INPUT_GOV_SAFE_AUTOFIX_V1", trace, result: curator?.result ?? { status: "CURATOR_UNRESOLVED" } }, { status: 409 });
        }
      }

      if (state?.status === "VALIDATOR_RUNTIME_REQUIRED") {
        const runId = resolvedRunId(state);
        if (!runId) throw new Error("VALIDATOR_RUN_ID_UNRESOLVED");
        const validator = await callRuntime("input-governance-validator-v1", { run_id: runId });
        trace.push({ step: "VALIDATOR", cycle, status: validator?.result?.status, run_id: runId, identity: validator?.identity ?? null });
        if (!["COMPLETED", "NOOP_COMPLETED"].includes(validator?.result?.status)) {
          return Response.json({ runtime: "input-governance-agent-v1", remediation_contract: "INPUT_GOV_SAFE_AUTOFIX_V1", trace, result: validator?.result ?? { status: "VALIDATOR_UNRESOLVED" } }, { status: 409 });
        }

        const autofix = await rpc("fn_input_governance_safe_autofix_v1", { p_run_id: runId });
        trace.push({ step: "SAFE_AUTOFIX", cycle, run_id: runId, applied_count: autofix?.applied_count ?? 0, skipped_count: autofix?.skipped_count ?? 0, successor_required: autofix?.successor_required ?? false });
        if (autofix?.successor_required === true) continue;
      }

      const finalState = await rpc("fn_input_governance_execute", { p_pantalla_id: pantallaId, p_consumer: consumer });
      trace.push({ step: "DISPATCH_FINAL", cycle, status: finalState?.status, run_id: resolvedRunId(finalState) });
      lastState = finalState;
      if (["READY", "HUMAN_DECISION_REQUIRED", "BLOCKED"].includes(finalState?.status)) {
        return Response.json({ runtime: "input-governance-agent-v1", remediation_contract: "INPUT_GOV_SAFE_AUTOFIX_V1", trace, result: finalState });
      }
    }

    return Response.json({
      error: "INPUT_GOVERNANCE_REMEDIATION_CYCLE_LIMIT",
      remediation_contract: "INPUT_GOV_SAFE_AUTOFIX_V1",
      max_cycles: MAX_REMEDIATION_CYCLES,
      trace,
      result: lastState,
    }, { status: 409 });
  } catch (e) {
    return Response.json({ error: "INPUT_GOVERNANCE_ORCHESTRATION_FAILED", detail: e instanceof Error ? e.message : String(e) }, { status: 409 });
  }
});

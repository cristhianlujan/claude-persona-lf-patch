import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v5-service-role-controlled-protocol";

function responseHeaders(): HeadersInit {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
  const origin = Deno.env.get("LF_EDGE_ALLOWED_ORIGIN")?.trim();
  if (origin) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders() });
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let diff = a.length ^ b.length;
  const size = Math.max(a.length, b.length);
  for (let i = 0; i < size; i += 1) {
    diff |= (a[i % Math.max(a.length, 1)] ?? 0) ^ (b[i % Math.max(b.length, 1)] ?? 0);
  }
  return diff === 0;
}

function authorize(req: Request): Response | null {
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const match = (req.headers.get("authorization") ?? "").match(/^Bearer\s+(.+)$/i);
  const received = match?.[1]?.trim() ?? "";
  if (!expected) return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_SECRET_UNAVAILABLE" }, 500);
  if (!received || !constantTimeEqual(received, expected)) {
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "SERVICE_ROLE_REQUIRED" }, 403);
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...responseHeaders(),
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "METHOD_NOT_ALLOWED" }, 405);

  const authFailure = authorize(req);
  if (authFailure) return authFailure;

  return json({
    outcome: "CONTROLLED_PROTOCOL_AVAILABLE",
    endpoint_version: ENDPOINT_VERSION,
    protocol: {
      protocol_code: "PROTOCOLO_CREACION_PERFIL_LF_RUNTIME",
      protocol_version: "v1_1_controlled_sandbox",
      state: "READ_ONLY",
      runtime_status: "CONTROLLED_SANDBOX_ONLY",
      usable_for_runtime: false,
      usable_for_production: false,
      max_canonical_step: 7,
    },
    gates: {
      require_formulario_confirmado: true,
      writes_allowed: false,
      runtime_source: "Supabase",
      operation_code: "CREACION_PERFIL_LF",
      secure_redesign_pending: true,
      external_judge_pending: true,
    },
    data_accessed: false,
    next_gate: "DEFINE_GOVERNED_CALLER_AND_RUNTIME_EVIDENCE",
  });
});

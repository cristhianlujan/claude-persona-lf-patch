import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v15-quarantined-pending-secure-redesign";

function responseHeaders(): HeadersInit {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
  const allowedOrigin = Deno.env.get("LF_EDGE_ALLOWED_ORIGIN")?.trim();
  if (allowedOrigin) headers["Access-Control-Allow-Origin"] = allowedOrigin;
  return headers;
}

function jsonResponse(body: unknown, status: number): Response {
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

function requireServiceRole(req: Request): Response | null {
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (!expected) {
    return jsonResponse({
      outcome: "BLOCKED",
      endpoint_version: ENDPOINT_VERSION,
      code: "SERVICE_ROLE_SECRET_UNAVAILABLE",
    }, 500);
  }

  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  const received = match?.[1]?.trim() ?? "";
  if (!received || !constantTimeEqual(received, expected)) {
    return jsonResponse({
      outcome: "BLOCKED",
      endpoint_version: ENDPOINT_VERSION,
      code: "SERVICE_ROLE_REQUIRED",
    }, 403);
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

  if (req.method !== "POST") {
    return jsonResponse({
      outcome: "BLOCKED",
      endpoint_version: ENDPOINT_VERSION,
      code: "METHOD_NOT_ALLOWED",
    }, 405);
  }

  const authFailure = requireServiceRole(req);
  if (authFailure) return authFailure;

  return jsonResponse({
    outcome: "BLOCKED",
    endpoint_version: ENDPOINT_VERSION,
    code: "TEMPORARILY_DISABLED_PENDING_SECURE_REDESIGN",
    data_accessed: false,
    write_executed: false,
    next_gate: "DEFINE_GOVERNED_CALLER_AND_MINIMUM_DATA_CONTRACT",
  }, 503);
});

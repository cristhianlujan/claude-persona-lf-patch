import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v4-service-role-dry-run-only";
const MAX_BODY_BYTES = 64_000;

function headers(): HeadersInit {
  const value: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  };
  const origin = Deno.env.get("LF_EDGE_ALLOWED_ORIGIN")?.trim();
  if (origin) value["Access-Control-Allow-Origin"] = origin;
  return value;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: headers() });
}

function text(value: unknown): string {
  return String(value ?? "").trim();
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

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((value) => value.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...headers(),
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "METHOD_NOT_ALLOWED" }, 405);

  const authFailure = authorize(req);
  if (authFailure) return authFailure;

  const contentLength = Number(req.headers.get("content-length") ?? 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "BODY_TOO_LARGE" }, 413);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "INVALID_JSON" }, 400);
  }
  if (new TextEncoder().encode(JSON.stringify(payload)).byteLength > MAX_BODY_BYTES) {
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "BODY_TOO_LARGE" }, 413);
  }

  const required = ["mode", "packet_id", "candidate_transfer_key", "candidate_hash", "estado_recibido", "siguiente_gate"];
  const missing = required.filter((field) => !text(payload[field]));
  if (missing.length) {
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "PAYLOAD_INCOMPLETE", missing_fields: missing }, 400);
  }

  const violations: string[] = [];
  if (text(payload.mode).toUpperCase() !== "DRY_RUN") violations.push("ONLY_DRY_RUN_ALLOWED");
  if (!/^[a-f0-9]{64}$/i.test(text(payload.candidate_hash))) violations.push("CANDIDATE_HASH_INVALID");
  if (text(payload.estado_recibido) !== "CANDIDATO_NO_OFICIAL") violations.push("STATE_NOT_ALLOWED");
  if (text(payload.siguiente_gate) !== "FORMALIZACION_Y_JUEZ_EXTERNO") violations.push("NEXT_GATE_NOT_ALLOWED");
  if (violations.length) {
    return json({ outcome: "BLOCKED", endpoint_version: ENDPOINT_VERSION, code: "DRY_RUN_GATE_REJECTED", violations }, 400);
  }

  const fingerprint = await sha256Hex(JSON.stringify({
    packet_id: text(payload.packet_id),
    candidate_transfer_key: text(payload.candidate_transfer_key),
    candidate_hash: text(payload.candidate_hash),
    estado_recibido: text(payload.estado_recibido),
    siguiente_gate: text(payload.siguiente_gate),
  }));

  return json({
    outcome: "DRY_RUN_COMPLETED_WITH_EXPECTED_LIMITS",
    endpoint_version: ENDPOINT_VERSION,
    no_write_guarantee: true,
    database_accessed: false,
    packet_id: text(payload.packet_id),
    local_transfer_fingerprint: fingerprint,
    blockers: ["CONTROLLED_REGISTRY_NOT_ENABLED", "WRITES_DISABLED_BY_DESIGN"],
    runtime_status: "CONTROLLED_SANDBOX_ONLY",
    usable_for_production: false,
    next_required_gate: "EXTERNAL_JUDGE_AND_CONTROLLED_REGISTRY_DESIGN",
  });
});

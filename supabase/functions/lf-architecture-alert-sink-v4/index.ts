import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const ENDPOINT_VERSION = "v6-attempt-linked-hmac-no-downgrade";
const DELIVERY_SCHEMA_VERSION = "lf-architecture-alert-delivery/v6";
const AUTH_MODEL = "HMAC_SHA256_ATTEMPT_LINKED_V6_DATABASE_VERIFIED";
const MAX_BODY_BYTES = 256_000;
const UUID_V4_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const ALLOWED_KEYS = new Set([
  "delivery_schema_version",
  "attempt_id",
  "outbox_id",
  "alert_id",
  "payload_sha256",
  "payload",
  "signature",
  "signature_issued_at_unix",
  "signature_nonce",
  "secret_version",
]);

function responseHeaders(extra: Record<string, string> = {}): HeadersInit {
  return {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...extra,
  };
}

function json(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(extra),
  });
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function positiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function validateEnvelope(body: unknown): string | null {
  if (!isPlainObject(body)) return "ENVELOPE_NOT_OBJECT";

  for (const key of Object.keys(body)) {
    if (!ALLOWED_KEYS.has(key)) return "ENVELOPE_UNKNOWN_FIELD";
  }
  for (const key of ALLOWED_KEYS) {
    if (!(key in body)) return "ENVELOPE_FIELD_MISSING";
  }

  if (body.delivery_schema_version !== DELIVERY_SCHEMA_VERSION) return "SCHEMA_VERSION_REJECTED";
  if (!positiveSafeInteger(body.attempt_id)) return "ATTEMPT_ID_INVALID";
  if (!positiveSafeInteger(body.outbox_id)) return "OUTBOX_ID_INVALID";
  if (!positiveSafeInteger(body.alert_id)) return "ALERT_ID_INVALID";
  if (typeof body.payload_sha256 !== "string" || !SHA256_RE.test(body.payload_sha256)) return "PAYLOAD_SHA256_INVALID";
  if (!isPlainObject(body.payload)) return "PAYLOAD_INVALID";
  if (typeof body.signature !== "string" || !SHA256_RE.test(body.signature)) return "SIGNATURE_INVALID";
  if (!positiveSafeInteger(body.signature_issued_at_unix)) return "SIGNATURE_TIMESTAMP_INVALID";
  if (typeof body.signature_nonce !== "string" || !UUID_V4_RE.test(body.signature_nonce)) return "SIGNATURE_NONCE_INVALID";
  if (!positiveSafeInteger(body.secret_version) || body.secret_version > 32767) return "SECRET_VERSION_INVALID";

  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(
      { outcome: "BLOCKED", code: "METHOD_NOT_ALLOWED", endpoint_version: ENDPOINT_VERSION },
      405,
      { "Allow": "POST" },
    );
  }

  const contentType = (req.headers.get("content-type") ?? "").toLowerCase();
  if (!contentType.startsWith("application/json")) {
    return json(
      { outcome: "BLOCKED", code: "CONTENT_TYPE_REQUIRED", endpoint_version: ENDPOINT_VERSION },
      415,
    );
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return json(
      { outcome: "BLOCKED", code: "BODY_TOO_LARGE", endpoint_version: ENDPOINT_VERSION },
      413,
    );
  }

  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return json(
      { outcome: "BLOCKED", code: "BODY_READ_FAILED", endpoint_version: ENDPOINT_VERSION },
      400,
    );
  }

  if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
    return json(
      { outcome: "BLOCKED", code: "BODY_TOO_LARGE", endpoint_version: ENDPOINT_VERSION },
      413,
    );
  }

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json(
      { outcome: "BLOCKED", code: "INVALID_JSON", endpoint_version: ENDPOINT_VERSION },
      400,
    );
  }

  const validationError = validateEnvelope(body);
  if (validationError) {
    return json(
      { outcome: "BLOCKED", code: validationError, endpoint_version: ENDPOINT_VERSION },
      400,
    );
  }

  const envelope = body as Record<string, unknown>;
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    return json(
      { outcome: "BLOCKED", code: "INTERNAL_AUTH_CONFIGURATION_UNAVAILABLE", endpoint_version: ENDPOINT_VERSION },
      500,
    );
  }

  const executionId = `EDGE-HMAC-V6-${crypto.randomUUID()}`;
  const rpcBody = {
    p_delivery_schema_version: envelope.delivery_schema_version,
    p_attempt_id: envelope.attempt_id,
    p_outbox_id: envelope.outbox_id,
    p_payload_sha256: envelope.payload_sha256,
    p_payload: envelope.payload,
    p_signature: envelope.signature,
    p_signature_issued_at_unix: envelope.signature_issued_at_unix,
    p_signature_nonce: envelope.signature_nonce,
    p_secret_version: envelope.secret_version,
    p_details: {
      edge_function: "lf-architecture-alert-sink-v4",
      edge_version: ENDPOINT_VERSION,
      auth_model: AUTH_MODEL,
    },
    p_execution_id: executionId,
  };

  let rpcResponse: Response;
  try {
    rpcResponse = await fetch(
      `${supabaseUrl}/rest/v1/rpc/record_lf_alert_delivery_receipt_v6`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${serviceRoleKey}`,
          "apikey": serviceRoleKey,
          "Cache-Control": "no-store",
        },
        body: JSON.stringify(rpcBody),
        signal: AbortSignal.timeout(5_000),
      },
    );
  } catch {
    console.error(JSON.stringify({
      event: "HMAC_V6_RPC_TRANSPORT_FAILURE",
      endpoint_version: ENDPOINT_VERSION,
      execution_id: executionId,
    }));
    return json(
      { outcome: "BLOCKED", code: "INTERNAL_RECEIPT_SERVICE_UNAVAILABLE", endpoint_version: ENDPOINT_VERSION },
      503,
    );
  }

  if (!rpcResponse.ok) {
    console.warn(JSON.stringify({
      event: "HMAC_V6_RECEIPT_REJECTED",
      endpoint_version: ENDPOINT_VERSION,
      execution_id: executionId,
      rpc_status: rpcResponse.status,
    }));
    return json(
      { outcome: "BLOCKED", code: "HMAC_RECEIPT_REJECTED", endpoint_version: ENDPOINT_VERSION },
      409,
    );
  }

  let receiptId: number | null = null;
  try {
    const value = await rpcResponse.json();
    if (positiveSafeInteger(value)) receiptId = value;
  } catch {
    return json(
      { outcome: "BLOCKED", code: "INTERNAL_RECEIPT_RESPONSE_INVALID", endpoint_version: ENDPOINT_VERSION },
      502,
    );
  }

  if (receiptId === null) {
    return json(
      { outcome: "BLOCKED", code: "INTERNAL_RECEIPT_RESPONSE_INVALID", endpoint_version: ENDPOINT_VERSION },
      502,
    );
  }

  return json(
    {
      outcome: "RECEIVER_ACCEPTED",
      code: "HMAC_V6_ACCEPTED",
      endpoint_version: ENDPOINT_VERSION,
      receiver_response_status: 202,
      receipt_id: receiptId,
    },
    202,
  );
});

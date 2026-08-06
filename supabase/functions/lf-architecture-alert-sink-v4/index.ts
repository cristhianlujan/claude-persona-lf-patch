import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) throw new Error("Supabase runtime secrets are missing");

function response(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}
function isSha64(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}
function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((value) => value.toString(16).padStart(2, "0")).join("");
}
async function sha256(value: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
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
    const error = new Error(`RPC ${name} failed (${result.status}): ${text.slice(0, 800)}`);
    (error as Error & { rpcStatus?: number }).rpcStatus = result.status;
    throw error;
  }
  return (text ? JSON.parse(text) : null) as T;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return response({ code: "METHOD_NOT_ALLOWED" }, 405);
    const body = await req.json();
    const schema = body?.delivery_schema_version;
    if (schema !== "lf-architecture-alert-delivery/v4" && schema !== "lf-architecture-alert-delivery/v5") {
      return response({ code: "UNSUPPORTED_DELIVERY_SCHEMA" }, 400);
    }

    const outboxId = Number(body.outbox_id);
    const attemptId = schema === "lf-architecture-alert-delivery/v5" ? Number(body.attempt_id) : null;
    const payloadSha = body.payload_sha256;
    const signature = body.signature;
    if (
      !Number.isSafeInteger(outboxId) || outboxId <= 0 ||
      (schema === "lf-architecture-alert-delivery/v5" && (!Number.isSafeInteger(attemptId) || Number(attemptId) <= 0)) ||
      !isSha64(payloadSha) || !isSha64(signature)
    ) {
      return response({ code: "INVALID_DELIVERY_ENVELOPE" }, 400);
    }

    const ack: Record<string, unknown> = {
      accepted: true,
      outbox_id: outboxId,
      payload_sha256: payloadSha,
      receiver: "lf-architecture-alert-sink-v4",
      receiver_contract: schema === "lf-architecture-alert-delivery/v5" ? "attempt-linked-v5" : "legacy-v4",
      received_at: new Date().toISOString(),
    };
    if (attemptId !== null) ack.attempt_id = attemptId;
    const ackSha = await sha256(JSON.stringify(ack));

    const receiptId = schema === "lf-architecture-alert-delivery/v5"
      ? await rpc<number>("record_lf_alert_delivery_receipt_v5", {
          p_attempt_id: attemptId,
          p_outbox_id: outboxId,
          p_payload_sha256: payloadSha,
          p_signature: signature,
          p_http_status: 200,
          p_response_body_sha256: ackSha,
          p_details: ack,
          p_execution_id: `EDGE-ALERT-SINK-V5-${attemptId}`,
        })
      : await rpc<number>("record_lf_alert_delivery_receipt_v4", {
          p_outbox_id: outboxId,
          p_payload_sha256: payloadSha,
          p_signature: signature,
          p_http_status: 200,
          p_response_sha256: ackSha,
          p_details: ack,
          p_execution_id: `EDGE-ALERT-SINK-V4-${outboxId}`,
        });

    return response({ ...ack, receipt_id: receiptId, response_body_sha256: ackSha });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    if (/invalid alert delivery signature|attempt .*mismatch|outbox payload mismatch|replay mismatch/i.test(message)) {
      return response({ code: "HMAC_RECEIPT_REJECTED" }, 409);
    }
    return response({ code: "ALERT_SINK_INTERNAL_ERROR" }, 500);
  }
});

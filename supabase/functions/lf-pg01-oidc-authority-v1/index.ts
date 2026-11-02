// PG-01 H1-C2 Edge receiver: verify GitHub OIDC (signature + fixed policy) BEFORE any write,
// then record through public.lf_pg01_oidc_authority_record_v1 (service_role stays inside Edge).
// The database re-derives claims from the token itself and performs the PG-01 readback.
import { isKind, verifyPg01Token, type Kind } from "./auth.ts";

type Record3 = (kind: Kind, token: string, payload: Record<string, unknown>) => Promise<Response>;
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

export async function postgrestRecord(kind: Kind, token: string, payload: Record<string, unknown>): Promise<Response> {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw Error("RECORDER_UNAVAILABLE");
  return await fetch(`${url}/rest/v1/rpc/lf_pg01_oidc_authority_record_v1`, {
    method: "POST",
    headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ p_kind: kind, p_token: token, p_payload: payload }),
  });
}

export async function handle(req: Request, deps: { jwks?: Parameters<typeof verifyPg01Token>[3]; record?: Record3 } = {}): Promise<Response> {
  if (req.method !== "POST") return reply(405, { decision: "VERIFICATION_FAILED", reason: "METHOD_NOT_ALLOWED" });
  let identityVerified = false;
  try {
    const auth = req.headers.get("authorization") ?? "";
    if (!auth.startsWith("Bearer ")) throw Error("OIDC_BEARER_REQUIRED");
    const token = auth.slice(7);
    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) throw Error("PAYLOAD_INVALID");
    const kind = (body as Record<string, unknown>).kind;
    const payload = (body as Record<string, unknown>).payload as Record<string, unknown>;
    if (!isKind(kind)) throw Error("PAYLOAD_KIND_INVALID");
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw Error("PAYLOAD_INVALID");
    await verifyPg01Token(token, kind, payload, deps.jwks);
    identityVerified = true;
    const res = await (deps.record ?? postgrestRecord)(kind, token, payload);
    const text = await res.text();
    if (res.ok) return reply(200, { ...JSON.parse(text), authenticated_by: "GITHUB_OIDC" });
    const m = /PG01_[A-Z0-9_]+/.exec(text);
    if (/23505|duplicate key/.test(text)) return reply(409, { decision: "VERIFICATION_FAILED", reason: "RECEIPT_DUPLICATE" });
    if (m) return reply(422, { decision: "VERIFICATION_FAILED", reason: m[0] });
    return reply(503, { decision: "VERIFICATION_FAILED", reason: "RECEIPT_REGISTRATION_UNAVAILABLE" });
  } catch (e) {
    const reason = String((e as Error).message ?? "");
    if (e instanceof SyntaxError || /^PAYLOAD_/.test(reason)) return reply(422, { decision: "VERIFICATION_FAILED", reason });
    if (identityVerified) return reply(503, { decision: "VERIFICATION_FAILED", reason: "RECEIPT_REGISTRATION_UNAVAILABLE" });
    return reply(401, { decision: "VERIFICATION_FAILED", reason: "OIDC_IDENTITY_REJECTED", detail: reason.slice(0, 80) });
  }
}

if (import.meta.main) Deno.serve((req) => handle(req));

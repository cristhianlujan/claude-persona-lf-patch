import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@6.0.11";
import postgres from "npm:postgres@3.4.7";

const ISSUER = "https://token.actions.githubusercontent.com";
const AUDIENCE = "lf-runtime-readback";
const REPO = "cristhianlujan/claude-persona-lf-patch";
const REF = "refs/heads/main";
const WORKFLOW = REPO + "/.github/workflows/lf-runtime-independent-readback.yml@" + REF;
const JWKS = createRemoteJWKSet(new URL(ISSUER + "/.well-known/jwks"));
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
export type Claims = Record<string, unknown>;
const val = (x: unknown) => String(x ?? "");

export function requireObserverClaims(c: Claims, receipt: Record<string, unknown>): void {
  if (c.repository !== REPO || val(c.repository_id) !== "1244397752") throw Error("OIDC_REPOSITORY_MISMATCH");
  if (c.ref !== REF) throw Error("OIDC_REF_MISMATCH");
  if (c.workflow_ref !== WORKFLOW || c.job_workflow_ref !== WORKFLOW) throw Error("OIDC_WORKFLOW_REF_MISMATCH");
  if (c.event_name !== "workflow_dispatch") throw Error("OIDC_EVENT_MISMATCH");
  if (!/^[0-9]+$/.test(val(c.run_id)) || !/^[0-9]+$/.test(val(c.run_attempt))) throw Error("OIDC_RUN_INVALID");
  if (val(c.run_id) !== val(receipt.workflow_run_id) || val(c.run_attempt) !== val(receipt.workflow_run_attempt))
    throw Error("OIDC_RUN_BINDING_MISMATCH");
  if (!HEX40.test(val(receipt.exact_head)) || val(receipt.execution_id).length < 8) throw Error("RECEIPT_IDENTITY_INVALID");
  if (val(receipt.release_path) !== "/opt/lf-profile-runtime-api/releases/" + val(receipt.exact_head))
    throw Error("RELEASE_PATH_INVALID");
  if (receipt.source_sha !== receipt.exact_head || receipt.runtime_sha !== receipt.exact_head ||
      receipt.manifest_matches !== true || receipt.process_release_matches !== true ||
      receipt.health_ok !== true || receipt.files_verified !== true)
    throw Error("READBACK_NOT_VERIFIED");
  if (!HEX64.test(val(receipt.manifest_digest))) throw Error("MANIFEST_DIGEST_INVALID");
}
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: {"content-type":"application/json","cache-control":"no-store"} });

Deno.serve(async req => {
 if (req.method !== "POST") return reply(405,{decision:"VERIFICATION_FAILED",reason:"METHOD_NOT_ALLOWED"});
 try {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) throw Error("OIDC_BEARER_REQUIRED");
  const token = auth.slice(7);
  const { payload } = await jwtVerify(token,JWKS,{issuer:ISSUER,audience:AUDIENCE,algorithms:["RS256"],clockTolerance:"5s"});
  const receipt = await req.json();
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) throw Error("RECEIPT_INVALID");
  requireObserverClaims(payload as Claims,receipt);
  const db = Deno.env.get("LF_RUNTIME_READBACK_WRITER_DATABASE_URL");
  if (!db) throw Error("WRITER_DATABASE_URL_MISSING");
  const sql = postgres(db,{max:1,prepare:false,connect_timeout:8});
  try {
   const digest = await crypto.subtle.digest("SHA-256",new TextEncoder().encode(token));
   const tokenHash = Array.from(new Uint8Array(digest)).map(v=>v.toString(16).padStart(2,"0")).join("");
   // Only dedicated PostgreSQL role can INSERT; DB RLS and grants enforce this independently.
   const rows = await sql`insert into private.lf_runtime_readback_oidc_receipts
   (execution_id,exact_head,release_path,runtime_sha,manifest_digest,receipt,claims,
    authenticated_by,workflow_run_id,workflow_run_attempt,token_sha256)
   values (${val(receipt.execution_id)},${val(receipt.exact_head)},${val(receipt.release_path)},
    ${val(receipt.runtime_sha)},${val(receipt.manifest_digest)},
    ${sql.json(receipt)},${sql.json(payload)},'GITHUB_OIDC',
    ${val(payload.run_id)},${val(payload.run_attempt)},${tokenHash})
   returning receipt_id`;
   return reply(200,{decision:"VERIFICATION_VERIFIED",receipt_id:rows[0].receipt_id,authenticated_by:"GITHUB_OIDC"});
  } finally { await sql.end({timeout:1}); }
 } catch(e) {
  return reply(401,{decision:"VERIFICATION_FAILED",reason:String((e as Error).message).slice(0,130)});
 }
});

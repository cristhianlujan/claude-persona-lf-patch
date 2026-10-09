import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "npm:postgres@3.4.7";
import { verifyObserverToken } from "./auth.ts";
const val = (x: unknown) => String(x ?? "");
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: {"content-type":"application/json","cache-control":"no-store"} });

Deno.serve(async req => {
 if (req.method !== "POST") return reply(405,{decision:"VERIFICATION_FAILED",reason:"METHOD_NOT_ALLOWED"});
 try {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) throw Error("OIDC_BEARER_REQUIRED");
  const token = auth.slice(7);
  
  const receipt = await req.json();
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) throw Error("RECEIPT_INVALID");
  const payload = await verifyObserverToken(token,receipt);
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

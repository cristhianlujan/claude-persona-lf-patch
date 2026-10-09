import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "npm:jose@6.0.11";
export const ISSUER = "https://token.actions.githubusercontent.com";
export const AUDIENCE = "lf-runtime-readback";
export const REPO = "cristhianlujan/claude-persona-lf-patch";
export const REF = "refs/heads/main";
export const WORKFLOW = REPO + "/.github/workflows/lf-runtime-independent-readback.yml@" + REF;
export const CALLER_WORKFLOW = REPO + "/.github/workflows/lf-runtime-independent-readback-dispatch.yml@" + REF;
export const JWKS = createRemoteJWKSet(new URL(ISSUER + "/.well-known/jwks"));
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const val = (x: unknown) => String(x ?? "");

export function requireObserverClaims(c: JWTPayload, receipt: Record<string, unknown>): void {
  if (c.repository !== REPO || val(c.repository_id) !== "1244397752") throw Error("OIDC_REPOSITORY_MISMATCH");
  if (c.ref !== REF) throw Error("OIDC_REF_MISMATCH");
  if (c.workflow_ref !== CALLER_WORKFLOW || c.job_workflow_ref !== WORKFLOW) throw Error("OIDC_WORKFLOW_REF_MISMATCH");
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

export async function verifyObserverToken(token: string, receipt: Record<string, unknown>, jwks: Parameters<typeof jwtVerify>[1] = JWKS): Promise<JWTPayload> {
 const { payload } = await jwtVerify(token,jwks,{issuer:ISSUER,audience:AUDIENCE,algorithms:["RS256"],clockTolerance:"5s"});
 requireObserverClaims(payload,receipt);
 return payload;
}

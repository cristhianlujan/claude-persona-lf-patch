// PG-01 H1-C2: GitHub OIDC verification. Reuses issuer, repository and JWKS of the existing
// deploy-readback verifier; audiences, workflows and environments are PG-01-specific so a
// deploy-readback token can never authorize PG-01 (and vice versa).
import { jwtVerify, type JWTPayload } from "npm:jose@6.0.11";
import { ISSUER, REPO, JWKS } from "../lf-runtime-independent-readback-v1/auth.ts";

export { ISSUER, REPO };
export const REPO_ID = "1244397752";
export const REF = "refs/heads/main";
export type Kind = "SUBJECT_VERIFICATION" | "REVIEW_ATTESTATION";
const wf = (file: string) => `${REPO}/.github/workflows/${file}@${REF}`;
export const POLICY: Record<Kind, { audience: string; workflow: string; environment: string }> = {
  SUBJECT_VERIFICATION: { audience: "lf-pg01-subject-verification", workflow: wf("lf-pg01-oidc-subject-verifier.yml"), environment: "lf-pg01-verifier" },
  REVIEW_ATTESTATION:   { audience: "lf-pg01-review-attestation",   workflow: wf("lf-pg01-oidc-review-auditor.yml"),   environment: "lf-pg01-auditor" },
};
const HEX40 = /^[0-9a-f]{40}$/, HEX64 = /^[0-9a-f]{64}$/, UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const val = (x: unknown) => String(x ?? "");

export function isKind(k: unknown): k is Kind { return k === "SUBJECT_VERIFICATION" || k === "REVIEW_ATTESTATION"; }

export function requirePg01Claims(kind: Kind, c: JWTPayload, payload: Record<string, unknown> | null): void {
  const p = POLICY[kind];
  if (c.repository !== REPO || val(c.repository_id) !== REPO_ID) throw Error("OIDC_REPOSITORY_MISMATCH");
  if (c.ref !== REF) throw Error("OIDC_REF_MISMATCH");
  if (c.event_name !== "workflow_dispatch") throw Error("OIDC_EVENT_MISMATCH");
  if (c.workflow_ref !== p.workflow || c.job_workflow_ref !== p.workflow) throw Error("OIDC_WORKFLOW_REF_MISMATCH");
  if (c.environment !== p.environment) throw Error("OIDC_ENVIRONMENT_MISMATCH");
  if (!/^[0-9]+$/.test(val(c.run_id)) || !/^[0-9]+$/.test(val(c.run_attempt))) throw Error("OIDC_RUN_INVALID");
  if (payload === null) return; // offline re-verification of a stored receipt
  if (val(c.run_id) !== val(payload.workflow_run_id) || val(c.run_attempt) !== val(payload.workflow_run_attempt))
    throw Error("OIDC_RUN_BINDING_MISMATCH");
  if (kind === "SUBJECT_VERIFICATION") {
    if (!UUID.test(val(payload.receipt_id)) || !UUID.test(val(payload.context_id)) ||
        !HEX64.test(val(payload.subject_sha256)) || !HEX40.test(val(payload.source_head_sha)))
      throw Error("PAYLOAD_SUBJECT_INVALID");
    const gr = (payload.github_readback ?? {}) as Record<string, unknown>;
    if (gr.head_commit_verified !== true || gr.head_sha !== payload.source_head_sha) throw Error("PAYLOAD_GITHUB_READBACK_MISSING");
  } else {
    if (val(payload.judge_execution_id).length < 2 || !HEX64.test(val(payload.verifier_token_sha256)))
      throw Error("PAYLOAD_REVIEW_INVALID");
    if (payload.verifier_token_reverified !== true) throw Error("PAYLOAD_VERIFIER_TOKEN_NOT_REVERIFIED");
  }
}

type Keys = Parameters<typeof jwtVerify>[1];
export async function verifyPg01Token(token: string, kind: Kind, payload: Record<string, unknown> | null,
  jwks: Keys = JWKS, currentDate?: Date): Promise<JWTPayload> {
  const { payload: claims } = await jwtVerify(token, jwks, {
    issuer: ISSUER, audience: POLICY[kind].audience, algorithms: ["RS256"], clockTolerance: "5s",
    ...(currentDate ? { currentDate } : {}),
  });
  requirePg01Claims(kind, claims, payload);
  return claims;
}

export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((v) => v.toString(16).padStart(2, "0")).join("");
}

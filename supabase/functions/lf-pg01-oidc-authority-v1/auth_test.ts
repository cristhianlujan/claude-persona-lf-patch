// PG-01 H1-C2 OIDC boundary: SYNTHETIC tests (local RS256 key). They prove the verifier logic,
// not an authentic GitHub token. Authentic PASS requires a real workflow run (see runbook).
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "npm:jose@6.0.11";
import { ISSUER, POLICY, REF, REPO, REPO_ID, type Kind, verifyPg01Token } from "./auth.ts";
import { handle } from "./index.ts";

export async function testKeys(kid = "pg01-test") {
  const { privateKey, publicKey } = await generateKeyPair("RS256", { extractable: true });
  const jwk = { ...(await exportJWK(publicKey)), kid, alg: "RS256", use: "sig" };
  return { privateKey, jwk, jwks: createLocalJWKSet({ keys: [jwk] }) };
}
export function claimsFor(kind: Kind, run = "1001", over: Record<string, unknown> = {}) {
  const p = POLICY[kind];
  return { repository: REPO, repository_id: REPO_ID, ref: REF, event_name: "workflow_dispatch",
    workflow_ref: p.workflow, job_workflow_ref: p.workflow, environment: p.environment,
    run_id: run, run_attempt: "1", ...over };
}
export async function sign(privateKey: CryptoKey, claims: Record<string, unknown>, aud: string,
  o: { expired?: boolean; kid?: string; iss?: string } = {}) {
  return await new SignJWT(claims).setProtectedHeader({ alg: "RS256", kid: o.kid ?? "pg01-test" })
    .setIssuer(o.iss ?? ISSUER).setAudience(aud).setIssuedAt(o.expired ? Math.floor(Date.now() / 1000) - 900 : undefined)
    .setExpirationTime(o.expired ? Math.floor(Date.now() / 1000) - 600 : "5m").sign(privateKey);
}
export const subjectPayload = (run = "1001", over: Record<string, unknown> = {}) => ({
  workflow_run_id: run, workflow_run_attempt: "1", receipt_id: "11111111-0000-4000-8000-000000000001",
  context_id: "aaaaaaaa-0000-4000-8000-000000000001", subject_sha256: "a".repeat(64), source_head_sha: "1".repeat(40),
  github_readback: { head_commit_verified: true, head_sha: "1".repeat(40) }, ...over });
export const reviewPayload = (run = "2001", over: Record<string, unknown> = {}) => ({
  workflow_run_id: run, workflow_run_attempt: "1", judge_execution_id: "J1",
  verifier_token_sha256: "b".repeat(64), verifier_token_reverified: true, ...over });

Deno.test("PG-01 OIDC boundary matrix (synthetic)", async () => {
  const k = await testKeys(), other = await testKeys(), S = "SUBJECT_VERIFICATION" as Kind, R = "REVIEW_ATTESTATION" as Kind;
  const A = POLICY[S].audience, AR = POLICY[R].audience;
  const cases: Array<[string, Promise<string>, Kind, Record<string, unknown>, string]> = [
    ["forged_signature_other_key", sign(other.privateKey, claimsFor(S), A), S, subjectPayload(), "signature"],
    ["unknown_kid", sign(k.privateKey, claimsFor(S), A, { kid: "nope" }), S, subjectPayload(), "JWKSNoMatchingKey"],
    ["expired", sign(k.privateKey, claimsFor(S), A, { expired: true }), S, subjectPayload(), "exp"],
    ["wrong_issuer", sign(k.privateKey, claimsFor(S), A, { iss: "https://evil.example" }), S, subjectPayload(), "iss"],
    ["deploy_readback_audience", sign(k.privateKey, claimsFor(S), "lf-runtime-readback"), S, subjectPayload(), "aud"],
    ["review_audience_on_subject", sign(k.privateKey, claimsFor(S), AR), S, subjectPayload(), "aud"],
    ["other_repository", sign(k.privateKey, claimsFor(S, "1001", { repository: "evil/repo" }), A), S, subjectPayload(), "OIDC_REPOSITORY_MISMATCH"],
    ["other_repository_id", sign(k.privateKey, claimsFor(S, "1001", { repository_id: "1" }), A), S, subjectPayload(), "OIDC_REPOSITORY_MISMATCH"],
    ["other_branch", sign(k.privateKey, claimsFor(S, "1001", { ref: "refs/heads/feature" }), A), S, subjectPayload(), "OIDC_REF_MISMATCH"],
    ["pull_request_event", sign(k.privateKey, claimsFor(S, "1001", { event_name: "pull_request" }), A), S, subjectPayload(), "OIDC_EVENT_MISMATCH"],
    ["deploy_workflow", sign(k.privateKey, claimsFor(S, "1001", { job_workflow_ref: REPO + "/.github/workflows/lf-runtime-independent-readback.yml@" + REF }), A), S, subjectPayload(), "OIDC_WORKFLOW_REF_MISMATCH"],
    ["auditor_workflow_as_verifier", sign(k.privateKey, claimsFor(S, "1001", { workflow_ref: POLICY[R].workflow, job_workflow_ref: POLICY[R].workflow }), A), S, subjectPayload(), "OIDC_WORKFLOW_REF_MISMATCH"],
    ["verifier_workflow_as_auditor", sign(k.privateKey, claimsFor(R, "2001", { workflow_ref: POLICY[S].workflow, job_workflow_ref: POLICY[S].workflow }), AR), R, reviewPayload(), "OIDC_WORKFLOW_REF_MISMATCH"],
    ["wrong_environment", sign(k.privateKey, claimsFor(R, "2001", { environment: "lf-pg01-verifier" }), AR), R, reviewPayload(), "OIDC_ENVIRONMENT_MISMATCH"],
    ["run_invalid", sign(k.privateKey, claimsFor(S, "x1"), A), S, subjectPayload("x1"), "OIDC_RUN_INVALID"],
    ["run_binding_other_run", sign(k.privateKey, claimsFor(S, "1001"), A), S, subjectPayload("9999"), "OIDC_RUN_BINDING_MISMATCH"],
    ["no_github_readback", sign(k.privateKey, claimsFor(S), A), S, subjectPayload("1001", { github_readback: undefined }), "PAYLOAD_GITHUB_READBACK_MISSING"],
    ["readback_other_head", sign(k.privateKey, claimsFor(S), A), S, subjectPayload("1001", { github_readback: { head_commit_verified: true, head_sha: "2".repeat(40) } }), "PAYLOAD_GITHUB_READBACK_MISSING"],
    ["declared_verified_only", sign(k.privateKey, claimsFor(S), A), S, { workflow_run_id: "1001", workflow_run_attempt: "1", verification_state: "VERIFIED" }, "PAYLOAD_SUBJECT_INVALID"],
    ["auditor_without_reverify", sign(k.privateKey, claimsFor(R, "2001"), AR), R, reviewPayload("2001", { verifier_token_reverified: false }), "PAYLOAD_VERIFIER_TOKEN_NOT_REVERIFIED"],
  ];
  const failures: string[] = [];
  for (const [name, tok, kind, payload, expect] of cases) {
    let got = "ACCEPTED";
    try { await verifyPg01Token(await tok, kind, payload, k.jwks); } catch (e) { got = `${(e as Error).name}:${(e as Error).message}:${(e as { code?: string }).code ?? ""}:${(e as { claim?: string }).claim ?? ""}`; }
    if (!got.includes(expect)) failures.push(`${name} expected ${expect} got ${got}`);
  }
  for (const [kind, run, payload] of [[S, "1001", subjectPayload()], [R, "2001", reviewPayload()]] as Array<[Kind, string, Record<string, unknown>]>) {
    await verifyPg01Token(await sign(k.privateKey, claimsFor(kind, run), POLICY[kind].audience), kind, payload, k.jwks);
  }
  if (failures.length) throw Error(failures.join("\n"));
  console.log(`PG01_OIDC_BOUNDARY_SYNTHETIC_PASSED:${cases.length + 2}`);
});

Deno.test("PG-01 OIDC handler never records an unauthenticated request (synthetic)", async () => {
  const k = await testKeys(), other = await testKeys(); let calls = 0;
  const record = async () => { calls++; return new Response('{"decision":"VERIFIED_RECORDED"}', { status: 200 }); };
  const post = (tok: string | null, body: unknown) => handle(new Request("http://x", { method: "POST",
    headers: tok ? { authorization: `Bearer ${tok}` } : {}, body: JSON.stringify(body) }), { jwks: k.jwks, record });
  const S = "SUBJECT_VERIFICATION" as Kind;
  const r1 = await post(null, { kind: S, payload: subjectPayload() });
  const r2 = await post(await sign(other.privateKey, claimsFor(S), POLICY[S].audience), { kind: S, payload: subjectPayload() });
  const r3 = await post(await sign(k.privateKey, claimsFor(S), POLICY[S].audience), { kind: "ADMIN", payload: subjectPayload() });
  const r4 = await handle(new Request("http://x", { method: "GET" }), { jwks: k.jwks, record });
  if (r1.status !== 401 || r2.status !== 401 || r3.status !== 422 || r4.status !== 405 || calls !== 0)
    throw Error(`unexpected ${r1.status} ${r2.status} ${r3.status} ${r4.status} calls=${calls}`);
  const ok = await post(await sign(k.privateKey, claimsFor(S), POLICY[S].audience), { kind: S, payload: subjectPayload() });
  if (ok.status !== 200 || calls !== 1) throw Error(`positive ${ok.status} calls=${calls}`);
  console.log("PG01_OIDC_HANDLER_SYNTHETIC_PASSED:5");
});

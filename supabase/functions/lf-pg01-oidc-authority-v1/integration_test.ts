// PG-01 H1-C2 INTEGRATION tests: Edge handler -> public RPC -> disposable PostgreSQL (Supabase-shaped).
// Tokens are signed by a local key pinned as a TEST fixture (not GitHub's key): integration PASS, not authentic PASS.
// Driven by sandbox/.../run_pg01_oidc_authority_v1.sh (env PG01_IT_*). Never point it at a hosted DB.
import { type Kind, POLICY } from "./auth.ts";
import { handle } from "./index.ts";
import { claimsFor, githubShape, reviewPayload, sign, subjectPayload, testKeys } from "./auth_test.ts";
import { reverify } from "../../../scripts/lf_pg01_oidc_receipt_reverify.ts";

const E = (k: string) => Deno.env.get(k) ?? "";
const enabled = E("PG01_IT_PORT") !== "";
async function psql(user: string, pw: string, sql: string, host = E("PG01_IT_HOST")): Promise<{ ok: boolean; out: string }> {
  const p = new Deno.Command(E("PG01_IT_PSQL"), { args: ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-h", host, "-p", E("PG01_IT_PORT"), "-U", user, "-d", "postgres"],
    env: { PGPASSWORD: pw }, stdin: "piped", stdout: "piped", stderr: "piped" }).spawn();
  const w = p.stdin.getWriter(); await w.write(new TextEncoder().encode(sql)); await w.close();
  const o = await p.output(); const d = new TextDecoder();
  return { ok: o.success, out: (d.decode(o.stdout) + d.decode(o.stderr)).trim() };
}
const asService = (sql: string) => psql("authenticator", E("PG01_IT_AUTH_PW"), "SET ROLE service_role;\n" + sql);
const su = (sql: string) => psql(E("PG01_IT_SU"), "", sql, E("PG01_IT_SU_HOST"));
const rpcSql = (kind: string, tok: string, payload: unknown) =>
  `SELECT public.lf_pg01_oidc_authority_record_v1($q$${kind}$q$,$q$${tok}$q$,$q$${JSON.stringify(payload)}$q$::jsonb);`;
const record = async (kind: Kind, token: string, payload: Record<string, unknown>) => {
  const r = await asService(rpcSql(kind, token, payload));
  return new Response(r.ok ? r.out : r.out, { status: r.ok ? 200 : 500 });
};

Deno.test({ name: "PG-01 OIDC integration RED/GREEN (Edge -> RPC -> PostgreSQL)", ignore: !enabled, fn: async () => {
  const k = await testKeys(), attacker = await testKeys(); // attacker key reuses the same kid: forged signature
  const S = "SUBJECT_VERIFICATION" as Kind, R = "REVIEW_ATTESTATION" as Kind;
  const ctx1 = E("PG01_IT_CTX1_SHA"), ctx2 = E("PG01_IT_CTX2_SHA"), ctx3 = E("PG01_IT_CTX3_SHA");
  const res: Array<[string, boolean, string]> = [];
  // Simulates the governed key-pin migration: only the table owner (Train) can write pinned keys.
  const pin = (jwk: Record<string, unknown>) => `INSERT INTO private.lf_pg01_oidc_jwks_v1(kid,kty,n,e,issuer,source_ref)
    VALUES('${jwk.kid}','RSA',private.fn_lf_pg01_b64url_v1('${jwk.n}'),private.fn_lf_pg01_b64url_v1('${jwk.e}'),
    'https://token.actions.githubusercontent.com','TEST_FIXTURE_NOT_GITHUB');`;
  const viaEdge = async (tok: string, kind: Kind, payload: Record<string, unknown>) => {
    const r = await handle(new Request("http://edge", { method: "POST", headers: { authorization: `Bearer ${tok}` },
      body: JSON.stringify({ kind, payload }) }), { jwks: k.jwks, record });
    return `${r.status}:${await r.text()}`;
  };
  const check = (name: string, got: string, re: RegExp) => res.push([name, re.test(got), got.slice(0, 220)]);
  const sTok = (run: string, over: Record<string, unknown> = {}, key = k.privateKey, o = {}) => sign(key, claimsFor(S, run, over), POLICY[S].audience, o);
  const rTok = (run: string, over: Record<string, unknown> = {}, key = k.privateKey, o = {}) => sign(key, claimsFor(R, run, over), POLICY[R].audience, o);
  const subj = (run: string, rid: string, cid: string, sha: string, head = "1".repeat(40)) => subjectPayload(run,
    { receipt_id: rid, context_id: cid, subject_sha256: sha, source_head_sha: head, github_readback: { head_commit_verified: true, head_sha: head } });
  const R1 = "11111111-0000-4000-8000-000000000001", C1 = "aaaaaaaa-0000-4000-8000-000000000001", C2 = "aaaaaaaa-0000-4000-8000-000000000002";

  // ---- RED before any key is pinned: everything fails closed in the DB, even with a valid signature
  check("N_db_no_pinned_key_fail_closed", (await asService(rpcSql(S, await sTok("1000"), subj("1000", R1, C1, ctx1)))).out, /PG01_OIDC_KID_NOT_PINNED/);
  check("N_service_role_cannot_pin_key", (await asService(pin(k.jwk))).out, /permission denied/);
  check("PIN_test_key_by_owner", (await su(pin(k.jwk))).out, /^$/);

  // ---- RED: subject verification
  check("N_subject_hash_altered_ledger", await viaEdge(await sTok("1101"), S, subj("1101", "11111111-0000-4000-8000-000000000003", C1, ctx1)), /^422:.*PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH/);
  check("N_context_swapped", await viaEdge(await sTok("1102"), S, subj("1102", "11111111-0000-4000-8000-000000000007", C1, ctx1)), /^422:.*PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH/);
  check("N_payload_hash_not_readback", await viaEdge(await sTok("1103"), S, subj("1103", "11111111-0000-4000-8000-000000000007", C2, "c".repeat(64))), /^422:.*PG01_OIDC_PAYLOAD_READBACK_MISMATCH/);
  check("N_payload_head_not_readback", await viaEdge(await sTok("1104"), S, subj("1104", "11111111-0000-4000-8000-000000000007", C2, ctx2, "2".repeat(40))), /^422:.*PG01_OIDC_PAYLOAD_READBACK_MISMATCH/);
  check("N_ledger_head_invalid", await viaEdge(await sTok("1105"), S, subj("1105", "11111111-0000-4000-8000-000000000004", C1, ctx1)), /^422:.*PG01_SUBJECT_VERIFY_HEAD_INVALID/);
  check("N_receipt_missing", await viaEdge(await sTok("1106"), S, subj("1106", "11111111-0000-4000-8000-0000000000ff", C1, ctx1)), /^422:.*PG01_SUBJECT_VERIFY_RECEIPT_MISSING/);
  check("N_anchored_by_producer", await viaEdge(await sTok("1107"), S, subj("1107", "11111111-0000-4000-8000-000000000005", C1, ctx1)), /^422:.*PG01_SUBJECT_VERIFY_ANCHORED_BY_PRODUCER/);
  check("N_producer_run_self_verification", await viaEdge(await sTok("1077"), S, subj("1077", "11111111-0000-4000-8000-000000000006", "aaaaaaaa-0000-4000-8000-000000000003", ctx3)), /^422:.*PG01_OIDC_PRODUCER_SELF_VERIFICATION/);
  check("N_edge_forged_signature", await viaEdge(await sTok("1108", {}, attacker.privateKey), S, subj("1108", R1, C1, ctx1)), /^401:.*OIDC_IDENTITY_REJECTED/);
  check("N_edge_expired", await viaEdge(await sTok("1109", {}, k.privateKey, { expired: true }), S, subj("1109", R1, C1, ctx1)), /^401:/);
  check("N_rollback_left_no_receipts", (await su("SELECT count(*) FROM private.lf_pg01_oidc_authority_receipts_v1")).out, /^0$/);

  // ---- GREEN 1: verifier identity (workflow + environment lf-pg01-verifier)
  // Positives use the authentic GitHub claim shape (job_workflow_ref == workflow_ref).
  const vTok = await sign(k.privateKey, githubShape(S, "1001"), POLICY[S].audience);
  check("G1_subject_verified", await viaEdge(vTok, S, subj("1001", R1, C1, ctx1)), /^200:.*VERIFIED_RECORDED.*lf-pg01-oidc-subject-verifier\.yml/);
  check("N_replay_same_token", await viaEdge(vTok, S, subj("1001", R1, C1, ctx1)), /^409:/);
  check("N_replay_new_run_same_receipt", await viaEdge(await sTok("1002"), S, subj("1002", R1, C1, ctx1)), /^409:/);
  check("G1_readback", (await su(`SELECT session_principal||'|'||authority_role||'|'||observed_subject_sha256 FROM private.lf_pg01_subject_verifications_v1 WHERE receipt_id='${R1}'`)).out,
    new RegExp(`^GITHUB_OIDC:.*lf-pg01-oidc-subject-verifier\\.yml@refs/heads/main#environment=lf-pg01-verifier\\|GITHUB_OIDC_SUBJECT_VERIFIER\\|${ctx1}$`));
  const vRun = "1001";
  const rb = (run: string, over: Record<string, unknown> = {}) => ({ workflow_path: ".github/workflows/lf-pg01-oidc-subject-verifier.yml", conclusion: "success", head_branch: "main", run_id: run, ...over });
  const rev = (run: string, over: Record<string, unknown> = {}) => reviewPayload(run, { verifier_run_id: vRun, verifier_run_readback: rb(vRun), ...over });

  // ---- RED: review attestation / independence
  check("N_edge_auditor_names_own_run", await viaEdge(await rTok("1001"), R, rev("1001", { verifier_run_id: "1001", verifier_run_readback: rb("1001") })), /^422:.*PAYLOAD_SAME_RUN_NOT_INDEPENDENT/);
  check("N_rpc_auditor_names_own_run", (await asService(rpcSql(R, await rTok("2014"), rev("2014", { verifier_run_id: "2014", verifier_run_readback: rb("2014") })))).out, /PG01_OIDC_SAME_RUN_NOT_INDEPENDENT/);
  check("N_rpc_one_run_two_identities", (await asService(rpcSql(R, await rTok("1001"), rev("1001", { verifier_run_id: "1000", verifier_run_readback: rb("1000") })))).out, /PG01_OIDC_VERIFIER_RECEIPT_MISMATCH|duplicate key/);
  check("N_review_wrong_verifier_run", await viaEdge(await rTok("2002"), R, rev("2002", { verifier_run_id: "1999", verifier_run_readback: rb("1999") })), /^422:.*PG01_OIDC_VERIFIER_RECEIPT_MISMATCH/);
  check("N_rpc_review_declared_hash_flag_only", (await asService(rpcSql(R, await rTok("2015"), { workflow_run_id: "2015", workflow_run_attempt: "1", judge_execution_id: "J1", verifier_token_sha256: "b".repeat(64), verifier_token_reverified: true }))).out, /PG01_OIDC_REVIEW_PAYLOAD_INVALID/);
  check("N_rpc_review_without_run_readback", (await asService(rpcSql(R, await rTok("2016"), rev("2016", { verifier_run_readback: rb(vRun, { conclusion: "failure" }) })))).out, /PG01_OIDC_VERIFIER_RUN_READBACK_MISSING/);
  check("N_review_judge_not_completed", await viaEdge(await rTok("2003"), R, rev("2003", { judge_execution_id: "J2" })), /^422:.*PG01_REVIEW_ATTEST_JUDGE_INVALID/);
  check("N_review_judge_head_altered", await viaEdge(await rTok("2004"), R, rev("2004", { judge_execution_id: "J4" })), /^422:.*PG01_REVIEW_ATTEST_SUBJECT_NOT_VERIFIED/);
  check("N_rpc_bypass_verifier_identity_as_auditor", (await asService(rpcSql(R, await sign(k.privateKey, claimsFor(R, "2005", { workflow_ref: POLICY[S].workflow, job_workflow_ref: POLICY[S].workflow, environment: "lf-pg01-verifier" }), POLICY[R].audience), rev("2005")))).out, /PG01_OIDC_WORKFLOW_MISMATCH/);
  check("N_rpc_bypass_verifier_audience_on_review", (await asService(rpcSql(R, await sign(k.privateKey, claimsFor(R, "2006"), POLICY[S].audience), rev("2006")))).out, /PG01_OIDC_AUDIENCE_MISMATCH/);
  check("N_rpc_bypass_expired", (await asService(rpcSql(R, await rTok("2007", {}, k.privateKey, { expired: true }), rev("2007")))).out, /PG01_OIDC_TOKEN_EXPIRED/);
  check("N_rpc_reusable_job_workflow_ref", (await asService(rpcSql(R, await rTok("2022", { job_workflow_ref: "cristhianlujan/claude-persona-lf-patch/.github/workflows/some-reusable.yml@refs/heads/main" }), rev("2022")))).out, /PG01_OIDC_WORKFLOW_MISMATCH/);
  check("N_rpc_bypass_unpinned_kid", (await asService(rpcSql(R, await rTok("2017", {}, k.privateKey, { kid: "not-pinned" }), rev("2017")))).out, /PG01_OIDC_KID_NOT_PINNED/);
  check("N_rpc_bypass_other_repo", (await asService(rpcSql(S, await sTok("2008", { repository: "evil/repo" }), subj("2008", R1, C1, ctx1)))).out, /PG01_OIDC_REPOSITORY_MISMATCH/);
  check("N_rpc_bypass_other_branch", (await asService(rpcSql(S, await sTok("2009", { ref: "refs/heads/x" }), subj("2009", R1, C1, ctx1)))).out, /PG01_OIDC_REF_MISMATCH/);
  check("N_rpc_bypass_run_binding", (await asService(rpcSql(S, await sTok("2010"), subj("2999", R1, C1, ctx1)))).out, /PG01_OIDC_RUN_BINDING_MISMATCH/);
  check("N_rpc_malformed_token", (await asService(rpcSql(S, "not.a.jwt$", subj("2011", R1, C1, ctx1)))).out, /PG01_OIDC_TOKEN_MALFORMED/);
  check("N_rpc_forged_signature_subject", (await asService(rpcSql(S, await sTok("2018", {}, attacker.privateKey), subj("2018", "11111111-0000-4000-8000-000000000007", C2, ctx2)))).out, /PG01_OIDC_SIGNATURE_INVALID/);
  check("N_rpc_truncated_signature", (await asService(rpcSql(S, (await sTok("2019")).slice(0, -10), subj("2019", "11111111-0000-4000-8000-000000000007", C2, ctx2)))).out, /PG01_OIDC_SIGNATURE_INVALID/);
  check("N_rpc_payload_swapped_after_signing", (await asService(rpcSql(S, (await sTok("2020")).replace(/^([^.]+)\.([^.]+)\./, (_m, h) => h + "." + btoa(JSON.stringify(claimsFor(S, "2021"))).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_") + "."), subj("2021", "11111111-0000-4000-8000-000000000007", C2, ctx2)))).out, /PG01_OIDC_SIGNATURE_INVALID/);
  check("N_rpc_declared_verified_payload", (await asService(rpcSql(S, await sTok("2012"), { workflow_run_id: "2012", workflow_run_attempt: "1", verification_state: "VERIFIED" }))).out, /PG01_OIDC_SUBJECT_PAYLOAD_INVALID/);

  // ---- service_role cannot bypass the recorder
  check("N_service_role_insert_verification", (await asService(`INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('${R1}','${C1}');`)).out, /permission denied/);
  check("N_service_role_insert_attestation", (await asService(`INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J1');`)).out, /permission denied/);
  check("N_service_role_insert_oidc_receipt", (await asService(`INSERT INTO private.lf_pg01_oidc_authority_receipts_v1(kind,subject_key,token,token_sha256,claims,principal,workflow_run_id,workflow_run_attempt,payload) VALUES('REVIEW_ATTESTATION','J1','x','${"e".repeat(64)}','{}','x','9','1','{}');`)).out, /permission denied/);
  check("N_service_role_call_core", (await asService(`SELECT private.fn_lf_pg01_oidc_record_core_v1('SUBJECT_VERIFICATION','a.b.c','{}');`)).out, /permission denied/);

  // ---- GREEN 2: auditor identity (different workflow + environment lf-pg01-auditor)
  const aTok = await sign(k.privateKey, githubShape(R, "2001"), POLICY[R].audience);
  check("G2_review_attested", await viaEdge(aTok, R, rev("2001")), /^200:.*ATTESTED_RECORDED.*lf-pg01-oidc-review-auditor\.yml.*LF_PG_RS256_V1/);
  check("N_replay_review_new_run", await viaEdge(await rTok("2013"), R, rev("2013")), /^409:/);
  check("N_replay_review_same_token", await viaEdge(aTok, R, rev("2001")), /^409:/);
  check("G2_readback_three_parties", (await su(`SELECT producer_execution_id||'|'||(verifier_session_principal<>session_principal)::text||'|'||authority_role||'|'||(manifest_sha256=private.fn_lf_pg01_judge_digest_v1('J1')->>'manifest_sha256')::text FROM private.lf_pg01_review_attestations_v1 WHERE judge_execution_id='J1'`)).out,
    /^PROFILE\|true\|GITHUB_OIDC_REVIEW_AUDITOR\|true$/);

  // ---- service_role forging executions/steps
  await asService(`INSERT INTO public.lf_operation_execution SELECT 'J-FAKE',operation_code,status,manifest||jsonb_build_object('subject_receipt_id','11111111-0000-4000-8000-000000000007','subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/${C2}','subject_sha256','${ctx2}'),'FORGED' FROM public.lf_operation_execution WHERE execution_id='J1';
   INSERT INTO public.lf_operation_execution_steps VALUES('J-FAKE','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','FORGED');`);
  check("N_forged_judge_via_edge_fake_auditor", await viaEdge(await rTok("3001", {}, attacker.privateKey), R, rev("3001", { judge_execution_id: "J-FAKE" })), /^401:/);
  check("N_forged_judge_rpc_fake_auditor", (await asService(rpcSql(R, await rTok("3003", {}, attacker.privateKey), rev("3003", { judge_execution_id: "J-FAKE" })))).out, /PG01_OIDC_SIGNATURE_INVALID/);
  check("N_auditor_without_crypto_verified_verifier", (await asService(rpcSql(R, await rTok("3002"), rev("3002", { judge_execution_id: "J-FAKE" })))).out, /PG01_OIDC_VERIFIER_RECEIPT_MISMATCH/);
  await asService(`UPDATE public.lf_operation_execution_steps SET evidence_payload='{"verdict":"PASS","tampered":1}' WHERE execution_id='J1' AND step_id='semantic_review';`);
  check("N_post_attest_step_tamper_detected", (await su(`SELECT (steps_sha256=private.fn_lf_pg01_judge_digest_v1('J1')->>'steps_sha256')::text FROM private.lf_pg01_review_attestations_v1 WHERE judge_execution_id='J1'`)).out, /^false$/);

  // ---- Former RESIDUAL now BLOCKED: forged signatures cannot be recorded by any caller
  const fv = await sTok("4001", {}, attacker.privateKey);
  check("N_rpc_fake_signature_subject_blocked", (await asService(rpcSql(S, fv, subj("4001", "11111111-0000-4000-8000-000000000007", C2, ctx2)))).out, /PG01_OIDC_SIGNATURE_INVALID/);
  check("N_superuser_direct_insert_forged_receipt_blocked", (await su(`INSERT INTO private.lf_pg01_oidc_authority_receipts_v1(kind,subject_key,token,token_sha256,claims,principal,workflow_run_id,workflow_run_attempt,payload,signature_kid,signature_verifier) VALUES('SUBJECT_VERIFICATION','x','${fv}','${"0".repeat(64)}','{}','GITHUB_OIDC:x','4001','1','{}','pg01-test','LF_PG_RS256_V1');`)).out, /PG01_OIDC_SIGNATURE_INVALID/);
  check("N_forged_paths_left_no_authority", (await su(`SELECT (SELECT count(*) FROM private.lf_pg01_subject_verifications_v1)||'/'||(SELECT count(*) FROM private.lf_pg01_review_attestations_v1)||'/'||(SELECT count(*) FROM private.lf_pg01_oidc_authority_receipts_v1)||'/'||(SELECT count(*) FROM private.lf_pg01_oidc_authority_receipts_v1 WHERE signature_verifier<>'LF_PG_RS256_V1')`)).out, /^1\/1\/2\/0$/);

  // ---- Offline re-verification of the DB readback (what a consumer gate must run)
  const rbq = await su(`SELECT json_agg(json_build_object('kind',kind,'token',token,'token_sha256',token_sha256,'run',workflow_run_id) ORDER BY oidc_receipt_id) FROM private.lf_pg01_oidc_authority_receipts_v1`);
  check("READBACK_receipts_readable", rbq.out, /^\[/);
  const rows = rbq.ok && rbq.out.startsWith("[") ? JSON.parse(rbq.out) : [];
  const rv = await reverify(rows, k.jwks);
  const byRun = Object.fromEntries(rows.map((r: Record<string, unknown>, i: number) => [r.run, rv.results[i]?.reverified]));
  check("REVERIFY_genuine_receipts_pass", `${byRun["1001"]}/${byRun["2001"]}`, /^true\/true$/);
  check("REVERIFY_all_stored_receipts_genuine", `${rows.length}/${rv.all_reverified}`, /^2\/true$/);
  check("N_receipts_append_only", (await su(`UPDATE private.lf_pg01_oidc_authority_receipts_v1 SET principal='x';`)).out, /PG01_ATTESTATION_APPEND_ONLY/);

  const bad = res.filter((r) => !r[1]);
  for (const r of res) console.log(`${r[1] ? "PASS" : "FAIL"} ${r[0]}${r[1] ? "" : " :: " + r[2]}`);
  if (bad.length) throw Error(`PG01_OIDC_INTEGRATION_FAILED:${bad.length}`);
  console.log(`PG01_OIDC_INTEGRATION_PASSED:${res.length}`);
} });

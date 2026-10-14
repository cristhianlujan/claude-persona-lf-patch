-- IG M10.5 CP2 only. Append-only EKB; no release, Edge deployment or checkpoint transition.
WITH findings(codigo,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia) AS (
 VALUES
 (
 'IG-M105-CP2-OIDC-BRIDGE-MISSING-010',
 'OIDC caller identity existed, but no M10.5 CP2 action forwarded to genuine Edge',
 '2026-10-14: Existing lf-profiles-governance-caller-v1 verified exact GitHub OIDC, but its accepted Input Governance actions operated DIRECT_SQL_PERSISTED_QUEUE_V1; CP2 RUN_TEST producer could not get authenticated service-role transport.',
 'OIDC trust and service-role proxy were reused only for SQL recuration, not Edge post-cutover cohort runs, and the current identity action allowlist denied the CP2 scope.',
 'Reuse the same exact dispatch workflow OIDC claims and protected service-role Edge caller; add isolated actions ig_m105_cp2_edge_preflight_v1 and ig_m105_cp2_edge_screen_v1, require canonical dispatch_context gate before Edge, frozen 13-screen membership, signed per-run receipt plus canonical readback; no new secret, no new login or production activation.',
 'PR #2561 merged via Train; Deno CP2 positive/negative test CI PASS, workflow F0 PASS, GitHub OIDC preflight run 38501386804 proves current deployed caller still rejects action until separately deployed.',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2561; github://cristhianlujan/claude-persona-lf-patch/actions/runs/38501386804'
 ),
 (
 'IG-M105-CP2-OIDC-SOURCE-DEPLOY-DRIFT-011',
 'GitHub merged OIDC CP2 bridge not deployed in live Edge runtime',
 'Source after PR #2561 contains cp2_edge_bridge.ts and new caller action, but live lf-profiles-governance-caller-v1@23 exposes only previous index.ts/caller.ts; real GitHub OIDC preflight returned OIDC_ACTION_SCOPE_MISMATCH and created no new run.',
 'Git merge proves source readiness, not Edge deployment. No automatic deployment in existing GitHub PR Train; post-merge readback must check deployed source or version.',
 'Keep SOURCE_MERGED and RUNTIME_DEPLOYED as separate states. Deploy exact merged Edge bundle through governed runtime deployment when authorized; then rerun one preflight and demand canonical authorization denial until vNext signed. Never count source tests as live Edge proof.',
 'OIDC_AUTH PASS, GitHub run 38501386804 CP2_AUTHORITY_DENIED:OIDC_ACTION_SCOPE_MISMATCH, no Edge jobs scheduled, no CP2 PASS.',
 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/38501386804'
 ),
 (
 'IG-M105-CP2-OIDC-LEGACY-TEST-SEMANTIC-DRIFT-012',
 'Existing OIDC caller tests assert obsolete SQL-versus-Edge behavior',
 'PR #2561 initial CI ran historical caller_test.ts and observed 22 failures: expected Edge recuration and terminal READY even though current governed caller uses durable direct SQL queue and can return BLOCKED. Separately authored CP2 tests and F0 pass.',
 'A legacy test harness expected code behavior superseded by DIRECT_SQL_PERSISTED_QUEUE_V1; unrelated baseline failures must not be patched by relaxing live gate or simulating Edge.',
 'Preserve legacy behavior and record test debt; isolate new CP2 exact OIDC positive/negative tests in independent bridge CI and verify no false PASS. Repair legacy fixture against current contract in its own scope, without changing M10.5 CP2.',
 'CI 38500970431 failed 22 historical cases, CI 38501080659 succeeded for CP2 bridge checks, F0 workflow tests passed.',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2561'
 )
)
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT f.codigo,'INPUT_GOVERNANCE',f.titulo,f.descripcion,f.causa_raiz,f.prevencion,f.validacion,f.evidencia,
'programacion.engineering_plan_units/M10.5/NEW_RUNS_VNEXT',
'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5','ACTIVO','EXECUTION_PREFLIGHT',
ARRAY['Architect','Builder','Judge','Auditor']::text[]
FROM findings f
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge k WHERE k.codigo=f.codigo);

DO $verify$
BEGIN
 IF (SELECT count(*) FROM transversal.error_knowledge WHERE codigo IN (
 'IG-M105-CP2-OIDC-BRIDGE-MISSING-010',
 'IG-M105-CP2-OIDC-SOURCE-DEPLOY-DRIFT-011',
 'IG-M105-CP2-OIDC-LEGACY-TEST-SEMANTIC-DRIFT-012'))<>3
 THEN RAISE EXCEPTION 'IG_M105_CP2_OIDC_EKB_READBACK_FAIL'; END IF;
END $verify$;

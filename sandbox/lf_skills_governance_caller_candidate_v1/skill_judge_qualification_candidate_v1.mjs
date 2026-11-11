/**
 * Source-only, framework-independent audit of EJECUCION_SKILL_LF's judge coverage.
 * No SQL/Edge writes; no invocation, external authorization or operational PASS.
 * All input, including objects called 'server', is UNAUTHENTICATED in this module.
 */
export const OPERATION = 'EJECUCION_SKILL_LF';
export const ACTIVE = 'ACTIVE_ENFORCEMENT';
export const CLEAN = 'STEP_PASS_WITH_EVIDENCE';
const sha = /^[a-f0-9]{64}$/;
const allowed = new Set(['DETERMINISTIC','HYBRID','INDETERMINISTIC']);
const obj = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const nonempty = x => typeof x === 'string' && x.trim() === x && x.length > 0;
const unique = xs => xs.length === new Set(xs).size;
const isStrList = xs => Array.isArray(xs) && xs.every(nonempty) && unique(xs);

const result = (blocking_codes, n, m) => ({
  schema: 'LF_SKILL_JUDGE_COVERAGE_CANDIDATE_V1',
  status: blocking_codes.length ? 'NOT_QUALIFIED' : 'CANDIDATE_COVERAGE_CONSISTENT_UNAUTHENTICATED',
  blocking_codes: [...new Set(blocking_codes)],
  matrix_rows_checked: n,
  binding_rows_checked: m,
  source_authenticated: false,
  independent_judge_executed: false,
  coverage_operationally_verified: false,
  permission_to_record_step: false,
  permission_to_close_run: false,
  a3_allowed: false,
});

/** All rows must come from a real, authenticated DB reader in deployment.
 * This pure candidate is intentionally incapable of authenticating them.
 */
export function qualifyJudgeCoverage({judge, bindings, operationSteps, matrix, tests} = {}) {
  const errors=[];
  if (!obj(judge) || judge.operation_code !== OPERATION || !nonempty(judge.judge_code) ||
      judge.status !== ACTIVE || !nonempty(judge.judge_path)) errors.push('JUDGE_CURRENT_BINDING_INVALID');
  if (!obj(judge) || !sha.test(String(judge.judge_sha ?? ''))) errors.push('JUDGE_SOURCE_DIGEST_UNATTESTED');
  const pass=obj(judge)?judge.pass_if:null, fail=obj(judge)?judge.fail_if:null;
  if (!isStrList(pass) || !isStrList(fail)) errors.push('JUDGE_ASSERTION_SHAPE_INVALID');
  else {
    if (pass.length===0 || fail.length===0) errors.push('JUDGE_VACUOUS_INVARIANTS');
    if (pass.some(x=>fail.includes(x))) errors.push('JUDGE_PASS_FAIL_OVERLAP');
  }
  const steps=Array.isArray(operationSteps)?operationSteps.filter(x=>obj(x)&&x.required===true&&x.active===true):[];
  if (!steps.length || !isStrList(steps.map(x=>x.step_id)) ||
      steps.some(x=>x.operation_code!==OPERATION || !Number.isInteger(x.step_order)) ||
      !unique(steps.map(x=>x.step_order))) errors.push('OPERATION_REQUIRED_STEPS_NOT_QUALIFIED');
  const bs=Array.isArray(bindings)?bindings:[];
  if (!steps.length || bs.length !== steps.length ||
      !isStrList(bs.map(x=>x?.step_id)) ||
      bs.some(x=>!obj(x) || x.operation_code !== OPERATION || x.status !== ACTIVE ||
        x.judge_code !== judge?.judge_code || x.clean_result_value !== CLEAN ||
        !steps.some(s=>s.step_id===x.step_id && s.step_order===x.step_order))) {
    errors.push('JUDGE_STEP_BINDINGS_NOT_EXACT');
  }
  const ms=Array.isArray(matrix)?matrix:[];
  if (!ms.length || !isStrList(ms.map(x=>x?.id))) errors.push('COVERAGE_MATRIX_EMPTY_OR_DUPLICATED');
  const ts=Array.isArray(tests)?tests:[];
  if (!isStrList(ts.map(x=>x?.id))) errors.push('COVERAGE_TEST_INDEX_DUPLICATED');
  const observed = new Map(ts.filter(obj).map(t=>[t.id,t]));
  const coveredPass=new Set(), coveredFail=new Set();
  for (const m of ms) {
    if (!obj(m) || !nonempty(m.requirement) || !nonempty(m.risk) ||
        !nonempty(m.invariant) || !allowed.has(m.classification) ||
        !nonempty(m.evidence_ref) || !nonempty(m.pass_assertion) || !nonempty(m.fail_assertion) ||
        !nonempty(m.positive_test_id) || !nonempty(m.negative_test_id)) {
      errors.push('COVERAGE_MATRIX_ROW_INCOMPLETE'); continue;
    }
    coveredPass.add(m.pass_assertion); coveredFail.add(m.fail_assertion);
    const p=observed.get(m.positive_test_id), n=observed.get(m.negative_test_id);
    if (!obj(p) || p.kind!=='POSITIVE' || p.status!=='PASS' || p.assertion!==m.pass_assertion ||
        !obj(n) || n.kind!=='NEGATIVE' || n.status!=='BLOCKED' || n.assertion!==m.fail_assertion ||
        p.id===n.id) errors.push('COVERAGE_POSITIVE_NEGATIVE_TESTS_NOT_PAIRED');
    if (m.classification==='HYBRID' && m.deterministic_precondition_required!==true)
      errors.push('HYBRID_DETERMINISTIC_PRECONDITION_REQUIRED');
    if ((m.classification==='INDETERMINISTIC' || m.classification==='HYBRID') &&
        m.independent_judge_evidence_required!==true)
      errors.push('INDEPENDENT_JUDGE_EVIDENCE_REQUIRED');
  }
  if (isStrList(pass) && isStrList(fail) &&
      (pass.some(x=>!coveredPass.has(x)) || fail.some(x=>!coveredFail.has(x)) ||
       [...coveredPass].some(x=>!pass.includes(x)) || [...coveredFail].some(x=>!fail.includes(x))))
    errors.push('JUDGE_MATRIX_ASSERTION_COVERAGE_MISMATCH');
  if (ms.length && (([...coveredPass].length!==ms.length)||([...coveredFail].length!==ms.length)))
    errors.push('COVERAGE_ASSERTION_COLLISION');
  return result(errors,ms.length,bs.length);
}

/** Checks deterministic preconditions before any semantic result. Caller data not authority. */
export function assessCandidateStepTrust({coverage, deterministicChecks, semantic}={}) {
  const codes=[];
  if (!obj(coverage) || coverage.status!=='CANDIDATE_COVERAGE_CONSISTENT_UNAUTHENTICATED' ||
      !Array.isArray(coverage.blocking_codes) || coverage.blocking_codes.length)
    codes.push('JUDGE_COVERAGE_NOT_QUALIFIED');
  if (!Array.isArray(deterministicChecks) || !deterministicChecks.length ||
      !isStrList(deterministicChecks.map(x=>x?.id))) codes.push('SERVER_DETERMINISTIC_CHECKS_NOT_PROVIDED');
  else if(deterministicChecks.some(x=>x.ok!==true || x.source!=='SERVER_READBACK' || !sha.test(String(x.source_sha256??''))))
    codes.push('SERVER_DETERMINISTIC_PRECONDITION_NOT_CLEAN');
  // Even a convincing semantic PASS may not override failed deterministic checks.
  if (!obj(semantic) || semantic.verdict!=='PASS' || semantic.independent!==true ||
      !sha.test(String(semantic.output_sha256??'')) || !sha.test(String(semantic.evidence_sha256??'')))
    codes.push('INDEPENDENT_SEMANTIC_RECEIPT_NOT_QUALIFIED');
  return {
    status: codes.length ? 'BLOCKED_CANDIDATE' : 'CANDIDATE_EVIDENCE_CONSISTENT_UNAUTHENTICATED',
    blocking_codes: codes,
    trustworthy: false, actual_rpc_invoked:false, actual_judge_invoked:false,
    next_step:null, permission_to_record_step:false, permission_to_close_run:false, a3_allowed:false,
  };
}

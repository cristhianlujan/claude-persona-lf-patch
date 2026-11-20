import test from 'node:test';
import assert from 'node:assert/strict';
import {qualifyJudgeCoverage,assessCandidateStepTrust,OPERATION} from './skill_judge_qualification_candidate_v1.mjs';
const H='a'.repeat(64);
const steps=['init_execution','router','skill_resolve','skill_source_read','input_validate','execute_skill','output_validate','semantic_judge','report_output'].map((step_id,i)=>({operation_code:OPERATION,step_id,step_order:i*10,required:true,active:true}));
const matrix=[
 ['P01','Parent identity','Cross-RUN invocation','DETERMINISTIC'],
 ['P02','Business and ACT-0001','LF/SALY scope confusion','DETERMINISTIC'],
 ['P03','Asset READY and binding','Unapproved skill','DETERMINISTIC'],
 ['P04','Profile authority','Privilege drift','DETERMINISTIC'],
 ['P05','Current source hash','Stale SKILL.md','DETERMINISTIC'],
 ['P06','Idempotency and replay','Cross-manifest collision','DETERMINISTIC'],
 ['P07','Immutable step zero','Fake execution start','DETERMINISTIC'],
 ['P08','Ordered steps','Bypassed validation','DETERMINISTIC'],
 ['P09','Deterministic precedence','Semantic overrides hard fail','HYBRID'],
 ['P10','Independent review','Producer self-certification','INDETERMINISTIC'],
 ['P11','Internal A2 judge','A3 before A2 PASS','HYBRID'],
 ['P12','Step 80 close','Early completion','DETERMINISTIC']
].map(([id,requirement,risk,classification])=>({id,requirement,risk,invariant:`${id}_invariant`,classification,
 evidence_ref:`supabase://evidence/${id}`,pass_assertion:`${id}_pass`,fail_assertion:`${id}_fail`,
 positive_test_id:`T_${id}_positive`,negative_test_id:`T_${id}_negative`,
 deterministic_precondition_required:classification==='HYBRID',independent_judge_evidence_required:classification!=='DETERMINISTIC'}));
const tests=matrix.flatMap(m=>[
 {id:m.positive_test_id,kind:'POSITIVE',status:'PASS',assertion:m.pass_assertion},
 {id:m.negative_test_id,kind:'NEGATIVE',status:'BLOCKED',assertion:m.fail_assertion}
]);
function fixture(){return {
 judge:{operation_code:OPERATION,judge_code:'JUDGE-EJECUCION-SKILL-LF-v0.1',status:'ACTIVE_ENFORCEMENT',judge_path:'public.lf_operation_judges/EJECUCION_SKILL_LF/judge',judge_sha:H,
  pass_if:matrix.map(m=>m.pass_assertion), fail_if:matrix.map(m=>m.fail_assertion),result_values:['STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER']},
 bindings:steps.map(s=>({operation_code:OPERATION,step_id:s.step_id,step_order:s.step_order,judge_code:'JUDGE-EJECUCION-SKILL-LF-v0.1',clean_result_value:'STEP_PASS_WITH_EVIDENCE',status:'ACTIVE_ENFORCEMENT'})),
 operationSteps:structuredClone(steps),matrix:structuredClone(matrix),tests:structuredClone(tests)
};}
function check(name,mutate,code){test(name,()=>{const f=fixture();mutate(f);const out=qualifyJudgeCoverage(f);assert.equal(out.status,'NOT_QUALIFIED');assert.ok(out.blocking_codes.includes(code),JSON.stringify(out));assert.equal(out.coverage_operationally_verified,false);assert.equal(out.a3_allowed,false);});}
test('healthy synthetic fixture remains NON OPERATIONAL',()=>{let x=qualifyJudgeCoverage(fixture());assert.equal(x.status,'CANDIDATE_COVERAGE_CONSISTENT_UNAUTHENTICATED');assert.equal(x.matrix_rows_checked,12);assert.equal(x.binding_rows_checked,9);assert.equal(x.source_authenticated,false);assert.equal(x.permission_to_close_run,false);assert.equal(x.independent_judge_executed,false);});
check('real current judge from Supabase is explicitly NOT qualified',f=>{f.judge.judge_sha=null;f.judge.pass_if=[];f.judge.fail_if=[];},'JUDGE_VACUOUS_INVARIANTS');
check('empty judge SHA not qualified',f=>{f.judge.judge_sha=null;},'JUDGE_SOURCE_DIGEST_UNATTESTED');
check('wrong judge operation blocked',f=>{f.judge.operation_code='EJECUCION_PERFIL_LF';},'JUDGE_CURRENT_BINDING_INVALID');
check('wrong judge catalog status blocked',f=>{f.judge.status='CANDIDATE';},'JUDGE_CURRENT_BINDING_INVALID');
check('empty pass list blocked',f=>{f.judge.pass_if=[];},'JUDGE_VACUOUS_INVARIANTS');
check('empty fail list blocked',f=>{f.judge.fail_if=[];},'JUDGE_VACUOUS_INVARIANTS');
check('same pass/fail assertion blocked',f=>{f.judge.fail_if[0]=f.judge.pass_if[0];},'JUDGE_PASS_FAIL_OVERLAP');
check('duplicate pass assertions blocked',f=>{f.judge.pass_if.push(f.judge.pass_if[0]);},'JUDGE_ASSERTION_SHAPE_INVALID');
check('missing binding blocked',f=>{f.bindings.pop();},'JUDGE_STEP_BINDINGS_NOT_EXACT');
check('binding to another judge blocked',f=>{f.bindings[0].judge_code='OTHER';},'JUDGE_STEP_BINDINGS_NOT_EXACT');
check('binding wrong operation blocked',f=>{f.bindings[0].operation_code='EJECUCION_PERFIL_LF';},'JUDGE_STEP_BINDINGS_NOT_EXACT');
check('binding stale result blocked',f=>{f.bindings[0].clean_result_value='BLOCKED_STEP_NOT_CLEAN';},'JUDGE_STEP_BINDINGS_NOT_EXACT');
check('missing required step blocked',f=>{f.operationSteps.pop();},'JUDGE_STEP_BINDINGS_NOT_EXACT');
check('duplicate step identity blocked',f=>{f.operationSteps[1].step_id=f.operationSteps[0].step_id;},'OPERATION_REQUIRED_STEPS_NOT_QUALIFIED');
check('empty matrix blocked',f=>{f.matrix=[];},'COVERAGE_MATRIX_EMPTY_OR_DUPLICATED');
check('matrix row with missing risk blocked',f=>{delete f.matrix[0].risk;},'COVERAGE_MATRIX_ROW_INCOMPLETE');
check('matrix risk class unspecified blocked',f=>{f.matrix[0].classification='UNKNOWN';},'COVERAGE_MATRIX_ROW_INCOMPLETE');
check('no positive test blocked',f=>{f.tests=f.tests.filter(x=>x.id!==f.matrix[0].positive_test_id);},'COVERAGE_POSITIVE_NEGATIVE_TESTS_NOT_PAIRED');
check('negative test incorrectly PASS blocked',f=>{f.tests.find(x=>x.id===f.matrix[0].negative_test_id).status='PASS';},'COVERAGE_POSITIVE_NEGATIVE_TESTS_NOT_PAIRED');
check('positive test incorrectly BLOCKED blocked',f=>{f.tests.find(x=>x.id===f.matrix[0].positive_test_id).status='BLOCKED';},'COVERAGE_POSITIVE_NEGATIVE_TESTS_NOT_PAIRED');
check('duplicate test index blocked',f=>{f.tests.push({...f.tests[0]});},'COVERAGE_TEST_INDEX_DUPLICATED');
check('unmapped judge pass assertion blocked',f=>{f.judge.pass_if.push('unknown_gate');},'JUDGE_MATRIX_ASSERTION_COVERAGE_MISMATCH');
check('unmapped judge fail assertion blocked',f=>{f.judge.fail_if.push('unknown_fail');},'JUDGE_MATRIX_ASSERTION_COVERAGE_MISMATCH');
check('hybrid without deterministic gate blocked',f=>{f.matrix.find(x=>x.classification==='HYBRID').deterministic_precondition_required=false;},'HYBRID_DETERMINISTIC_PRECONDITION_REQUIRED');
check('hybrid without independent judge blocked',f=>{f.matrix.find(x=>x.classification==='HYBRID').independent_judge_evidence_required=false;},'INDEPENDENT_JUDGE_EVIDENCE_REQUIRED');
check('indeterministic without independent evidence blocked',f=>{f.matrix.find(x=>x.classification==='INDETERMINISTIC').independent_judge_evidence_required=false;},'INDEPENDENT_JUDGE_EVIDENCE_REQUIRED');
check('duplicated assertion in two invariants blocked',f=>{f.matrix[1].pass_assertion=f.matrix[0].pass_assertion;},'COVERAGE_ASSERTION_COLLISION');
const sem={verdict:'PASS',independent:true,output_sha256:H,evidence_sha256:H};
const checks=[{id:'server_guard_1',ok:true,source:'SERVER_READBACK',source_sha256:H}];
test('synthetic trust gate never grants execution on apparently clean receipts',()=>{const c=qualifyJudgeCoverage(fixture());const r=assessCandidateStepTrust({coverage:c,deterministicChecks:checks,semantic:sem});assert.equal(r.status,'CANDIDATE_EVIDENCE_CONSISTENT_UNAUTHENTICATED');assert.equal(r.permission_to_record_step,false);assert.equal(r.a3_allowed,false);});
test('current judge coverage blocks claimed PASS',()=>{const f=fixture();f.judge.pass_if=[];f.judge.fail_if=[];const r=assessCandidateStepTrust({coverage:qualifyJudgeCoverage(f),deterministicChecks:checks,semantic:sem});assert.ok(r.blocking_codes.includes('JUDGE_COVERAGE_NOT_QUALIFIED'));assert.equal(r.a3_allowed,false);});
test('deterministic failure overrides claimed semantic PASS',()=>{const r=assessCandidateStepTrust({coverage:qualifyJudgeCoverage(fixture()),deterministicChecks:[{...checks[0],ok:false}],semantic:sem});assert.ok(r.blocking_codes.includes('SERVER_DETERMINISTIC_PRECONDITION_NOT_CLEAN'));assert.equal(r.a3_allowed,false);});
test('caller asserted source without server readback blocked',()=>{const r=assessCandidateStepTrust({coverage:qualifyJudgeCoverage(fixture()),deterministicChecks:[{...checks[0],source:'CALLER'}],semantic:sem});assert.ok(r.blocking_codes.includes('SERVER_DETERMINISTIC_PRECONDITION_NOT_CLEAN'));});
test('semantic receipt missing signature digest blocked',()=>{const r=assessCandidateStepTrust({coverage:qualifyJudgeCoverage(fixture()),deterministicChecks:checks,semantic:{...sem,evidence_sha256:'bogus'}});assert.ok(r.blocking_codes.includes('INDEPENDENT_SEMANTIC_RECEIPT_NOT_QUALIFIED'));});
test('producer self-approved semantic PASS blocked',()=>{const r=assessCandidateStepTrust({coverage:qualifyJudgeCoverage(fixture()),deterministicChecks:checks,semantic:{...sem,independent:false}});assert.ok(r.blocking_codes.includes('INDEPENDENT_SEMANTIC_RECEIPT_NOT_QUALIFIED'));});
test('absent server checks blocked',()=>{const r=assessCandidateStepTrust({coverage:qualifyJudgeCoverage(fixture()),deterministicChecks:[],semantic:sem});assert.ok(r.blocking_codes.includes('SERVER_DETERMINISTIC_CHECKS_NOT_PROVIDED'));});
test('input mutation not allowed by structural qualification',()=>{const f=fixture(),before=structuredClone(f);qualifyJudgeCoverage(f);assert.deepEqual(f,before);});

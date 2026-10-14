import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveProfileRequiredSteps as select} from './required_profile_steps.ts';

const steps=[
 {step_id:'init_execution',required:true,execution_order:0},
 {step_id:'router',required:true,execution_order:10},
 {step_id:'baseline_read',required:true,execution_order:30},
 {step_id:'github_write',required:true,execution_order:70},
 {step_id:'post_merge_reconcile',required:true,execution_order:115},
 {step_id:'report_output',required:true,execution_order:130},
 {step_id:'disabled_audit',required:false,execution_order:140},
];
const snap=(value)=>({operation_policy_snapshots:{PASS_POLICY:{policy_payload:{required_steps:value}}}});
const ids=(value)=>value.map(x=>x.step_id);
test('frozen old lineage omits new post-merge requirement',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',steps,snap(['init_execution','router','baseline_read','github_write','report_output']))),['init_execution','router','baseline_read','github_write','report_output']));
test('current full update lineage remains unchanged',()=>assert.equal(select('ACTUALIZACION_PERFIL_LF',steps,snap(['init_execution','router','baseline_read','github_write','post_merge_reconcile','report_output'])).length,6));
test('future no-write subset is projected, not automatically authorized',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',steps,snap(['init_execution','router','baseline_read','report_output']))),['init_execution','router','baseline_read','report_output']));
test('absent snapshot keeps catalog compatibility',()=>assert.equal(select('ACTUALIZACION_PERFIL_LF',steps,{}).length,6));
test('null snapshot keeps catalog compatibility',()=>assert.equal(select('ACTUALIZACION_PERFIL_LF',steps,snap(null)).length,6));
test('creation operation not changed',()=>assert.equal(select('CREACION_PERFIL_LF',steps,snap(['router'])).length,6));
for(const [label,invalid] of [['empty',[]],['duplicate',['router','router']],['unknown',['router','missing']],['optional',['router','disabled_audit']],['mixed',['router',false]],['string','router']]){
 test('reject '+label,()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',steps,snap(invalid)),/FROZEN_REQUIRED_STEPS_INVALID/));
}

const full=['init_execution','router','profile_resolve','baseline_read','method_selection','evolution_decision','change_scope','regression_plan','pre_write_execution_binding_gate','github_write','github_readback','deterministic_validation','semantic_judge','regression_after','post_merge_reconcile','close','report_output'];
const noChange=['init_execution','router','profile_resolve','baseline_read','method_selection','evolution_decision','deterministic_validation','semantic_judge','close','report_output'];
const evolved=full.map((step_id,i)=>({step_id,required:true,execution_order:i*10}));
const routes=(update=full,unchanged=noChange)=>({operation_policy_snapshots:{PASS_POLICY:{policy_payload:{required_steps:update,required_steps_by_outcome:{UPDATE:update,NO_CHANGE:unchanged},required_steps_before_decision:update.slice(0,6)}}}});
const decision=(name,status='STEP_PASS_WITH_EVIDENCE')=>[{step_id:'evolution_decision',status,evidence_payload:{
 decision:name,
 evolution_mode:name==='NO_CHANGE'?'NO_CHANGE':'PATCH',
 recorded_by_rpc:'lf_record_profile_operation_step_v1',
 mini_judge_result:'STEP_PASS_WITH_EVIDENCE'
}}];
test('before clean decision only common prefix is exposed',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',evolved,routes())),full.slice(0,6)));
test('frozen conditional UPDATE follows full protected path',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',evolved,routes(),decision('UPDATE'))),full));
test('frozen conditional NO_CHANGE skips all profile mutations',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',evolved,routes(),decision('NO_CHANGE'))),noChange));
test('candidate NO_CHANGE does not obtain operational route',()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(),decision('NO_CHANGE_CANDIDATE')),/PROFILE_EVOLUTION_ROUTE_NOT_ADMITTED/));
test('unverified judge cannot choose route',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',evolved,routes(),decision('NO_CHANGE','BLOCKED_STEP_NOT_CLEAN'))),full.slice(0,6)));
test('pending evidence cannot close',()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(),decision('NEEDS_MORE_EVIDENCE')),/PROFILE_EVOLUTION_ROUTE_NOT_ADMITTED/));
test('conditional no-change cannot include prewrite',()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,[...noChange,'pre_write_execution_binding_gate'])),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/));
test('conditional no-change cannot include github_write',()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,[...noChange,'github_write'])),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/));
test('conditional no-change cannot include merge',()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,[...noChange,'post_merge_reconcile'])),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/));
test('conditional source order cannot change',()=>assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes([...full].reverse(),noChange)),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/));
test('old frozen v0.1 ignores new steps even when currently active',()=>assert.deepEqual(ids(select('ACTUALIZACION_PERFIL_LF',evolved,snap(['init_execution','router','profile_resolve','baseline_read','change_scope','regression_plan','pre_write_execution_binding_gate','github_write','github_readback','deterministic_validation','semantic_judge','regression_after','post_merge_reconcile','close','report_output']))),full.filter(x=>!['method_selection','evolution_decision'].includes(x))));

test('conditional route rejects producer-originated pass',()=>{
 const recorded=decision('NO_CHANGE');
 recorded[0].evidence_payload.recorded_by_rpc='producer_claim';
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(),recorded),/PROFILE_EVOLUTION_ROUTE_RECORDER_UNVERIFIED/);
});
test('conditional route rejects missing mini-judge proof',()=>{
 const recorded=decision('UPDATE');
 delete recorded[0].evidence_payload.mini_judge_result;
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(),recorded),/PROFILE_EVOLUTION_ROUTE_RECORDER_UNVERIFIED/);
});
test('conditional route rejects NO_CHANGE with PATCH mode',()=>{
 const recorded=decision('NO_CHANGE');
 recorded[0].evidence_payload.evolution_mode='PATCH';
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(),recorded),/PROFILE_EVOLUTION_DECISION_MODE_MISMATCH/);
});
test('conditional route rejects UPDATE with NO_CHANGE mode',()=>{
 const recorded=decision('UPDATE');
 recorded[0].evidence_payload.evolution_mode='NO_CHANGE';
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(),recorded),/PROFILE_EVOLUTION_DECISION_MODE_MISMATCH/);
});

test('reject frozen prefix missing from conditional policy',()=>{
 const snap=routes();
 delete snap.operation_policy_snapshots.PASS_POLICY.policy_payload.required_steps_before_decision;
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,snap),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject frozen prefix tampered by caller',()=>{
 const snap=routes();
 snap.operation_policy_snapshots.PASS_POLICY.policy_payload.required_steps_before_decision[4]='change_scope';
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,snap),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject missing prefix even after clean decision',()=>{
 const snap=routes();
 snap.operation_policy_snapshots.PASS_POLICY.policy_payload.required_steps_before_decision=[];
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,snap,decision('NO_CHANGE')),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});

test('reject NO_CHANGE that omits semantic review',()=>{
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,noChange.filter(v=>v!=='semantic_judge'))),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject NO_CHANGE that omits deterministic verification',()=>{
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,noChange.filter(v=>v!=='deterministic_validation'))),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject NO_CHANGE that omits closure',()=>{
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,noChange.filter(v=>v!=='close'))),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject NO_CHANGE frozen suffix reordered relative to UPDATE',()=>{
 const reordered=[...noChange];
 [reordered[6],reordered[7]]=[reordered[7],reordered[6]];
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,reordered),decision('NO_CHANGE')),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject NO_CHANGE containing GitHub readback without write',()=>{
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(full,[...noChange,'github_readback'])),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});
test('reject UPDATE missing holdout',()=>{
 const incomplete=full.filter(v=>v!=='regression_after');
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,routes(incomplete,noChange)),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});

// SQL parity regression: the conditional policy must freeze exactly six
// prefix steps, with method_selection/evolution_decision in slots five/six.
test('reject shifted method/decision prefix even when both route lists agree',()=>{
 const shifted=[...full];
 shifted.splice(3,4,'method_selection','evolution_decision','change_scope','baseline_read');
 const shiftedNoChange=[...noChange];
 shiftedNoChange.splice(3,3,'method_selection','evolution_decision','baseline_read');
 const policy=routes(shifted,shiftedNoChange);
 policy.operation_policy_snapshots.PASS_POLICY.policy_payload.required_steps_before_decision=shifted.slice(0,5);
 assert.throws(()=>select('ACTUALIZACION_PERFIL_LF',evolved,policy),/PROFILE_EVOLUTION_FROZEN_ROUTES_INVALID/);
});

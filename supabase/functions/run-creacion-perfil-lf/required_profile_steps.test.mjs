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

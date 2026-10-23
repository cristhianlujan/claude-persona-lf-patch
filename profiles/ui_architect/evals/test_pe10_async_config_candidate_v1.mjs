// Frozen PE10_C3 V2 UI asynchronous and configuration invariants.
// Synthetic state-machine proxy; does not execute the UI Architect model.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const text=readFileSync(new URL('../SKILL.md',import.meta.url),'utf8');
assert.ok(text.includes('## Conditional asynchronous-state and runtime-configuration remediation'));
assert.ok(text.includes('out-of-order responses'));
assert.ok(text.includes('do not fabricate one'));
assert.ok(text.includes('Server RBAC'));
function state(){ return {id:'L1',sequence:1,loaded:null,configRevision:11,contact:'current'}; }
const s=state();
function applyLoad(id, seq, payload) {
  if(id!==s.id||seq!==s.sequence) return false;
  s.loaded=payload; return true;
}
s.id='L2';s.sequence=2;s.loaded=null;
assert.equal(applyLoad('L1',1,{id:'L1',ready:true}),false);
assert.equal(s.loaded,null);
assert.equal(applyLoad('L2',2,{id:'L2',ready:true}),true);
assert.equal(s.loaded.id,'L2');
function config(revision,contact) {
  if(typeof revision!=='number'||revision<s.configRevision)return false;
  s.configRevision=revision;s.contact=contact;return true;
}
assert.equal(config(9,'stale'),false);
assert.equal(s.contact,'current');
assert.equal(config(undefined,'unversioned'),false);
assert.equal(config(12,'new'),true);
assert.equal(s.contact,'new');
let attempts=0;
function submit({role,load,loading}) {
  if(loading||!role.canApprove||!load||load.id!==s.id||load.state!=='READY')return false;
  attempts++;return true;
}
assert.equal(submit({role:{canApprove:true},load:{id:'L1',state:'READY'},loading:false}),false);
assert.equal(submit({role:{canApprove:false},load:{id:'L2',state:'READY'},loading:false}),false);
assert.equal(submit({role:{canApprove:true},load:{id:'L2',state:'READY'},loading:true}),false);
assert.equal(attempts,0);
console.log('PASS: source+synthetic UI cross-state regressions; NO_BROWSER_OR_PROFILE_MODEL_JUDGE');

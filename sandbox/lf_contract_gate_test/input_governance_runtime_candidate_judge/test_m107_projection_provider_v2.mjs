// Candidate-only run-scoped provider regression: node --test
import test from 'node:test';
import assert from 'node:assert/strict';
import {createRunScopedProjectionProviderV2} from '../../../supabase/functions/_shared/ig_snapshot_projection_provider_v2.mjs';
import {selectSnapshotReadV1,sha256Hex} from '../../../supabase/functions/_shared/ig_snapshot_reader_v1.mjs';
const base={run_id:933,pantalla_id:43,version_id:19,status:'VALIDATING',
 contract_snapshot_sha256:'a'.repeat(64),source_snapshot_sha256:'b'.repeat(64),
 curator_identity:'CURATOR_A',validator_identity:'VALIDATOR_B'};
const source={rules:[{regla_id:7,codigo:'R7'},{regla_id:8,codigo:'R8'}],
 contracts:[{contrato_codigo:'C1',especificacion:{enabled:true}},{contrato_codigo:'C2'}],
 families:[{family_code:'ACTIONS',coverage_status:'COMPLETE'},{family_code:'ANALYTICS',coverage_status:'COMPLETE'}],
 graph:{screen:{id:43},contract:{visual:{color:'yellow'}}}};
function fixture(copy=structuredClone(source),override={}){
 let calls=0;
 const provider=createRunScopedProjectionProviderV2({
  loadTrustedRunData:async identity=>{calls++;return {identity:{...identity,...override},data:copy};}
 });
 return {provider,calls:()=>calls};
}
test('trusted dataset loaded once across many selections',async()=>{
 const x=fixture();
 const a=await x.provider.select({consumer:'INPUT_VALIDATOR',run:base,selection:{rules:[7]}});
 const b=await x.provider.select({consumer:'INPUT_VALIDATOR',run:base,selection:{contracts:['C2']}});
 assert.equal(a.data.rules[0].regla_id,7);assert.equal(b.data.contracts[0].contrato_codigo,'C2');
 assert.equal(x.calls(),1);assert.equal(x.provider.metrics().trusted_source_loads,1);
});
test('selected result excludes unrequested variables and shares frozen backing',async()=>{
 const x=fixture();const bound=await x.provider.open({consumer:'INPUT_VALIDATOR',run:base});
 const a=bound.read({families:['ACTIONS']}),b=bound.read({families:['ACTIONS']});
 assert.deepEqual(Object.keys(a),['families']);assert.strictEqual(a.families[0],b.families[0]);
 assert.ok(Object.isFrozen(a.families[0]));assert.equal(x.calls(),1);
});
test('one batched transfer gives only selected rules and one contract',async()=>{
 const x=fixture();
 const p=await x.provider.projectForTransfer({consumer:'INPUT_VALIDATOR',run:base,
  selection:{rules:[8],contracts:['C1']}});
 assert.equal(p.data.rules.length,1);assert.equal(p.data.contracts.length,1);
 assert.equal(Object.hasOwn(p.data,'families'),false);assert.equal(Object.hasOwn(p.data,'graph'),false);
 assert.equal(await sha256Hex(p.data),p.data_sha256);
});
test('projected packet is accepted by original selective reader',async()=>{
 const x=fixture();
 const p=await x.provider.projectForTransfer({consumer:'INPUT_VALIDATOR',run:base,selection:{families:['ANALYTICS']}});
 const b=await selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run:base,loadTrustedSnapshot:async()=>p});
 assert.equal(b.read({families:['ANALYTICS']}).families[0].family_code,'ANALYTICS');
 assert.throws(()=>b.read({rules:[7]}),{code:'IG_SNAPSHOT_RULES_MISSING'});
});
test('selector never sends whole data implicitly',async()=>{
 const x=fixture();const p=await x.provider.projectForTransfer({consumer:'INPUT_VALIDATOR',run:base,selection:{graph:['screen.id']}});
 assert.deepEqual(Object.keys(p.data),['graph']);
 assert.equal(p.data.graph.screen.id,43);
});
test('same frozen dataset can be rebound to curator stage only with valid identity',async()=>{
 const x=fixture();
 const c={...base,status:'CURATING'};
 const a=await x.provider.select({consumer:'INPUT_CURATOR',run:c,selection:{rules:[7]}});
 const b=await x.provider.select({consumer:'INPUT_VALIDATOR',run:base,selection:{rules:[7]}});
 assert.equal(x.calls(),1);assert.equal(a.data.rules[0].regla_id,b.data.rules[0].regla_id);
});
test('wrong lifecycle stage skips provider load',async()=>{
 const x=fixture();const r=await x.provider.select({consumer:'INPUT_CURATOR',run:base,selection:{rules:[7]}});
 assert.equal(r.mode,'CANONICAL_CURRENT');assert.equal(x.calls(),0);
});
test('concurrent requests share in-flight trusted load',async()=>{
 const x=fixture();
 const [a,b]=await Promise.all([
  x.provider.select({consumer:'INPUT_VALIDATOR',run:base,selection:{rules:[7]}}),
  x.provider.select({consumer:'INPUT_VALIDATOR',run:base,selection:{rules:[8]}})
 ]);
 assert.equal(a.data.rules.length,1);assert.equal(b.data.rules.length,1);assert.equal(x.calls(),1);
});
test('a different run cannot reuse the cached dataset',async()=>{
 const x=fixture();await x.provider.open({consumer:'INPUT_VALIDATOR',run:base});
 await assert.rejects(x.provider.open({consumer:'INPUT_VALIDATOR',run:{...base,run_id:934}}),{code:'IG_PROVIDER_RUN_SCOPE_MISMATCH'});
});
test('a different source hash cannot reuse the cached dataset',async()=>{
 const x=fixture();await x.provider.open({consumer:'INPUT_VALIDATOR',run:base});
 await assert.rejects(x.provider.open({consumer:'INPUT_VALIDATOR',run:{...base,source_snapshot_sha256:'c'.repeat(64)}}),{code:'IG_PROVIDER_RUN_SCOPE_MISMATCH'});
});
test('untrusted source identity is rejected',async()=>{
 const x=fixture(structuredClone(source),{pantalla_id:44});
 await assert.rejects(x.provider.open({consumer:'INPUT_VALIDATOR',run:base}),{code:'IG_PROVIDER_TRUSTED_IDENTITY_MISMATCH'});
});
test('missing trusted source is rejected',async()=>{
 const x=createRunScopedProjectionProviderV2({loadTrustedRunData:async()=>null});
 await assert.rejects(x.open({consumer:'INPUT_VALIDATOR',run:base}),{code:'IG_PROVIDER_TRUSTED_DATA_MISSING'});
});
test('unknown consumer is never served',async()=>{
 const x=fixture();
 await assert.rejects(x.provider.open({consumer:'UNKNOWN',run:base}),{code:'IG_SNAPSHOT_CONSUMER_NOT_ALLOWED'});
 assert.equal(x.calls(),0);
});
test('missing requested variable rejects, never falls back to database',async()=>{
 const x=fixture();
 await assert.rejects(x.provider.select({consumer:'INPUT_VALIDATOR',run:base,selection:{contracts:['ABSENT']}}),
 {code:'IG_SNAPSHOT_CONTRACTS_KEY_MISSING'});assert.equal(x.calls(),1);
});
test('a tampered projection is rejected by receiving reader',async()=>{
 const x=fixture();
 const p=await x.provider.projectForTransfer({consumer:'INPUT_VALIDATOR',run:base,selection:{rules:[7]}});
 const t={...p,data:{rules:[{regla_id:999}]}};
 await assert.rejects(selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run:base,loadTrustedSnapshot:async()=>t}),
 {code:'IG_SNAPSHOT_DATA_TAMPERED'});
});
test('provider requires trusted backend loader, never request-supplied packet',()=>{
 assert.throws(()=>createRunScopedProjectionProviderV2({}),{code:'IG_PROVIDER_TRUSTED_LOADER_MISSING'});
});

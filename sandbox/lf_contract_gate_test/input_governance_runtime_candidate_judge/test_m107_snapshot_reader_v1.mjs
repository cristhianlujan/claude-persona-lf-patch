// Candidate-only tests. Run with: node --test <this file>
import test from 'node:test';
import assert from 'node:assert/strict';
import {selectSnapshotReadV1,sha256Hex} from '../../../supabase/functions/_shared/ig_snapshot_reader_v1.mjs';
const run={run_id:933,pantalla_id:43,version_id:19,status:'VALIDATING',contract_snapshot_sha256:'contract',source_snapshot_sha256:'source',curator_identity:'CURATOR_A',validator_identity:'VALIDATOR_B'};
const data={rules:[{rule_id:7}],contracts:[{code:'IG'}],families:[{family_code:'ACTIONS'}],graph:{screen_id:43}};
async function packet(custom={}) {return {schema_version:'IG_EXECUTION_SOURCE_CONTEXT_V2',purpose:'READ_ONLY_DATA_PACKET',reuse_scope:'RUN_IMMUTABLE_COMPLETE',consumer_stage:'VALIDATING',...run,data,data_sha256:await sha256Hex(data),...custom}}
async function choose(p=undefined, context=run) {if(p===undefined)p=await packet();return selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run:context,loadTrustedSnapshot:async()=>p})}
test('valid stage => selective immutable snapshot',async()=>{const r=await choose();assert.equal(r.mode,'SHARED_SNAPSHOT');const v=r.read({rules:[7]});assert.ok(Object.isFrozen(v.rules[0]));assert.equal(v.rules[0].rule_id,7);assert.equal(Object.hasOwn(r,'data'),false)});
test('G1 reference only => canonical legacy, never incomplete reuse',async()=>{const p={schema_version:'IG_EXECUTION_SOURCE_CONTEXT_V1',reuse_scope:'RUN_PINNED_FIELDS_ONLY',run_id:933};assert.equal((await choose(p)).reason,'G1_REFERENCE_ONLY')});
test('missing packet => original path',async()=>{assert.equal((await choose(null)).mode,'CANONICAL_CURRENT')});
test('different stage does not call provider',async()=>{const r=await selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run:{...run,status:'CURATING'},loadTrustedSnapshot:()=>{throw Error('must not fetch')}});assert.equal(r.reason,'STAGE_NOT_APPLICABLE')});
test('Curator CURATING uses complete internal packet only when available',async()=>{const cr={...run,status:'CURATING'};const p=await packet({consumer_stage:'CURATING'});const r=await selectSnapshotReadV1({consumer:'INPUT_CURATOR',run:cr,loadTrustedSnapshot:async()=>p});assert.equal(r.mode,'SHARED_SNAPSHOT')});
test('source identity changes => reject',async()=>{await assert.rejects(choose(await packet({source_snapshot_sha256:'other'})),{code:'IG_SNAPSHOT_IDENTITY_MISMATCH_SOURCE_SNAPSHOT_SHA256'})});
test('cross-run packet => reject',async()=>{await assert.rejects(choose(await packet({run_id:934})),{code:'IG_SNAPSHOT_IDENTITY_MISMATCH_RUN_ID'})});
test('altered payload => reject',async()=>{const p=await packet();p.data={...p.data,rules:[{rule_id:8}]};await assert.rejects(choose(p),{code:'IG_SNAPSHOT_DATA_TAMPERED'})});
test('partial packet => only missing requested section rejects',async()=>{const p=await packet();p.data={rules:[{rule_id:7}]};p.data_sha256=await sha256Hex(p.data);const r=await choose(p);assert.equal(r.read({rules:[7]}).rules.length,1);assert.throws(()=>r.read({graph:['screen_id']}),{code:'IG_SNAPSHOT_GRAPH_MISSING'})});
test('Validator identity not independent => reject',async()=>{await assert.rejects(choose(await packet(),{...run,validator_identity:'CURATOR_A'}),{code:'IG_SNAPSHOT_VALIDATOR_INDEPENDENCE_MISSING'})});
test('unknown consumer => reject',async()=>{await assert.rejects(selectSnapshotReadV1({consumer:'OTHER',run,loadTrustedSnapshot:()=>null}),{code:'IG_SNAPSHOT_CONSUMER_NOT_ALLOWED'})});

test('select only requested sections and values, not full packet',async()=>{
 const r=await choose();const v=r.read({rules:[7],contracts:['IG'],families:['ACTIONS'],graph:['screen_id']});
 assert.deepEqual(v.rules.map(x=>x.rule_id),[7]);assert.deepEqual(v.contracts.map(x=>x.code),['IG']);
 assert.deepEqual(v.families.map(x=>x.family_code),['ACTIONS']);assert.equal(v.graph.screen_id,43);
 assert.equal(Object.keys(v).length,4);assert.equal(Object.hasOwn(v,'other'),false);
});
test('read repeatedly from one indexed snapshot without another provider call or clone',async()=>{
 let loads=0;const r=await selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run,
 loadTrustedSnapshot:async()=>{loads++;return packet()}});
 const a=r.read({rules:[7]}),b=r.read({rules:[7]}),c=r.read({contracts:['IG']});
 assert.equal(loads,1);assert.strictEqual(a.rules[0],b.rules[0]);assert.ok(Object.isFrozen(c.contracts[0]));
});
test('Curator gets only the requested variables, not all sources',async()=>{
 const cr={...run,status:'CURATING'};const p=await packet({consumer_stage:'CURATING'});
 const r=await selectSnapshotReadV1({consumer:'INPUT_CURATOR',run:cr,loadTrustedSnapshot:async()=>p});
 const v=r.read({graph:['screen_id']});assert.equal(v.graph.screen_id,43);assert.equal(Object.hasOwn(v,'rules'),false);
});
test('missing key rejects rather than issuing another database request',async()=>{
 const r=await choose();assert.throws(()=>r.read({rules:[999]}),{code:'IG_SNAPSHOT_RULES_KEY_MISSING'});
});
test('unrequested sections need not be indexed',async()=>{
 const p=await packet();p.data=structuredClone(p.data);p.data.rules.push({rule_id:7});p.data_sha256=await sha256Hex(p.data);
 const r=await choose(p);assert.equal(r.read({graph:['screen_id']}).graph.screen_id,43);
 assert.throws(()=>r.read({rules:[7]}),{code:'IG_SNAPSHOT_RULES_IDENTITY_INVALID'});
});
test('returned projections and backing records cannot be mutated',async()=>{
 const p=await packet();const r=await choose(p);const v=r.read({families:['ACTIONS']});
 assert.ok(Object.isFrozen(p.data));assert.ok(Object.isFrozen(v.families));assert.ok(Object.isFrozen(v.families[0]));
 assert.throws(()=>{v.families[0].family_code='OTHER'},TypeError);
});
test('explicit whole-section access remains available when truly needed',async()=>{
 const r=await choose();assert.equal(r.read({rules:true}).rules.length,1);assert.equal(r.read({graph:true}).graph.screen_id,43);
});
test('unknown or missing selection rejects',async()=>{
 const r=await choose();assert.throws(()=>r.read({}),{code:'IG_SNAPSHOT_SELECTION_INVALID'});
 assert.throws(()=>r.read({verdict:true}),{code:'IG_SNAPSHOT_SELECTION_INVALID'});
});
test('graph requests are own-fields only, not prototype traversal',async()=>{
 const r=await choose();
 assert.throws(()=>r.read({graph:['__proto__']}),{code:'IG_SNAPSHOT_GRAPH_FIELD_MISSING'});
 assert.throws(()=>r.read({graph:['missing']}),{code:'IG_SNAPSHOT_GRAPH_FIELD_MISSING'});
});
test('empty packet, even with matching hash, cannot be admitted',async()=>{
 const p=await packet();p.data={};p.data_sha256=await sha256Hex(p.data);
 await assert.rejects(choose(p),{code:'IG_SNAPSHOT_DATA_INCOMPLETE'});
});

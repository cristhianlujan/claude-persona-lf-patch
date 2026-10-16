// Candidate-only tests. Run with: node --test <this file>
import test from 'node:test';
import assert from 'node:assert/strict';
import {selectSnapshotReadV1,sha256Hex} from '../../../supabase/functions/_shared/ig_snapshot_reader_v1.mjs';
const run={run_id:933,pantalla_id:43,version_id:19,status:'VALIDATING',contract_snapshot_sha256:'contract',source_snapshot_sha256:'source',curator_identity:'CURATOR_A',validator_identity:'VALIDATOR_B'};
const data={rules:[{rule_id:7}],contracts:[{code:'IG'}],families:[{family_code:'ACTIONS'}],graph:{screen_id:43}};
async function packet(custom={}) {return {schema_version:'IG_EXECUTION_SOURCE_CONTEXT_V2',purpose:'READ_ONLY_DATA_PACKET',reuse_scope:'RUN_IMMUTABLE_COMPLETE',consumer_stage:'VALIDATING',...run,data,data_sha256:await sha256Hex(data),...custom}}
async function choose(p=undefined, context=run) {if(p===undefined)p=await packet();return selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run:context,loadTrustedSnapshot:async()=>p})}
test('valid stage, pinned identity, full data => immutable snapshot',async()=>{const r=await choose();assert.equal(r.mode,'SHARED_SNAPSHOT');assert.ok(Object.isFrozen(r.data.rules[0]));assert.equal(r.data.rules[0].rule_id,7)});
test('G1 reference only => canonical legacy, never incomplete reuse',async()=>{const p={schema_version:'IG_EXECUTION_SOURCE_CONTEXT_V1',reuse_scope:'RUN_PINNED_FIELDS_ONLY',run_id:933};assert.equal((await choose(p)).reason,'G1_REFERENCE_ONLY')});
test('missing packet => original path',async()=>{assert.equal((await choose(null)).mode,'CANONICAL_CURRENT')});
test('different stage does not call provider',async()=>{const r=await selectSnapshotReadV1({consumer:'INPUT_VALIDATOR',run:{...run,status:'CURATING'},loadTrustedSnapshot:()=>{throw Error('must not fetch')}});assert.equal(r.reason,'STAGE_NOT_APPLICABLE')});
test('Curator CURATING uses complete internal packet only when available',async()=>{const cr={...run,status:'CURATING'};const p=await packet({consumer_stage:'CURATING'});const r=await selectSnapshotReadV1({consumer:'INPUT_CURATOR',run:cr,loadTrustedSnapshot:async()=>p});assert.equal(r.mode,'SHARED_SNAPSHOT')});
test('source identity changes => reject',async()=>{await assert.rejects(choose(await packet({source_snapshot_sha256:'other'})),{code:'IG_SNAPSHOT_IDENTITY_MISMATCH_SOURCE_SNAPSHOT_SHA256'})});
test('cross-run packet => reject',async()=>{await assert.rejects(choose(await packet({run_id:934})),{code:'IG_SNAPSHOT_IDENTITY_MISMATCH_RUN_ID'})});
test('altered payload => reject',async()=>{const p=await packet();p.data={...p.data,rules:[{rule_id:8}]};await assert.rejects(choose(p),{code:'IG_SNAPSHOT_DATA_TAMPERED'})});
test('partial payload => reject',async()=>{const p=await packet();p.data={rules:[],contracts:[],families:[]};await assert.rejects(choose(p),{code:'IG_SNAPSHOT_DATA_INCOMPLETE'})});
test('Validator identity not independent => reject',async()=>{await assert.rejects(choose(await packet(),{...run,validator_identity:'CURATOR_A'}),{code:'IG_SNAPSHOT_VALIDATOR_INDEPENDENCE_MISSING'})});
test('unknown consumer => reject',async()=>{await assert.rejects(selectSnapshotReadV1({consumer:'OTHER',run,loadTrustedSnapshot:()=>null}),{code:'IG_SNAPSHOT_CONSUMER_NOT_ALLOWED'})});

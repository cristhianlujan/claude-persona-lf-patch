import test from 'node:test';
import assert from 'node:assert/strict';
import {createTrustedRunDataLoaderV1} from '../../../supabase/functions/_shared/ig_trusted_run_loader_v1.mjs';
import {createRunScopedProjectionProviderV2} from '../../../supabase/functions/_shared/ig_snapshot_projection_provider_v2.mjs';
const run={run_id:1337,pantalla_id:43,version_id:19,status:'VALIDATING',
 contract_snapshot_sha256:'a'.repeat(64),source_snapshot_sha256:'b'.repeat(64),
 curator_identity:'CURATOR',validator_identity:'VALIDATOR'};
const keys=['run_id','pantalla_id','version_id','contract_snapshot_sha256','source_snapshot_sha256'];
const identity=Object.fromEntries(keys.map(x=>[x,run[x]]));
const data={rules:[{regla_id:7,codigo:'R7'}],contracts:[{contrato_codigo:'C1'}],
 families:[{family_code:'ACTIONS'}],graph:{screen_code:'B2B'}};
function fixture(opts={}){
 let transactions=0;const calls=[];
 const withReadOnlyRepeatableRead=async fn=>{
  transactions++;
  return await fn({query:async(sql,params)=>{
   calls.push({sql,params});
   if(opts.dbFailure)throw opts.dbFailure;
   return {rows:[{payload:{identity:{...identity,...opts.identity},data:opts.data??structuredClone(data)}}]};
  }});
 };
 return {loadTrustedRunData:createTrustedRunDataLoaderV1({withReadOnlyRepeatableRead}),
  metrics:()=>({transactions,calls})};
}
test('one real SQL target for concurrent and repeated projections',async()=>{
 const x=fixture(),p=createRunScopedProjectionProviderV2({loadTrustedRunData:x.loadTrustedRunData});
 const [a,b]=await Promise.all([
  p.select({consumer:'INPUT_VALIDATOR',run,selection:{rules:[7]}}),
  p.select({consumer:'INPUT_VALIDATOR',run,selection:{families:['ACTIONS']}})
 ]);
 assert.equal(a.data.rules[0].regla_id,7);
 assert.equal(b.data.families[0].family_code,'ACTIONS');
 assert.equal(x.metrics().transactions,1);assert.equal(x.metrics().calls.length,1);
 assert.match(x.metrics().calls[0].sql,/fn_ig_m107_trusted_run_data_v1\(\$1::bigint\)/);
 assert.deepEqual(x.metrics().calls[0].params,[run.run_id]);
});
test('no trusted backend transaction driver rejects',()=>{
 assert.throws(()=>createTrustedRunDataLoaderV1({}),{code:'IG_F_TRUSTED_TRANSACTION_REQUIRED'});
});
test('wrong returned run identity rejects',async()=>{
 const x=fixture({identity:{pantalla_id:44}});
 await assert.rejects(x.loadTrustedRunData(identity),{code:'IG_F_SQL_IDENTITY_MISMATCH'});
});
test('missing sections reject',async()=>{
 const x=fixture({data:{rules:[],contracts:[],families:[],graph:{}}});
 await assert.rejects(x.loadTrustedRunData(identity),{code:'IG_F_SQL_DATA_INCOMPLETE'});
});
test('database refusal propagates and does not turn into canonical PASS',async()=>{
 const x=fixture({dbFailure:new Error('IG_M107_TRUSTED_SNAPSHOT_TX_REQUIRED')});
 await assert.rejects(x.loadTrustedRunData(identity),/IG_M107_TRUSTED_SNAPSHOT_TX_REQUIRED/);
});
test('additional decision outputs fail closed',async()=>{
 const x=fixture({data:{...data,validator_outcome:'PASS'}});
 await assert.rejects(x.loadTrustedRunData(identity),{code:'IG_F_SQL_DATA_UNEXPECTED_SECTION'});
});
test('wrong stage keeps canonical route without DB load',async()=>{
 const x=fixture(),p=createRunScopedProjectionProviderV2({loadTrustedRunData:x.loadTrustedRunData});
 const response=await p.select({consumer:'INPUT_CURATOR',run,selection:{rules:[7]}});
 assert.equal(response.mode,'CANONICAL_CURRENT');assert.equal(x.metrics().transactions,0);
});
test('invalid input run id rejected before database',async()=>{
 const x=fixture();
 await assert.rejects(x.loadTrustedRunData({...identity,run_id:0}),{code:'IG_F_PINNED_IDENTITY_MISSING'});
 assert.equal(x.metrics().transactions,0);
});

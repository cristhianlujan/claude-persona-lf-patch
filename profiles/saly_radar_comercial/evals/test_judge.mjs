import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {judgeDetails} from '../judges/judge.mjs';

const hash = s => createHash('sha256').update(s).digest('hex');
const policy = JSON.parse(readFileSync(new URL('../config/pte_pilot.v1.json', import.meta.url)));
const original = [
 {fila_origen:1,nombre:'Fixture only - A',ruc:'20100000001',ubigeo:'150101'},
 {fila_origen:2,nombre:'Fixture only - B',ruc:null,ubigeo:'110101'}
];
const capture = JSON.stringify(original);
const expected = hash(capture);
const good = {
 status:'VALID_OUTPUT',project_code:'SALY',profile_code:'PERFIL-RADAR-COMERCIAL-SALY',
 identity_verified:false,production_authorized:false,pack_type:'profile',
 deliverable_created:{source_id:'PE-PTE',scope_key:'LIMA_ICA',source_version:'2026-08',
  capture_sha256:expected,observed_count:2,existing_count:2,unmatched_count:0,effect:'READ_ONLY'},
 evidence_map:['fixture readback'],blocking_codes:[],next_gate:'NATIVE_PROFILE_REGISTRATION'
};
const trusted = {policy, capture_json:capture, authority:{source_kind:'SUPABASE_READBACK',
 source_ref:'fixture-lookup',query_ref:'fixture-query',capture_sha256:expected,
 stored_count:2,matching_count:2}};
const copy = value => structuredClone(value);
const cases = [
 ['positive',good,trusted,'RADAR_SEMANTIC_READ_ONLY_PASS'],
 ['no independent context',good,null,'RADAR_MISSING_INDEPENDENT_CONTEXT'],
 ['extra field', {...good,garbage:true},trusted,'RADAR_PACKET_SHAPE'],
 ['wrong project',{...good,project_code:'LF'},trusted,'RADAR_PROJECT_OR_AUTHORITY'],
 ['fake identity',{...good,identity_verified:true},trusted,'RADAR_PROJECT_OR_AUTHORITY'],
 ['fake production',{...good,production_authorized:true},trusted,'RADAR_PROJECT_OR_AUTHORITY'],
 ['cross-profile',{...good,profile_code:'PERFIL-PRODUCT-DIRECTOR-LF'},trusted,'RADAR_PROJECT_OR_AUTHORITY'],
 ['write attempt',{...good,deliverable_created:{...good.deliverable_created,effect:'WRITE_GOVERNED'}},trusted,'RADAR_RESULT_SHAPE'],
 ['no evidence',{...good,evidence_map:[]},trusted,'RADAR_EVIDENCE_SHAPE'],
 ['policy scope drift',good,{...trusted,policy:{...policy,source_id:'PE-OTHER'}},'RADAR_POLICY_DRIFT'],
 ['authority forged shape',good,{...trusted,authority:{...trusted.authority,source_kind:'USER_ASSERTION'}},'RADAR_AUTHORITY_RECEIPT_SHAPE'],
 ['broken JSON',good,{...trusted,capture_json:'not-json'},'RADAR_CAPTURE_PARSE'],
 ['missing row name',good,{...trusted,capture_json:JSON.stringify([{...original[0],nombre:' '},original[1]])},'RADAR_CAPTURE_ROW_CONTRACT'],
 ['duplicate source ordinal',good,{...trusted,capture_json:JSON.stringify([original[0],{...original[1],fila_origen:1}])},'RADAR_DUPLICATE_SOURCE_ORDINAL'],
 ['changed content',good,{...trusted,capture_json:JSON.stringify([{...original[0],nombre:'MUTATED'},original[1]])},'RADAR_CAPTURE_HASH_MISMATCH'],
 ['changed DB hash',good,{...trusted,authority:{...trusted.authority,capture_sha256:'a'.repeat(64)}},'RADAR_STORED_HASH_MISMATCH'],
 ['wrong count',{...good,deliverable_created:{...good.deliverable_created,observed_count:3}},trusted,'RADAR_COUNT_READBACK_MISMATCH'],
 ['mismatch between DB and result',{...good,deliverable_created:{...good.deliverable_created,existing_count:0}},trusted,'RADAR_COUNT_READBACK_MISMATCH'],
 ['negative unmatched',{...good,deliverable_created:{...good.deliverable_created,unmatched_count:-1}},trusted,'RADAR_RESULT_SHAPE']
];
for (const [name,input,evidence,code] of cases) {
  const originalInput=copy(input), originalContext=copy(evidence);
  const result=judgeDetails(input,evidence);
  assert.equal(result.code,code,name);
  assert.equal(result.status,code==='RADAR_SEMANTIC_READ_ONLY_PASS'?'VALID_OUTPUT':'BLOCK_PIPELINE',name);
  assert.deepEqual(input,originalInput,'mutated input for '+name);
  assert.deepEqual(evidence,originalContext,'mutated context for '+name);
}
assert.match(judgeDetails(good,trusted).judged_sha256,/^[a-f0-9]{64}$/);
assert.notEqual(judgeDetails(good,trusted).judged_sha256,
 judgeDetails({...good,evidence_map:['different receipt']},trusted).judged_sha256);

// Mutation qualification: each guard is *removed* while keeping syntax valid.
// Count a mutation only when the named negative fails on the expected assertion.
const source = readFileSync(new URL('../judges/judge.mjs', import.meta.url),'utf8');
const mutants = [
 {anchor:'packet.production_authorized !== false',replacement:'false',caseName:'fake production'},
 {anchor:'computed !== d.capture_sha256',replacement:'false',caseName:'changed content'},
 {anchor:'auth.capture_sha256 !== computed',replacement:'false',caseName:'changed DB hash'},
 {anchor:'new Set(rows.map(row => row.fila_origen)).size !== rows.length',replacement:'false',caseName:'duplicate source ordinal'}
];
for (const mutant of mutants) {
  assert.equal(source.split(mutant.anchor).length,2,'unreliable mutation '+mutant.caseName);
  const modified = source.replace(mutant.anchor,mutant.replacement);
  const url = 'data:text/javascript;base64,'+Buffer.from(modified).toString('base64');
  const imported = await import(url);
  const sample = cases.find(([name])=>name===mutant.caseName);
  let input = sample[1], evidence = sample[2];
  if (mutant.caseName === 'changed content') {
    // Isolate the first hash guard: the authoritative source changed, but
    // the candidate packet still cites its previous hash.
    evidence = {...evidence, authority:{...evidence.authority,
      capture_sha256:hash(evidence.capture_json)}};
  }
  if (mutant.caseName === 'duplicate source ordinal') {
    // Isolate the ordinal gate from both hash gates.
    const digest=hash(evidence.capture_json);
    input = {...input,deliverable_created:{...input.deliverable_created,capture_sha256:digest}};
    evidence = {...evidence,authority:{...evidence.authority,capture_sha256:digest}};
  }
  assert.equal(judgeDetails(input,evidence).code,sample[3],'control masked by another guard: '+mutant.caseName);
  const result=imported.judgeDetails(input,evidence);
  assert.equal(result.code,'RADAR_SEMANTIC_READ_ONLY_PASS','mutation not isolated: '+mutant.caseName);
  assert.notEqual(result.code,sample[3],'mutation survived: '+mutant.caseName);
}
console.log('PASS_RADAR_JUDGE '+cases.length+' functional cases, 4 guard mutations killed by intended assertions, input stable, verdict hash dynamic');

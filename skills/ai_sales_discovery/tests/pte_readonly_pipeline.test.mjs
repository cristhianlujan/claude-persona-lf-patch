import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {normalizePteCsv} from '../../../docs/saly/ventas/candidate/pte/normalize_pte_csv.mjs';
import {inspectPteReadOnly, DISCOVERY_STEPS} from '../core/pte_readonly_pipeline.mjs';

const hash = input => createHash('sha256').update(input,'utf8').digest('hex');
const header='DSC_INSTITUCION,DSC_RUC,COD_UBICACION\n';
const csv=header+
  '"Gobierno, "Institución" A",20100000001,150101\n'.replace(
    '"Gobierno, "Institución" A"','"Gobierno, ""Institución"" A"')+
  'Entidad B,20100000001,110101\n'+
  'Entidad C,,040101\n'+
  'Entidad sin RUC,,150102\n';
const request={request_ref:'fixture-only-001',business_code:'SALY',
  source_id:'PE-PTE',source_version:'2026-08',scope_key:'LIMA_ICA'};
const policy={business_code:'SALY',source_id:'PE-PTE',scope_key:'LIMA_ICA',
  policy_ref:'fixture://lf_global_config/SALY_DISCOVERY/PTE_POLICY_V1',
  policy_version:'v1',allowed_effect:'READ_ONLY',
  ubigeo_prefixes:['15','11'],
  transport:{max_attempts:2,max_rows:20,max_bytes:8192,timeout_ms:40}};
const source={source_id:'PE-PTE',source_version:'2026-08',rights_status:'PERSISTENCIA_PERMITIDA',
  rights_evidence_ref:'saly.evidencias:SALY-PTE-L39-CAPTURE-001',
  rights_checked_at:'2026-11-21',license_code:'ODC-BY',
  attribution:'PCM — Plataforma Nacional de Datos Abiertos',
  source_ref:'fixture://source-with-rights',
  habilitada:true,persist_business_data:true,
  runtime_status:'PILOT_BOOTSTRAP_ONLY_NO_RUNTIME',
  resource_url:'https://www.datosabiertos.gob.pe/sites/default/files/01%20listado_entidades_2026_08.csv'};
const normalized=normalizePteCsv(csv,{source_id:'PE-PTE',scope_key:'LIMA_ICA',
  ubigeo_prefixes:['15','11']});
const expectedHash=hash(normalized.capture);
assert.equal(normalized.total,4);
assert.equal(normalized.rows.length,3);
assert.equal(normalized.rows[0].nombre,'Gobierno, "Institución" A');
assert.equal(normalized.rows[0].ruc,normalized.rows[1].ruc);
assert.equal(normalized.rows[2].ruc,null);
const readback={source_id:'PE-PTE',source_version:'2026-08',scope_key:'LIMA_ICA',
  found:true,recorded_hash:expectedHash,stored_count:3,matched_count:3,
  readback_ref:'fixture://SQL-independent-readback'};

function providers(patch={}){
  const counters={loadPolicy:0,loadSource:0,fetchCsv:0,readback:0};
  return {counters,
    loadPolicy: async (...args) => {counters.loadPolicy++;return patch.loadPolicy?
       patch.loadPolicy(...args):structuredClone(policy);},
    loadSource: async (...args) => {counters.loadSource++;return patch.loadSource?
       patch.loadSource(...args):structuredClone(source);},
    fetchCsv: async (...args) => {counters.fetchCsv++;return patch.fetchCsv?
       patch.fetchCsv(...args):{status:200,content_type:'text/csv',body:csv};},
    readback: async args => {counters.readback++;
      assert.equal(args.business_code,'SALY');
      assert.equal(args.expected_rows.length,3);
      return patch.readback?patch.readback(args):structuredClone(readback);}
  };
}
const check = async (name, r, p, status, code=null) => {
  const input=structuredClone(r);
  const result=await inspectPteReadOnly(r,p);
  assert.equal(result.state,status,name);
  assert.equal(result.reason,code,name);
  assert.equal(result.flow_terminated,true,name);
  assert.equal(result.db_write_confirmed,false,name);
  assert.equal(result.commercial_runtime_enabled,false,name);
  assert.equal(result.mode,'READ_ONLY',name);
  assert.equal(result.events.at(-1).stage,'CLOSE_RECEIPT',name);
  assert.ok(result.events.length>0,name);
  assert.deepEqual(r,input,'request mutated: '+name);
  assert.equal(Object.hasOwn(result,'rows'),false,'raw rows must not leak: '+name);
  assert.equal(Object.hasOwn(result,'body'),false,'raw CSV must not leak: '+name);
  return result;
};
let verified=0;
async function test(name,r,p,status,code=null){
  const v=await check(name,r,p,status,code);verified++;return v;
}
const ok=await test('identical baseline',request,providers(),'SNAPSHOT_IDENTICAL');
assert.equal(ok.capture_sha256,expectedHash);
assert.equal(ok.observed_count,3);
assert.equal(ok.source_total,4);
assert.equal(ok.policy_ref,policy.policy_ref);
assert.deepEqual(DISCOVERY_STEPS.map(s=>s),ok.events.map(x=>x.stage));
await test('BOM source',request,providers({fetchCsv:()=>({
  status:200,content_type:'text/csv; charset=utf-8',body:'\uFEFF'+csv
})}),'SNAPSHOT_IDENTICAL');
await test('new version candidate',request,providers({readback:()=>({
  ...readback,found:false,recorded_hash:null,stored_count:0,matched_count:0
})}),'NEW_SNAPSHOT_CANDIDATE');
await test('version collision',request,providers({readback:()=>({
  ...readback,recorded_hash:'0'.repeat(64)
})}),'BLOCKED','DISCOVERY_SAME_VERSION_CONTENT_CHANGED');
await test('wrong count',request,providers({readback:()=>({
  ...readback,stored_count:2
})}),'BLOCKED','DISCOVERY_READBACK_INCONSISTENT');
await test('wrong matched count',request,providers({readback:()=>({
  ...readback,matched_count:2
})}),'BLOCKED','DISCOVERY_READBACK_INCONSISTENT');
await test('foreign source readback',request,providers({readback:()=>({
  ...readback,source_id:'LF-OTHER'
})}),'BLOCKED','DISCOVERY_READBACK_NOT_VERIFIED');
await test('no readback ref',request,providers({readback:()=>({
  ...readback,readback_ref:''
})}),'BLOCKED','DISCOVERY_READBACK_NOT_VERIFIED');
await test('new snapshot inconsistent',request,providers({readback:()=>({
  ...readback,found:false
})}),'BLOCKED','DISCOVERY_READBACK_INCONSISTENT');
const noProfile=providers();
await test('unrelated source rejected', {...request,source_id:'SUNAT'},noProfile,'BLOCKED','DISCOVERY_UNSUPPORTED_OR_INCOMPLETE_REQUEST');
assert.equal(noProfile.counters.loadPolicy,0);
const noPolicy=providers({loadPolicy:()=>({...policy,business_code:'LF'})});
await test('no cross-business policy',request,noPolicy,'BLOCKED','DISCOVERY_POLICY_NOT_READY');
assert.equal(noPolicy.counters.loadSource,0);
await test('missing policy limits',request,providers({loadPolicy:()=>({
  ...policy,transport:{}
})}),'BLOCKED','DISCOVERY_POLICY_NOT_READY');
await test('policy without version',request,providers({loadPolicy:()=>({
  ...policy,policy_version:''
})}),'BLOCKED','DISCOVERY_POLICY_NOT_READY');
await test('duplicate geographic prefix',request,providers({loadPolicy:()=>({
  ...policy,ubigeo_prefixes:['15','15']
})}),'BLOCKED','DISCOVERY_POLICY_NOT_READY');
const denied=providers({loadSource:()=>({...source,rights_evidence_ref:null})});
await test('no source rights proof',request,denied,'BLOCKED','DISCOVERY_SOURCE_AUTHORITY_BLOCK');
assert.equal(denied.counters.fetchCsv,0);
await test('not enabled source',request,providers({loadSource:()=>({
  ...source,habilitada:false
})}),'BLOCKED','DISCOVERY_SOURCE_AUTHORITY_BLOCK');
await test('source version mismatch',request,providers({loadSource:()=>({
  ...source,source_version:'2026-09'
})}),'BLOCKED','DISCOVERY_SOURCE_AUTHORITY_BLOCK');
await test('url credential denied',request,providers({loadSource:()=>({
  ...source,resource_url:'https://fake@www.datosabiertos.gob.pe/sites/default/files/list.csv'
})}),'BLOCKED','DISCOVERY_SOURCE_URI_DENIED');
await test('url foreign host denied',request,providers({loadSource:()=>({
  ...source,resource_url:'https://evil.example.com/sites/default/files/list.csv'
})}),'BLOCKED','DISCOVERY_SOURCE_URI_DENIED');
const forbiddenHttp=providers({fetchCsv:()=>({
  status:403,content_type:'text/html',body:'denied'
})});
await test('forbidden no retry',request,forbiddenHttp,'BLOCKED','DISCOVERY_HTTP_STATUS_403');
assert.equal(forbiddenHttp.counters.fetchCsv,1);
await test('wrong content type',request,providers({fetchCsv:()=>({
  status:200,content_type:'text/html',body:'<html></html>'
})}),'BLOCKED','DISCOVERY_CONTENT_TYPE_DENIED');
await test('empty body',request,providers({fetchCsv:()=>({
  status:200,content_type:'text/csv',body:''
})}),'BLOCKED','DISCOVERY_EMPTY_BODY');
await test('too large',request,providers({loadPolicy:()=>({
  ...policy,transport:{...policy.transport,max_bytes:20}
})}),'BLOCKED','DISCOVERY_BODY_TOO_LARGE');
await test('excessive rows',request,providers({loadPolicy:()=>({
  ...policy,transport:{...policy.transport,max_rows:2}
})}),'BLOCKED','DISCOVERY_ROW_LIMIT_EXCEEDED');
await test('invalid CSV header',request,providers({fetchCsv:()=>({
  status:200,content_type:'text/csv',body:'not csv'
})}),'BLOCKED','PTE_CSV_HEADER');
await test('missing scope',request,providers({fetchCsv:()=>({
  status:200,content_type:'text/csv',body:header+'Entidad fuera,20100000001,040101\n'
})}),'BLOCKED','DISCOVERY_NO_ROWS_IN_SCOPE');
const transient=providers({fetchCsv:(_)=> transient.counters.fetchCsv===1 ?
  {status:503,body:'transient'}:{status:200,content_type:'text/csv',body:csv}});
await test('retry 503 then succeed',request,transient,'SNAPSHOT_IDENTICAL');
assert.equal(transient.counters.fetchCsv,2);
const exhausted=providers({fetchCsv:()=>({status:429,body:'limited'})});
await test('retry 429 exhausted',request,exhausted,'BLOCKED','DISCOVERY_HTTP_STATUS_429');
assert.equal(exhausted.counters.fetchCsv,2);
const timeoutProviders=providers({
 loadPolicy:()=>({...policy,transport:{...policy.transport,max_attempts:1,timeout_ms:10}}),
 fetchCsv:()=>new Promise(()=>{})
});
await test('deadline must terminate hanging provider',request,timeoutProviders,'BLOCKED','DISCOVERY_TIMEOUT');
assert.equal(timeoutProviders.counters.fetchCsv,1);
await test('policy loader fault',request,providers({loadPolicy:()=>{throw Error('secret failure')}}),'BLOCKED','DISCOVERY_UNEXPECTED_FAILURE');
await test('readback query fault',request,providers({readback:()=>{throw Error('query failed')}}),'BLOCKED','DISCOVERY_UNEXPECTED_FAILURE');
await test('missing dependencies',request,{},'BLOCKED','DISCOVERY_PROVIDER_MISSING');
console.log('PASS_AI_SALES_DISCOVERY_PTE_E2E '+verified+' scenarios; no profile, no writes, every exit terminal');

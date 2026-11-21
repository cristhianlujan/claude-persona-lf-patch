// AI Sales discovery skill core: read-only. No Router, profile, DB or CRM effects.
// A caller supplies trusted-policy/source/readback providers; the skill cannot
// authenticate that caller itself. The existing PTE CSV parser is reused.
import {createHash} from 'node:crypto';
import {resolveSourceAdapter} from '../adapters/registry.mjs';

const digest = s => createHash('sha256').update(s,'utf8').digest('hex');
const obj = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const nonempty = x => typeof x === 'string' && x.trim().length > 0;
const count = x => Number.isSafeInteger(x) && x >= 0;
const hex = x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x);
const fail = code => {throw Object.assign(new Error(code),{code});};
export const DISCOVERY_STEPS = Object.freeze([
 'ADMIT_REQUEST','RESOLVE_BUSINESS_POLICY','CHECK_SOURCE_AUTHORITY',
 'FETCH_SOURCE','NORMALIZE_SOURCE','COMPARE_READBACK','CLOSE_RECEIPT'
]);
function validatePolicy(p,r){
 if(!obj(p) || p.business_code!==r.business_code ||
    p.source_id!==r.source_id || p.scope_key!==r.scope_key ||
    !nonempty(p.policy_ref) || !nonempty(p.policy_version) ||
    p.allowed_effect!=='READ_ONLY' || !obj(p.transport) ||
    !Number.isSafeInteger(p.transport.max_attempts) || p.transport.max_attempts<1 ||
    !Number.isSafeInteger(p.transport.max_bytes) || p.transport.max_bytes<1 ||
    !Number.isSafeInteger(p.transport.max_rows) || p.transport.max_rows<1 ||
    !Number.isSafeInteger(p.transport.timeout_ms) || p.transport.timeout_ms<1)
   fail('DISCOVERY_POLICY_NOT_READY');
}
function compareReadback(b,r,n,hash) {
 if(!obj(b) || b.source_id!==r.source_id ||
    b.source_version!==r.source_version || b.scope_key!==r.scope_key ||
    typeof b.found!=='boolean' || !nonempty(b.readback_ref))
    fail('DISCOVERY_READBACK_NOT_VERIFIED');
 if(!b.found){
   if(b.recorded_hash!==null || b.stored_count!==0 || b.matched_count!==0)
     fail('DISCOVERY_READBACK_INCONSISTENT');
   return 'NEW_SNAPSHOT_CANDIDATE';
 }
 if(!hex(b.recorded_hash) || !count(b.stored_count) ||
    !count(b.matched_count) || b.matched_count>b.stored_count ||
    b.matched_count>n)
   fail('DISCOVERY_READBACK_INCONSISTENT');
 if(b.recorded_hash!==hash) fail('DISCOVERY_SAME_VERSION_CONTENT_CHANGED');
 if(b.stored_count!==n || b.matched_count!==n)
   fail('DISCOVERY_READBACK_INCONSISTENT');
 return 'SNAPSHOT_IDENTICAL';
}

export async function inspectDiscoveryReadOnly(request, providers) {
 const events=[];
 const receipt={
   schema_version:'ai-sales-discovery-skill/v1', mode:'READ_ONLY',
   flow_terminated:true, db_write_confirmed:false, commercial_runtime_enabled:false,
   state:'BLOCKED', reason:null, observed_count:null, source_total:null,
   selected_count:null, capture_sha256:null, request_ref:null,
   business_code:null, source_id:null, source_version:null, scope_key:null,
   policy_ref:null, source_ref:null, readback_ref:null, events
 };
 let stage='ADMIT_REQUEST';
 const mark=(name,code)=>{stage=name;events.push(Object.freeze({stage:name,code}));};
 try {
   if(!obj(request) || !nonempty(request.business_code) ||
      !nonempty(request.source_id) || !nonempty(request.source_version) ||
      !nonempty(request.scope_key) || !nonempty(request.request_ref) ||
      !resolveSourceAdapter(request.source_id))
     fail('DISCOVERY_UNSUPPORTED_OR_INCOMPLETE_REQUEST');
   Object.assign(receipt,{
     request_ref:request.request_ref,business_code:request.business_code,
     source_id:request.source_id,source_version:request.source_version,scope_key:request.scope_key
   });
   mark('ADMIT_REQUEST','PASS');
   if(!obj(providers) || typeof providers.loadPolicy!=='function' ||
      typeof providers.loadSource!=='function' ||
      typeof providers.fetchCsv!=='function' ||
      typeof providers.readback!=='function')
     fail('DISCOVERY_PROVIDER_MISSING');
   const policy=await providers.loadPolicy({
     business_code:request.business_code,source_id:request.source_id,
     scope_key:request.scope_key
   });
   validatePolicy(policy,request);
   const adapter=resolveSourceAdapter(request.source_id);
   adapter.validatePolicy(policy,request);
   receipt.policy_ref=policy.policy_ref;
   mark('RESOLVE_BUSINESS_POLICY','PASS');
   const source=await providers.loadSource({
     source_id:request.source_id,source_version:request.source_version,
     business_code:request.business_code
   });
   const url=adapter.validateSource(source,request);
   receipt.source_ref=source.source_ref;
   mark('CHECK_SOURCE_AUTHORITY','PASS');

   let response=null;
   for(let attempt=1;attempt<=policy.transport.max_attempts;attempt++){
     const controller=new AbortController();
     let handle;
     const timeout=new Promise((_,reject)=>{
       handle=setTimeout(()=>{
         controller.abort();
         reject(Object.assign(new Error('DISCOVERY_TIMEOUT'),{code:'DISCOVERY_TIMEOUT'}));
       },policy.transport.timeout_ms);
     });
     try{
       response=await Promise.race([
         providers.fetchCsv({url,attempt,signal:controller.signal}),timeout
       ]);
       if(!obj(response) || !Number.isInteger(response.status))
         fail('DISCOVERY_HTTP_RESPONSE_INVALID');
       if([408,429,502,503,504].includes(response.status) &&
          attempt<policy.transport.max_attempts){
         mark('FETCH_SOURCE','RETRY_TRANSIENT_HTTP');
         continue;
       }
       if(response.status!==200)fail('DISCOVERY_HTTP_STATUS_'+response.status);
       if(!nonempty(response.content_type) ||
          !/^(text\/csv|application\/csv|application\/octet-stream)(?:\s*;|$)/i.test(response.content_type))
         fail('DISCOVERY_CONTENT_TYPE_DENIED');
       if(typeof response.body!=='string' || !response.body)
         fail('DISCOVERY_EMPTY_BODY');
       if(Buffer.byteLength(response.body,'utf8')>policy.transport.max_bytes)
         fail('DISCOVERY_BODY_TOO_LARGE');
       break;
     } catch(e) {
       if(e?.code==='DISCOVERY_TIMEOUT' &&
          attempt<policy.transport.max_attempts){
         mark('FETCH_SOURCE','RETRY_TIMEOUT');continue;
       }
       throw e;
     } finally{clearTimeout(handle);}
   }
   if(!response || response.status!==200)fail('DISCOVERY_FETCH_FAILED');
   mark('FETCH_SOURCE','PASS');
   const normalized=adapter.normalize(response.body,policy,request);
   if(!count(normalized.total) ||
      normalized.total>policy.transport.max_rows ||
      normalized.rows.length>policy.transport.max_rows)
     fail('DISCOVERY_ROW_LIMIT_EXCEEDED');
   if(normalized.rows.length===0)fail('DISCOVERY_NO_ROWS_IN_SCOPE');
   const hash=digest(normalized.capture);
   Object.assign(receipt,{
     source_total:normalized.total, selected_count:normalized.rows.length,
     observed_count:normalized.rows.length, capture_sha256:hash
   });
   mark('NORMALIZE_SOURCE','PASS');
   const snapshot=await providers.readback({
     business_code:request.business_code,source_id:request.source_id,
     scope_key:request.scope_key,source_version:request.source_version,
     capture_sha256:hash,expected_rows:normalized.rows
   });
   const outcome=compareReadback(snapshot,request,normalized.rows.length,hash);
   receipt.readback_ref=snapshot.readback_ref;
   mark('COMPARE_READBACK',outcome);
   receipt.state=outcome; receipt.reason=null;
   mark('CLOSE_RECEIPT','TERMINAL_READ_ONLY');
 } catch(e){
   receipt.state='BLOCKED';
   receipt.reason=typeof e?.code==='string' ? e.code :
      (typeof e?.message==='string' && /^PTE_[A-Z_]+$/.test(e.message) ?
       e.message:'DISCOVERY_UNEXPECTED_FAILURE');
   mark(stage,'BLOCKED:'+receipt.reason);
   mark('CLOSE_RECEIPT','TERMINAL_BLOCK');
 }
 Object.freeze(events);
 return Object.freeze(receipt);
}

// Compatibility with the initial PTE-only proof; shared callers use the generic entrypoint.
export const inspectPteReadOnly=inspectDiscoveryReadOnly;

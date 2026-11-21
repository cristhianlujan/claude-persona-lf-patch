// Source-specific adapter: PTE PCM. No direct network, DB or execution access.
import {normalizePteCsv} from '../../../docs/saly/ventas/candidate/pte/normalize_pte_csv.mjs';

const obj = x => x!==null && typeof x==='object' && !Array.isArray(x);
const value = x => typeof x==='string' && x.trim().length>0;
const reject = code => {throw Object.assign(new Error(code),{code});};
function validatePolicy(p) {
 if(!obj(p) || !Array.isArray(p.ubigeo_prefixes) ||
    p.ubigeo_prefixes.length===0 ||
    p.ubigeo_prefixes.some(x=>typeof x!=='string'||!/^[0-9]{2}$/.test(x)) ||
    new Set(p.ubigeo_prefixes).size!==p.ubigeo_prefixes.length)
   reject('DISCOVERY_POLICY_NOT_READY');
}
function validateSource(s,r) {
 if(!obj(s) || s.source_id!==r.source_id ||
    s.source_version!==r.source_version ||
    !value(s.source_ref) || !value(s.rights_evidence_ref) ||
    !value(s.rights_checked_at) || !value(s.license_code) ||
    !value(s.attribution) ||
    s.habilitada!==true || s.persist_business_data!==true ||
    s.rights_status!=='PERSISTENCIA_PERMITIDA' ||
    s.runtime_status!=='PILOT_BOOTSTRAP_ONLY_NO_RUNTIME')
    reject('DISCOVERY_SOURCE_AUTHORITY_BLOCK');
 let u;
 try{u=new URL(s.resource_url);}catch{reject('DISCOVERY_SOURCE_URI_DENIED');}
 if(u.protocol!=='https:' || u.hostname!=='www.datosabiertos.gob.pe' ||
    u.port || u.username || u.password || u.search || u.hash ||
    !u.pathname.startsWith('/sites/default/files/') ||
    !u.pathname.toLowerCase().endsWith('.csv'))
    reject('DISCOVERY_SOURCE_URI_DENIED');
 return u.href;
}
function normalize(body,policy,request) {
 return normalizePteCsv(body.replace(/^\uFEFF/,''),{
   source_id:request.source_id,scope_key:request.scope_key,
   ubigeo_prefixes:policy.ubigeo_prefixes
 });
}
export const PTE_CSV_ADAPTER=Object.freeze({
 adapter_code:'AI_SALES_PTE_CSV_V1',
 source_id:'PE-PTE',validatePolicy,validateSource,normalize
});

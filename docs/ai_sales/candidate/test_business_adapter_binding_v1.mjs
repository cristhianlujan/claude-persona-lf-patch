import assert from 'node:assert/strict';
import {planBusinessAdapterBinding} from './business_adapter_binding_v1.mjs';
const base = {
 routerBusiness:{source:'ACT-0001_EXTERNAL_TRUSTED_HANDOFF',business_code:'SALY'},
 businessCatalog:[{business_code:'LF',status:'ENABLED'},{business_code:'SALY',status:'ENABLED'}],
 businessPolicy:{business_code:'SALY',policy_ref:'public.lf_global_config:SALY_DISCOVERY/PTE_POLICY_V1',version:'v1',sources:['PE-PTE'],effect:'READ_ONLY'},
 sourceAdapter:{adapter_id:'SOURCE-PE-PTE',source_id:'PE-PTE',effect:'READ_ONLY',business_specific:false},
 specialistRole:{role:'DISCOVERY',business_code:null,runtime_selected:false}
};
const changed=(k,v)=>({...base,[k]:{...base[k],...v}});
const cases=[
 ['SALY enabled shared role',base,'CANDIDATE_BINDING_ONLY'],
 ['LF not allowed to consume SALY policy',changed('routerBusiness',{business_code:'LF'}),'BUSINESS_POLICY_NOT_BOUND'],
 ['unregistered business',changed('routerBusiness',{business_code:'OTHER'}),'BUSINESS_NOT_ENABLED_OR_AMBIGUOUS'],
 ['no router binding',changed('routerBusiness',{source:'USER_INPUT'}),'MISSING_TRUSTED_ROUTER_BUSINESS'],
 ['wrong business policy',changed('businessPolicy',{business_code:'LF'}),'BUSINESS_POLICY_NOT_BOUND'],
 ['missing policy version',changed('businessPolicy',{version:''}),'BUSINESS_POLICY_NOT_BOUND'],
 ['source not permitted by business',changed('sourceAdapter',{source_id:'GOOGLE_MAPS'}),'SOURCE_ADAPTER_NOT_ALLOWED_BY_BUSINESS'],
 ['no business-specific adapter clone',changed('sourceAdapter',{business_specific:true}),'SOURCE_ADAPTER_NOT_ALLOWED_BY_BUSINESS'],
 ['no per-business profile',changed('specialistRole',{business_code:'SALY'}),'ROLE_MUST_REMAIN_SHARED_CANDIDATE'],
 ['no pretense to runtime',changed('specialistRole',{runtime_selected:true}),'ROLE_MUST_REMAIN_SHARED_CANDIDATE'],
 ['duplicate catalog', {...base,businessCatalog:[...base.businessCatalog,{business_code:'SALY',status:'ENABLED'}]},'BUSINESS_NOT_ENABLED_OR_AMBIGUOUS'],
 ['LF synthetic independent policy',{...base,routerBusiness:{...base.routerBusiness,business_code:'LF'},businessPolicy:{...base.businessPolicy,business_code:'LF',policy_ref:'FIXTURE_ONLY/LF/POLICY',sources:['SOURCE-FIXTURE']},sourceAdapter:{...base.sourceAdapter,adapter_id:'SOURCE-FIXTURE',source_id:'SOURCE-FIXTURE'}},'CANDIDATE_BINDING_ONLY']
];
for(const [name,input,expected] of cases){const copy=structuredClone(input);const result=planBusinessAdapterBinding(input);assert.equal(result.status==='BLOCKED'?result.code:result.status,expected,name);assert.equal(result.runtime_authorized,false,name);assert.deepEqual(input,copy,name);}
console.log('PASS_AI_SALES_SHARED_PROFILE_BUSINESS_BINDING '+cases.length+'/12; no runtime authority');

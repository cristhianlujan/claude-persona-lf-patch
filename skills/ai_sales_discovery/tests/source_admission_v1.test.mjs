import assert from 'node:assert/strict';
import {inspectSourceCandidate} from '../adapters/source_admission_v1.mjs';
const valid={
 source:{source_id:'PE-PTE',business_code:'SALY',source_version:'2026-08',
  format:'CSV',resource_url:'https://www.datosabiertos.gob.pe/sites/default/files/fixture.csv'},
 catalog:{source_id:'PE-PTE',source_version:'2026-08',format:'CSV',
  resource_url:'https://www.datosabiertos.gob.pe/sites/default/files/fixture.csv',
  dataset_uri:'https://www.datosabiertos.gob.pe/dataset/fixture',
  publisher:'PCM',readback_ref:'fixture://source-catalog',checked_at:'2026-11-21',
  license_status:'VERIFIED_REUSE_PERMITTED',license_code:'ODC-BY',
  license_evidence_ref:'fixture://license',personal_data_scope:'NO',declared_size_bytes:100},
 business_policy:{business_code:'SALY',effect:'READ_ONLY',
  policy_ref:'fixture://policy',approved_sources:['PE-PTE'],
  personal_data_use_approved:false,personal_data_decision_ref:null},
 technical:{max_download_bytes:1000,max_unpacked_bytes:2000,
  capability_ref:'fixture://limits',zip_streaming_verified:false,zip_test_ref:null,
  zip_entry_safety_verified:false,zip_entry_safety_ref:null,
  schema_verified:true,schema_ref:'fixture://schema',
  adapter_tested:true,adapter_test_ref:'fixture://adapter',
  billing_authorized:false,billing_decision_ref:null,
  terms_approved:false,terms_decision_ref:null}
};
const edit=(section,delta)=>({...valid,[section]:{...valid[section],...delta}});
const cases=[
 ['valid candidate, not production',valid,'SOURCE_PREFLIGHT_PASS_CANDIDATE_ONLY'],
 ['untrusted cross business',edit('source',{business_code:'LF'}),'SOURCE_NOT_ALLOWED_BY_BUSINESS'],
 ['source not on approved list',edit('business_policy',{approved_sources:['SUNAT']}),'SOURCE_NOT_ALLOWED_BY_BUSINESS'],
 ['policy grants write',edit('business_policy',{effect:'WRITE_GOVERNED'}),'SOURCE_NOT_ALLOWED_BY_BUSINESS'],
 ['catalog version mismatch',edit('catalog',{source_version:'2026-09'}),'SOURCE_CATALOG_INDEPENDENT_MATCH_MISSING'],
 ['catalog missing readback',edit('catalog',{readback_ref:''}),'SOURCE_CATALOG_INDEPENDENT_MATCH_MISSING'],
 ['credential in URL',edit('source',{resource_url:'https://user:pass@www.datosabiertos.gob.pe/sites/default/files/fixture.csv'}),'SOURCE_CATALOG_INDEPENDENT_MATCH_MISSING'],
 ['foreign host injection',edit('source',{resource_url:'https://evil.example/fixture.csv'}),'SOURCE_CATALOG_INDEPENDENT_MATCH_MISSING'],
 ['unverified license',edit('catalog',{license_status:'NOT_SPECIFIED'}),'SOURCE_LICENSE_OR_USAGE_UNRESOLVED'],
 ['no license receipt',edit('catalog',{license_evidence_ref:null}),'SOURCE_LICENSE_OR_USAGE_UNRESOLVED'],
 ['unknown personal data',edit('catalog',{personal_data_scope:'UNKNOWN'}),'SOURCE_PERSONAL_DATA_UNKNOWN'],
 ['personal data no decision',edit('catalog',{personal_data_scope:'YES'}),'SOURCE_PERSONAL_DATA_SCOPE_BLOCK'],
 ['personal data explicit decision',{...valid,catalog:{...valid.catalog,personal_data_scope:'YES'},business_policy:{...valid.business_policy,personal_data_use_approved:true,personal_data_decision_ref:'fixture://approved'}},'SOURCE_PREFLIGHT_PASS_CANDIDATE_ONLY'],
 ['no byte ceiling',edit('technical',{max_download_bytes:null}),'SOURCE_TECHNICAL_LIMITS_MISSING'],
 ['download too large',edit('catalog',{declared_size_bytes:1001}),'SOURCE_SIZE_UNVERIFIED_OR_OVER_LIMIT'],
 ['unknown size',edit('catalog',{declared_size_bytes:null}),'SOURCE_SIZE_UNVERIFIED_OR_OVER_LIMIT'],
 ['schema unavailable',edit('technical',{schema_verified:false}),'SOURCE_SCHEMA_NOT_VERIFIED'],
 ['adapter not verified',edit('technical',{adapter_tested:false}),'SOURCE_NEEDS_ADAPTER_TEST']
];
const zip={
 ...valid,
 source:{...valid.source,source_id:'SUNAT-RUC',format:'ZIP',source_version:'2026-10'},
 catalog:{...valid.catalog,source_id:'SUNAT-RUC',format:'ZIP',source_version:'2026-10',
  personal_data_scope:'POSSIBLE'},
 business_policy:{...valid.business_policy,approved_sources:['SUNAT-RUC'],
  personal_data_use_approved:true,personal_data_decision_ref:'fixture://decision'}
};
cases.push(
 ['ZIP needs stream',zip,'SOURCE_ZIP_STREAMING_NOT_PROVEN'],
 ['ZIP needs bomb and traversal gate', {...zip,technical:{...zip.technical,zip_streaming_verified:true,zip_test_ref:'fixture://stream'}},'SOURCE_ZIP_BOMB_PATH_TRAVERSAL_UNPROVEN'],
 ['ZIP safe synthetic', {...zip,technical:{...zip.technical,zip_streaming_verified:true,zip_test_ref:'fixture://stream',zip_entry_safety_verified:true,zip_entry_safety_ref:'fixture://zip-security'}},'SOURCE_PREFLIGHT_PASS_CANDIDATE_ONLY']
);
const api={
 ...valid,
 source:{...valid.source,source_id:'GOOGLE_PLACES_API_NEW',format:'API_JSON'},
 catalog:{...valid.catalog,source_id:'GOOGLE_PLACES_API_NEW',format:'API_JSON'},
 business_policy:{...valid.business_policy,approved_sources:['GOOGLE_PLACES_API_NEW']}
};
cases.push(
 ['API needs billing',api,'SOURCE_API_BILLING_BLOCK'],
 ['API needs terms',{...api,technical:{...api.technical,billing_authorized:true,billing_decision_ref:'fixture://billing'}},'SOURCE_API_TERMS_BLOCK'],
 ['API fully approved fixture only',{...api,technical:{...api.technical,billing_authorized:true,billing_decision_ref:'fixture://billing',terms_approved:true,terms_decision_ref:'fixture://terms'}},'SOURCE_PREFLIGHT_PASS_CANDIDATE_ONLY']
);
for(const [name,input,expected] of cases) {
 const before=structuredClone(input);
 const r=inspectSourceCandidate(input);
 assert.equal(r.code,expected,name);
 assert.equal(r.runtime_authorized,false,name);
 assert.equal(r.write_authorized,false,name);
 assert.equal(r.contact_authorized,false,name);
 assert.equal(r.evidence_verified_by_runtime,false,name);
 assert.deepEqual(input,before,name);
}
console.log('PASS_AI_SALES_SOURCE_PREFLIGHT '+cases.length+' fixtures, no grants or new source activation');

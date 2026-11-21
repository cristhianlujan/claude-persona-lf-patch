import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('../adapters/sunat_records_candidate.mjs',import.meta.url),'utf8');
const schema={resource_variant:'SUNAT_MONTHLY_RUC',source_version:'fixture',schema_ref:'fixture://schema',evidence_status:'FIXTURE_ONLY',encoding:'utf-8',delimiter:'|',trailing_delimiter:false,columns:['RUC','NOMBRE','ESTADO','CONDICION','UBIGEO'],field_map:{ruc:'RUC',nombre:'NOMBRE',estado:'ESTADO',condicion:'CONDICION',ubigeo:'UBIGEO'}};
const policy={business_code:'FIXTURE',policy_ref:'fixture://policy',resource_variant:schema.resource_variant,source_version:schema.source_version,allowed_effect:'READ_ONLY',ubigeo_prefixes:['15'],limits:{max_input_bytes:512,max_record_bytes:128,max_records:10,max_candidates:10}};
const header=schema.columns.join('|')+'\n';
const row='20000000001|ENTIDAD FICTICIA|ACTIVO|HABIDO|150101\n';
async function* bytes(s){yield Buffer.from(s);}
const original=(await import('../adapters/sunat_records_candidate.mjs')).inspectSunatRecordsCandidate;
async function mutant(from,to){assert.equal(source.split(from).length,2,'mutation anchor drift');return (await import('data:text/javascript;base64,'+Buffer.from(source.replace(from,to)).toString('base64'))).inspectSunatRecordsCandidate;}
let passed=0;
const badHeader=header.replace('RUC|NOMBRE','NOMBRE|RUC')+row;
await assert.rejects(()=>original(bytes(badHeader),schema,policy),e=>e.code==='SUNAT_HEADER_DRIFT');
const m1=await mutant("columns.some((x,i)=>x!==schema.columns[i])","false");
assert.equal((await m1(bytes(badHeader),schema,policy)).selected_count,1,'header mutant must expose drift');passed++;
const personal=header+row.replace('20','10');
assert.equal((await original(bytes(personal),schema,policy)).selected_count,0);
const m2=await mutant("!ruc.startsWith('20')","false");
assert.equal((await m2(bytes(personal),schema,policy)).selected_count,1,'privacy guard mutant must leak synthetic row');passed++;
const small={...policy,limits:{...policy.limits,max_candidates:1}};
const two=header+row+row.replace('20000000001','20000000002');
await assert.rejects(()=>original(bytes(two),schema,small),e=>e.code==='SUNAT_CANDIDATE_LIMIT');
const m3=await mutant('rows.length>=cap.max_candidates','false');
assert.equal((await m3(bytes(two),schema,small)).selected_count,2,'limit mutant must violate quota');passed++;
console.log('PASS_AI_SALES_SUNAT_MUTATIONS '+passed+' controls, killed by intended assertions');

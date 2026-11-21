import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm,readdir,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {deflateRawSync} from 'node:zlib';
import {inspectZipCandidate,verifyZipContentCandidate,readZipEntryCandidate} from '../adapters/zip_archive_preflight.mjs';
import {inspectSunatZipCandidate} from '../adapters/sunat_zip_candidate.mjs';
const schema={resource_variant:'SUNAT_MONTHLY_RUC',source_version:'fixture',schema_ref:'fixture://schema',evidence_status:'FIXTURE_ONLY',encoding:'utf-8',delimiter:'|',trailing_delimiter:false,columns:['RUC','NOMBRE','ESTADO','CONDICION','UBIGEO'],field_map:{ruc:'RUC',nombre:'NOMBRE',estado:'ESTADO',condicion:'CONDICION',ubigeo:'UBIGEO'}};
const policy={business_code:'FIXTURE',policy_ref:'fixture://policy',resource_variant:schema.resource_variant,source_version:schema.source_version,allowed_effect:'READ_ONLY',ubigeo_prefixes:['15'],limits:{max_input_bytes:1000000,max_record_bytes:256,max_records:10000,max_candidates:10000}};
const limits={max_download_bytes:2000000,max_central_directory_bytes:10000,max_entries:5,max_unpacked_bytes:1000000,max_entry_bytes:1000000,max_ratio:1000,timeout_ms:5000};
const header=schema.columns.join('|')+'\n',row='20000000001|EMPRESA SINTETICA|ACTIVO|HABIDO|150101\n',personal='10000000001|PERSONA SINTETICA|ACTIVO|HABIDO|150101\n';
const body=header+row+personal;
const sha=b=>createHash('sha256').update(b).digest('hex');
function crc32(b){let c=0xffffffff;for(const x of b){c^=x;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function zip(entries){let offset=0;const local=[],central=[];for(const e of entries){const name=Buffer.from(e.name),raw=Buffer.from(e.text),method=e.method??8,data=method===8?deflateRawSync(raw):raw,crc=e.crc??crc32(raw);const h=Buffer.alloc(30),c=Buffer.alloc(46);h.writeUInt32LE(0x04034b50);h.writeUInt16LE(method,8);h.writeUInt32LE(crc,14);h.writeUInt32LE(data.length,18);h.writeUInt32LE(raw.length,22);h.writeUInt16LE(name.length,26);c.writeUInt32LE(0x02014b50);c.writeUInt16LE(method,10);c.writeUInt32LE(crc,16);c.writeUInt32LE(data.length,20);c.writeUInt32LE(raw.length,24);c.writeUInt16LE(name.length,28);c.writeUInt32LE(offset,42);const part=Buffer.concat([h,name,data]);local.push(part);central.push(Buffer.concat([c,name]));offset+=part.length;}const cd=Buffer.concat(central),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(cd.length,12);end.writeUInt32LE(offset,16);return Buffer.concat([...local,cd,end]);}
const dir=await mkdtemp(join(tmpdir(),'sunat-zip-candidate-'));let passed=0;
const selected={name:'padron.txt',text:body};
async function run(label,entries,error,opts={}){const filePath=join(dir,'fixture-'+passed+'.zip'),blob=zip(entries);await writeFile(filePath,blob);const input={filePath,entryName:selected.name,archiveLimits:limits,schema,policy,...opts};if(error){await assert.rejects(()=>inspectSunatZipCandidate(input),e=>e.code===error,label);}else{const r=await inspectSunatZipCandidate(input);assert.equal(r.state,'SUNAT_ZIP_RECORDS_CANDIDATE_ONLY',label);assert.equal(r.archive_integrity_verified,true);assert.equal(r.archive.archive_sha256,sha(blob));assert.equal(r.archive.content_crc_verified,true);assert.equal(r.bytes_read,r.archive.selected_unpacked_bytes);assert.equal(r.capture_sha256,sha(JSON.stringify(r.rows)));assert.equal(r.schema_authority_verified,false);assert.equal(r.source_license_verified,false);assert.equal(r.runtime_authorized,false);assert.equal(r.write_authorized,false);assert.equal(r.contact_authorized,false);assert.equal(r.identity_verified,false);assert.ok(!JSON.stringify(r).includes('PERSONA SINTETICA'));assert.ok(Object.isFrozen(r.rows));assert.ok(Object.isFrozen(r.archive));assert.deepEqual(await readFile(filePath),blob);passed++;return r;}assert.deepEqual(await readFile(filePath),blob);passed++;}
try{
 const a=await run('deflate real integration',[selected],null);assert.equal(a.selected_count,1);assert.equal(a.records_read,2);assert.equal(a.excluded_non_legal_prefix,1);
 await run('STORE real integration',[{...selected,method:0}],null);
 await run('companion good after selected',[selected,{name:'readme.txt',text:'note'}],null);
 await run('companion bad after selected must block entire result',[selected,{name:'readme.txt',text:'note',crc:0}],'ZIP_CRC_MISMATCH');
 await run('selected CRC invalid',[{...selected,crc:0}],'ZIP_CRC_MISMATCH');
 await run('header drift over actual ZIP',[{...selected,text:body.replace('RUC|NOMBRE','NOMBRE|RUC')}],'SUNAT_HEADER_DRIFT');
 await run('candidate limit over actual ZIP',[{...selected,text:body+row.replace('20000000001','20000000002')}],'SUNAT_CANDIDATE_LIMIT',{policy:{...policy,limits:{...policy.limits,max_candidates:1}}});
 await run('entry selection exact',[{...selected,name:'other.txt'}],'ZIP_SELECTED_ENTRY_MISSING');
 await run('unsafe requested path',[selected],'ZIP_ENTRY_PATH_UNSAFE',{entryName:'../padron.txt'});
 await run('timeout required',[selected],'ZIP_TIMEOUT_POLICY_INVALID',{archiveLimits:{...limits,timeout_ms:null}});
 await run('schema mismatch precedes file access',[selected],'SUNAT_SCHEMA_CONTRACT_INVALID',{filePath:'/unavailable',schema:{...schema,schema_ref:''}});
 const large=header+Array.from({length:4000},(_,i)=>row.replace('20000000001','20'+String(i).padStart(9,'0'))).join('');
 const largeResult=await run('multiple decompressed chunks and no lost records',[{...selected,text:large}],null);assert.equal(largeResult.selected_count,4000);
 await run('elapsed deadline blocks archive',[{...selected,text:large}],'ZIP_OPERATION_TIMEOUT',{archiveLimits:{...limits,timeout_ms:1}});
 const file=join(dir,'compat.zip');await writeFile(file,zip([selected]));const metadata=await inspectZipCandidate(file,limits);assert.equal(metadata.state,'ZIP_METADATA_CANDIDATE');assert.equal(Object.hasOwn(metadata,'entry_result'),false);const verify=await verifyZipContentCandidate(file,limits);assert.equal(verify.state,'ZIP_CONTENT_VERIFIED_CANDIDATE');assert.equal(verify.actual_unpacked_bytes,Buffer.byteLength(body));passed++;
 await assert.rejects(()=>readZipEntryCandidate(file,limits,'padron.txt',async()=>({early:true})),e=>e.code==='ZIP_ENTRY_CONSUMER_INCOMPLETE');passed++;
 await assert.rejects(()=>inspectSunatZipCandidate(null),e=>e.code==='SUNAT_ZIP_CONTRACT_INVALID');passed++;
 assert.equal((await readdir(dir)).length,passed-2,'no extracted files');
 console.log('PASS_AI_SALES_SUNAT_ZIP_INTEGRATION '+passed+' cases; CRC barrier, bounded streaming, no writes');
 // Mutation: remove only the CRC gate. The exact companion fixture must now
 // return a candidate, proving the original rejection was not accidental.
 const mutdir=join(dir,'mutation');await mkdir(mutdir);
 for(const name of ['zip_archive_preflight.mjs','zip_content_verify.mjs','sunat_records_candidate.mjs','sunat_zip_candidate.mjs']){
  let source=await readFile(new URL('../adapters/'+name,import.meta.url),'utf8');
  if(name==='zip_content_verify.mjs'){
   const guard="if(((crc^0xffffffff)>>>0)!==e.crc)fail('ZIP_CRC_MISMATCH');";
   assert.equal(source.split(guard).length,2);source=source.replace(guard,'if(false)fail(\'ZIP_CRC_MISMATCH\');');
  }
  await writeFile(join(mutdir,name),source);
 }
 const mutant=(await import(pathToFileURL(join(mutdir,'sunat_zip_candidate.mjs')).href)).inspectSunatZipCandidate;
 const badFile=join(dir,'bad-companion.zip');await writeFile(badFile,zip([selected,{name:'readme.txt',text:'note',crc:0}]));
 const input={filePath:badFile,entryName:selected.name,archiveLimits:limits,schema,policy};
 await assert.rejects(()=>inspectSunatZipCandidate(input),e=>e.code==='ZIP_CRC_MISMATCH');
 assert.equal((await mutant(input)).selected_count,1,'CRC mutant must expose invalid archive');
 console.log('PASS_AI_SALES_SUNAT_ZIP_MUTATION 1 CRC barrier mutation killed by intended assertion');
}finally{await rm(dir,{recursive:true,force:true});}

import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,symlink,rm,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {deflateRawSync} from 'node:zlib';
import {inspectZipCandidate,verifyZipContentCandidate} from '../adapters/zip_archive_preflight.mjs';
const limits={max_download_bytes:20000,max_central_directory_bytes:2000,max_entries:5,max_unpacked_bytes:1000,max_entry_bytes:800,max_ratio:50};
const dir=await mkdtemp(join(tmpdir(),'ai-sales-zip-content-'));
let passed=0;
function fixture(entries=[{}]){
 const local=[],central=[];let offset=0;
 for(const e of entries){
  const name=Buffer.from(e.name??'padron.txt'),raw=Buffer.from(e.empty?'':'hello');
  const method=e.method??8,flags=e.flags??0;
  const payload=method===8?deflateRawSync(raw):raw;
  const data=Buffer.concat([payload,Buffer.alloc(e.trailing??0)]);
  const crc=e.crc??(e.empty?0:0x3610a686),size=e.size??raw.length;
  const h=Buffer.alloc(30);h.writeUInt32LE(0x04034b50);h.writeUInt16LE(20,4);h.writeUInt16LE(flags,6);h.writeUInt16LE(method,8);h.writeUInt32LE(crc,14);h.writeUInt32LE(data.length,18);h.writeUInt32LE(size,22);h.writeUInt16LE(name.length,26);
  const c=Buffer.alloc(46);c.writeUInt32LE(0x02014b50);c.writeUInt16LE(20,4);c.writeUInt16LE(20,6);c.writeUInt16LE(flags,8);c.writeUInt16LE(method,10);c.writeUInt32LE(crc,16);c.writeUInt32LE(data.length,20);c.writeUInt32LE(size,24);c.writeUInt16LE(name.length,28);c.writeUInt32LE(e.offset??offset,42);
  const part=Buffer.concat([h,name,data]);local.push(part);central.push(Buffer.concat([c,name]));offset+=part.length;
 }
 const cd=Buffer.concat(central),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(cd.length,12);end.writeUInt32LE(offset,16);
 return Buffer.concat([...local,cd,end]);
}
async function probe(label,blob,expected,policy=limits,bytes=5){
 const file=join(dir,'fixture-'+passed+'.zip');await writeFile(file,blob);
 if(expected===null){
  const result=await verifyZipContentCandidate(file,policy);
  assert.equal(result.state,'ZIP_CONTENT_VERIFIED_CANDIDATE',label);assert.equal(result.content_crc_verified,true,label);assert.equal(result.actual_unpacked_bytes,bytes,label);assert.equal(result.archive_sha256,createHash('sha256').update(blob).digest('hex'),label);
  assert.equal(result.extracted,false,label);assert.equal(result.rows_parsed,false,label);assert.equal(result.runtime_authorized,false,label);assert.equal(result.write_authorized,false,label);assert.equal(result.source_license_verified,false,label);
 }else await assert.rejects(()=>verifyZipContentCandidate(file,policy),e=>e.code===expected,label);
 assert.deepEqual(await readFile(file),blob,label);passed++;
}
try{
 await probe('deflated',fixture(),null);
 await probe('stored',fixture([{method:0}]),null);
 await probe('empty',fixture([{empty:true,method:0}]),null,limits,0);
 await probe('two entries',fixture([{name:'a.txt'},{name:'b.txt',method:0}]),null,limits,10);
 await probe('CRC wrong in local and central',fixture([{crc:0}]),'ZIP_CRC_MISMATCH');
 await probe('forged short declaration',fixture([{size:1}]),'ZIP_ACTUAL_OUTPUT_LIMIT');
 await probe('forged large declaration',fixture([{size:6}]),'ZIP_ACTUAL_LENGTH_MISMATCH');
 const mismatch=fixture();mismatch.writeUInt32LE(0,14);await probe('local CRC mismatch',mismatch,'ZIP_LOCAL_CENTRAL_MISMATCH');
 const name=fixture();name[30]^=1;await probe('local name mismatch',name,'ZIP_LOCAL_CENTRAL_MISMATCH');
 await probe('descriptor unsupported',fixture([{flags:8}]),'ZIP_CONTENT_FLAGS_UNSUPPORTED');
 await probe('extra deflate bytes',fixture([{trailing:2}]),'ZIP_DEFLATE_TRAILING_BYTES');
 const broken=fixture();broken.fill(255,30+'padron.txt'.length,broken.readUInt32LE(18)+30+'padron.txt'.length);await probe('bad deflate',broken,'ZIP_DECOMPRESSION_INVALID');
 await probe('stored size mismatch',fixture([{method:0,size:1}]),'ZIP_STORED_LENGTH_MISMATCH');
 await probe('local offset mismatch',fixture([{offset:1}]),'ZIP_LOCAL_RANGE_INVALID');
 await probe('unpacked aggregate ceiling',fixture([{name:'a.txt'},{name:'b.txt'}]),'ZIP_TOTAL_UNPACKED_EXCEEDS_LIMIT',{...limits,max_unpacked_bytes:9});
 await probe('path traversal',fixture([{name:'../escape.txt'}]),'ZIP_ENTRY_PATH_UNSAFE');
 const metaFile=join(dir,'metadata-only.zip');await writeFile(metaFile,fixture([{crc:0}]));const meta=await inspectZipCandidate(metaFile,limits);assert.equal(meta.state,'ZIP_METADATA_CANDIDATE');assert.equal(Object.hasOwn(meta,'content_crc_verified'),false);passed++;
 const link=join(dir,'link.zip');await symlink(metaFile,link);await assert.rejects(()=>verifyZipContentCandidate(link,limits),e=>e.code==='ZIP_INPUT_NOT_FOUND');passed++;
 assert.equal((await readdir(dir)).length,passed,'no extra extracted files');
 console.log('PASS_AI_SALES_ZIP_CONTENT_VERIFY '+passed+' cases; no extraction and no runtime authorization');
}finally{await rm(dir,{recursive:true,force:true});}

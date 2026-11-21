// Synthetic ZIPs only. Never fetch or open the real SUNAT padrón.
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {inspectZipCandidate} from '../adapters/zip_archive_preflight.mjs';
const cap={
 max_download_bytes:20000,max_central_directory_bytes:2000,max_entries:5,
 max_unpacked_bytes:1000,max_entry_bytes:800,max_ratio:50
};
function makeZip(entries){
 const local=[],central=[];let offset=0;
 for(const ent of entries){
  const name=Buffer.from(ent.name??'padron.csv','utf8');
  const size=ent.compressed??5,uncompressed=ent.uncompressed??5;
  const method=ent.method??0,flags=ent.flags??0,attrs=ent.attrs??0;
  const header=Buffer.alloc(30);
  header.writeUInt32LE(0x04034b50,0);header.writeUInt16LE(20,4);
  header.writeUInt16LE(flags,6);header.writeUInt16LE(method,8);
  header.writeUInt32LE(size,18);header.writeUInt32LE(uncompressed,22);
  header.writeUInt16LE(name.length,26);
  const part=Buffer.concat([header,name,Buffer.alloc(size,0x51)]);
  local.push(part);
  const center=Buffer.alloc(46);
  center.writeUInt32LE(0x02014b50,0);
  center.writeUInt16LE(20,4);center.writeUInt16LE(20,6);
  center.writeUInt16LE(flags,8);center.writeUInt16LE(method,10);
  center.writeUInt32LE(size,20);center.writeUInt32LE(uncompressed,24);
  center.writeUInt16LE(name.length,28);
  center.writeUInt32LE(attrs>>>0,38);
  center.writeUInt32LE(offset,42);
  central.push(Buffer.concat([center,name]));
  offset+=part.length;
 }
 const cd=Buffer.concat(central);
 const end=Buffer.alloc(22);
 end.writeUInt32LE(0x06054b50,0);
 end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);
 end.writeUInt32LE(cd.length,12);end.writeUInt32LE(offset,16);
 return Buffer.concat([...local,cd,end]);
}
const d=await mkdtemp(join(tmpdir(),'ai-sales-sunat-zip-fixture-'));
let passes=0;
async function probe(label,blob,policy,code){
 const file=join(d,'fixture-'+(passes+1)+'.zip');
 await writeFile(file,blob);
 const unmodified=Buffer.from(blob);
 if(code===null){
  const value=await inspectZipCandidate(file,policy);
  assert.equal(value.state,'ZIP_METADATA_CANDIDATE',label);
  assert.equal(value.runtime_authorized,false,label);
  assert.equal(value.write_authorized,false,label);
  assert.equal(value.source_license_verified,false,label);
  assert.equal(value.extracted,false,label);
  assert.equal(value.rows_parsed,false,label);
  assert.equal(value.archive_sha256,createHash('sha256').update(blob).digest('hex'),label);
 }else{
  await assert.rejects(()=>inspectZipCandidate(file,policy),error=>error.code===code,label);
 }
 assert.deepEqual(blob,unmodified,'modified ZIP input: '+label);
 passes++;
}
try{
 const good=makeZip([{name:'PadronRUC_202610.csv',compressed:5,uncompressed:5}]);
 await probe('one CSV no extraction',good,cap,null);
 await probe('multiple distinct CSVs',makeZip([{name:'A.csv'},{name:'B.csv'}]),cap,null);
 await probe('directory marker',makeZip([{name:'data/',compressed:0,uncompressed:0},
  {name:'data/padron.csv'}]),cap,null);
 await probe('path traversal',makeZip([{name:'../escape.csv'}]),cap,'ZIP_ENTRY_PATH_UNSAFE');
 await probe('absolute path',makeZip([{name:'/tmp/escape.csv'}]),cap,'ZIP_ENTRY_PATH_UNSAFE');
 await probe('windows backslash',makeZip([{name:'..\\escape.csv'}]),cap,'ZIP_ENTRY_PATH_UNSAFE');
 await probe('windows drive',makeZip([{name:'C:/escape.csv'}]),cap,'ZIP_ENTRY_PATH_UNSAFE');
 await probe('hidden dot segment',makeZip([{name:'x/./y.csv'}]),cap,'ZIP_ENTRY_PATH_UNSAFE');
 await probe('nested archive denied',makeZip([{name:'payload.ZIP'}]),cap,'ZIP_NESTED_ARCHIVE_UNSUPPORTED');
 await probe('duplicate filename case',makeZip([{name:'A.csv'},{name:'a.CSV'}]),cap,'ZIP_DUPLICATE_ENTRY_NAME');
 await probe('symlink',makeZip([{name:'ref.csv',attrs:(0xa000<<16)>>>0}]),cap,'ZIP_SYMLINK_DENIED');
 await probe('encrypted',makeZip([{name:'secret.csv',flags:1}]),cap,'ZIP_ENCRYPTED_DENIED');
 await probe('unsupported method',makeZip([{name:'future.csv',method:99}]),cap,'ZIP_COMPRESSION_METHOD_DENIED');
 await probe('decompression ratio bomb',makeZip([{name:'bomb.csv',uncompressed:501,compressed:1}]),cap,'ZIP_DECOMPRESSION_RATIO_BLOCK');
 await probe('declared single entry limit',makeZip([{name:'huge.csv',uncompressed:801,compressed:30}]),cap,'ZIP_SINGLE_ENTRY_TOO_LARGE');
 await probe('declared aggregate limit',makeZip([{name:'one.csv',uncompressed:600,compressed:20},{name:'two.csv',uncompressed:600,compressed:20}]),cap,'ZIP_TOTAL_UNPACKED_EXCEEDS_LIMIT');
 await probe('too many entries',makeZip(Array.from({length:6},(_,i)=>({name:i+'.csv'}))),cap,'ZIP_ENTRY_COUNT_BLOCK');
 await probe('central memory bound',good,{...cap,max_central_directory_bytes:50},'ZIP_CENTRAL_DIRECTORY_BOUNDARY');
 await probe('compressed upload quota',good,{...cap,max_download_bytes:good.length-1},'ZIP_FILE_SIZE_OR_TYPE_BLOCK');
 await probe('invalid archive',Buffer.from('not a zip file with no EOCD'),cap,'ZIP_EOCD_MISSING_OR_TRAILING_DATA');
 await probe('trailing payload',Buffer.concat([good,Buffer.from('trailer')]),cap,'ZIP_EOCD_MISSING_OR_TRAILING_DATA');
 const broken=Buffer.from(good);
 const at=broken.lastIndexOf(Buffer.from([0x50,0x4b,0x01,0x02]));
 broken.writeUInt32LE(0xdeadbeef,at);
 await probe('corrupt central directory',broken,cap,'ZIP_CENTRAL_DIRECTORY_CORRUPT');
 const zip64=Buffer.from(good);zip64.writeUInt16LE(0xffff,zip64.length-22+10);
 await probe('ZIP64 requires separate handling',zip64,cap,'ZIP64_NEEDS_SEPARATE_VALIDATION');
 const wrongCentral=Buffer.from(good);
 wrongCentral.writeUInt32LE(0xffffffff,wrongCentral.length-22+16);
 await probe('no forged central offset',wrongCentral,cap,'ZIP64_NEEDS_SEPARATE_VALIDATION');
 await probe('missing max limits',good,{...cap,max_ratio:null},'ZIP_LIMITS_UNTRUSTED_OR_MISSING');
 const weird=makeZip([{name:'a\u0000.csv'}]);
 await probe('null byte name rejected',weird,cap,'ZIP_ENTRY_PATH_UNSAFE');
 const encode=makeZip([{name:'á.csv'}]);
 const badEncoding=Buffer.from(encode);
 const mid=badEncoding.lastIndexOf(Buffer.from('á.csv','utf8'));
 badEncoding[mid]=0xff;
 await probe('invalid encoding',badEncoding,cap,'ZIP_FILENAME_ENCODING_UNSUPPORTED');
 console.log('PASS_AI_SALES_ZIP_ARCHIVE_PREFLIGHT '+passes+' synthetic ZIP cases; no extraction');
}finally{await rm(d,{recursive:true,force:true});}

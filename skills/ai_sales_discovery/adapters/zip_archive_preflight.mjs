// Bounded ZIP inspection, with optional in-memory streaming content verification.
// No network, extraction to disk, CSV parsing, CRM, DB or production authority.
import {open} from 'node:fs/promises';
import {constants} from 'node:fs';
import {verifyZipEntries} from './zip_content_verify.mjs';
import {createHash} from 'node:crypto';
import {TextDecoder} from 'node:util';

const reject=(code)=>{throw Object.assign(new Error(code),{code});};
const positive=n=>Number.isSafeInteger(n)&&n>0;
const required=['max_download_bytes','max_central_directory_bytes','max_entries',
 'max_unpacked_bytes','max_entry_bytes','max_ratio'];
const SIG_EOCD=0x06054b50, SIG_CENTRAL=0x02014b50;
function validLimits(limits) {
 if(!limits||typeof limits!=='object'||Array.isArray(limits)||
    required.some(key=>!positive(limits[key])))
   reject('ZIP_LIMITS_UNTRUSTED_OR_MISSING');
}
function safeName(name,seen) {
 if(!name || name.includes('\0') || name.includes('\\') ||
    name.startsWith('/') || /^[a-zA-Z]:/.test(name) ||
    name.split('/').some(p=>p==='.'||p==='..') ||
    name.split('/').slice(0,-1).some(p=>!p))
   reject('ZIP_ENTRY_PATH_UNSAFE');
 const normalized=name.endsWith('/')?name.slice(0,-1):name;
 if(!normalized)reject('ZIP_ENTRY_PATH_UNSAFE');
 const key=normalized.toLowerCase();
 if(seen.has(key))reject('ZIP_DUPLICATE_ENTRY_NAME');
 seen.add(key);
 if(/\.zip$/i.test(normalized))reject('ZIP_NESTED_ARCHIVE_UNSUPPORTED');
}
async function fileRead(handle,bytes,start){
 const buf=Buffer.alloc(bytes);
 let at=0;
 while(at<bytes){
  const {bytesRead}=await handle.read(buf,at,bytes-at,start+at);
  if(!bytesRead)reject('ZIP_TRUNCATED_READ');
  at+=bytesRead;
 }
 return buf;
}
async function inspectArchive(filePath,limits,verifyContent,selection=null){
 validLimits(limits);
 limits=structuredClone(limits);
 selection?.checkDeadline();
 if(typeof filePath!=='string'||!filePath)
   reject('ZIP_INPUT_INVALID');
 // Use a single descriptor, reject symlinks/FIFOs, and never reopen by path.
 const file=await open(filePath,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK).catch(()=>reject('ZIP_INPUT_NOT_FOUND'));
 try{
  selection?.checkDeadline();
  const details=await file.stat();
  if(!details.isFile()||details.size<22||details.size>limits.max_download_bytes)
    reject('ZIP_FILE_SIZE_OR_TYPE_BLOCK');
  const tailSize=Math.min(details.size,65557);
  const tail=await fileRead(file,tailSize,details.size-tailSize);
  let eocd=-1;
  for(let pos=tail.length-22;pos>=0;pos--){
    if(tail.readUInt32LE(pos)===SIG_EOCD &&
       pos+22+tail.readUInt16LE(pos+20)===tail.length){
      eocd=pos;break;
    }
  }
  if(eocd<0)reject('ZIP_EOCD_MISSING_OR_TRAILING_DATA');
  const disk=tail.readUInt16LE(eocd+4),centralDisk=tail.readUInt16LE(eocd+6);
  const diskEntries=tail.readUInt16LE(eocd+8),entries=tail.readUInt16LE(eocd+10);
  const cdSize=tail.readUInt32LE(eocd+12),cdOffset=tail.readUInt32LE(eocd+16);
  if(entries===0xffff||cdSize===0xffffffff||cdOffset===0xffffffff)
    reject('ZIP64_NEEDS_SEPARATE_VALIDATION');
  if(disk!==0||centralDisk!==0||entries!==diskEntries)
    reject('ZIP_MULTI_DISK_DENIED');
  if(entries===0||entries>limits.max_entries)
    reject('ZIP_ENTRY_COUNT_BLOCK');
  if(!positive(cdSize)||cdSize>limits.max_central_directory_bytes||
     cdOffset+cdSize!==details.size-tailSize+eocd)
    reject('ZIP_CENTRAL_DIRECTORY_BOUNDARY');
  const cd=await fileRead(file,cdSize,cdOffset);
  let cursor=0,totalUnpacked=0,totalCompressed=0;
  const seen=new Set(),descriptors=[];
  for(let n=0;n<entries;n++){
    selection?.checkDeadline();
    if(cursor+46>cd.length||cd.readUInt32LE(cursor)!==SIG_CENTRAL)
      reject('ZIP_CENTRAL_DIRECTORY_CORRUPT');
    const flags=cd.readUInt16LE(cursor+8),method=cd.readUInt16LE(cursor+10);
    const crc=cd.readUInt32LE(cursor+16);
    const comp=cd.readUInt32LE(cursor+20),uncomp=cd.readUInt32LE(cursor+24);
    const fileNameBytes=cd.readUInt16LE(cursor+28);
    const extraBytes=cd.readUInt16LE(cursor+30);
    const commentBytes=cd.readUInt16LE(cursor+32);
    const startDisk=cd.readUInt16LE(cursor+34);
    const attr=cd.readUInt32LE(cursor+38);
    const localOffset=cd.readUInt32LE(cursor+42);
    const end=cursor+46+fileNameBytes+extraBytes+commentBytes;
    if(end>cd.length||!fileNameBytes||startDisk!==0||
       localOffset>=cdOffset)
      reject('ZIP_CENTRAL_DIRECTORY_CORRUPT');
    if(comp===0xffffffff||uncomp===0xffffffff||localOffset===0xffffffff)
      reject('ZIP64_NEEDS_SEPARATE_VALIDATION');
    if((flags&0x1)!==0)reject('ZIP_ENCRYPTED_DENIED');
    if(method!==0&&method!==8)reject('ZIP_COMPRESSION_METHOD_DENIED');
    let name;
    try {
      name=new TextDecoder('utf-8',{fatal:true}).decode(
        cd.subarray(cursor+46,cursor+46+fileNameBytes));
    } catch {reject('ZIP_FILENAME_ENCODING_UNSUPPORTED');}
    safeName(name,seen);
    const unixType=(attr>>>16)&0xf000;
    if(unixType===0xa000)reject('ZIP_SYMLINK_DENIED');
    if(uncomp>limits.max_entry_bytes)
      reject('ZIP_SINGLE_ENTRY_TOO_LARGE');
    if(uncomp>0 && (comp===0||uncomp/comp>limits.max_ratio))
      reject('ZIP_DECOMPRESSION_RATIO_BLOCK');
    totalUnpacked+=uncomp;totalCompressed+=comp;
    if(totalUnpacked>limits.max_unpacked_bytes)
      reject('ZIP_TOTAL_UNPACKED_EXCEEDS_LIMIT');
    if(verifyContent)descriptors.push({name,offset:localOffset,flags,method,crc,compressed:comp,
      uncompressed:uncomp,nameBytes:cd.subarray(cursor+46,cursor+46+fileNameBytes)});
    cursor=end;
  }
  if(cursor!==cd.length)reject('ZIP_CENTRAL_DIRECTORY_EXTRA_DATA');
  const proof=verifyContent?await verifyZipEntries(file,descriptors,cdOffset,limits,selection):null;
  const actualBytes=selection?proof.total:proof;
  const hash=createHash('sha256');
  for(let offset=0;offset<details.size;){
    selection?.checkDeadline();
    const chunk=await fileRead(file,Math.min(65536,details.size-offset),offset);
    hash.update(chunk);offset+=chunk.length;
  }
  const after=await file.stat();
  selection?.checkDeadline();
  if(after.size!==details.size||after.mtimeMs!==details.mtimeMs||after.ctimeMs!==details.ctimeMs)
    reject('ZIP_FILE_CHANGED_DURING_INSPECTION');
  const verified=verifyContent?{content_crc_verified:true,actual_unpacked_bytes:actualBytes}:{};
  const parsed=selection?{entry_name:selection.name,selected_unpacked_bytes:proof.selectedBytes,entry_result:proof.selectedResult}:{};
  return Object.freeze({state:selection?'ZIP_ENTRY_VERIFIED_CANDIDATE':verifyContent?'ZIP_CONTENT_VERIFIED_CANDIDATE':'ZIP_METADATA_CANDIDATE',...verified,...parsed,entry_count:entries,
    compressed_bytes:details.size,declared_unpacked_bytes:totalUnpacked,
    declared_payload_compressed_bytes:totalCompressed,
    archive_sha256:hash.digest('hex'),
    extracted:false,rows_parsed:false,runtime_authorized:false,
    write_authorized:false,source_license_verified:false});
 }finally{await file.close();}
}

export const inspectZipCandidate=(filePath,limits)=>inspectArchive(filePath,limits,false);
export const verifyZipContentCandidate=(filePath,limits)=>inspectArchive(filePath,limits,true);

// Internal skill integration: consumer must be pure, fully drain the stream and
// retain its result privately. No result is returned until ALL entries pass CRC.
export async function readZipEntryCandidate(filePath,limits,entryName,consume){
 validLimits(limits);
 if(!positive(limits.timeout_ms)||limits.timeout_ms>2147483647)reject('ZIP_TIMEOUT_POLICY_INVALID');
 if(typeof entryName!=='string'||entryName.endsWith('/')||typeof consume!=='function')reject('ZIP_SELECTED_ENTRY_INVALID');
 safeName(entryName,new Set());
 const cap=structuredClone(limits),controller=new AbortController(),deadline=performance.now()+cap.timeout_ms;
 const timeout=()=>controller.abort(Object.assign(new Error('ZIP_OPERATION_TIMEOUT'),{code:'ZIP_OPERATION_TIMEOUT'}));
 const checkDeadline=()=>{if(performance.now()>=deadline)timeout();controller.signal.throwIfAborted();};
 const timer=setTimeout(timeout,cap.timeout_ms);
 try{return await inspectArchive(filePath,cap,true,{name:entryName,consume,signal:controller.signal,checkDeadline});}
 finally{clearTimeout(timer);}
}

// Internal streaming content verifier. Only called after bounded central-directory scan.
import {createInflateRaw} from 'node:zlib';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
const fail=code=>{throw Object.assign(new Error(code),{code});};
const table=Uint32Array.from({length:256},(_,i)=>{for(let j=0;j<8;j++)i=(i&1)?(0xedb88320^(i>>>1)):(i>>>1);return i>>>0;});
async function read(file,n,pos){const b=Buffer.alloc(n);let at=0;while(at<n){const r=await file.read(b,at,n-at,pos+at);if(!r.bytesRead)fail('ZIP_CONTENT_TRUNCATED');at+=r.bytesRead;}return b;}
async function* chunks(file,start,end){while(start<end){const b=await read(file,Math.min(65536,end-start),start);start+=b.length;yield b;}}
export async function verifyZipEntries(file,entries,centralOffset,limits,selection=null){
 let total=0,endOfLast=0,selectedResult=null,selectedBytes=null;
 if(selection&&!entries.some(e=>e.name===selection.name))fail('ZIP_SELECTED_ENTRY_MISSING');
 const ordered=[...entries].sort((a,b)=>a.offset-b.offset);
 for(const e of ordered){
  selection?.checkDeadline();
  // Strict classic ZIP subset: no data descriptor, encryption or unsupported flags.
  // Reject rather than guess at layouts. A real SUNAT ZIP may need additional support.
  if((e.flags&~0x0806)!==0)fail('ZIP_CONTENT_FLAGS_UNSUPPORTED');
  if(e.offset!==endOfLast||e.offset+30>centralOffset)fail('ZIP_LOCAL_RANGE_INVALID');
  const h=await read(file,30,e.offset);
  if(h.readUInt32LE(0)!==0x04034b50||h.readUInt16LE(6)!==e.flags||h.readUInt16LE(8)!==e.method||h.readUInt32LE(14)!==e.crc||h.readUInt32LE(18)!==e.compressed||h.readUInt32LE(22)!==e.uncompressed)fail('ZIP_LOCAL_CENTRAL_MISMATCH');
  const n=h.readUInt16LE(26),extra=h.readUInt16LE(28),start=e.offset+30+n+extra,end=start+e.compressed;
  if(n!==e.nameBytes.length||end>centralOffset||!(await read(file,n,e.offset+30)).equals(e.nameBytes))fail('ZIP_LOCAL_CENTRAL_MISMATCH');
  if(e.method===0&&e.compressed!==e.uncompressed)fail('ZIP_STORED_LENGTH_MISMATCH');
  let count=0,crc=0xffffffff;
  let drained=false;
  const checked=async function*(source){
   for await(const chunk of source){
    selection?.checkDeadline();count+=chunk.length;total+=chunk.length;
    if(count>e.uncompressed||count>limits.max_entry_bytes||total>limits.max_unpacked_bytes||(count>0&&(e.compressed===0||count/e.compressed>limits.max_ratio)))fail('ZIP_ACTUAL_OUTPUT_LIMIT');
    for(const x of chunk)crc=(crc>>>8)^table[(crc^x)&255];
    yield chunk;
   }
   drained=true;
  };
  const finish=async source=>{
   if(selection&&e.name===selection.name){
    selectedResult=await selection.consume(source);
    if(!drained)fail('ZIP_ENTRY_CONSUMER_INCOMPLETE');
   }else{for await(const _ of source){/* validate and discard */}}
  };
  const input=Readable.from(chunks(file,start,end));
  const inflate=e.method===8?createInflateRaw():null;
  try{await pipeline(input,...(inflate?[inflate]:[]),checked,finish,selection?{signal:selection.signal}:{});}
  catch(err){selection?.checkDeadline();if(typeof err.code==='string'&&/^(ZIP_|SUNAT_)/.test(err.code))throw err;fail('ZIP_DECOMPRESSION_INVALID');}
  selection?.checkDeadline();
  if(inflate&&inflate.bytesWritten!==e.compressed)fail('ZIP_DEFLATE_TRAILING_BYTES');
  if(count!==e.uncompressed)fail('ZIP_ACTUAL_LENGTH_MISMATCH');
  if(((crc^0xffffffff)>>>0)!==e.crc)fail('ZIP_CRC_MISMATCH');
  if(selection&&e.name===selection.name)selectedBytes=count;
  endOfLast=end;
 }
 if(endOfLast!==centralOffset)fail('ZIP_LOCAL_RANGE_INVALID');
 return selection?{total,selectedResult,selectedBytes}:total;
}

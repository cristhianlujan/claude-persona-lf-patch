// Candidate record reader, independent of ZIP and business. No source fetch or writes.
// Caller supplies a byte stream and an independently established exact schema.
// This module does not certify the schema's provenance or the archive's integrity.
const fail=code=>{throw Object.assign(new Error(code),{code});};
const obj=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const str=x=>typeof x==='string'&&x.trim().length>0;
const pos=x=>Number.isSafeInteger(x)&&x>0;
const fields=['ruc','nombre','estado','condicion','ubigeo'];
const limits=['max_input_bytes','max_record_bytes','max_records','max_candidates'];
function check(schema,policy){
 if(!obj(schema)||!str(schema.resource_variant)||!str(schema.source_version)||!str(schema.schema_ref)||
    !['FIXTURE_ONLY','EXTERNAL_SCHEMA_CANDIDATE'].includes(schema.evidence_status)||
    ![',',';','|','\t'].includes(schema.delimiter)||!['utf-8','windows-1252'].includes(schema.encoding)||
    typeof schema.trailing_delimiter!=='boolean'||!Array.isArray(schema.columns)||!schema.columns.length||
    schema.columns.some(x=>!str(x))||new Set(schema.columns).size!==schema.columns.length||
    !obj(schema.field_map)||Object.keys(schema.field_map).length!==fields.length||
    fields.some(x=>!str(schema.field_map[x])||!schema.columns.includes(schema.field_map[x]))||
    new Set(fields.map(x=>schema.field_map[x])).size!==fields.length)fail('SUNAT_SCHEMA_CONTRACT_INVALID');
 if(!obj(policy)||!str(policy.business_code)||!str(policy.policy_ref)||policy.resource_variant!==schema.resource_variant||
    policy.source_version!==schema.source_version||policy.allowed_effect!=='READ_ONLY'||
    !Array.isArray(policy.ubigeo_prefixes)||!policy.ubigeo_prefixes.length||
    policy.ubigeo_prefixes.some(x=>typeof x!=='string'||!/^\d{2}$/.test(x))||
    new Set(policy.ubigeo_prefixes).size!==policy.ubigeo_prefixes.length||
    !obj(policy.limits)||limits.some(x=>!pos(policy.limits[x]))||
    policy.limits.max_record_bytes>policy.limits.max_input_bytes||
    policy.limits.max_candidates>policy.limits.max_records)fail('SUNAT_POLICY_CONTRACT_INVALID');
}
// Strict single-line delimited dialect, doubles quotes inside quoted fields.
// Multiline quoted values are intentionally unsupported and block the receipt.
function split(line,delimiter,trailing){
 const out=[];let field='',quoted=false,closed=false;
 for(let i=0;i<line.length;i++){
  const c=line[i];
  if(quoted){if(c==='"'&&line[i+1]==='"'){field+='"';i++;}else if(c==='"'){quoted=false;closed=true;}else field+=c;continue;}
  if(c===delimiter){out.push(field);field='';closed=false;continue;}
  if(c==='"'){if(field||closed)fail('SUNAT_QUOTE_INVALID');quoted=true;continue;}
  if(closed)fail('SUNAT_QUOTE_INVALID');field+=c;
 }
 if(quoted)fail('SUNAT_QUOTE_INVALID');out.push(field);
 if(trailing){if(out.at(-1)!==''||!line.endsWith(delimiter))fail('SUNAT_TRAILING_DELIMITER_MISSING');out.pop();}
 return out;
}
export async function inspectSunatRecordsCandidate(chunks,inputSchema,inputPolicy){
 check(inputSchema,inputPolicy);
 const schema=structuredClone(inputSchema),policy=structuredClone(inputPolicy),cap=policy.limits;
 if(!chunks||typeof chunks[Symbol.asyncIterator]!=='function')fail('SUNAT_BYTE_STREAM_REQUIRED');
 const decode=new TextDecoder(schema.encoding,{fatal:true,ignoreBOM:true});
 const idx=Object.fromEntries(fields.map(x=>[x,schema.columns.indexOf(schema.field_map[x])]));
 let bytes=0,records=0,excludedNonLegal=0,excludedTerritory=0,header=false,parts=[],pending=0;
 const rows=[],seen=new Set();
 const consume=()=>{
  let b=Buffer.concat(parts,pending);parts=[];pending=0;
  if(b.at(-1)===13)b=b.subarray(0,b.length-1);
  let line;try{line=decode.decode(b);}catch{fail('SUNAT_ENCODING_INVALID');}
  if(!header)line=line.replace(/^\uFEFF/,'');
  if(!line||line.includes('\0')||line.includes('\r')||line.includes('\uFFFD'))fail('SUNAT_ROW_INVALID');
  const columns=split(line,schema.delimiter,schema.trailing_delimiter);
  if(!header){if(columns.length!==schema.columns.length||columns.some((x,i)=>x!==schema.columns[i]))fail('SUNAT_HEADER_DRIFT');header=true;return;}
  if(columns.length!==schema.columns.length)fail('SUNAT_ROW_WIDTH_MISMATCH');
  records++;if(records>cap.max_records)fail('SUNAT_RECORD_LIMIT');
  const ruc=columns[idx.ruc].trim();if(!/^\d{11}$/.test(ruc))fail('SUNAT_RUC_SHAPE_INVALID');
  // SUNAT documents prefix 20 for legal entities. Exclusion is conservative;
  // other prefixes are not classified as legal entities or returned.
  if(!ruc.startsWith('20')){excludedNonLegal++;return;}
  const ubigeo=columns[idx.ubigeo].trim();if(!/^\d{6}$/.test(ubigeo))fail('SUNAT_UBIGEO_SHAPE_INVALID');
  if(!policy.ubigeo_prefixes.some(x=>ubigeo.startsWith(x))){excludedTerritory++;return;}
  const nombre=columns[idx.nombre].trim(),estado=columns[idx.estado].trim(),condicion=columns[idx.condicion].trim();
  if(!nombre||!estado||!condicion)fail('SUNAT_REQUIRED_VALUE_MISSING');
  if(seen.has(ruc))fail('SUNAT_DUPLICATE_CANDIDATE_RUC');
  if(rows.length>=cap.max_candidates)fail('SUNAT_CANDIDATE_LIMIT');
  seen.add(ruc);rows.push(Object.freeze({fila_origen:records,ruc,nombre,estado,condicion,ubigeo}));
 };
 for await(const item of chunks){
  if(!(item instanceof Uint8Array))fail('SUNAT_BYTE_STREAM_REQUIRED');
  bytes+=item.byteLength;if(bytes>cap.max_input_bytes)fail('SUNAT_INPUT_LIMIT');
  const chunk=Buffer.from(item.buffer,item.byteOffset,item.byteLength);let start=0;
  while(start<chunk.length){const nl=chunk.indexOf(10,start),end=nl<0?chunk.length:nl;
   pending+=end-start;if(pending>cap.max_record_bytes)fail('SUNAT_RECORD_BYTE_LIMIT');
   if(end>start)parts.push(Buffer.from(chunk.subarray(start,end)));
   if(nl<0)break;consume();start=nl+1;
  }
 }
 if(pending)consume();if(!header)fail('SUNAT_HEADER_MISSING');
 if(!records)fail('SUNAT_NO_RECORDS');
 return Object.freeze({state:'SUNAT_RECORDS_CANDIDATE_ONLY',business_code:policy.business_code,
  resource_variant:schema.resource_variant,source_version:schema.source_version,schema_ref:schema.schema_ref,
  policy_ref:policy.policy_ref,bytes_read:bytes,records_read:records,excluded_non_legal_prefix:excludedNonLegal,
  excluded_territory:excludedTerritory,selected_count:rows.length,rows:Object.freeze(rows),
  schema_authority_verified:false,archive_integrity_verified:false,identity_verified:false,
  runtime_authorized:false,write_authorized:false,contact_authorized:false});
}

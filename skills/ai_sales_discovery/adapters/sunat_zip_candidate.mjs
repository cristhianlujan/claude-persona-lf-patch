// Local, read-only composition of the reusable ZIP processor and SUNAT reader.
import {createHash} from 'node:crypto';
import {readZipEntryCandidate} from './zip_archive_preflight.mjs';
import {inspectSunatRecordsCandidate,validateSunatRecordsContract} from './sunat_records_candidate.mjs';
export async function inspectSunatZipCandidate(input){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Object.assign(new Error('SUNAT_ZIP_CONTRACT_INVALID'),{code:'SUNAT_ZIP_CONTRACT_INVALID'});
 const {filePath,entryName,archiveLimits,schema,policy}=input;
 validateSunatRecordsContract(schema,policy);
 const schemaSnapshot=structuredClone(schema),policySnapshot=structuredClone(policy);
 const archive=await readZipEntryCandidate(filePath,archiveLimits,entryName,stream=>inspectSunatRecordsCandidate(stream,schemaSnapshot,policySnapshot));
 const records=archive.entry_result;
 if(archive.content_crc_verified!==true||!records||records.bytes_read!==archive.selected_unpacked_bytes)throw Object.assign(new Error('SUNAT_ARCHIVE_RECEIPT_INVALID'),{code:'SUNAT_ARCHIVE_RECEIPT_INVALID'});
 const {entry_result,...archiveReceipt}=archive;
 return Object.freeze({...records,state:'SUNAT_ZIP_RECORDS_CANDIDATE_ONLY',archive_integrity_verified:true,
  capture_sha256:createHash('sha256').update(JSON.stringify(records.rows),'utf8').digest('hex'),archive:Object.freeze(archiveReceipt),
  schema_authority_verified:false,source_license_verified:false,runtime_authorized:false,write_authorized:false,contact_authorized:false});
}

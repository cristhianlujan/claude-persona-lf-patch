import test from 'node:test';
import assert from 'node:assert/strict';
import {classifySemanticReadback} from './semantic_continuation.ts';

const sha='a'.repeat(64), shaB='b'.repeat(64);
const base={run_id:949,promotion_authorized:false,production_authorized:false};
const missing={...base,status:'SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED',model_candidate_verified:false,auditor_verified:false};
const auditor={...base,status:'INDEPENDENT_SEMANTIC_VERDICT_REQUIRED',candidate_sha256:sha,candidate_evidence_receipt_id:101,model_candidate_verified:true,auditor_verified:false};
const reviewed={...base,status:'SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE',candidate_sha256:sha,candidate_evidence_receipt_id:101,independent_audit_receipt_id:102,model_candidate_verified:true,auditor_verified:true,semantic_independence_credited:false,official_write_authorized:false,audit_verdict:'PASS'};
const a=(data,run=949,digest=null)=>classifySemanticReadback(data,run,digest);
const p=(name,fn)=>test(name,fn);

p('missing candidate receipt => wait on same RUN without model retry',()=>{
  const out=a(missing);assert.equal(out.status,'CANDIDATE_EVIDENCE_REQUIRED');assert.equal(out.retry_policy,'NO_AUTOMATIC_MODEL_RETRY');assert.equal(out.same_run,true);
});
p('candidate verified => independent auditor required',()=>{
  const out=a(auditor);assert.equal(out.status,'INDEPENDENT_REVIEW_REQUIRED');assert.equal(out.next_action,'EXTERNAL_INDEPENDENT_AUDITOR_REQUIRED');
});
p('audit PASS never means rules PASS',()=>{
  const out=a(reviewed,949,sha);assert.equal(out.status,'SEMANTIC_AUDIT_PASS_NOT_RULE_PASS');assert.equal(out.semantic_rule_pass_authorized,false);assert.equal(out.independent_semantic_quality_proven,false);
});
p('audit FAIL requires remediating evidence',()=>{
  const out=a({...reviewed,audit_verdict:'FAIL'});assert.equal(out.status,'SEMANTIC_AUDIT_FAILED_REMEDIATION_REQUIRED');assert.equal(out.next_action,'REMEDIATION_WITH_AUDIT_FINDINGS_REQUIRED');
});
p('audit BLOCKED requires human decision',()=>{
  const out=a({...reviewed,audit_verdict:'BLOCKED'});assert.equal(out.status,'SEMANTIC_AUDIT_BLOCKED_HUMAN_DECISION_REQUIRED');assert.equal(out.next_action,'HUMAN_DECISION_REQUIRED');
});
p('all positive paths explicitly deny writes and promotion',()=>{
  for(const data of [missing,auditor,reviewed,{...reviewed,audit_verdict:'FAIL'},{...reviewed,audit_verdict:'BLOCKED'}]){
    const out=a(data);assert.equal(out.official_write_authorized,false);assert.equal(out.promotion_authorized,false);assert.equal(out.production_authorized,false);
  }
});
const negatives=[
  ['null receipt',null,949,null,/RECEIPT_NOT_OBJECT/],
  ['array receipt',[],949,null,/RECEIPT_NOT_OBJECT/],
  ['run mismatch',{...missing,run_id:950},949,null,/RUN_OR_AUTHORITY_MISMATCH/],
  ['run invalid',missing,0,null,/RUN_ID_INVALID/],
  ['claim promotion',{...missing,promotion_authorized:true},949,null,/RUN_OR_AUTHORITY_MISMATCH/],
  ['claim production',{...missing,production_authorized:true},949,null,/RUN_OR_AUTHORITY_MISMATCH/],
  ['claim official writes',{...reviewed,official_write_authorized:true},949,null,/RUN_OR_AUTHORITY_MISMATCH/],
  ['unknown receipt status',{...missing,status:'COMPLETED'},949,null,/RECEIPT_STATUS_UNRECOGNIZED/],
  ['faked missing evidence',{...missing,model_candidate_verified:true},949,null,/MISSING_EVIDENCE_STATUS_MISMATCH/],
  ['candidate verified without id',{...auditor,candidate_evidence_receipt_id:null},949,null,/AUDITOR_REQUIRED_BINDING_INVALID/],
  ['candidate with invalid SHA',{...auditor,candidate_sha256:'fake'},949,null,/AUDITOR_REQUIRED_BINDING_INVALID/],
  ['reviewed without independent receipt',{...reviewed,independent_audit_receipt_id:null},949,null,/AUDIT_RECEIPT_BINDING_INVALID/],
  ['fake semantic independence claim',{...reviewed,semantic_independence_credited:true},949,null,/AUDIT_RECEIPT_BINDING_INVALID/],
  ['unspecified verdict',{...reviewed,audit_verdict:'UNKNOWN'},949,null,/AUDIT_VERDICT_INVALID/],
  ['candidate SHA mismatch',reviewed,949,shaB,/CANDIDATE_SHA_MISMATCH/],
  ['requested SHA invalid',reviewed,949,'invalid',/EXPECTED_CANDIDATE_DIGEST_INVALID/]
];
for(const [name,data,run,digest,pattern] of negatives)p(name,()=>assert.throws(()=>a(data,run,digest),pattern));

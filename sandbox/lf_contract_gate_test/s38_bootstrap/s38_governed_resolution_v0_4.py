#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path
from typing import Any,Mapping

GITHUB_REF=re.compile(r"^github://(?P<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@(?P<revision>[0-9a-f]{40})/(?P<path>.+)$")
ROOT=Path(__file__).resolve().parent
PASS='PASS'; BLOCKED='BLOCKED'
CANONICAL_REPO_SLUG='cristhianlujan/claude-persona-lf-patch'
CANONICAL_REPOSITORY_ID=1244397752
RESOLVER_ID='S38_GOVERNED_REF_RESOLVER_V4'
LEGACY_RESOLVER_IDS={'QUALITY_PACK_TRUSTED_REF_RESOLVER_V1','S38_GOVERNED_REF_RESOLVER_V2','S38_GOVERNED_REF_RESOLVER_V3'}
POLICY_REL='sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_trust_policy_v0_3.json'
RUNTIME_TCB_PATHS={
 'sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_resolution_v0_4.py',
 POLICY_REL,
 'sandbox/lf_contract_gate_test/s38_bootstrap/validate_s38_dg_contracts_v0_7.py',
 'sandbox/lf_contract_gate_test/s38_bootstrap/lf_common_evidence_envelope_v0_7_candidate.schema.json',
 'sandbox/lf_contract_gate_test/s31_bootstrap/lf_shared_authority_typed_context_v0_2_candidate.schema.json',
 'sandbox/lf_contract_gate_test/s31_bootstrap/lf_capability_manifest_v0_3_candidate.schema.json',
 'sandbox/lf_contract_gate_test/s38_bootstrap/lf_runtime_execution_port_v0_2_candidate.schema.json',
 'sandbox/lf_contract_gate_test/s38_bootstrap/lf_runtime_execution_output_v0_2_candidate.schema.json',
}
EVIDENCE_TCB_PATHS={
 'sandbox/lf_contract_gate_test/s38_bootstrap/test_s38_dg_contracts_v0_7.py',
 'sandbox/lf_contract_gate_test/s38_bootstrap/s38_ir008_historical_pin_inventory_v0_1.json',
 'sandbox/lf_contract_gate_test/s31_bootstrap/s31_trusted_resolution_v0_1.py',
}
class ResolutionError(RuntimeError):
 def __init__(self,code:str,detail:str=''):
  super().__init__(f'{code}:{detail}' if detail else code); self.code=code; self.detail=detail
def _sha256(raw:bytes)->str:return hashlib.sha256(raw).hexdigest()
def canonical_manifest_bytes(value:Mapping[str,Any])->bytes:return (json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def _git(root:Path,args:list[str],*,binary=False):
 p=subprocess.run(['git','-C',str(root),*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if p.returncode!=0: raise ResolutionError('GIT_READBACK_FAILED',p.stderr.decode('utf-8','replace').strip()[:240])
 return p.stdout if binary else p.stdout.decode().strip()
def _repo_root(start:Path)->Path:return Path(_git(start,['rev-parse','--show-toplevel'])).resolve()
class S38GovernedRefResolver:
 def __init__(self,subject_manifest:Mapping[str,Any],verification_receipt:Mapping[str,Any],expected_signer_digest:str)->None:
  self.root=_repo_root(ROOT); self.repo=CANONICAL_REPO_SLUG; self.resolver_id=RESOLVER_ID
  self.artifact_head=_git(self.root,['rev-parse','HEAD']); self.head=self.artifact_head
  if not isinstance(subject_manifest,Mapping): raise ResolutionError('BLOCK_ATTESTED_SUBJECT_MISSING')
  if subject_manifest.get('manifest_version')!='LF_TRUSTED_SUBJECT_MANIFEST_V1' or subject_manifest.get('profile')!='S38_DG_IR008': raise ResolutionError('BLOCK_ATTESTED_SUBJECT_PROFILE')
  if subject_manifest.get('repository')!=CANONICAL_REPO_SLUG or subject_manifest.get('repository_id')!=CANONICAL_REPOSITORY_ID: raise ResolutionError('BLOCK_ATTESTED_REPOSITORY_IDENTITY')
  if subject_manifest.get('candidate_sha')!=self.artifact_head: raise ResolutionError('BLOCK_ATTESTED_CANDIDATE_SHA_MISMATCH')
  if not re.fullmatch(r'[0-9a-f]{40}',str(expected_signer_digest or '')): raise ResolutionError('BLOCK_EXPECTED_SIGNER_DIGEST_INVALID')
  if not isinstance(verification_receipt,Mapping) or verification_receipt.get('status')!='VERIFIED_EXTERNAL_SIGSTORE': raise ResolutionError('BLOCK_EXTERNAL_ATTESTATION_REQUIRED')
  subject_sha=_sha256(canonical_manifest_bytes(subject_manifest))
  expected={'subject_sha256':subject_sha,'signer_digest':expected_signer_digest,'source_digest':self.artifact_head,'repository':CANONICAL_REPO_SLUG,'repository_id':CANONICAL_REPOSITORY_ID}
  for key,val in expected.items():
   if verification_receipt.get(key)!=val: raise ResolutionError('BLOCK_EXTERNAL_ATTESTATION_BINDING_MISMATCH',key)
  self.subject_manifest=dict(subject_manifest); self.subject_sha256=subject_sha; self.expected_signer_digest=expected_signer_digest
  self._verify_tcb('runtime_tcb',RUNTIME_TCB_PATHS); self._verify_tcb('evidence_tcb',EVIDENCE_TCB_PATHS)
  self._historical={}
  for item in subject_manifest.get('historical_pins') or []:
   if not isinstance(item,Mapping) or not isinstance(item.get('ref'),str): raise ResolutionError('BLOCK_ATTESTED_HISTORICAL_PIN_SHAPE')
   ref=item['ref']; m=GITHUB_REF.fullmatch(ref)
   if not m or m.group('repo')!=CANONICAL_REPO_SLUG: raise ResolutionError('BLOCK_ATTESTED_HISTORICAL_REF_INVALID',ref)
   if ref in self._historical: raise ResolutionError('BLOCK_ATTESTED_HISTORICAL_PIN_DUPLICATE',ref)
   raw=self._raw_git(m.group('revision'),m.group('path')); blob=_git(self.root,['rev-parse',f"{m.group('revision')}:{m.group('path')}"])
   if _sha256(raw)!=item.get('sha256') or blob!=item.get('blob_sha'): raise ResolutionError('BLOCK_ATTESTED_HISTORICAL_PIN_MISMATCH',ref)
   self._historical[ref]=dict(item)
  policy_raw=self._raw_git(self.artifact_head,POLICY_REL)
  try:self.policy_snapshot=json.loads(policy_raw.decode())
  except Exception as exc: raise ResolutionError('BLOCK_ATTESTED_POLICY_INVALID',type(exc).__name__) from exc
  if self.policy_snapshot.get('resolver_id')!=RESOLVER_ID: raise ResolutionError('BLOCK_ATTESTED_POLICY_RESOLVER_MISMATCH')
  if 'canonical_repository' in self.policy_snapshot: raise ResolutionError('BLOCK_POLICY_REPOSITORY_IDENTITY_FORBIDDEN')
  self.policy_sha256=_sha256(policy_raw); self.verified=True
 def _raw_git(self,revision:str,path:str)->bytes:
  parts=Path(path).parts
  if path.startswith('/') or '..' in parts or not path or '\x00' in path or ':' in path: raise ResolutionError('UNSAFE_REPOSITORY_PATH',path[:160])
  return bytes(_git(self.root,['show',f'{revision}:{path}'],binary=True))
 def _verify_tcb(self,key:str,required:set[str])->None:
  entries=self.subject_manifest.get(key) or []
  if not isinstance(entries,list): raise ResolutionError('BLOCK_ATTESTED_TCB_SHAPE',key)
  by={str(x.get('path')):x for x in entries if isinstance(x,Mapping)}
  if set(by)!=required: raise ResolutionError('BLOCK_ATTESTED_TCB_COVERAGE_MISMATCH',key)
  for path,item in by.items():
   if item.get('revision')!=self.artifact_head: raise ResolutionError('BLOCK_ATTESTED_TCB_REVISION_MISMATCH',path)
   raw=self._raw_git(self.artifact_head,path); blob=_git(self.root,['rev-parse',f'{self.artifact_head}:{path}'])
   if _sha256(raw)!=item.get('sha256') or blob!=item.get('blob_sha'): raise ResolutionError('BLOCK_ATTESTED_TCB_GIT_MISMATCH',path)
   local=self.root/path
   if not local.is_file() or _sha256(local.read_bytes())!=item.get('sha256'): raise ResolutionError('BLOCK_ATTESTED_TCB_BYTE_MISMATCH',path)
 def load_json_at_artifact_head(self,rel:str)->Mapping[str,Any]:
  raw=self._raw_git(self.artifact_head,rel)
  try:v=json.loads(raw.decode())
  except Exception as exc: raise ResolutionError('GOVERNED_CANONICAL_JSON_INVALID',rel) from exc
  if not isinstance(v,Mapping): raise ResolutionError('GOVERNED_CANONICAL_JSON_NOT_OBJECT',rel)
  return v
 def resolve(self,ref:str)->dict[str,Any]:
  if not isinstance(ref,str): raise ResolutionError('REF_MISSING')
  m=GITHUB_REF.fullmatch(ref.strip())
  if not m: raise ResolutionError('UNSUPPORTED_REF_SCHEME',str(ref)[:160])
  repo,rev,path=m.group('repo'),m.group('revision'),m.group('path')
  if repo!=CANONICAL_REPO_SLUG: raise ResolutionError('FOREIGN_REPO_NOT_RESOLVABLE_BY_GOVERNED_RESOLVER',repo)
  if rev!=self.artifact_head and ref not in self._historical: raise ResolutionError('BLOCK_HISTORICAL_REF_NOT_ATTESTED',ref)
  raw=self._raw_git(rev,path); blob=_git(self.root,['rev-parse',f'{rev}:{path}'])
  out={'ref':ref,'repo':repo,'revision':rev,'path':path,'sha256':_sha256(raw),'blob_sha':blob,'bytes':len(raw),'raw':raw}
  if rev!=self.artifact_head:
   pin=self._historical[ref]
   if out['sha256']!=pin.get('sha256') or blob!=pin.get('blob_sha'): raise ResolutionError('BLOCK_HISTORICAL_PIN_RUNTIME_MISMATCH',ref)
  return out
 def content_current(self,observed:Mapping[str,Any])->bool:
  try:
   if _sha256(self._raw_git(self.artifact_head,str(observed['path'])))==observed.get('sha256'): return True
  except ResolutionError: pass
  for e in (self.policy_snapshot.get('currentness') or {}).get('archival_registry') or []:
   if not isinstance(e,Mapping) or e.get('status')!='CURRENT': continue
   refs=[]
   if isinstance(e.get('historical_ref'),str): refs.append(e['historical_ref'])
   refs.extend([r for r in e.get('historical_refs') or [] if isinstance(r,str)])
   if observed.get('ref') in refs and observed.get('sha256')==e.get('sha256') and observed.get('ref') in self._historical: return True
  return False
def is_trusted_resolver(resolver:Any)->bool:return type(resolver) is S38GovernedRefResolver and resolver.verified is True
def block(code:str,**extra:Any)->dict[str,Any]:return {'status':BLOCKED,'code':code,**extra}
def resolve_source(resolver:Any,ref:str,expected_sha256:str,label:str,*,require_current_content:bool=True):
 if not is_trusted_resolver(resolver):return block('BLOCK_UNTRUSTED_RESOLVER_TYPE',binding=label),None
 try:observed=resolver.resolve(ref)
 except ResolutionError as exc:return block('BLOCK_TRUSTED_REF_RESOLUTION_FAILED',binding=label,resolver_code=exc.code),None
 except Exception as exc:return block('BLOCK_TRUSTED_REF_RESOLUTION_FAILED',binding=label,error=type(exc).__name__),None
 if observed.get('sha256')!=expected_sha256:return block('BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH',binding=label,expected=expected_sha256,observed=observed.get('sha256')),None
 if require_current_content and not resolver.content_current(observed):return block('BLOCK_PROVIDER_SOURCE_STALE',binding=label,ref=ref),None
 return {'status':PASS,'code':'PASS_GOVERNED_SOURCE_RESOLUTION','binding':label},observed
def resolve_json_binding(resolver:Any,binding:Mapping[str,Any]|None,expected_type:str,label:str,*,require_current_content:bool=True):
 if not isinstance(binding,Mapping):return block('BLOCK_EVIDENCE_BINDING_MISSING',binding=label),None,None
 if not is_trusted_resolver(resolver):return block('BLOCK_UNTRUSTED_RESOLVER_TYPE',binding=label),None,None
 if binding.get('resolver_id') not in ({resolver.resolver_id}|LEGACY_RESOLVER_IDS):return block('BLOCK_UNTRUSTED_RESOLVER_ID',binding=label),None,None
 ref=binding.get('ref');sha=binding.get('sha256') or binding.get('digest')
 if not isinstance(ref,str) or not ref:return block('BLOCK_EVIDENCE_REF_MISSING',binding=label),None,None
 if not isinstance(sha,str) or len(sha)!=64:return block('BLOCK_EVIDENCE_SHA256_INVALID',binding=label),None,None
 status,observed=resolve_source(resolver,ref,sha,label,require_current_content=require_current_content)
 if status.get('status')!=PASS:return status,None,observed
 try:record=json.loads(observed['raw'].decode())
 except Exception:return block('BLOCK_RESOLVED_EVIDENCE_NOT_JSON',binding=label),None,observed
 if not isinstance(record,Mapping):return block('BLOCK_RESOLVED_EVIDENCE_NOT_OBJECT',binding=label),None,observed
 if record.get('evidence_type')!=expected_type:return block('BLOCK_EVIDENCE_TYPE_MISMATCH',binding=label,expected=expected_type,observed=record.get('evidence_type')),None,observed
 if record.get('status')!=PASS:return block('BLOCK_RESOLVED_EVIDENCE_NOT_PASS',binding=label,observed=record.get('status')),None,observed
 return {'status':PASS,'code':'PASS_TRUSTED_JSON_EVIDENCE','binding':label},record,observed

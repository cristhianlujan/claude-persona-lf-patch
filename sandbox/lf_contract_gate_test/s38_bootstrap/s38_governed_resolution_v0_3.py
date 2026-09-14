#!/usr/bin/env python3
from __future__ import annotations

import hashlib, json, re, ssl, subprocess, tempfile, urllib.request
from pathlib import Path
from typing import Any, Mapping

GITHUB_REF=re.compile(r"^github://(?P<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@(?P<revision>[0-9a-f]{40})/(?P<path>.+)$")
ROOT=Path(__file__).resolve().parent
PASS="PASS"; BLOCKED="BLOCKED"
LEGACY_RESOLVER_IDS={"QUALITY_PACK_TRUSTED_REF_RESOLVER_V1","S38_GOVERNED_REF_RESOLVER_V2"}
CANONICAL_REPO_SLUG="cristhianlujan/claude-persona-lf-patch"
CANONICAL_REMOTE_URL="https://github.com/cristhianlujan/claude-persona-lf-patch.git"
CANONICAL_API_URL="https://api.github.com/repos/cristhianlujan/claude-persona-lf-patch"
CANONICAL_REPOSITORY_ID=1244397752
TRUST_ANCHOR_COMMIT="3b39657fbf14f29c7839ecb26d715ed5c6fad59e"
RESOLVER_ID="S38_GOVERNED_REF_RESOLVER_V3"
POLICY_REL="sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_trust_policy_v0_2.json"
LOAD_BEARING_LOCAL_PATHS=(
 "sandbox/lf_contract_gate_test/s38_bootstrap/s38_governed_resolution_v0_3.py",
 POLICY_REL,
 "sandbox/lf_contract_gate_test/s38_bootstrap/validate_s38_dg_contracts_v0_6.py",
 "sandbox/lf_contract_gate_test/s38_bootstrap/lf_common_evidence_envelope_v0_6_candidate.schema.json",
 "sandbox/lf_contract_gate_test/s31_bootstrap/lf_shared_authority_typed_context_v0_2_candidate.schema.json",
)
GIT_BIN="/usr/bin/git"
SYSTEM_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"

class ResolutionError(RuntimeError):
 def __init__(self,code:str,detail:str=""):
  super().__init__(f"{code}:{detail}" if detail else code); self.code=code; self.detail=detail

def _sha256(raw:bytes)->str: return hashlib.sha256(raw).hexdigest()
def _safe_git_env()->dict[str,str]:
 return {"PATH":"/usr/bin:/bin","HOME":"/nonexistent","LANG":"C.UTF-8","LC_ALL":"C.UTF-8","GIT_CONFIG_GLOBAL":"/dev/null","GIT_CONFIG_SYSTEM":"/dev/null","GIT_CONFIG_NOSYSTEM":"1","GIT_TERMINAL_PROMPT":"0"}
def _git(root:Path,args:list[str],*,text:bool=False)->bytes|str:
 if not Path(GIT_BIN).is_file(): raise ResolutionError("GOVERNED_GIT_BINARY_UNAVAILABLE",GIT_BIN)
 p=subprocess.run([GIT_BIN,"-C",str(root),*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=text,env=_safe_git_env())
 if p.returncode!=0:
  err=p.stderr.strip() if text else p.stderr.decode("utf-8","replace").strip(); raise ResolutionError("GIT_READBACK_FAILED",err[:240])
 return p.stdout
def _repo_root(start:Path)->Path:
 p=subprocess.run([GIT_BIN,"-C",str(start),"rev-parse","--show-toplevel"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=_safe_git_env())
 if p.returncode!=0: raise ResolutionError("GOVERNED_ARTIFACT_ROOT_UNRESOLVED",p.stderr.strip()[:240])
 return Path(p.stdout.strip()).resolve()
def _github_api_json(url:str)->Mapping[str,Any]:
 ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname=True; ctx.verify_mode=ssl.CERT_REQUIRED
 if not Path(SYSTEM_CA_BUNDLE).is_file(): raise ResolutionError("GOVERNED_SYSTEM_CA_BUNDLE_UNAVAILABLE",SYSTEM_CA_BUNDLE)
 ctx.load_verify_locations(cafile=SYSTEM_CA_BUNDLE)
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=ctx))
 req=urllib.request.Request(url,headers={"User-Agent":"LF-S38-Governed-Resolver/3","Accept":"application/vnd.github+json"})
 try:
  with opener.open(req,timeout=20) as resp: return json.loads(resp.read().decode("utf-8"))
 except Exception as exc: raise ResolutionError("GOVERNED_REPOSITORY_ATTESTATION_UNAVAILABLE",type(exc).__name__) from exc

class S38GovernedRefResolver:
 def __init__(self)->None:
  self.root=_repo_root(ROOT); self.repo=CANONICAL_REPO_SLUG; self.remote_url=CANONICAL_REMOTE_URL; self.resolver_id=RESOLVER_ID
  self.artifact_head=str(_git(self.root,["rev-parse","HEAD"],text=True)).strip(); self.head=self.artifact_head
  self._verify_repository_identity_and_publication()
  self._tmp=tempfile.TemporaryDirectory(prefix="s38-governed-resolver-v3-"); self.cache=Path(self._tmp.name)/"objects.git"
  subprocess.run([GIT_BIN,"init","--bare","-q",str(self.cache)],check=True,env=_safe_git_env())
  self._fetch_commit(TRUST_ANCHOR_COMMIT); self._fetch_commit(self.artifact_head)
  policy_raw=self._raw(self.artifact_head,POLICY_REL)
  try: self.policy_snapshot=json.loads(policy_raw.decode("utf-8"))
  except Exception as exc: raise ResolutionError("GOVERNED_TRUST_POLICY_INVALID",type(exc).__name__) from exc
  if self.policy_snapshot.get("resolver_id")!=RESOLVER_ID: raise ResolutionError("GOVERNED_TRUST_POLICY_RESOLVER_MISMATCH")
  if "canonical_repository" in self.policy_snapshot: raise ResolutionError("GOVERNED_TRUST_POLICY_MUST_NOT_DEFINE_REPOSITORY_IDENTITY")
  self.policy_sha256=_sha256(policy_raw)
  for rel in LOAD_BEARING_LOCAL_PATHS: self._verify_local_rel_against_canonical(rel)
  self.verified=True
 def _verify_repository_identity_and_publication(self)->None:
  repo=_github_api_json(CANONICAL_API_URL)
  if repo.get("id")!=CANONICAL_REPOSITORY_ID or str(repo.get("full_name") or "")!=CANONICAL_REPO_SLUG: raise ResolutionError("GOVERNED_REPOSITORY_IDENTITY_MISMATCH")
  commit=_github_api_json(f"{CANONICAL_API_URL}/commits/{self.artifact_head}")
  if commit.get("sha")!=self.artifact_head: raise ResolutionError("GOVERNED_ARTIFACT_HEAD_NOT_ATTESTED_BY_CANONICAL_REPOSITORY")
 def close(self)->None:
  tmp=getattr(self,"_tmp",None)
  if tmp is not None: tmp.cleanup(); self._tmp=None
 def __del__(self):
  try:self.close()
  except Exception:pass
 def _fetch_commit(self,revision:str)->None:
  p=subprocess.run([GIT_BIN,"-C",str(self.cache),"cat-file","-e",f"{revision}^{{commit}}"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=_safe_git_env())
  if p.returncode==0:return
  p=subprocess.run([GIT_BIN,"-C",str(self.cache),"fetch","-q","--depth=1","--no-tags",CANONICAL_REMOTE_URL,revision],stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=_safe_git_env())
  if p.returncode!=0: raise ResolutionError("CANONICAL_REMOTE_FETCH_FAILED",p.stderr.decode("utf-8","replace").strip()[:240])
  fetched=str(_git(self.cache,["rev-parse","FETCH_HEAD"],text=True)).strip()
  if fetched!=revision: raise ResolutionError("CANONICAL_REMOTE_REVISION_MISMATCH",f"expected={revision} observed={fetched}")
 def _raw(self,revision:str,path:str)->bytes:
  self._fetch_commit(revision)
  try:return bytes(_git(self.cache,["show",f"{revision}:{path}"]))
  except ResolutionError as exc: raise ResolutionError("CANONICAL_REMOTE_PATH_UNRESOLVED",f"{revision}:{path}") from exc
 def _verify_local_rel_against_canonical(self,rel:str)->None:
  local_path=self.root/rel
  if not local_path.is_file(): raise ResolutionError("GOVERNED_LOAD_BEARING_ARTIFACT_MISSING",rel)
  canonical=self._raw(self.artifact_head,rel)
  if _sha256(canonical)!=_sha256(local_path.read_bytes()): raise ResolutionError("BLOCK_GOVERNED_ARTIFACT_BYTE_MISMATCH",rel)
 def load_json_at_artifact_head(self,rel:str)->Mapping[str,Any]:
  raw=self._raw(self.artifact_head,rel)
  try:value=json.loads(raw.decode("utf-8"))
  except Exception as exc: raise ResolutionError("GOVERNED_CANONICAL_JSON_INVALID",rel) from exc
  if not isinstance(value,Mapping): raise ResolutionError("GOVERNED_CANONICAL_JSON_NOT_OBJECT",rel)
  return value
 def resolve(self,ref:str)->dict[str,Any]:
  if not isinstance(ref,str):raise ResolutionError("REF_MISSING")
  m=GITHUB_REF.fullmatch(ref.strip())
  if not m:raise ResolutionError("UNSUPPORTED_REF_SCHEME",str(ref)[:160])
  repo,revision,path=m.group("repo"),m.group("revision"),m.group("path")
  if repo!=CANONICAL_REPO_SLUG:raise ResolutionError("FOREIGN_REPO_NOT_RESOLVABLE_BY_GOVERNED_RESOLVER",repo)
  parts=Path(path).parts
  if path.startswith("/") or ".." in parts or not path or "\x00" in path or ":" in path:raise ResolutionError("UNSAFE_REPOSITORY_PATH",path[:160])
  raw=self._raw(revision,path); return {"ref":ref,"repo":repo,"revision":revision,"path":path,"sha256":_sha256(raw),"bytes":len(raw),"raw":raw}
 def content_current(self,observed:Mapping[str,Any])->bool:
  try:
   current_raw=self._raw(self.artifact_head,str(observed["path"]))
   if _sha256(current_raw)==observed.get("sha256"):return True
  except ResolutionError:pass
  for entry in (self.policy_snapshot.get("currentness") or {}).get("archival_registry") or []:
   if not isinstance(entry,Mapping) or entry.get("status")!="CURRENT":continue
   refs=[]
   if isinstance(entry.get("historical_ref"),str):refs.append(entry["historical_ref"])
   refs.extend([r for r in entry.get("historical_refs") or [] if isinstance(r,str)])
   if observed.get("ref") in refs and observed.get("sha256")==entry.get("sha256"):return True
  return False

def is_trusted_resolver(resolver:Any)->bool:return type(resolver) is S38GovernedRefResolver and resolver.verified is True
def block(code:str,**extra:Any)->dict[str,Any]:return {"status":BLOCKED,"code":code,**extra}
def resolve_source(resolver:Any,ref:str,expected_sha256:str,label:str,*,require_current_content:bool=True):
 if not is_trusted_resolver(resolver):return block("BLOCK_UNTRUSTED_RESOLVER_TYPE",binding=label),None
 try:observed=resolver.resolve(ref)
 except ResolutionError as exc:return block("BLOCK_TRUSTED_REF_RESOLUTION_FAILED",binding=label,resolver_code=exc.code),None
 except Exception as exc:return block("BLOCK_TRUSTED_REF_RESOLUTION_FAILED",binding=label,error=type(exc).__name__),None
 if observed.get("sha256")!=expected_sha256:return block("BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH",binding=label,expected=expected_sha256,observed=observed.get("sha256")),None
 if require_current_content and not resolver.content_current(observed):return block("BLOCK_PROVIDER_SOURCE_STALE",binding=label,ref=ref),None
 return {"status":PASS,"code":"PASS_GOVERNED_SOURCE_RESOLUTION","binding":label},observed
def resolve_json_binding(resolver:Any,binding:Mapping[str,Any]|None,expected_type:str,label:str,*,require_current_content:bool=True):
 if not isinstance(binding,Mapping):return block("BLOCK_EVIDENCE_BINDING_MISSING",binding=label),None,None
 if not is_trusted_resolver(resolver):return block("BLOCK_UNTRUSTED_RESOLVER_TYPE",binding=label),None,None
 if binding.get("resolver_id") not in ({resolver.resolver_id}|LEGACY_RESOLVER_IDS):return block("BLOCK_UNTRUSTED_RESOLVER_ID",binding=label),None,None
 ref=binding.get("ref");sha=binding.get("sha256") or binding.get("digest")
 if not isinstance(ref,str) or not ref:return block("BLOCK_EVIDENCE_REF_MISSING",binding=label),None,None
 if not isinstance(sha,str) or len(sha)!=64:return block("BLOCK_EVIDENCE_SHA256_INVALID",binding=label),None,None
 status,observed=resolve_source(resolver,ref,sha,label,require_current_content=require_current_content)
 if status.get("status")!=PASS:return status,None,observed
 try:record=json.loads(observed["raw"].decode("utf-8"))
 except Exception:return block("BLOCK_RESOLVED_EVIDENCE_NOT_JSON",binding=label),None,observed
 if not isinstance(record,Mapping):return block("BLOCK_RESOLVED_EVIDENCE_NOT_OBJECT",binding=label),None,observed
 if record.get("evidence_type")!=expected_type:return block("BLOCK_EVIDENCE_TYPE_MISMATCH",binding=label,expected=expected_type,observed=record.get("evidence_type")),None,observed
 if record.get("status")!=PASS:return block("BLOCK_RESOLVED_EVIDENCE_NOT_PASS",binding=label,observed=record.get("status")),None,observed
 return {"status":PASS,"code":"PASS_TRUSTED_JSON_EVIDENCE","binding":label},record,observed

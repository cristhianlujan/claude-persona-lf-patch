#!/usr/bin/env python3
"""Governed exact sandbox GET /body readback for LF IG transport-guard Edge.
Existing Management token is consumed by the pinned Supabase CLI, never logged.
No effecting write is allowed; importable for offline tests.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

PROJECT="mhwmirqcgxxukpctffuv"
ROLLOUT={
  "input-governance-agent-v1":19,
  "input-governance-validator-v1":20,
  "input-governance-curator-v1":15,
}
ROLLBACK="d25d3350346620d23a61de277cac796b3be6a8c3"
SHARED="supabase/functions/_shared/lf_ig_transport_guard_v1.ts"
MAX_SIZE=2_000_000
class ReadbackBlocked(Exception):
    pass

def sha(raw:bytes)->str: return hashlib.sha256(raw).hexdigest()

def validate(meta:dict,slug:str,mode:str,index:bytes,shared:bytes|None,expected_index:bytes,expected_shared:bytes|None)->dict:
    if slug not in ROLLOUT or mode not in ("before","after"):raise ReadbackBlocked("IG_DEPLOY_SCOPE_INVALID")
    if not isinstance(meta,dict) or meta.get("slug")!=slug:
        raise ReadbackBlocked("IG_READBACK_WRONG_SLUG")
    if meta.get("status")!="ACTIVE" or meta.get("verify_jwt") is not True:
        raise ReadbackBlocked("IG_READBACK_STATUS_OR_JWT_DRIFT")
    version=meta.get("version")
    if type(version) is not int or version < ROLLOUT[slug]+(mode=="after"):
        raise ReadbackBlocked("IG_READBACK_VERSION_NOT_ADVANCED")
    if mode=="before" and version!=ROLLOUT[slug]:
        raise ReadbackBlocked("IG_READBACK_PREVERSION_DRIFT")
    if not isinstance(index,bytes) or not 0<len(index)<=MAX_SIZE:
        raise ReadbackBlocked("IG_READBACK_INDEX_MISSING")
    if index!=expected_index:
        raise ReadbackBlocked("IG_READBACK_INDEX_SOURCE_DRIFT")
    if mode=="after":
        if not isinstance(shared,bytes) or not 0<len(shared)<=MAX_SIZE or shared!=expected_shared:
            raise ReadbackBlocked("IG_READBACK_SHARED_GUARD_DRIFT")
        if b'validateLfIgTransport' not in index:
            raise ReadbackBlocked("IG_DEPLOY_GUARD_IMPORT_MISSING")
    return {"status":"READBACK_PASS","project_ref":PROJECT,"slug":slug,"version":version,
        "verify_jwt":True,"index_sha256":sha(index),
        "guard_sha256":sha(shared) if shared else None,
        "mode":mode,"source_transport":"MANAGEMENT_BODY_UNBUNDLED_PINNED_CLI"}

def fetch_metadata(slug:str)->dict:
    token=os.environ.get("SUPABASE_ACCESS_TOKEN","")
    if slug not in ROLLOUT or not token:raise ReadbackBlocked("IG_MANAGEMENT_AUTHORITY_MISSING")
    url=f"https://api.supabase.com/v1/projects/{PROJECT}/functions/{slug}"
    req=Request(url,headers={"Authorization":"Bearer "+token,"Accept":"application/json","Cache-Control":"no-store"},method="GET")
    try:
        with urlopen(req,timeout=20) as res:
            if res.status!=200:raise ReadbackBlocked("IG_MANAGEMENT_NOT_200")
            return json.loads(res.read(2_000_000))
    except HTTPError as e:
        raise ReadbackBlocked("IG_MANAGEMENT_HTTP_"+str(e.code)) from None
    except (URLError,OSError,TimeoutError):
        raise ReadbackBlocked("IG_MANAGEMENT_UNAVAILABLE") from None

def fetch_body(slug:str)->tuple[bytes,bytes|None]:
    if slug not in ROLLOUT or not os.environ.get("SUPABASE_ACCESS_TOKEN"):
        raise ReadbackBlocked("IG_BODY_AUTHORITY_MISSING")
    with tempfile.TemporaryDirectory(prefix="lf-ig-guard-getbody-") as td:
        root=Path(td)
        config=Path("supabase/config.toml")
        if not config.is_file():raise ReadbackBlocked("IG_BODY_LOCAL_CONFIG_MISSING")
        (root/"supabase").mkdir()
        shutil.copyfile(config,root/"supabase/config.toml")
        cmd=["supabase","functions","download",slug,"--project-ref",PROJECT,"--use-api"]
        try:
            p=subprocess.run(cmd,cwd=str(root),env=os.environ.copy(),
                capture_output=True,timeout=120,check=False)
        except (OSError,subprocess.TimeoutExpired):
            raise ReadbackBlocked("IG_BODY_DOWNLOAD_UNAVAILABLE") from None
        if p.returncode!=0:raise ReadbackBlocked("IG_BODY_DOWNLOAD_REJECTED")
        source=root/"supabase/functions"/slug/"index.ts"
        if not source.is_file() or source.is_symlink() or source.stat().st_size>MAX_SIZE:
            raise ReadbackBlocked("IG_BODY_INDEX_NOT_DOWNLOADED")
        share=root/SHARED
        if share.is_symlink():raise ReadbackBlocked("IG_BODY_SHARED_SYMLINK")
        return source.read_bytes(), share.read_bytes() if share.is_file() else None

def github_source(path:str,ref:str)->bytes:
    if ref not in ("HEAD",ROLLBACK):raise ReadbackBlocked("IG_SOURCE_REF_UNTRUSTED")
    cmd=["git","show",ref+":"+path]
    p=subprocess.run(cmd,capture_output=True,timeout=25,check=False)
    if p.returncode or not p.stdout or len(p.stdout)>MAX_SIZE:
        raise ReadbackBlocked("IG_REPO_SOURCE_UNAVAILABLE")
    return p.stdout

def main(argv):
    if len(argv)!=3:raise ReadbackBlocked("IG_READBACK_ARGS_INVALID")
    slug,mode=argv[1:]
    if slug not in ROLLOUT or mode not in ("before","after"):
        raise ReadbackBlocked("IG_READBACK_SCOPE_INVALID")
    ref=ROLLBACK if mode=="before" else "HEAD"
    expected_index=github_source("supabase/functions/"+slug+"/index.ts",ref)
    expected_shared=github_source(SHARED,ref) if mode=="after" else None
    index,shared=fetch_body(slug)
    return validate(fetch_metadata(slug),slug,mode,index,shared,expected_index,expected_shared)

if __name__=="__main__":
    try:
        print(json.dumps(main(sys.argv),sort_keys=True))
    except (ReadbackBlocked,ValueError,json.JSONDecodeError) as e:
        print(json.dumps({"status":"BLOCKED","reason":str(e)}))
        raise SystemExit(2)

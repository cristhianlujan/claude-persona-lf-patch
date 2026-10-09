#!/usr/bin/env python3
"""GitHub Actions-only independent readback. Never writes to the VPS."""
import hashlib
import json
import os
import pathlib
import re
import subprocess
import tempfile
import urllib.request

def require(ok, message):
    if not ok:
        raise ValueError(message)

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def main():
    head=os.environ["EXACT_HEAD"]
    release=os.environ["RELEASE_PATH"]
    execution=os.environ["EXECUTION_ID"]
    require(re.fullmatch(r"[0-9a-f]{40}",head),"invalid SHA")
    require(release==f"/opt/lf-profile-runtime-api/releases/{head}","invalid release path")
    subprocess.check_call(["git","cat-file","-e",head+"^{commit}"])
    paths=subprocess.check_output(["git","ls-tree","-r","--name-only",head,"services/profile_runtime_api"],text=True).splitlines()
    require(bool(paths),"missing source manifest")
    manifest={p:sha256(subprocess.check_output(["git","show",head+":"+p])) for p in sorted(paths)}
    # A restricted VPS account with a forced command handles /health, /runtime,
    # /proc and file hashing read-only, using only the expected SHA parameter.
    # The remote command itself is provisioned by the VPS owner, not this PR.
    with tempfile.TemporaryDirectory() as tmp:
        key=pathlib.Path(tmp)/"ssh_key"
        hosts=pathlib.Path(tmp)/"known_hosts"
        key.write_text(os.environ["OBSERVER_PRIVATE_KEY"])
        hosts.write_text(os.environ["OBSERVER_KNOWN_HOSTS"])
        key.chmod(0o600)
        host=os.environ["OBSERVER_HOST"]
        user=os.environ["OBSERVER_USER"]
        require(re.fullmatch(r"[A-Za-z0-9_.-]+",host) is not None,"host invalid")
        require(re.fullmatch(r"[A-Za-z0-9_-]+",user) is not None,"user invalid")
        out=subprocess.check_output(["ssh","-F","/dev/null","-i",str(key),
            "-o","BatchMode=yes","-o","IdentitiesOnly=yes",
            "-o","StrictHostKeyChecking=yes","-o",f"UserKnownHostsFile={hosts}",
            f"{user}@{host}",f"readback {head}"],timeout=90)
    observed=json.loads(out)
    require(isinstance(observed,dict),"observer payload invalid")
    require(observed.get("source_sha")==head,"runtime SHA drift")
    require(observed.get("process_release_path")==release,"process not executing release")
    require(observed.get("current_release_path")==release,"current symlink drift")
    require(observed.get("health_ok") is True,"unhealthy runtime")
    require(observed.get("runtime_checked") is True,"/runtime not independently read")
    actual=observed.get("file_hashes")
    require(isinstance(actual,dict) and actual==manifest,"actual release file hashes mismatch")
    canonical=json.dumps(manifest,sort_keys=True,separators=(",",":")).encode()
    receipt={
      "schema_version":"LF_RUNTIME_INDEPENDENT_READBACK_V1",
      "producer":"GITHUB_ACTIONS_VPS_READ_ONLY",
      "execution_id":execution,
      "exact_head":head,
      "release_path":release,
      "source_sha":head,
      "runtime_sha":observed["source_sha"],
      "health_ok":True,
      "files_verified":True,
      "manifest_matches":True,
      "process_release_matches":True,
      "manifest_digest":sha256(canonical),
      "file_hashes":actual,
      "workflow_run_id":os.environ["GITHUB_RUN_ID"],
      "workflow_run_attempt":os.environ["GITHUB_RUN_ATTEMPT"],
    }
    request_url=os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    separator="&" if "?" in request_url else "?"
    oidc_url=request_url+separator+"audience=lf-runtime-readback"
    token_request=urllib.request.Request(oidc_url,headers={
      "Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
    with urllib.request.urlopen(token_request,timeout=15) as response:
        oidc=json.load(response)["value"]
    edge=os.environ["READBACK_EDGE_URL"]
    require(edge.startswith("https://") and "/functions/v1/" in edge,"invalid edge URL")
    req=urllib.request.Request(edge,method="POST",
       headers={"Authorization":"Bearer "+oidc,"Content-Type":"application/json"},
       data=json.dumps(receipt,separators=(",",":")).encode())
    with urllib.request.urlopen(req,timeout=20) as response:
        result=json.load(response)
    require(result.get("authenticated_by")=="GITHUB_OIDC","OIDC receipt not stored")
    print(json.dumps({"receipt_id":result["receipt_id"],
        "decision":result.get("decision"),"execution_id":execution,"exact_head":head}))

if __name__=="__main__":
    main()

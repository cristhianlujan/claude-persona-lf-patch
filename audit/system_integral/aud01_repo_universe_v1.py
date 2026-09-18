#!/usr/bin/env python3
"""AUD-1 repository universe freezer.

Read-only GitHub tree inventory bound to a specific commit SHA.
Uses only Python stdlib. Emits JSON to stdout.
"""
from __future__ import annotations
import argparse, json, os, urllib.request

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument("--repo", default="cristhianlujan/claude-persona-lf-patch")
    ap.add_argument("--sha", default="dafe10a6a730d63bc59ce036360f214cd6fd8d96")
    ns=ap.parse_args()
    url=f"https://api.github.com/repos/{ns.repo}/git/trees/{ns.sha}?recursive=1"
    headers={"Accept":"application/vnd.github+json","User-Agent":"lf-system-integral-audit"}
    token=os.getenv("GITHUB_TOKEN")
    if token: headers["Authorization"]=f"Bearer {token}"
    req=urllib.request.Request(url,headers=headers)
    with urllib.request.urlopen(req,timeout=30) as resp:
        data=json.load(resp)
    blobs=[x for x in data.get("tree",[]) if x.get("type")=="blob"]
    def n(prefix=None,suffix=None):
        xs=blobs
        if prefix is not None: xs=[x for x in xs if x["path"].startswith(prefix)]
        if suffix is not None: xs=[x for x in xs if x["path"].endswith(suffix)]
        return len(xs)
    workflows=sorted(x["path"] for x in blobs if x["path"].startswith(".github/workflows/") and x["path"].endswith((".yml",".yaml")))
    runnerish=sorted(
        x["path"] for x in blobs
        if x["path"].endswith((".py",".ts",".js",".sh"))
        and any("/"+k in "/"+x["path"].lower() for k in ("run","runner","execute","executor","validate","validator","check"))
    )
    out={
      "schema_version":"aud01-repo-universe/v1",
      "repo":ns.repo,"main_sha":ns.sha,
      "tree_sha":data.get("sha"),"truncated":bool(data.get("truncated")),
      "total_entries":len(data.get("tree",[])),"total_files":len(blobs),
      "python_files":n(suffix=".py"),"sql_files":n(suffix=".sql"),
      "workflows":workflows,"workflow_count":len(workflows),
      "families":{
        "profiles_files":n(prefix="profiles/"),"cards_files":n(prefix="cards/"),
        "adapters_files":n(prefix="adapters/"),"skills_files":n(prefix="skills/"),
        "governance_files":n(prefix="gobernanza/"),"docs_files":n(prefix="docs/"),
        "sandbox_files":n(prefix="sandbox/"),"sandbox_runs_files":n(prefix="sandbox_runs/"),
        "services_files":n(prefix="services/"),"supabase_files":n(prefix="supabase/")
      },
      "runnerish_count":len(runnerish)
    }
    print(json.dumps(out,sort_keys=True,separators=(",",":")))

if __name__=="__main__":
    main()

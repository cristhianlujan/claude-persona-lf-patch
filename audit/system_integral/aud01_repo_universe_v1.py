#!/usr/bin/env python3
"""AUD-1 repository universe freezer v2.

Read-only, SHA-bound and source-portable. The old heuristic runnerish_count is
retired: it matched substrings such as "runtime". Executables are classified
only by declarations observable in repository content.

Sources:
  --source auto|api|tarball|local
  API and tarball must resolve the same immutable SHA. local requires --root.
Uses only Python stdlib. Emits deterministic JSON.
"""
from __future__ import annotations
import argparse, io, json, os, pathlib, re, tarfile, urllib.request

EXEC_SUFFIXES=(".py",".sh",".ts",".js")
WORKFLOW_PATH_RE=re.compile(r"(?<![A-Za-z0-9_.-])((?:\.?[A-Za-z0-9_-]+/)+[A-Za-z0-9_.-]+\.(?:py|sh|ts|js))(?![A-Za-z0-9_.-])")
PY_MAIN_RE=re.compile(r"""if\s+__name__\s*==\s*["']__main__["']\s*:""")
EDGE_RE=re.compile(r"^supabase/functions/[^/]+/(?:index|main)\.(?:ts|js)$")

def _request(url:str, token:str|None=None):
    h={"Accept":"application/vnd.github+json","User-Agent":"lf-system-integral-audit"}
    if token: h["Authorization"]=f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url,headers=h),timeout=60)

def load_api(repo:str,sha:str,token:str|None):
    base=f"https://api.github.com/repos/{repo}"
    with _request(f"{base}/git/trees/{sha}?recursive=1",token) as r:
        tree=json.load(r)
    if tree.get("truncated"): raise RuntimeError("recursive Git tree is truncated")
    blobs=[x for x in tree.get("tree",[]) if x.get("type")=="blob"]
    cache={}
    def read(path:str)->str:
        if path not in cache:
            item=next(x for x in blobs if x["path"]==path)
            with _request(item["url"],token) as r: raw=json.load(r)
            import base64
            cache[path]=base64.b64decode(raw["content"]).decode("utf-8","replace")
        return cache[path]
    return [x["path"] for x in blobs],read,tree.get("sha")

def load_tarball(repo:str,sha:str,token:str|None):
    url=f"https://codeload.github.com/{repo}/tar.gz/{sha}"
    with _request(url,token) as r: payload=r.read()
    tf=tarfile.open(fileobj=io.BytesIO(payload),mode="r:gz")
    members=[m for m in tf.getmembers() if m.isfile()]
    prefix=members[0].name.split("/",1)[0]+"/" if members else ""
    paths=[m.name[len(prefix):] for m in members]
    by_path={m.name[len(prefix):]:m for m in members}
    def read(path:str)->str:
        f=tf.extractfile(by_path[path])
        return (f.read() if f else b"").decode("utf-8","replace")
    return paths,read,sha

def load_local(root:str,sha:str):
    p=pathlib.Path(root)
    paths=sorted(str(x.relative_to(p)).replace(os.sep,"/") for x in p.rglob("*") if x.is_file())
    def read(path:str)->str: return (p/path).read_text(encoding="utf-8",errors="replace")
    return paths,read,sha

def classify(paths,read):
    pathset=set(paths)
    workflows=sorted(p for p in paths if p.startswith(".github/workflows/") and p.endswith((".yml",".yaml")))
    workflow_invoked=set()
    for wf in workflows:
        for m in WORKFLOW_PATH_RE.finditer(read(wf)):
            p=m.group(1).removeprefix("./")
            if p in pathset and p.endswith(EXEC_SUFFIXES): workflow_invoked.add(p)
    edge=sorted(p for p in paths if EDGE_RE.match(p))
    py_main=[]
    for p in paths:
        if p.endswith(".py") and PY_MAIN_RE.search(read(p)): py_main.append(p)
    declared=sorted(set(workflow_invoked)|set(edge)|set(py_main))
    return {
      "workflow_paths":workflows,
      "workflow_invoked_executables":sorted(workflow_invoked),
      "edge_entrypoints":edge,
      "python_main_entrypoints":sorted(py_main),
      "declared_repo_executables":declared,
      "counts":{
        "workflows":len(workflows),
        "workflow_invoked_executables":len(workflow_invoked),
        "edge_entrypoints":len(edge),
        "python_main_entrypoints":len(py_main),
        "declared_repo_executables_union":len(declared)
      },
      "contract_bound_validators_note":"Joined separately by aud01_contract_bound_executables_v1.sql; do not infer from filename."
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--repo",default="cristhianlujan/claude-persona-lf-patch")
    ap.add_argument("--sha",default="dafe10a6a730d63bc59ce036360f214cd6fd8d96")
    ap.add_argument("--source",choices=("auto","api","tarball","local"),default="auto")
    ap.add_argument("--root")
    ns=ap.parse_args(); token=os.getenv("GITHUB_TOKEN")
    errors=[]
    if ns.source=="local":
        if not ns.root: raise SystemExit("--root required for --source local")
        paths,read,tree_sha=load_local(ns.root,ns.sha); source="local"
    else:
        loaders=(("api",load_api),("tarball",load_tarball)) if ns.source=="auto" else ((ns.source,load_api if ns.source=="api" else load_tarball),)
        for source,loader in loaders:
            try:
                paths,read,tree_sha=loader(ns.repo,ns.sha,token); break
            except Exception as e:
                errors.append(f"{source}:{type(e).__name__}:{e}")
        else: raise RuntimeError("; ".join(errors))
    cls=classify(paths,read)
    out={
      "schema_version":"aud01-repo-universe/v2",
      "repo":ns.repo,"main_sha":ns.sha,"tree_sha":tree_sha,"source":source,
      "fallback_errors":errors,
      "total_files":len(paths),
      "python_files":sum(p.endswith(".py") for p in paths),
      "sql_files":sum(p.endswith(".sql") for p in paths),
      "families":{k:sum(p.startswith(v) for p in paths) for k,v in {
        "profiles_files":"profiles/","cards_files":"cards/","adapters_files":"adapters/",
        "skills_files":"skills/","governance_files":"gobernanza/","docs_files":"docs/",
        "sandbox_files":"sandbox/","sandbox_runs_files":"sandbox_runs/","services_files":"services/",
        "supabase_files":"supabase/"}.items()},
      "execution_declarations":cls
    }
    print(json.dumps(out,sort_keys=True,separators=(",",":")))

if __name__=="__main__":
    main()

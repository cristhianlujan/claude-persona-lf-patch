#!/usr/bin/env python3
"""AUD-2 repository dependency graph v1.

Read-only, SHA-bound. Sources: auto|api|tarball|local.
Emits:
- static Python import graph using ast
- dynamic spec_from_file_location declarations
- local paths declared by GitHub workflows, including sandbox/ paths
No filename-based runner heuristic.
"""
from __future__ import annotations
import argparse, ast, base64, io, json, os, pathlib, posixpath, re, tarfile, urllib.request

PATH_RE=re.compile(r"(?<![A-Za-z0-9_.-])((?:\.?[A-Za-z0-9_-]+/)+[A-Za-z0-9_.-]+)(?![A-Za-z0-9_.-])")

def request(url,token=None):
    h={"Accept":"application/vnd.github+json","User-Agent":"lf-system-integral-audit"}
    if token: h["Authorization"]=f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url,headers=h),timeout=60)

def load_api(repo,sha,token):
    base=f"https://api.github.com/repos/{repo}"
    with request(f"{base}/git/trees/{sha}?recursive=1",token) as r: tree=json.load(r)
    if tree.get("truncated"): raise RuntimeError("recursive tree truncated")
    blobs=[x for x in tree["tree"] if x.get("type")=="blob"]; cache={}
    def read(path):
        if path not in cache:
            item=next(x for x in blobs if x["path"]==path)
            with request(item["url"],token) as r: raw=json.load(r)
            cache[path]=base64.b64decode(raw["content"]).decode("utf-8","replace")
        return cache[path]
    return [x["path"] for x in blobs],read,tree.get("sha"),"api"

def load_tarball(repo,sha,token):
    with request(f"https://codeload.github.com/{repo}/tar.gz/{sha}",token) as r: payload=r.read()
    tf=tarfile.open(fileobj=io.BytesIO(payload),mode="r:gz")
    ms=[m for m in tf.getmembers() if m.isfile()]
    prefix=ms[0].name.split("/",1)[0]+"/" if ms else ""
    by={m.name[len(prefix):]:m for m in ms}; paths=sorted(by)
    def read(path):
        f=tf.extractfile(by[path]); return (f.read() if f else b"").decode("utf-8","replace")
    return paths,read,sha,"tarball"

def load_local(root,sha):
    p=pathlib.Path(root); paths=sorted(str(x.relative_to(p)).replace(os.sep,"/") for x in p.rglob("*") if x.is_file() and ".git" not in x.relative_to(p).parts)
    return paths,lambda path:(p/path).read_text(encoding="utf-8",errors="replace"),sha,"local"

def module_index(py_paths):
    idx={}
    for p in py_paths:
        if p.endswith("/__init__.py"): mod=p[:-12].replace("/",".")
        else: mod=p[:-3].replace("/",".")
        if mod: idx[mod]=p
    return idx

def resolve_module(name,idx):
    cur=name
    while cur:
        if cur in idx: return idx[cur]
        cur=cur.rsplit(".",1)[0] if "." in cur else ""
    return None

def source_package(path):
    mod=path[:-3].replace("/",".")
    if mod.endswith(".__init__"): return mod[:-9]
    return mod.rsplit(".",1)[0] if "." in mod else ""

def static_imports(paths,read):
    py=sorted(p for p in paths if p.endswith(".py")); idx=module_index(py)
    edges=set(); parsed=[]; parse_errors=[]; dynamic=[]
    for p in py:
        try: tree=ast.parse(read(p),filename=p)
        except SyntaxError as e:
            parse_errors.append({"path":p,"line":e.lineno,"error":e.msg}); continue
        parsed.append(p); pkg=source_package(p)
        for node in ast.walk(tree):
            if isinstance(node,ast.Import):
                for a in node.names:
                    dst=resolve_module(a.name,idx)
                    if dst and dst!=p: edges.add((p,dst,"IMPORT",a.name))
            elif isinstance(node,ast.ImportFrom):
                base=node.module or ""
                if node.level:
                    parts=pkg.split(".") if pkg else []
                    keep=max(0,len(parts)-node.level+1)
                    prefix=".".join(parts[:keep])
                    base=".".join(x for x in (prefix,base) if x)
                candidates=[base+"."+a.name for a in node.names if a.name!="*"]+[base]
                dst=next((resolve_module(c,idx) for c in candidates if c),None)
                if dst and dst!=p: edges.add((p,dst,"IMPORT_FROM",base))
            elif isinstance(node,ast.Call):
                fn=node.func
                name=(fn.attr if isinstance(fn,ast.Attribute) else fn.id if isinstance(fn,ast.Name) else "")
                if name=="spec_from_file_location":
                    lit=None
                    if len(node.args)>=2 and isinstance(node.args[1],ast.Constant) and isinstance(node.args[1].value,str): lit=node.args[1].value
                    dynamic.append({"source":p,"line":getattr(node,"lineno",None),"literal_path":lit})
    return py,parsed,parse_errors,sorted(edges),dynamic

def workflow_paths(paths,read):
    pathset=set(paths); wfs=sorted(p for p in paths if p.startswith(".github/workflows/") and p.endswith((".yml",".yaml")))
    refs=set(); sandbox=set()
    for wf in wfs:
        txt=read(wf)
        for m in PATH_RE.finditer(txt):
            raw=m.group(1).removeprefix("./").rstrip(",:)'\"")
            if raw in pathset: refs.add((wf,raw))
            if raw.startswith("sandbox/"): sandbox.add(raw)
    return wfs,sorted(refs),sorted(sandbox)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--repo",default="cristhianlujan/claude-persona-lf-patch")
    ap.add_argument("--sha",default="dafe10a6a730d63bc59ce036360f214cd6fd8d96")
    ap.add_argument("--source",choices=("auto","api","tarball","local"),default="auto"); ap.add_argument("--root")
    ns=ap.parse_args(); token=os.getenv("GITHUB_TOKEN"); errs=[]
    if ns.source=="local":
        if not ns.root: raise SystemExit("--root required")
        paths,read,tree_sha,source=load_local(ns.root,ns.sha)
    else:
        loaders=(("api",load_api),("tarball",load_tarball)) if ns.source=="auto" else ((ns.source,load_api if ns.source=="api" else load_tarball),)
        for _,loader in loaders:
            try: paths,read,tree_sha,source=loader(ns.repo,ns.sha,token); break
            except Exception as e: errs.append(f"{type(e).__name__}:{e}")
        else: raise RuntimeError("; ".join(errs))
    py,parsed,parse_errors,edges,dynamic=static_imports(paths,read)
    workflows,wfrefs,sandbox=workflow_paths(paths,read)
    out={
      "schema_version":"aud02-repo-dependency-graph/v1","repo":ns.repo,"main_sha":ns.sha,"tree_sha":tree_sha,"source":source,
      "fallback_errors":errs,
      "static_ast":{"python_files":len(py),"parsed_files":len(parsed),"parse_errors":parse_errors,"internal_edges":len(edges),"edges":[{"source":a,"target":b,"kind":k,"module":m} for a,b,k,m in edges]},
      "dynamic_imports":{"spec_from_file_location_calls":len(dynamic),"files":len({x["source"] for x in dynamic}),"declarations":dynamic},
      "workflows":{"count":len(workflows),"local_path_edges":len(wfrefs),"sandbox_paths":len(sandbox),"sandbox_path_list":sandbox,"edges":[{"source":a,"target":b,"kind":"WORKFLOW_PATH"} for a,b in wfrefs]}
    }
    print(json.dumps(out,sort_keys=True,separators=(",",":")))

if __name__=="__main__": main()

#!/usr/bin/env python3
"""AUD-2 repository dependency graph v2.

Read-only, SHA-bound. Sources: auto|api|tarball|local.
Static import metrics are explicit at three granularities:
- unique_file_pairs
- statement_edges
- alias_edges
Dynamic imports distinguish text references from executable AST calls.
Workflow sandbox routes are material only when exact file, exact directory, or glob.
"""
from __future__ import annotations
import argparse, ast, base64, io, json, os, pathlib, re, tarfile, urllib.request

SANDBOX_RE=re.compile(r'sandbox/[A-Za-z0-9_./*?{}:+-]+')
SPEC_TOKEN="spec_from_file_location"

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
    p=pathlib.Path(root)
    paths=sorted(str(x.relative_to(p)).replace(os.sep,"/") for x in p.rglob("*")
                 if x.is_file() and ".git" not in x.relative_to(p).parts)
    return paths,lambda path:(p/path).read_text(encoding="utf-8",errors="replace"),sha,"local"

def module_index(py_paths):
    idx={}
    for p in py_paths:
        mod=p[:-12].replace("/",".") if p.endswith("/__init__.py") else p[:-3].replace("/",".")
        if mod: idx[mod]=p
    return idx

def module_and_pkg(path):
    mod=path[:-12].replace("/",".") if path.endswith("/__init__.py") else path[:-3].replace("/",".")
    pkg=mod if path.endswith("/__init__.py") else (mod.rsplit(".",1)[0] if "." in mod else "")
    return mod,pkg

def local_variants(name,pkg):
    out=[name] if name else []; parts=pkg.split(".") if pkg else []
    for i in range(len(parts),0,-1):
        cand=".".join(parts[:i]+([name] if name else []))
        if cand: out.append(cand)
    return list(dict.fromkeys(out))

def resolve(cands,idx):
    for cand in cands:
        cur=cand
        while cur:
            if cur in idx: return idx[cur]
            cur=cur.rsplit(".",1)[0] if "." in cur else ""
    return None

def repo_graph(paths,read):
    py=sorted(p for p in paths if p.endswith(".py")); idx=module_index(py)
    pairs=set(); stmt=[]; aliases=[]; parse_errors=[]; dynamic_calls=[]; dynamic_text=[]
    for p in py:
        text=read(p)
        if SPEC_TOKEN in text: dynamic_text.append(p)
        try: tree=ast.parse(text,filename=p)
        except SyntaxError as e:
            parse_errors.append({"path":p,"line":e.lineno,"error":e.msg}); continue
        _,pkg=module_and_pkg(p)
        for node in ast.walk(tree):
            if isinstance(node,ast.Import):
                dsts=[]
                for a in node.names:
                    dst=resolve(local_variants(a.name,pkg),idx)
                    if dst and dst!=p:
                        pairs.add((p,dst)); aliases.append((p,dst,a.name,node.lineno)); dsts.append(dst)
                for dst in sorted(set(dsts)): stmt.append((p,dst,node.lineno,"IMPORT"))
            elif isinstance(node,ast.ImportFrom):
                base=node.module or ""
                if node.level:
                    parts=pkg.split(".") if pkg else []; keep=max(0,len(parts)-node.level+1)
                    bases=[".".join(parts[:keep]+([base] if base else []))]
                else: bases=local_variants(base,pkg)
                dsts=[]
                for a in node.names:
                    cands=[]
                    if a.name!="*": cands += [(b+"."+a.name).strip(".") for b in bases]
                    cands += bases
                    dst=resolve(cands,idx)
                    if dst and dst!=p:
                        pairs.add((p,dst)); aliases.append((p,dst,(base+"."+a.name).strip("."),node.lineno)); dsts.append(dst)
                for dst in sorted(set(dsts)): stmt.append((p,dst,node.lineno,"IMPORT_FROM"))
            elif isinstance(node,ast.Call):
                f=node.func; name=f.attr if isinstance(f,ast.Attribute) else f.id if isinstance(f,ast.Name) else ""
                if name==SPEC_TOKEN:
                    lit=node.args[1].value if len(node.args)>=2 and isinstance(node.args[1],ast.Constant) and isinstance(node.args[1].value,str) else None
                    dynamic_calls.append({"source":p,"line":getattr(node,"lineno",None),"literal_path":lit})
    return {
      "python_files":len(py),"parsed_files":len(py)-len(parse_errors),"parse_errors":parse_errors,
      "unique_file_pairs":len(pairs),"statement_edges":len(stmt),"alias_edges":len(aliases),
      "pair_edges":[{"source":a,"target":b} for a,b in sorted(pairs)],
      "dynamic_text_reference_files":len(set(dynamic_text)),
      "dynamic_ast_call_files":len({x["source"] for x in dynamic_calls}),
      "dynamic_ast_calls":len(dynamic_calls),"dynamic_declarations":dynamic_calls
    }

def workflows(paths,read):
    pathset=set(paths); wfs=sorted(p for p in paths if p.startswith(".github/workflows/") and p.endswith((".yml",".yaml")))
    dirs=set()
    for p in paths:
        parts=p.split("/")
        for i in range(1,len(parts)): dirs.add("/".join(parts[:i]))
    raw=set(); material=set(); dyn_occ=0
    for wf in wfs:
        text=read(wf); dyn_occ += text.count(SPEC_TOKEN)
        for m in SANDBOX_RE.finditer(text):
            tok=m.group(0).rstrip(".,;:)'\"}]"); raw.add(tok)
            if tok in pathset or tok in dirs or any(c in tok for c in "*?["): material.add(tok)
    return {
      "count":len(wfs),"paths":wfs,"dynamic_spec_occurrences":dyn_occ,
      "sandbox_tokens_raw":len(raw),"sandbox_routes_material":len(material),
      "sandbox_routes":sorted(material),"discarded_nonmaterial_tokens":sorted(raw-material)
    }

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--repo",default="cristhianlujan/claude-persona-lf-patch")
    ap.add_argument("--sha",default="dafe10a6a730d63bc59ce036360f214cd6fd8d96")
    ap.add_argument("--source",choices=("auto","api","tarball","local"),default="auto"); ap.add_argument("--root")
    ns=ap.parse_args(); token=os.getenv("GITHUB_TOKEN"); errs=[]
    if ns.source=="local":
        if not ns.root: raise SystemExit("--root required")
        paths,read,tree_sha,source=load_local(ns.root,ns.sha)
    else:
        loaders=(load_api,load_tarball) if ns.source=="auto" else ((load_api,) if ns.source=="api" else (load_tarball,))
        for loader in loaders:
            try: paths,read,tree_sha,source=loader(ns.repo,ns.sha,token); break
            except Exception as e: errs.append(f"{type(e).__name__}:{e}")
        else: raise RuntimeError("; ".join(errs))
    out={"schema_version":"aud02-repo-dependency-graph/v2","repo":ns.repo,"main_sha":ns.sha,"tree_sha":tree_sha,
         "source":source,"fallback_errors":errs,"static_ast":repo_graph(paths,read),"workflows":workflows(paths,read)}
    print(json.dumps(out,sort_keys=True,separators=(",",":")))
if __name__=="__main__": main()

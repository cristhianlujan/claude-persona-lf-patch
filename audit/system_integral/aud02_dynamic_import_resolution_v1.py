#!/usr/bin/env python3
"""AUD-2 dynamic import resolver v1.

Read-only static dataflow for importlib.util.spec_from_file_location.
Resolves simple Path/str/join assignments without executing repository code.
Every call is emitted as RESOLVED_EXISTING, RESOLVED_MISSING, or UNRESOLVED_DYNAMIC.
"""
from __future__ import annotations
import argparse,ast,json,os,pathlib

SPEC="spec_from_file_location"
UNKNOWN=object()

def func_name(n):
    if isinstance(n,ast.Name): return n.id
    if isinstance(n,ast.Attribute):
        p=func_name(n.value)
        return (p+"."+n.attr) if p else n.attr
    return ""

class Eval:
    def __init__(self,root:pathlib.Path,source:pathlib.Path,env=None):
        self.root=root.resolve(); self.source=source.resolve()
        self.env=dict(env or {}); self.env["__file__"]=self.source
    def ev(self,n):
        if n is None:return UNKNOWN
        if isinstance(n,ast.Constant) and isinstance(n.value,(str,int)):return n.value
        if isinstance(n,ast.Name):return self.env.get(n.id,UNKNOWN)
        if isinstance(n,ast.BinOp):
            a,b=self.ev(n.left),self.ev(n.right)
            if a is UNKNOWN or b is UNKNOWN:return UNKNOWN
            if isinstance(n.op,ast.Div):
                try:return pathlib.Path(a)/str(b)
                except:return UNKNOWN
            if isinstance(n.op,ast.Add):
                try:return a+b
                except:return UNKNOWN
        if isinstance(n,ast.Attribute):
            v=self.ev(n.value)
            if v is UNKNOWN:return UNKNOWN
            if n.attr=="parent":
                try:return pathlib.Path(v).parent
                except:return UNKNOWN
            if n.attr=="name":
                try:return pathlib.Path(v).name
                except:return UNKNOWN
            if n.attr=="stem":
                try:return pathlib.Path(v).stem
                except:return UNKNOWN
        if isinstance(n,ast.Subscript) and isinstance(n.value,ast.Attribute) and n.value.attr=="parents":
            v=self.ev(n.value.value); idx=self.ev(n.slice)
            if v is UNKNOWN or not isinstance(idx,int):return UNKNOWN
            try:return pathlib.Path(v).parents[idx]
            except:return UNKNOWN
        if isinstance(n,ast.Call):
            fn=func_name(n.func)
            args=[self.ev(x) for x in n.args]
            if fn in ("Path","pathlib.Path"):
                if not args or args[0] is UNKNOWN:return UNKNOWN
                return pathlib.Path(args[0])
            if fn in ("str",):
                if not args or args[0] is UNKNOWN:return UNKNOWN
                return str(args[0])
            if fn.endswith(".resolve"):
                base=self.ev(n.func.value) if isinstance(n.func,ast.Attribute) else UNKNOWN
                return base
            if fn in ("os.path.join","posixpath.join"):
                if any(x is UNKNOWN for x in args):return UNKNOWN
                return pathlib.Path(str(args[0])).joinpath(*map(str,args[1:]))
            if fn.endswith(".joinpath"):
                base=self.ev(n.func.value) if isinstance(n.func,ast.Attribute) else UNKNOWN
                if base is UNKNOWN or any(x is UNKNOWN for x in args):return UNKNOWN
                return pathlib.Path(base).joinpath(*map(str,args))
        return UNKNOWN

def targets(n):
    if isinstance(n,(ast.Tuple,ast.List)):
        return [x.id for x in n.elts if isinstance(x,ast.Name)]
    return [n.id] if isinstance(n,ast.Name) else []

def normalize(v,root,source):
    if v is UNKNOWN:return None
    p=pathlib.Path(v)
    if not p.is_absolute():
        # Repo code commonly builds either source-relative or cwd/repo-relative paths.
        cands=[(source.parent/p).resolve(),(root/p).resolve()]
    else:cands=[p.resolve()]
    for c in cands:
        try:
            rel=c.relative_to(root)
            if c.exists():return rel.as_posix()
        except ValueError:pass
    # Prefer any in-repo candidate even if missing.
    for c in cands:
        try:return c.relative_to(root).as_posix()
        except ValueError:continue
    return str(cands[0])

def process_block(stmts,ev,rows):
    for st in stmts:
        if isinstance(st,(ast.Assign,ast.AnnAssign)):
            val=ev.ev(st.value)
            tgs=[]
            if isinstance(st,ast.Assign):
                for t in st.targets:tgs+=targets(t)
            else:tgs+=targets(st.target)
            for t in tgs:ev.env[t]=val
        # Process direct calls in this statement after assignments.
        for n in ast.walk(st):
            if isinstance(n,ast.Call) and func_name(n.func).split(".")[-1]==SPEC:
                arg=n.args[1] if len(n.args)>=2 else None
                v=ev.ev(arg); target=normalize(v,ev.root,ev.source)
                exists=bool(target and (ev.root/target).exists())
                status="UNRESOLVED_DYNAMIC" if target is None else ("RESOLVED_EXISTING" if exists else "RESOLVED_MISSING")
                rows.append({"source":ev.source.relative_to(ev.root).as_posix(),"line":getattr(n,"lineno",None),
                             "arg_expr":ast.unparse(arg) if arg else None,"status":status,"target":target})
        if isinstance(st,(ast.If,ast.For,ast.While,ast.With,ast.Try)):
            blocks=[]
            for attr in ("body","orelse","finalbody"):
                blocks+=list(getattr(st,attr,[]) or [])
            for h in getattr(st,"handlers",[]) or []:blocks+=h.body
            process_block(blocks,Eval(ev.root,ev.source,ev.env),rows)
        elif isinstance(st,(ast.FunctionDef,ast.AsyncFunctionDef)):
            # Module constants are visible; parameters are deliberately unresolved.
            child=Eval(ev.root,ev.source,ev.env)
            for a in list(st.args.args)+list(st.args.kwonlyargs):child.env.pop(a.arg,None)
            if st.args.vararg:child.env.pop(st.args.vararg.arg,None)
            if st.args.kwarg:child.env.pop(st.args.kwarg.arg,None)
            process_block(st.body,child,rows)

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
    root=pathlib.Path(ns.root).resolve();rows=[];text_ref=[]
    for source in sorted(root.rglob("*.py")):
        if ".git" in source.relative_to(root).parts:continue
        text=source.read_text(encoding="utf-8",errors="replace")
        if SPEC not in text:continue
        text_ref.append(source.relative_to(root).as_posix())
        try:tree=ast.parse(text,filename=str(source))
        except SyntaxError:continue
        process_block(tree.body,Eval(root,source),rows)
    counts={k:sum(r["status"]==k for r in rows) for k in ("RESOLVED_EXISTING","RESOLVED_MISSING","UNRESOLVED_DYNAMIC")}
    print(json.dumps({"schema_version":"aud02-dynamic-import-resolution/v1",
      "text_reference_files":len(set(text_ref)),"calls":len(rows),"counts":counts,"rows":rows},
      sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

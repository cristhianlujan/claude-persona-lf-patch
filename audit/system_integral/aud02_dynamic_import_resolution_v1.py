#!/usr/bin/env python3
"""AUD-2 dynamic import resolver v2.

Read-only static dataflow for importlib.util.spec_from_file_location.
Resolves simple module/local assignments made from Path/str/join expressions
without executing repository code. Each AST call is emitted exactly once.
"""
from __future__ import annotations
import argparse,ast,json,pathlib

SPEC="spec_from_file_location"
UNKNOWN=object()

def fname(n):
    if isinstance(n,ast.Name): return n.id
    if isinstance(n,ast.Attribute):
        p=fname(n.value); return (p+"."+n.attr) if p else n.attr
    return ""

class Eval:
    def __init__(self,root,source,env=None):
        self.root=pathlib.Path(root).resolve(); self.source=pathlib.Path(source).resolve()
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
            try:
                if n.attr=="parent":return pathlib.Path(v).parent
                if n.attr=="name":return pathlib.Path(v).name
                if n.attr=="stem":return pathlib.Path(v).stem
            except:return UNKNOWN
        if isinstance(n,ast.Subscript) and isinstance(n.value,ast.Attribute) and n.value.attr=="parents":
            v=self.ev(n.value.value); idx=self.ev(n.slice)
            if v is UNKNOWN or not isinstance(idx,int):return UNKNOWN
            try:return pathlib.Path(v).parents[idx]
            except:return UNKNOWN
        if isinstance(n,ast.Call):
            fn=fname(n.func); args=[self.ev(x) for x in n.args]
            if fn in ("Path","pathlib.Path"):
                if not args or args[0] is UNKNOWN:return UNKNOWN
                return pathlib.Path(args[0])
            if fn=="str":
                if not args or args[0] is UNKNOWN:return UNKNOWN
                return str(args[0])
            if fn.endswith(".resolve"):
                return self.ev(n.func.value) if isinstance(n.func,ast.Attribute) else UNKNOWN
            if fn in ("os.path.join","posixpath.join"):
                if not args or any(x is UNKNOWN for x in args):return UNKNOWN
                return pathlib.Path(str(args[0])).joinpath(*map(str,args[1:]))
            if fn.endswith(".joinpath"):
                base=self.ev(n.func.value) if isinstance(n.func,ast.Attribute) else UNKNOWN
                if base is UNKNOWN or any(x is UNKNOWN for x in args):return UNKNOWN
                return pathlib.Path(base).joinpath(*map(str,args))
        return UNKNOWN

def assign_names(target):
    if isinstance(target,ast.Name):return [target.id]
    if isinstance(target,(ast.Tuple,ast.List)):
        return [x.id for x in target.elts if isinstance(x,ast.Name)]
    return []

def apply_assignment(st,ev):
    if isinstance(st,ast.Assign):
        v=ev.ev(st.value)
        for t in st.targets:
            for n in assign_names(t):ev.env[n]=v
    elif isinstance(st,ast.AnnAssign):
        v=ev.ev(st.value)
        for n in assign_names(st.target):ev.env[n]=v

def normalize(v,root,source):
    if v is UNKNOWN:return None
    p=pathlib.Path(v)
    cands=[p.resolve()] if p.is_absolute() else [(source.parent/p).resolve(),(root/p).resolve()]
    for c in cands:
        try:
            rel=c.relative_to(root)
            if c.exists():return rel.as_posix()
        except ValueError:pass
    for c in cands:
        try:return c.relative_to(root).as_posix()
        except ValueError:continue
    return str(cands[0])

class DirectCallVisitor(ast.NodeVisitor):
    def __init__(self):self.calls=[]
    def visit_Call(self,node):
        if fname(node.func).split(".")[-1]==SPEC:self.calls.append(node)
        self.generic_visit(node)
    def visit_FunctionDef(self,node):pass
    def visit_AsyncFunctionDef(self,node):pass
    def visit_ClassDef(self,node):pass
    def visit_If(self,node):self.visit(node.test)
    def visit_For(self,node):self.visit(node.target);self.visit(node.iter)
    def visit_AsyncFor(self,node):self.visit(node.target);self.visit(node.iter)
    def visit_While(self,node):self.visit(node.test)
    def visit_With(self,node):
        for x in node.items:self.visit(x.context_expr)
    def visit_AsyncWith(self,node):
        for x in node.items:self.visit(x.context_expr)
    def visit_Try(self,node):pass

def direct_calls(st):
    v=DirectCallVisitor();v.visit(st);return v.calls

def process_block(stmts,ev,rows):
    for st in stmts:
        apply_assignment(st,ev)
        for n in direct_calls(st):
            arg=n.args[1] if len(n.args)>=2 else None
            target=normalize(ev.ev(arg),ev.root,ev.source)
            exists=bool(target and (ev.root/target).exists())
            status="UNRESOLVED_DYNAMIC" if target is None else ("RESOLVED_EXISTING" if exists else "RESOLVED_MISSING")
            rows.append({"source":ev.source.relative_to(ev.root).as_posix(),"line":n.lineno,
                         "arg_expr":ast.unparse(arg) if arg else None,"status":status,"target":target})
        if isinstance(st,(ast.FunctionDef,ast.AsyncFunctionDef)):
            child=Eval(ev.root,ev.source,ev.env)
            for a in list(st.args.args)+list(st.args.kwonlyargs):child.env.pop(a.arg,None)
            if st.args.vararg:child.env.pop(st.args.vararg.arg,None)
            if st.args.kwarg:child.env.pop(st.args.kwarg.arg,None)
            process_block(st.body,child,rows)
        elif isinstance(st,ast.ClassDef):
            process_block(st.body,Eval(ev.root,ev.source,ev.env),rows)
        elif isinstance(st,(ast.If,ast.For,ast.AsyncFor,ast.While,ast.With,ast.AsyncWith,ast.Try)):
            for attr in ("body","orelse","finalbody"):
                b=getattr(st,attr,None)
                if b:process_block(b,Eval(ev.root,ev.source,ev.env),rows)
            for h in getattr(st,"handlers",[]) or []:process_block(h.body,Eval(ev.root,ev.source,ev.env),rows)

def global_env(tree,root,source):
    ev=Eval(root,source)
    # Fixed point allows constants declared after helper definitions and chains.
    for _ in range(4):
        before=dict(ev.env)
        for st in tree.body:
            if isinstance(st,(ast.Assign,ast.AnnAssign)):apply_assignment(st,ev)
        if ev.env==before:break
    return ev.env

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
    root=pathlib.Path(ns.root).resolve();rows=[];refs=[]
    for source in sorted(root.rglob("*.py")):
        if ".git" in source.relative_to(root).parts:continue
        text=source.read_text(encoding="utf-8",errors="replace")
        if SPEC not in text:continue
        refs.append(source.relative_to(root).as_posix())
        try:tree=ast.parse(text,filename=str(source))
        except SyntaxError:continue
        process_block(tree.body,Eval(root,source,global_env(tree,root,source)),rows)
    counts={k:sum(r["status"]==k for r in rows) for k in ("RESOLVED_EXISTING","RESOLVED_MISSING","UNRESOLVED_DYNAMIC")}
    print(json.dumps({"schema_version":"aud02-dynamic-import-resolution/v2","text_reference_files":len(set(refs)),
      "calls":len(rows),"counts":counts,"rows":rows},sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

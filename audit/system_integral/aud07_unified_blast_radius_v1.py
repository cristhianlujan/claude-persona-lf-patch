#!/usr/bin/env python3
"""AUD-7 unified blast-radius runner v1.

Inputs:
- a checkout of the frozen subject repo (--root)
- JSON produced by aud07_db_graph_export_v1.sql (--db-export)

It reuses AUD-2 repo graph/dynamic/cross-layer runners from this audit directory.
Direction is consumer -> dependency. Blast radius walks reverse edges.
Material and inferred function-body views are reported separately.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, pathlib, subprocess, sys

FREEZE="dafe10a6a730d63bc59ce036360f214cd6fd8d96"

def run_json(script,*args):
    out=subprocess.check_output([sys.executable,str(script),*map(str,args)],text=True)
    return json.loads(out)

def unwrap_db(raw):
    if isinstance(raw,dict) and "aud07_db_graph_export" in raw:
        return raw["aud07_db_graph_export"]
    if isinstance(raw,list) and len(raw)==1 and isinstance(raw[0],dict):
        return unwrap_db(raw[0])
    if isinstance(raw,dict) and "result" in raw and isinstance(raw["result"],dict):
        return unwrap_db(raw["result"])
    if isinstance(raw,dict) and "schema_version" in raw:
        return raw
    raise ValueError("unsupported DB export envelope")

def add(edges,s,t,k,evidence):
    if s and t and s!=t:
        edges.add((s,t,k,evidence))

def radius(edges):
    rev=collections.defaultdict(set); nodes=set()
    for s,t,_,_ in edges:
        rev[t].add(s); nodes.add(s); nodes.add(t)
    out={}
    for seed in nodes:
        seen=set(); stack=list(rev.get(seed,()))
        while stack:
            n=stack.pop()
            if n in seen: continue
            seen.add(n); stack.extend(rev.get(n,()))
        out[seed]=len(seen)
    return out,nodes

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",required=True)
    ap.add_argument("--db-export",required=True)
    ap.add_argument("--audit-dir",default=str(pathlib.Path(__file__).resolve().parent))
    ns=ap.parse_args()
    root=pathlib.Path(ns.root).resolve(); audit=pathlib.Path(ns.audit_dir)
    db=unwrap_db(json.load(open(ns.db_export,encoding="utf-8")))
    if db.get("freeze",{}).get("main_sha")!=FREEZE:
        raise SystemExit("DB export freeze mismatch")

    g=run_json(audit/"aud02_repo_dependency_graph_v1.py","--source","local","--root",root,"--sha",FREEZE)
    d=run_json(audit/"aud02_dynamic_import_resolution_v1.py","--root",root)
    b=run_json(audit/"aud02_repo_cross_layer_bridges_v1.py","--root",root)

    db_objects={x["name"]:x["kind"] for x in db["db_objects"]}
    material=set(); inferred=set(); unresolved_repo_db=[]
    for x in g["static_ast"]["pair_edges"]:
        add(material,"repo::"+x["source"],"repo::"+x["target"],"REPO_AST","MATERIAL")
    for x in d["rows"]:
        if x["status"]=="RESOLVED_EXISTING":
            add(material,"repo::"+x["source"],"repo::"+x["target"],"REPO_DYNAMIC","MATERIAL")
    for x in b["workflow_edges"]:
        add(material,"repo::"+x["source"],"repo::"+x["target"],"WORKFLOW_SCRIPT","MATERIAL")
    for x in b["repo_db_edges"]:
        kind=db_objects.get(x["target"])
        if kind=="RELATION":
            add(material,"repo::"+x["source"],"db::"+x["target"],"REPO_DB_REF","MATERIAL")
        elif kind=="FUNCTION_FAMILY":
            add(material,"repo::"+x["source"],"dbfn::"+x["target"],"REPO_DB_REF","MATERIAL")
        else:
            unresolved_repo_db.append(x)
    for x in db["material_edges"]:
        add(material,x["source"],x["target"],x["kind"],"MATERIAL")
    inferred=set(material)
    for x in db["inferred_edges"]:
        add(inferred,x["source"],x["target"],x["kind"],"INFERRED")

    mr,mnodes=radius(material); er,enodes=radius(inferred)
    top=sorted(enodes,key=lambda n:(-mr.get(n,0),-er.get(n,0),n))[:100]
    rows=[{"node":n,"material_dependents":mr.get(n,0),"expanded_dependents":er.get(n,0)} for n in top]
    mat_pairs=sorted((s,t) for s,t,_,_ in material)
    exp_pairs=sorted((s,t) for s,t,_,_ in inferred)
    result={
      "schema_version":"aud07-unified-blast-radius/v1",
      "freeze":{"main_sha":FREEZE,"schema_fp":"56c2af889d3f6a4781b1ac74ba7da5bb"},
      "repo_metrics":{
        "ast_pairs":g["static_ast"]["unique_file_pairs"],
        "dynamic_existing":d["counts"]["RESOLVED_EXISTING"],
        "dynamic_unresolved":d["counts"]["UNRESOLVED_DYNAMIC"],
        "workflow_script_edges":b["workflow_script_edges"],
        "repo_db_edges_declared":b["repo_db_text_edges"],
        "repo_db_edges_material":b["repo_db_text_edges"]-len(unresolved_repo_db),
        "repo_db_unresolved":len(unresolved_repo_db)
      },
      "db_metrics":db.get("metrics",{}),
      "material":{"edges":len(mat_pairs),"nodes":len(mnodes),
        "repo_nodes":sum(n.startswith("repo::") for n in mnodes),
        "db_nodes":sum(n.startswith(("db::","dbfn::")) for n in mnodes),
        "operation_nodes":sum(n.startswith(("op::","step::","contract::","judge::","policy::")) for n in mnodes),
        "fingerprint":hashlib.md5("\n".join(f"{a}|{b}" for a,b in mat_pairs).encode()).hexdigest()},
      "expanded":{"edges":len(exp_pairs),"nodes":len(enodes),
        "fingerprint":hashlib.md5("\n".join(f"{a}|{b}" for a,b in exp_pairs).encode()).hexdigest()},
      "top_material_blast_radius":rows,
      "unresolved_repo_db":unresolved_repo_db,
      "candidate_unqualified_count":len(db.get("candidate_unqualified",[]))
    }
    print(json.dumps(result,sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

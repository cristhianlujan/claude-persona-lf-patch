#!/usr/bin/env python3
"""Verify an E.13 bundle against an externally anchored receipt digest."""
from __future__ import annotations
import argparse, json, re, sys
sys.dont_write_bytecode=True
from pathlib import Path
from typing import Any
import PR93_LOTE_E13_CAPTURE as cap

SHA256 = re.compile(r"^[0-9a-f]{64}$")
FILES = (
 "PR93_E13_FULL_TRANSCRIPT.log","PR93_E13_T1_TRANSCRIPT.log",
 "PR93_E13_T2_TRANSCRIPT.log","PR93_E13_PRE_STATE.json",
 "PR93_E13_POST_STATE.json","PR93_E13_PRE_STATE_COMMAND.log",
 "PR93_E13_POST_STATE_COMMAND.log",
)

def fail(msg:str)->None: raise ValueError(msg)
def one(lines:list[str], value:str, prefix:bool=False)->int:
    hits=[i for i,x in enumerate(lines) if x.startswith(value) if prefix] if prefix else [i for i,x in enumerate(lines) if x==value]
    if len(hits)!=1: fail(f"marker {value!r} count={len(hits)}")
    return hits[0]
def intval(lines:list[str], prefix:str)->int: return int(lines[one(lines,prefix,True)][len(prefix):])
def boolval(lines:list[str], prefix:str)->bool:
    value=lines[one(lines,prefix,True)][len(prefix):]
    if value not in {"true","false"}: fail(f"invalid boolean {prefix}")
    return value=="true"
def child(root:Path,name:str)->Path:
    if Path(name).name!=name or name in {".",".."}: fail(f"unsafe filename {name}")
    path=(root/name).resolve()
    if path.parent!=root.resolve(): fail(f"path escapes bundle {name}")
    return path

def verify_sources(r:dict[str,Any], repo:Path)->None:
    if cap.git_text(repo,["rev-parse","HEAD"],30)!=r["head_sha"]: fail("HEAD mismatch")
    if cap.git_text(repo,["status","--porcelain=v1","--untracked-files=all"],30): fail("dirty repository")
    sources=r.get("source_artifacts")
    if not isinstance(sources,dict) or not sources: fail("missing sources")
    for rel,meta in sources.items():
        if not isinstance(rel,str) or rel.startswith("/") or ".." in Path(rel).parts: fail("unsafe source")
        path=repo/rel
        if not path.is_file(): fail(f"missing source {rel}")
        data=path.read_bytes()
        if cap.sha256_bytes(data)!=meta.get("sha256") or len(data)!=meta.get("size_bytes"): fail(f"source mismatch {rel}")
        if cap.git_text(repo,["rev-parse",f"HEAD:{rel}"],30)!=meta.get("git_blob_sha1"): fail(f"blob mismatch {rel}")

def verify_bundle(r:dict[str,Any], root:Path)->None:
    evidence=r.get("evidence_files")
    if not isinstance(evidence,dict) or set(evidence)!=set(FILES): fail("evidence set mismatch")
    loaded={}
    for name in FILES:
        path=child(root,name)
        if not path.is_file(): fail(f"missing {name}")
        data=path.read_bytes(); meta=evidence[name]; loaded[name]=data
        if cap.sha256_bytes(data)!=meta.get("sha256"): fail(f"hash mismatch {name}")
        if len(data)!=meta.get("size_bytes") or cap.exact_line_count(data)!=meta.get("line_count"): fail(f"metadata mismatch {name}")
    full=loaded[FILES[0]].decode().splitlines(); t1=loaded[FILES[1]].decode().splitlines(); t2=loaded[FILES[2]].decode().splitlines()
    if not full or full[0]!="E13_CAPTURE_BEGIN" or full[-1]!="E13_CAPTURE_END": fail("full boundary mismatch")
    markers=[
      ("E13_HEAD_SHA=",1),("E13_STARTED_AT=",1),("E13_T1_PROCESS_BEGIN",0),("E13_T1_PROCESS_EXIT=",1),
      ("E13_T2_PRE_STATE_BEGIN",0),("E13_T2_PRE_STATE_EXIT=",1),("E13_T2_PROCESS_BEGIN",0),("E13_T2_PROCESS_EXIT=",1),
      ("E13_T2_POST_STATE_BEGIN",0),("E13_T2_POST_STATE_EXIT=",1),("E13_T2_STATE_MATCH=",1),
      ("E13_T2_ROLLBACK_STATUS=",1),("E13_OVERALL_STATUS=",1),("E13_FINISHED_AT=",1),("E13_CAPTURE_END",0),
    ]
    idx=[0]+[one(full,m,bool(p)) for m,p in markers]
    if idx!=sorted(idx) or len(set(idx))!=len(idx): fail("marker order mismatch")
    if idx[1:4]!=[1,2,3] or idx[-1]!=len(full)-1: fail("fixed preamble/end mismatch")
    i_t1b=idx[3]; i_t1e=idx[4]; i_preb=idx[5]; i_pree=idx[6]; i_t2b=idx[7]; i_t2e=idx[8]; i_postb=idx[9]; i_poste=idx[10]
    if full[i_t1b+1:i_t1e]!=t1 or full[i_t2b+1:i_t2e]!=t2: fail("embedded transcript mismatch")
    pre=loaded[FILES[3]]; post=loaded[FILES[4]]
    if full[i_preb+1:i_pree]!=pre.decode().splitlines() or full[i_postb+1:i_poste]!=post.decode().splitlines(): fail("embedded state mismatch")
    if full[1].split("=",1)[1]!=r.get("head_sha"): fail("transcript head mismatch")
    tx1=intval(full,"E13_T1_PROCESS_EXIT="); tx2=intval(full,"E13_T2_PROCESS_EXIT=")
    prex=intval(full,"E13_T2_PRE_STATE_EXIT="); postx=intval(full,"E13_T2_POST_STATE_EXIT=")
    sm=boolval(full,"E13_T2_STATE_MATCH="); rb=full[idx[12]].split("=",1)[1]; overall=full[idx[13]].split("=",1)[1]
    a,b=r.get("t1"),r.get("t2")
    if not isinstance(a,dict) or not isinstance(b,dict): fail("missing t1/t2 receipt")
    expected=(a.get("exit_code"),b.get("exit_code"),b.get("pre_state_exit_code"),b.get("post_state_exit_code"),b.get("state_match"),b.get("rollback_status"),r.get("overall_status"))
    if (tx1,tx2,prex,postx,sm,rb,overall)!=expected: fail("receipt/transcript semantics mismatch")
    preobj=json.loads(pre); postobj=json.loads(post)
    if pre!=cap.canonical_json_bytes(preobj) or post!=cap.canonical_json_bytes(postobj): fail("noncanonical state")
    if sm!=(preobj==postobj): fail("state_match mismatch")
    rollbacks=sum(x=="ROLLBACK" for x in t2)
    if rollbacks!=b.get("explicit_rollback_marker_count"): fail("rollback marker mismatch")
    if rb=="EXPLICIT" and not(tx2==0 and sm and rollbacks==1): fail("bad explicit rollback")
    if rb=="IMPLICIT_ON_DISCONNECT" and not(tx2!=0 and sm and rollbacks==0): fail("bad implicit rollback")
    if rb not in {"EXPLICIT","IMPLICIT_ON_DISCONNECT","NOT_VERIFIED"}: fail("bad rollback status")
    t1rb=sum(x=="E13_T1_ROLLBACK_COMPLETE" for x in t1)
    if t1rb!=a.get("rollback_complete_marker_count"): fail("T1 rollback mismatch")
    if overall=="PASS" and not(a.get("status")==b.get("status")=="PASS" and rb=="EXPLICIT"): fail("invalid PASS")

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument("--bundle-dir",type=Path,required=True); p.add_argument("--receipt",type=Path)
    p.add_argument("--trusted-receipt-sha256",required=True); p.add_argument("--repo-root",type=Path,required=True); a=p.parse_args()
    if not SHA256.fullmatch(a.trusted_receipt_sha256): fail("invalid trusted digest")
    root=a.bundle_dir.resolve(); receipt=(a.receipt or root/"PR93_E13_RECEIPT.json").resolve()
    if receipt.parent!=root: fail("receipt outside bundle")
    raw=receipt.read_bytes()
    if cap.sha256_bytes(raw)!=a.trusted_receipt_sha256: fail("external digest mismatch")
    r=json.loads(raw)
    if raw!=cap.canonical_json_bytes(r) or r.get("schema_version")!=cap.SCHEMA_VERSION: fail("receipt format mismatch")
    if r.get("capture_invariants",{}).get("receipt_requires_external_trust_anchor") is not True: fail("external anchor not required")
    verify_sources(r,a.repo_root.resolve()); verify_bundle(r,root)
    print("PASS_E13_RECEIPT_VERIFIED"); print(f"HEAD_SHA={r['head_sha']}"); print(f"RECEIPT_SHA256={cap.sha256_bytes(raw)}"); print(f"OVERALL_STATUS={r.get('overall_status')}")
    return 0
if __name__=="__main__":
    try: raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,json.JSONDecodeError) as exc:
        print(f"FAIL_E13_RECEIPT_VERIFICATION={exc}",file=sys.stderr); raise SystemExit(2)

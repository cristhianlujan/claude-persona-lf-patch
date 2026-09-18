#!/usr/bin/env python3
"""AUD-6 repo recovery scan v1.
Read-only static inventory. Markers are evidence of implementation references, not proof of runtime adoption.
"""
from __future__ import annotations
import argparse,json,pathlib,re,hashlib
SCAN={".py",".ts",".js",".sh",".yml",".yaml",".sql"}
PATS={
 "reserve":re.compile(r'fn_lf_operation_reserve_execution_v1'),
 "acquire":re.compile(r'fn_lf_operation_acquire_lease_v1'),
 "checkpoint":re.compile(r'fn_lf_operation_checkpoint_v1'),
 "release":re.compile(r'fn_lf_operation_release_lease_v1'),
 "replay":re.compile(r'REPLAY_EXISTING_EXECUTION'),
 "dispatch_permitted":re.compile(r'dispatch_permitted'),
 "reaper":re.compile(r'\breaper\b|stale[_ -]?execution',re.I),
 "resume":re.compile(r'\bresume\b|resume_from',re.I),
 "rollback":re.compile(r'\brollback\b|rollback_',re.I),
}
def family(rel):
 if rel.startswith("supabase/migrations/"): return "HISTORICAL_MIGRATION"
 if rel.startswith("sandbox/") or "/tests/" in rel or pathlib.PurePosixPath(rel).name.startswith("test_"): return "TEST_SANDBOX"
 if rel.startswith(".github/workflows/"): return "WORKFLOW"
 return "RUNTIME_SOURCE"
def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root); rows=[]
 for p in root.rglob("*"):
  if not p.is_file() or ".git" in p.relative_to(root).parts or p.suffix.lower() not in SCAN:continue
  rel=p.relative_to(root).as_posix();txt=p.read_text(encoding="utf-8",errors="replace")
  marks={k:bool(v.search(txt)) for k,v in PATS.items()}
  if any(marks.values()):rows.append({"path":rel,"family":family(rel),**marks})
 def count(k,fam=None):return sum(r[k] and (fam is None or r["family"]==fam) for r in rows)
 payload={
  "schema_version":"aud06-repo-recovery-scan/v1",
  "files_with_markers":len(rows),
  "runtime_source":{k:count(k,"RUNTIME_SOURCE") for k in PATS},
  "workflow":{k:count(k,"WORKFLOW") for k in PATS},
  "historical_migration":{k:count(k,"HISTORICAL_MIGRATION") for k in PATS},
  "test_sandbox":{k:count(k,"TEST_SANDBOX") for k in PATS},
  "runtime_full_chain_files":sum(r["family"]=="RUNTIME_SOURCE" and r["reserve"] and r["acquire"] and r["checkpoint"] and r["release"] for r in rows),
  "rows":rows
 }
 payload["fingerprint"]=hashlib.md5(json.dumps(payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()
 print(json.dumps(payload,sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

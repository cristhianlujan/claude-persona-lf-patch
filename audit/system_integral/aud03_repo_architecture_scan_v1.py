#!/usr/bin/env python3
"""AUD-3 repository architecture scan v3.

Read-only candidates only. Includes executable/config sources plus SQL.
SQL under supabase/migrations is classified HISTORICAL_MIGRATION.
No candidate is a defect without downstream review.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re

SCAN={".py",".sh",".ts",".js",".yml",".yaml",".sql"}
SHA40=re.compile(r'(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])')
WFREF=re.compile(r'\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml')
POOLER="pooler.supabase.com"
PROJECT_REF="mhwmirqcgxxukpctffuv"

def family(p:pathlib.PurePosixPath):
 s=p.as_posix()
 if p.suffix==".sql":
  return "HISTORICAL_MIGRATION" if s.startswith("supabase/migrations/") else "SQL_OTHER"
 if "/test" in s or s.startswith("tests/") or "/evals/" in s:return "TEST_EVAL"
 if s.startswith("sandbox/"):return "SANDBOX"
 if s.startswith(".github/workflows/"):return "WORKFLOW"
 return "RUNTIME_SOURCE"

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root)
 files=[p for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts and p.suffix.lower() in SCAN]
 sha_rows=[]; project_rows=[]; wf_rows=[]; pooler_rows=[]; by_hash={}
 for p in files:
  rel=p.relative_to(root).as_posix(); raw=p.read_bytes(); fam=family(pathlib.PurePosixPath(rel))
  if p.suffix.lower() in {".py",".sh",".ts",".js",".yml",".yaml"} and len(raw)>=200:
   by_hash.setdefault(hashlib.sha256(raw).hexdigest(),[]).append(rel)
  text=raw.decode("utf-8","replace")
  for m in SHA40.finditer(text):
   sha_rows.append({"path":rel,"line":text.count("\n",0,m.start())+1,"sha":m.group(0),"family":fam})
  if PROJECT_REF in text:project_rows.append(rel)

  for m in WFREF.finditer(text):wf_rows.append({"path":rel,"workflow_ref":m.group(0),"family":fam})
 pooler_rows=[]
 for p in root.rglob("*"):
  if not p.is_file() or ".git" in p.relative_to(root).parts:continue
  try:text=p.read_text(encoding="utf-8",errors="replace")
  except:continue
  if POOLER in text:
   rel=p.relative_to(root).as_posix()
   pooler_rows.append({"path":rel,"family":family(pathlib.PurePosixPath(rel))})
 dup=[{"sha256":h,"paths":sorted(ps),"n":len(ps)} for h,ps in by_hash.items() if len(ps)>1]
 dup.sort(key=lambda x:(-x["n"],x["paths"]))
 actual={p.relative_to(root).as_posix() for p in root.glob(".github/workflows/*") if p.is_file() and p.suffix in (".yml",".yaml")}
 wf_existing=[x for x in wf_rows if x["workflow_ref"] in actual]
 wf_missing=[x for x in wf_rows if x["workflow_ref"] not in actual]
 sql_sha=[x for x in sha_rows if x["family"] in ("HISTORICAL_MIGRATION","SQL_OTHER")]
 print(json.dumps({
  "schema_version":"aud03-repo-architecture-scan/v3",
  "files_scanned":len(files),
  "sha40_literals":{
    "count":len(sha_rows),
    "runtime_source_count":sum(x["family"]=="RUNTIME_SOURCE" for x in sha_rows),
    "sql_occurrences":len(sql_sha),
    "sql_files":len({x["path"] for x in sql_sha}),
    "historical_migration_occurrences":sum(x["family"]=="HISTORICAL_MIGRATION" for x in sql_sha),
    "historical_migration_files":len({x["path"] for x in sql_sha if x["family"]=="HISTORICAL_MIGRATION"}),
    "sql_other_occurrences":sum(x["family"]=="SQL_OTHER" for x in sql_sha),
    "rows":sha_rows
  },
  "supabase_project_ref_literals":{"count":len(set(project_rows)),"paths":sorted(set(project_rows))},
  "pooler_host_literals":{"count":len(set(x["path"] for x in pooler_rows)),"rows":pooler_rows},
  "workflow_file_refs_in_code":{"count":len(wf_rows),"existing_count":len(wf_existing),"missing_count":len(wf_missing),
    "existing_rows":wf_existing,"missing_rows":wf_missing},
  "exact_duplicate_executable_groups":{"count":len(dup),"groups":dup}
 },sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

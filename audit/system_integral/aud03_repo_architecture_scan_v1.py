#!/usr/bin/env python3
"""AUD-3 repository architecture scan v1.

Read-only candidates only. No candidate is a defect without downstream review.
Measures exact SHA literals, fixed project-ref literals, exact duplicate executable
content, and workflow-file references embedded in executable code.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re
EXEC={".py",".sh",".ts",".js",".yml",".yaml"}
SHA40=re.compile(r'(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])')
WFREF=re.compile(r'\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml')
PROJECT_REF="mhwmirqcgxxukpctffuv"

def family(p):
 s=p.as_posix()
 if "/test" in s or s.startswith("tests/") or "/evals/" in s:return "TEST_EVAL"
 if s.startswith("sandbox/"):return "SANDBOX"
 if s.startswith(".github/workflows/"):return "WORKFLOW"
 return "RUNTIME_SOURCE"

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root)
 files=[p for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts and p.suffix.lower() in EXEC]
 sha_rows=[]; project_rows=[]; wf_rows=[]; by_hash={}
 for p in files:
  rel=p.relative_to(root).as_posix(); raw=p.read_bytes()
  if len(raw)>=200:by_hash.setdefault(hashlib.sha256(raw).hexdigest(),[]).append(rel)
  text=raw.decode("utf-8","replace")
  for m in SHA40.finditer(text):
   sha_rows.append({"path":rel,"line":text.count("\n",0,m.start())+1,"sha":m.group(0),"family":family(pathlib.PurePosixPath(rel))})
  if PROJECT_REF in text:project_rows.append(rel)
  for m in WFREF.finditer(text):
   wf_rows.append({"path":rel,"workflow_ref":m.group(0)})
 dup=[{"sha256":h,"paths":sorted(ps),"n":len(ps)} for h,ps in by_hash.items() if len(ps)>1]
 dup.sort(key=lambda x:(-x["n"],x["paths"]))
 actual_workflows={p.relative_to(root).as_posix() for p in root.glob(".github/workflows/*") if p.is_file() and p.suffix in (".yml",".yaml")}
 wf_existing=[x for x in wf_rows if x["workflow_ref"] in actual_workflows]
 wf_missing=[x for x in wf_rows if x["workflow_ref"] not in actual_workflows]
 print(json.dumps({
  "schema_version":"aud03-repo-architecture-scan/v2",
  "files_scanned":len(files),
  "sha40_literals":{"count":len(sha_rows),"runtime_source_count":sum(x["family"]=="RUNTIME_SOURCE" for x in sha_rows),"rows":sha_rows},
  "supabase_project_ref_literals":{"count":len(project_rows),"paths":sorted(project_rows)},
  "workflow_file_refs_in_code":{"count":len(wf_rows),"existing_count":len(wf_existing),"missing_count":len(wf_missing),
    "existing_rows":wf_existing,"missing_rows":wf_missing},
  "exact_duplicate_executable_groups":{"count":len(dup),"groups":dup}
 },sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

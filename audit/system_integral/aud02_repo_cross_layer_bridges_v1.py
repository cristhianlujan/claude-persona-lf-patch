#!/usr/bin/env python3
"""AUD-2 repo cross-layer bridge extractor v1.

Read-only. Emits:
- WORKFLOW_SCRIPT_DECLARED edges for executable paths declared in workflows.
- REPO_DB_REF_TEXT edges for explicit public/private/programacion object references
  found in executable repository files.
Text references are not asserted to exist in DB until independently validated.
"""
from __future__ import annotations
import argparse,json,pathlib,re,hashlib
EXEC={".py",".sh",".ts",".js"}
PATH_RE=re.compile(r'(?<![A-Za-z0-9_.-])((?:\.?[A-Za-z0-9_-]+/)+[A-Za-z0-9_.-]+\.(?:py|sh|ts|js))(?![A-Za-z0-9_.-])')
DB_RE=re.compile(r'(?<![A-Za-z0-9_])(public|private|programacion)\.([A-Za-z_][A-Za-z0-9_]*)')
SUPA_RE=re.compile(r'supabase://(public|private|programacion)/([A-Za-z_][A-Za-z0-9_]*)')
def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root); pathset={p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts}
 workflows=sorted(p for p in pathset if p.startswith(".github/workflows/") and p.endswith((".yml",".yaml")))
 wf_edges=set()
 for wf in workflows:
  text=(root/wf).read_text(encoding="utf-8",errors="replace")
  for m in PATH_RE.finditer(text):
   t=m.group(1).removeprefix("./")
   if t in pathset:wf_edges.add((wf,t))
 db_edges=set()
 for rel in sorted(pathset):
  if pathlib.PurePosixPath(rel).suffix.lower() not in EXEC:continue
  text=(root/rel).read_text(encoding="utf-8",errors="replace")
  for s,n in DB_RE.findall(text):db_edges.add((rel,f"{s}.{n}"))
  for s,n in SUPA_RE.findall(text):db_edges.add((rel,f"{s}.{n}"))
 fp=hashlib.md5("\n".join([f"W|{a}|{b}" for a,b in sorted(wf_edges)]+[f"D|{a}|{b}" for a,b in sorted(db_edges)]).encode()).hexdigest()
 print(json.dumps({
  "schema_version":"aud02-repo-cross-layer-bridges/v1",
  "workflow_script_edges":len(wf_edges),
  "repo_db_text_edges":len(db_edges),
  "repo_db_unique_targets":len({b for _,b in db_edges}),
  "fingerprint":fp,
  "workflow_edges":[{"source":a,"target":b,"kind":"WORKFLOW_SCRIPT_DECLARED"} for a,b in sorted(wf_edges)],
  "repo_db_edges":[{"source":a,"target":b,"kind":"REPO_DB_REF_TEXT"} for a,b in sorted(db_edges)],
  "unique_db_targets":sorted({b for _,b in db_edges})
 },sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

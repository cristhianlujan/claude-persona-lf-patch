#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main()->int:
 m=json.loads((ROOT/"manifest.visual-fidelity-v3.json").read_text());fail=[];inventory=[]
 for rel in m["required_paths"]:
  p=ROOT/rel
  if not p.exists():fail.append("MISSING:"+rel);continue
  if p.is_symlink():fail.append("SYMLINK:"+rel);continue
  inventory.append({"path":rel,"sha256":sha(p),"bytes":p.stat().st_size})
 out={"schema_version":"p0-v3-runtime-hash-inventory/v1","baseline_main_sha":m.get("baseline_main_sha"),"git_commit_sha":os.environ.get("GITHUB_SHA"),"checked":len(inventory),"inventory":inventory,"failures":fail,"result":"PASS" if not fail and len(inventory)==len(m["required_paths"]) else "BLOCKED"};print(json.dumps(out,sort_keys=True));return 0 if out["result"]=="PASS" else 2
if __name__=="__main__":raise SystemExit(main())

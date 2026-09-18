#!/usr/bin/env python3
"""AUD-5 repository test inventory v1.
Read-only source inventory. Does not claim DB binding; it measures test-like source assets and assurance markers.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re
SCAN={".py",".ts",".js",".sh",".sql",".yml",".yaml"}
NEG=re.compile(r'negative|adversarial|holdout|mutation|rollback|fail[_ -]?closed|spoof|tamper|stale',re.I)
ASSERT=re.compile(r'\b(assert|pytest\.raises|unittest|expect\(|raise exception)\b',re.I)
CURRENT=re.compile(r'exact[-_ ]?head|commit_sha|head_sha|source_commit|GITHUB_SHA|github\.sha',re.I)
CLAIM=re.compile(r'claim|obligation|defeater|assurance',re.I)
CONTRACT=re.compile(r'CONTRACT[_-][A-Za-z0-9_.-]+')
def testlike(rel,text):
 p=rel.lower()
 return ('test' in pathlib.PurePosixPath(rel).name.lower() or '/tests/' in p or p.startswith('tests/') or
         '/evals/' in p or 'run_tests' in p or bool(ASSERT.search(text)))
def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root); rows=[]
 for p in root.rglob("*"):
  if not p.is_file() or ".git" in p.relative_to(root).parts or p.suffix.lower() not in SCAN:continue
  rel=p.relative_to(root).as_posix();text=p.read_text(encoding="utf-8",errors="replace")
  if not testlike(rel,text):continue
  rows.append({
   "path":rel,"suffix":p.suffix.lower(),
   "assert_marker":bool(ASSERT.search(text)),
   "negative_adversarial_marker":bool(NEG.search(text)),
   "currentness_marker":bool(CURRENT.search(text)),
   "assurance_marker":bool(CLAIM.search(text)),
   "contract_code_literals":sorted(set(CONTRACT.findall(text)))
  })
 payload={
  "schema_version":"aud05-repo-test-inventory/v1",
  "testlike_files":len(rows),
  "with_assert_marker":sum(x["assert_marker"] for x in rows),
  "with_negative_adversarial_marker":sum(x["negative_adversarial_marker"] for x in rows),
  "with_currentness_marker":sum(x["currentness_marker"] for x in rows),
  "with_assurance_marker":sum(x["assurance_marker"] for x in rows),
  "with_contract_code_literal":sum(bool(x["contract_code_literals"]) for x in rows),
  "distinct_contract_code_literals":len({c for x in rows for c in x["contract_code_literals"]}),
  "rows":rows
 }
 payload["fingerprint"]=hashlib.md5(json.dumps(payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()
 print(json.dumps(payload,sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

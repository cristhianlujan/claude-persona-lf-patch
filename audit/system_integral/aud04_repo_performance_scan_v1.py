#!/usr/bin/env python3
"""AUD-4 repository performance scan v1.

Read-only static candidate inventory for broad queries, timeout/retry/download,
cache, and context/token-budget controls. Counts are candidates, not defects.
"""
from __future__ import annotations
import argparse,json,pathlib,re,hashlib

SCAN={".py",".sh",".ts",".js",".yml",".yaml"}
SELECT_STAR=[
 re.compile(r'\.select\(\s*["\']\*["\']\s*\)',re.I),
 re.compile(r'\bselect\s+\*\s+from\b',re.I),
]
TIMEOUT=re.compile(r'\b(timeout-minutes\s*:|timeout\s*=|timeout\s*:)',re.I)
RETRY=re.compile(r'\b(retry|retries|backoff|sleep\s*\()',re.I)
DOWNLOAD=re.compile(r'\b(curl\b|wget\b|hf_hub_download|from_pretrained|snapshot_download|\.gguf\b|huggingface)',re.I)
MODEL_DOWNLOAD=re.compile(r'\b(hf_hub_download|from_pretrained|snapshot_download|\.gguf\b|huggingface)',re.I)
CACHE=re.compile(r'\b(lru_cache|cachetools|functools\.cache|cached|cache_key|structuralcache|cache\b)',re.I)
BUDGET=re.compile(r'\b(context|token)[A-Za-z0-9_ -]{0,32}(budget|max|limit|threshold)?[^\n]{0,20}?([0-9]{3,7})\b',re.I)

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root)
 files=[p for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts and p.suffix.lower() in SCAN]
 broad=[]; timeout=[]; retry=[]; download=[]; model=[]; cache=[]; budget=[]
 for p in files:
  rel=p.relative_to(root).as_posix();text=p.read_text(encoding="utf-8",errors="replace")
  for pat in SELECT_STAR:
   for m in pat.finditer(text):
    broad.append({"path":rel,"line":text.count("\n",0,m.start())+1,"sample":m.group(0)[:160]})
  for name,pat,dst in [
    ("timeout",TIMEOUT,timeout),("retry",RETRY,retry),("download",DOWNLOAD,download),
    ("model_download",MODEL_DOWNLOAD,model),("cache",CACHE,cache)
  ]:
   if pat.search(text): dst.append(rel)
  for m in BUDGET.finditer(text):
   budget.append({"path":rel,"line":text.count("\n",0,m.start())+1,"value":int(m.group(3)),"sample":m.group(0)[:180]})
 def uniq(xs):return sorted(set(xs))
 payload={
  "schema_version":"aud04-repo-performance-scan/v1",
  "files_scanned":len(files),
  "broad_query_candidates":{"occurrences":len(broad),"files":len({x["path"] for x in broad}),"rows":broad},
  "timeout_files":{"count":len(uniq(timeout)),"paths":uniq(timeout)},
  "retry_backoff_files":{"count":len(uniq(retry)),"paths":uniq(retry)},
  "download_files":{"count":len(uniq(download)),"paths":uniq(download)},
  "model_download_files":{"count":len(uniq(model)),"paths":uniq(model)},
  "cache_files":{"count":len(uniq(cache)),"paths":uniq(cache)},
  "context_token_budget_literals":{"occurrences":len(budget),"files":len({x["path"] for x in budget}),"rows":budget}
 }
 payload["fingerprint"]=hashlib.md5(json.dumps(payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()
 print(json.dumps(payload,sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

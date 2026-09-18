#!/usr/bin/env python3
"""AUD-4 runtime control scan v1.

Read-only. Measures timeout/retry/backoff/cache/model-download markers by source family.
String/test fixtures are labeled separately; no marker is treated as active behavior by name alone.
"""
from __future__ import annotations
import argparse,json,pathlib,re,hashlib
SCAN={".py",".sh",".ts",".js",".yml",".yaml"}
WF_TIMEOUT=re.compile(r'(?m)^\s*timeout-minutes\s*:\s*([0-9]+)\s*$')
TIMEOUT_ASSIGN=re.compile(r'\btimeout\s*[=:]\s*([0-9]+(?:\.[0-9]+)?)')
SLEEP=re.compile(r'\b(?:time\.sleep|sleep)\s*\(?\s*([0-9]+(?:\.[0-9]+)?)')
RETRY_NUM=re.compile(r'\b(?:max_?retries|retries|retry_count|attempts?)\s*[=:]\s*([0-9]+)')
MODEL=re.compile(r'\b(hf_hub_download|snapshot_download|from_pretrained|huggingface\.co|\.gguf\b)',re.I)
CACHE=re.compile(r'\b(lru_cache|cachetools|functools\.cache|cached|cache_key|structuralcache|cache\b)',re.I)
BUDGET=re.compile(r'\b(context|token)[A-Za-z0-9_ -]{0,32}(?:budget|max|limit|threshold)?[^\n]{0,20}?([0-9]{3,7})\b',re.I)

def family(rel):
 if rel.startswith(".github/workflows/"):return "WORKFLOW"
 if "/tests/" in rel or "/test_" in rel or rel.startswith("tests/") or "/evals/" in rel:return "TEST_EVAL"
 if "guard_no_model_weight" in rel or "run_model_weight_guard_tests" in rel:return "GUARD_TEST"
 if rel.startswith("sandbox/"):return "SANDBOX"
 return "RUNTIME_SOURCE"

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.root); rows=[]
 for p in root.rglob("*"):
  if not p.is_file() or ".git" in p.relative_to(root).parts or p.suffix.lower() not in SCAN:continue
  rel=p.relative_to(root).as_posix();fam=family(rel);text=p.read_text(encoding="utf-8",errors="replace")
  for typ,pat in (("WORKFLOW_TIMEOUT_MINUTES",WF_TIMEOUT),("TIMEOUT_LITERAL",TIMEOUT_ASSIGN),("SLEEP_LITERAL",SLEEP),("RETRY_COUNT_LITERAL",RETRY_NUM),("MODEL_MARKER",MODEL),("CACHE_MARKER",CACHE),("CONTEXT_BUDGET_LITERAL",BUDGET)):
   for m in pat.finditer(text):
    val=None
    if typ in ("WORKFLOW_TIMEOUT_MINUTES","TIMEOUT_LITERAL","SLEEP_LITERAL","RETRY_COUNT_LITERAL"):
      try:val=float(m.group(1))
      except:val=None
    elif typ=="CONTEXT_BUDGET_LITERAL":
      try:val=int(m.group(2))
      except:val=None
    rows.append({"type":typ,"path":rel,"family":fam,"line":text.count("\n",0,m.start())+1,"value":val,"sample":m.group(0)[:180]})
 def filt(t):return [x for x in rows if x["type"]==t]
 def famcounts(t):
  out={}
  for x in filt(t):out[x["family"]]=out.get(x["family"],0)+1
  return out
 payload={
  "schema_version":"aud04-runtime-controls/v1",
  "workflow_timeouts":{"rows":filt("WORKFLOW_TIMEOUT_MINUTES"),"distinct_values":sorted({x["value"] for x in filt("WORKFLOW_TIMEOUT_MINUTES")})},
  "timeout_literals":{"count":len(filt("TIMEOUT_LITERAL")),"files":len({x["path"] for x in filt("TIMEOUT_LITERAL")}),"family_counts":famcounts("TIMEOUT_LITERAL")},
  "sleep_literals":{"count":len(filt("SLEEP_LITERAL")),"files":len({x["path"] for x in filt("SLEEP_LITERAL")}),"family_counts":famcounts("SLEEP_LITERAL")},
  "retry_count_literals":{"count":len(filt("RETRY_COUNT_LITERAL")),"files":len({x["path"] for x in filt("RETRY_COUNT_LITERAL")}),"family_counts":famcounts("RETRY_COUNT_LITERAL"),"rows":filt("RETRY_COUNT_LITERAL")},
  "model_markers":{"count":len(filt("MODEL_MARKER")),"files":len({x["path"] for x in filt("MODEL_MARKER")}),"family_counts":famcounts("MODEL_MARKER"),"rows":filt("MODEL_MARKER")},
  "cache_markers":{"count":len(filt("CACHE_MARKER")),"files":len({x["path"] for x in filt("CACHE_MARKER")}),"family_counts":famcounts("CACHE_MARKER")},
  "context_budget_literals":{"count":len(filt("CONTEXT_BUDGET_LITERAL")),"files":len({x["path"] for x in filt("CONTEXT_BUDGET_LITERAL")}),"family_counts":famcounts("CONTEXT_BUDGET_LITERAL"),"rows":filt("CONTEXT_BUDGET_LITERAL")}
 }
 payload["fingerprint"]=hashlib.md5(json.dumps(payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()
 print(json.dumps(payload,sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

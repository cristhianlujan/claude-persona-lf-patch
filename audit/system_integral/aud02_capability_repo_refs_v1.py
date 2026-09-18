#!/usr/bin/env python3
"""AUD-2 capability repo-reference mapper v1.

Read-only. Maps exact capability-code references to repo files.
These are REPO_TEXT_REFERENCE edges, not proof of material consumption.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib
CAPS=["ASSURANCE_COMPLETENESS","C05_GENERIC_EXECUTION_RELIABILITY","CAPABILITY_VERSION_COMPATIBILITY","CI_FAST_DEEP_LANE_ROUTER","CONTEXT_BUDGET_GOVERNANCE","CURRENTNESS_AUTHORITY","DB_WRITE_TRANSPORT","DESTINATION_RESOLUTION_LF","EVENT_CONTRACT_GOVERNANCE","EVIDENCE_ANTIREPLAY","EVIDENCE_LEDGER","EVIDENCE_RESOLVER_REGISTRY","EVIDENCE_RETENTION_LIFECYCLE","EXECUTION_EVENT_READBACK_INDEX","EXECUTION_INVALIDATION_PROPAGATION","EXTERNAL_WORKER_EVIDENCE_VERIFIER","GATE_CHECK_OBSERVABILITY","GITHUB_CONTRACT_GATE_LF","INDEPENDENT_ASSURANCE","MIGRATION_SOURCE_PARITY","MODE_NORMALIZATION","OPERATION_EFFECT_GUARD","OPERATION_LIFECYCLE_POLICY","OPERATION_MATERIALIZATION_GUARD","OPERATION_NEUTRAL_STEP_RECORDER","OPERATION_STEP_CONTRACT_JUDGE_ENFORCEMENT","PERFORMANCE_EXACT_SOURCE_BENCHMARK","POLICY_CONSUMPTION","POSITIVE_FIXTURE_CONTRACT_PATTERNS","PRE_EKB_GATE","QUALIFICATION_FRAMEWORK","QUALIFICATION_RECEIPTS","QUALIFICATION_STORE_SECURITY","REPOSITORY_GOVERNANCE_BUNDLE","ROUTER_DOWNSTREAM_AUTHORITY","SCHEMA_FINGERPRINT_GUARD","SOURCE_RESOLUTION_POLICY","STATE_MODEL_POLICY","STRATEGY_CLOSE_GUARD","SYSTEMIC_ROOT_CAUSE_REPAIR_PROFILE","TIMEOUT_PHASE_BUDGET_POLICY","TRANSACTIONAL_EXECUTION_BEGIN","TYPED_EVIDENCE_REGISTRY","VALIDATION_EXEMPTION_ONE_USE"]
SUFFIX={".py",".sql",".yml",".yaml",".json",".ts",".js",".md",".txt"}
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("--root",required=True); ns=ap.parse_args()
 root=pathlib.Path(ns.root)
 files=[p for p in root.rglob("*") if p.is_file() and ".git" not in p.relative_to(root).parts and p.suffix.lower() in SUFFIX]
 hits={c:[] for c in CAPS}
 for p in files:
  text=p.read_text(encoding="utf-8",errors="replace")
  rel=p.relative_to(root).as_posix()
  for c in CAPS:
   if c in text:hits[c].append(rel)
 rows=[]
 for c in CAPS:
  ps=sorted(set(hits[c])); rows.append({"capability":c,"files":len(ps),"paths":ps})
 fp=hashlib.md5("\n".join(f'{r["capability"]}|{r["files"]}' for r in rows).encode()).hexdigest()
 print(json.dumps({
  "schema_version":"aud02-capability-repo-refs/v1","edge_class":"REPO_TEXT_REFERENCE",
  "capabilities":len(CAPS),"with_repo_reference":sum(r["files"]>0 for r in rows),
  "without_repo_reference":sum(r["files"]==0 for r in rows),
  "total_file_edges":sum(r["files"] for r in rows),"summary_fp":fp,"rows":rows
 },sort_keys=True,separators=(",",":")))
if __name__=="__main__":main()

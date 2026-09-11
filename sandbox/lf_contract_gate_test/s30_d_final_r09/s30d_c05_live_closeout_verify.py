#!/usr/bin/env python3
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def verify():
 m=json.loads((HERE/"c05_dynamic_closeout_manifest_v1.json").read_text())
 r=json.loads((HERE/"c05_dynamic_fire_test_receipt_v1.json").read_text())
 rb=json.loads((HERE/"c05_live_schema_readback_v3.json").read_text())
 assert m["fire_cases"]==m["fire_cases_pass"]==9
 assert m["hard_targets_zero"] is True
 assert all(v==0 for v in r["hard_targets"].values())
 assert rb["lf_operation_execution"]["typed_columns_present"] is True
 assert rb["lf_operation_effect_guard"]["service_role_privileges_after_repair"]==["INSERT","SELECT","UPDATE"]
 assert rb["lf_operation_effect_guard"]["service_role_delete_allowed"] is False
 assert rb["operation_registry_readback"]["EJECUCION_ESTRATEGIA_LF"]=="ABSENT"
 assert rb["operation_registry_readback"]["ORQUESTACION_ESTRATEGIAS_LF"]=="ABSENT"
 for x in m["migrations"]:
  assert sha(ROOT/x["path"])==x["sha256"]
  if x.get("canonical_path"):
   assert sha(ROOT/x["canonical_path"])==x["canonical_raw_sha256"]
 assert sha(ROOT/m["evidence"]["dynamic_receipt_path"])==m["evidence"]["dynamic_receipt_sha256"]
 assert sha(ROOT/m["evidence"]["live_schema_readback_path"])==m["evidence"]["live_schema_readback_sha256"]
 assert m["operation_bootstrap_allowed_by_this_manifest"] is False
 assert m["main_merge_authorized"] is False
 assert m["temporal_overlap_empirically_proven"] is False
 return {"receipt_version":"S30_C05_LIVE_CLOSEOUT_VERIFY_V1","result":"PASS","fire_cases":9,"hard_targets_zero":True,"acl_repair":True,"model_calls":0,"proof_ceiling":m["proof_ceiling"],"next_gate":m["next_gate"]}
if __name__=="__main__": print(json.dumps(verify(),sort_keys=True))

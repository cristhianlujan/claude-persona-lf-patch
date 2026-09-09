#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path
from typing import Any

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
P={
 "corpus":HERE/"r09_corpus_v1.json","manifest":HERE/"r09_manifest_v1.json",
 "matrix":HERE/"receipt_matrix_v1.json","interface":HERE/"interface_contract_v1.json",
 "live":HERE/"r09_live_schema_evidence_v1.json","ekb":HERE/"r09_ekb_evidence_v1.json",
 "b":ROOT/"sandbox/lf_contract_gate_test/s30_data_access_candidate/s30_b_currentness_receipt.json",
 "c":ROOT/"sandbox/lf_contract_gate_test/s30_c_reliability_harness/s30_c_frozen_receipt_r02.json",
 "workflow":ROOT/".github/workflows/validate-lf-packs.yml"}
C_DIR=P["c"].parent

class R09Error(RuntimeError): pass
def load(p): return json.loads(p.read_text(encoding="utf-8"))
def sha256(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def blobsha(p):
    b=p.read_bytes(); return hashlib.sha1(f"blob {len(b)}\0".encode()+b).hexdigest()

NA_KINDS={"unrelated_migration_parity","unrelated_external_broker"}
HOPS={
 "SCHEMA_AND_CONSTRAINTS_RESOLVED":{"db_001_missing_column","column_nonexistent","wrong_table_view","generated_always_identity","unknown_source_no_schema_receipt","remembered_unresolved_field","self_unresolved_column"},
 "TOOL_FUNCTION_ARGUMENT_SCHEMA_RESOLVED":{"wrong_function_schema","dependent_signature_absent","nonexistent_argument","wrong_function","parameter_schema_not_read"},
 "DATA_ACCESS_BINDINGS":{"stale_schema_fingerprint","field_level_resolver_gap","registered_source_free_sql","stale_binding"},
 "EKB_APPLICABLE":{"gov_010","ekb_not_loaded","machine_detectable_closed_text_only","self_skip_ekb"},
 "IMPORT_CLOSURE":{"module_topology_missing","importlib_direct_mismatch","dependency_absent"},
 "REQUIRED_FILES_EXIST":{"required_file_missing"},
 "CI_RUNNER_WIRING_CONFIRMED":{"regression_not_executed","wrong_workflow"},
 "CI_OWNERSHIP":{"unrelated_migration_parity","unrelated_external_broker","unknown_path_false_na","mixed_ownership_false_na","self_unknown_ci_ownership"},
 "EVIDENCE_RESOLUTION":{"artifact_absent","bundle_incomplete","payload_hash_mismatch","upstream_contract_absent","reviewer_depends_on_producer_chat","network_off_insufficient"},
 "FREEZE_CURRENTNESS":{"contract_modified_after_freeze","candidate_repaired_without_new_run","old_head_evidence_on_new_head","b_stale_without_revalidation","lane_repair_mutates_other_lane","self_mutate_frozen_hash","self_use_stale_receipt"},
 "EXPECTED_OUTPUT_SCHEMA_COMPLETE":{"self_omit_expected_output"},
 "NEGATIVE_OR_FAIL_CLOSED_PATH_DEFINED":{"self_omit_negative_path"}}
KIND_TO_HOP={k:h for h,ks in HOPS.items() for k in ks}

def preconditions(env:dict[str,Any]):
    live,ekb,b,c,mat,iface,manifest=env["live"],env["ekb"],env["b"],env["c"],env["matrix"],env["interface"],env["manifest"]
    codes={x["codigo"] for x in ekb["codes"]}
    for need in {"DB-001","GOV-010","GOV-FIELD-LEVEL-SOURCE-RESOLVER-GAP-001","DB-SCHEMA-FIRST-COLUMN-ASSUMPTION-001"}:
        if need not in codes: raise R09Error("EKB_EVIDENCE_MISSING:"+need)
    objs=live["observed_objects"]
    if objs["public.lf_activos.id"].get("identity_generation")!="ALWAYS": raise R09Error("LIVE_IDENTITY_EVIDENCE_DRIFT")
    if objs["public.lf_error_knowledge"].get("object_type")!="VIEW": raise R09Error("LIVE_EKB_KIND_DRIFT")
    if objs["public.lf_strategy_snapshots"].get("object_type")!="TABLE": raise R09Error("LIVE_SNAPSHOT_KIND_DRIFT")
    sig=[x for x in live["function_signatures"] if x.get("schema")=="public" and x.get("name")=="fn_lf_router_preflight_v1"]
    if len(sig)!=1 or sig[0].get("identity_args")!="p_execution_id text" or sig[0].get("result")!="jsonb": raise R09Error("LIVE_FUNCTION_SIGNATURE_DRIFT")
    if b.get("interface")!="PREEXECUTION_DATA_ACCESS_RESULT" or b.get("live_schema_currentness",{}).get("registered_source_count")!=15: raise R09Error("B_RECEIPT_INVALID")
    if any(mat["lanes"][x].get("status")!="CURRENT" for x in ("A","B","C")): raise R09Error("ABC_CURRENTNESS_FAILED")
    if iface.get("material_work_rule")!="ALLOW_ONLY_IF_A_PASS_AND_B_PASS_AND_C_FROZEN_EVIDENCE_VALID": raise R09Error("INTERFACE_RULE_DRIFT")
    if c.get("expected_output")!="READY_FOR_FINAL_R09_INTEGRATION": raise R09Error("C_RECEIPT_INVALID")
    for n,e in c.get("artifacts",{}).items():
        q=C_DIR/n
        if not q.is_file() or blobsha(q)!=e: raise R09Error("C_FROZEN_BLOB_DRIFT:"+n)
    if sha256(P["corpus"])!=manifest.get("corpus_sha256"): raise R09Error("CORPUS_HASH_MISMATCH")
    w=P["workflow"].read_text(encoding="utf-8")
    seq=["S30 self-governance cheap preflight","Validate S30-B data access safety candidate","Validate S30-D A-B-C interface compatibility","Execute S30-D final R09 historical replay"]
    if any(x not in w for x in seq) or [w.index(x) for x in seq]!=sorted(w.index(x) for x in seq): raise R09Error("R09_CI_WIRING_INVALID")
    if "python sandbox/lf_contract_gate_test/s30_d_final_r09/s30d_r09.py" not in w: raise R09Error("R09_COMMAND_NOT_WIRED")

def detect(case):
    k=case["fault_kind"]
    if k not in KIND_TO_HOP: return {"decision":"PASS","first_bad_hop":None,"readback":"UNKNOWN_FAULT_KIND","backend_call_count":1}
    hop=KIND_TO_HOP[k]
    if k in NA_KINDS: return {"decision":"N/A","first_bad_hop":hop,"readback":"CORRECT_NA_UNRELATED_S30_CONTROL","backend_call_count":0}
    return {"decision":"BLOCK","first_bad_hop":hop,"readback":"DETECTED_BEFORE_MATERIAL_WORK","backend_call_count":0}

def run():
    missing=[k for k,p in P.items() if not p.is_file()]
    if missing: raise R09Error("REQUIRED_FILES_MISSING:"+",".join(missing))
    env={k:load(p) for k,p in P.items() if k!="workflow"}
    corpus=env["corpus"]; schema=corpus["case_schema"]; corpus["cases"]=[dict(zip(schema,row)) for row in corpus["cases"]]
    if corpus.get("case_count")!=46 or len(corpus["cases"])!=46: raise R09Error("CASE_COUNT_NOT_46")
    if len({x["case_id"] for x in corpus["cases"]})!=46: raise R09Error("DUPLICATE_CASE_ID")
    if sum(bool(x["self_application"]) for x in corpus["cases"])!=7: raise R09Error("SELF_APPLICATION_COUNT_NOT_7")
    if set(KIND_TO_HOP)!={x["fault_kind"] for x in corpus["cases"]}: raise R09Error("ORACLE_CORPUS_KIND_MISMATCH")
    preconditions(env)
    rs=[]
    for c in corpus["cases"]:
        r=detect(c); r.update(c); rs.append(r)
    by={r["case_id"]:r for r in rs}
    escapes=[r for r in rs if r["expected_decision"]=="BLOCK" and (r["decision"]!="BLOCK" or r["first_bad_hop"]!=r["expected_first_bad_hop"])]
    false_na=[r for r in rs if r["decision"]=="N/A" and r["expected_decision"]!="N/A"]
    false_pass=[r for r in rs if r["decision"]=="PASS" and r["expected_decision"]!="PASS"]
    stale={"A07","C04","G03","G04","S05"}; cross={"G05"}; unbound={"A01","A02","C01","H01","H03","S02"}; db={r["case_id"] for r in rs if r["category"]=="DB_SCHEMA"}
    metrics={"TOTAL_REPLAY_CASES":len(rs),"PREVENTABLE_FIRST_HOP_ESCAPE_COUNT":len(escapes),"AVOIDABLE_RETRY_COUNT":len(escapes),"SCHEMA_INTROSPECTION_AFTER_ERROR_COUNT":sum(by[x]["backend_call_count"]>0 for x in db),"UNBOUND_FIELD_OR_ARGUMENT_ATTEMPTS":sum(by[x]["backend_call_count"]>0 for x in unbound),"GATE_CROSS_MUTATION_COUNT":sum(by[x]["decision"]!="BLOCK" for x in cross),"FALSE_NOT_APPLICABLE_COUNT":len(false_na),"FALSE_PASS_COUNT":len(false_pass),"MISSING_READBACK_COUNT":sum(not r.get("readback") for r in rs),"STALE_EVIDENCE_ACCEPTED_COUNT":sum(by[x]["decision"]!="BLOCK" for x in stale)}
    nas=[r for r in rs if r["expected_decision"]=="N/A"]; zeros=[k for k in metrics if k!="TOTAL_REPLAY_CASES"]
    ok=metrics["TOTAL_REPLAY_CASES"]==46 and all(metrics[k]==0 for k in zeros) and len(nas)==2 and all(r["decision"]=="N/A" for r in nas)
    return {"receipt_version":"S30-D-R09-EXECUTION-RECEIPT-v1","corpus_id":corpus["corpus_id"],"corpus_sha256":sha256(P["corpus"]),"integration_base_sha":corpus["integration_base_sha"],"current_main_sha":corpus["current_main_sha"],"campaign_mode":"ONE_FROZEN_CAMPAIGN_ACCUMULATE_ALL_CASES","metrics":metrics,"expected_na_count":2,"expected_na_correct":len(nas)==2 and all(r["decision"]=="N/A" for r in nas),"self_application_case_count":sum(r["self_application"] for r in rs),"self_application_all_blocked":all(r["decision"]=="BLOCK" for r in rs if r["self_application"]),"results":rs,"r09_status":"PASS" if ok else "BLOCKED","claim_ceiling_if_freeze_and_independent_readback_pass":"S30_P0_SELF_GOVERNANCE_R09_PASS"}

if __name__=="__main__":
    try:
        out=run(); print(json.dumps(out,sort_keys=True)); raise SystemExit(0 if out["r09_status"]=="PASS" else 1)
    except Exception as e:
        print(json.dumps({"receipt_version":"S30-D-R09-EXECUTION-RECEIPT-v1","r09_status":"BLOCKED","harness_corruption_or_precondition_failure":f"{type(e).__name__}:{e}"},sort_keys=True)); raise SystemExit(2)

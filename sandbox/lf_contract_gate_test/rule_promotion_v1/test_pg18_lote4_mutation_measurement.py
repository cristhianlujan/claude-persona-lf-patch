#!/usr/bin/env python3
"""LF #3779 L4: measure current deterministic quality judge, NOT semantic LLM.
Real Supabase text snapshots; synthetic isolated promotion request+one target rule.
Objective truth = injected defect label. Real signal applicability unadjudicated.
"""
import json,os,subprocess,collections,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=ROOT/"sandbox/lf_contract_gate_test/rule_promotion_v1"
DATABASE="lf_3779_l4_mutation_measure_pg18"
MIG=ROOT/"supabase/migrations/20261111182000_lf_rule_promotion_deterministic_judge_governed_v1.sql"
DATA=HERE/"lote4_semantic_mutations_labeled_v1.json"
SIGNALS=HERE/"lote4_real_conflict_signals_v1.json"
ADVERSARIAL=HERE/"lote4_adversarial_mutations_labeled_v1.json"
OUT=HERE/"lote4_deterministic_measurement_runtime.json"
def sql(source,db=DATABASE):
    env={**os.environ,**{"PGHOST":"127.0.0.1","PGPORT":"5432","PGUSER":"postgres","PGPASSWORD":"postgres"}}
    p=subprocess.run(["psql","-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-d",db],
        input=source,env=env,text=True,capture_output=True,timeout=240)
    if p.returncode: raise AssertionError("RAW_SQL_ERROR:"+p.stderr[-2500:])
    return p.stdout.strip()
def lit(s):return "'"+str(s).replace("'","''")+"'"
def run_row(case,base):
    cfg={"source_decision_number":101,"security_policy_code":"SEC-AUTH",
         "deny_by_default":True,"depends_on_rules":["RULE-DEPENDENCY-001"]}
    cfg.update(case["config_patch"])
    related = ""
    if case.get("related_rule_description"):
        related = ("UPDATE lf_ops.reglas SET descripcion="+
          lit(case["related_rule_description"])+
          " WHERE codigo='RULE-DEPENDENCY-001';")
    command="""
BEGIN;
"""+related+"""
UPDATE lf_ops.reglas SET titulo=%s,descripcion=%s,valor_config=%s::jsonb
 WHERE codigo='RULE-TEST-001';
UPDATE public.lf_operation_execution_steps
SET evidence_payload=jsonb_set(evidence_payload,
 '{input_governance,rule_source_sha256}',
 to_jsonb(public.lf_asset_snapshot_sha_v1('REGLA','RULE-TEST-001')),true)
WHERE execution_id='EXEC-PARENT-TEST-001' AND step_id='input_validate';
SELECT 'REQUEST|'||public.lf_rule_promotion_request_v1(
 'EXEC-PARENT-TEST-001','RULE-TEST-001','L4 mutation assessment')::text;
SELECT 'JUDGE|'||public.lf_rule_promotion_quality_judge_v1('PROM-TEST')::text;
ROLLBACK;
SELECT 'READBACK|'||jsonb_build_object(
 'state',(SELECT estado FROM lf_ops.reglas WHERE codigo='RULE-TEST-001'),
 'requests',(SELECT count(*) FROM public.lf_rule_promotion_v1))::text;
"""%(lit(base["titulo"]),lit(case["mutated_description"]),lit(json.dumps(cfg,ensure_ascii=False)))
    out={}
    for line in sql(command).splitlines():
        if "|" not in line:continue
        k,v=line.split("|",1)
        out[k]=json.loads(v)
    if out.get("READBACK")!={"state":"CANDIDATO","requests":0}:
        raise AssertionError("ROLLBACK_NOT_CLEAN "+case["id"]+" "+str(out))
    return out
def main():
    dataset=json.loads(DATA.read_text())
    signals=json.loads(SIGNALS.read_text())
    adversarial=json.loads(ADVERSARIAL.read_text())
    assert dataset["schema_version"]=="LF_L4_INJECTED_MUTATIONS_V1"
    assert len(dataset["cases"])==27
    assert len(signals["cases"])==9
    assert len(adversarial["cases"])==6
    bases={x["codigo"]:x for x in dataset["baselines"]}
    for x in (dataset["cases"]+adversarial["cases"]):
        if x["base_code"] not in bases:raise AssertionError("BASE_ABSENT "+x["base_code"])
        if x["label"] not in ("ALLOW","BLOCK"):raise AssertionError("TRUTH_INVALID")
    sql("CREATE DATABASE "+DATABASE+";",db="postgres")
    for file in ["promotion_pg18_sandbox_fixture.sql",
                 "live_promotion_baseline_fixture.sql"]:
        sql((HERE/file).read_text())
    sql(MIG.read_text())
    initial=sql("SELECT md5(pg_get_functiondef('public.lf_rule_promotion_quality_judge_v1(text)'::regprocedure));")
    rows=[]
    for case in (dataset["cases"]+adversarial["cases"]):
        out=run_row(case,bases[case["base_code"]])
        judge=out["JUDGE"]
        blocked=judge["classification"]=="BLOCKED"
        expected=case["label"]=="BLOCK"
        match=blocked==expected
        row={k:case[k] for k in ("id","family","label","label_origin","base_code","transformation")}
        row.update({"classification":judge["classification"],
                    "blocking_codes":judge["blocking_codes"],
                    "detected":blocked,"expected_defect":expected,
                    "correct":match,"false_negative":expected and not blocked,
                    "false_positive":not expected and blocked,
                    "source_snapshot_sha256":judge["source_snapshot_sha256"],
                    "post_rollback":out["READBACK"]})
        rows.append(row)
        print("RAW_DETERMINISTIC_"+case["id"]+" "+json.dumps(row,sort_keys=True,ensure_ascii=False),flush=True)
    families=collections.defaultdict(list)
    for row in rows: families[row["family"]].append(row)
    summaries={}
    for f,rr in sorted(families.items()):
        sums={"n":len(rr),"positive":sum(x["expected_defect"] for x in rr),
            "detected":sum(x["expected_defect"] and x["detected"] for x in rr),
            "missed":sum(x["false_negative"] for x in rr),
            "false_positive":sum(x["false_positive"] for x in rr),
            "true_negative":sum(not x["expected_defect"] and not x["detected"] for x in rr)}
        summaries[f]=sums
        print("RAW_FAMILY "+f+" "+json.dumps(sums,sort_keys=True),flush=True)
    totals={"cases":len(rows),"core_cases":len(dataset["cases"]),
        "adversarial_cases":len(adversarial["cases"]),
        "defects":sum(x["expected_defect"] for x in rows),
        "detected":sum(x["expected_defect"] and x["detected"] for x in rows),
        "false_negatives":sum(x["false_negative"] for x in rows),
        "healthy":sum(not x["expected_defect"] for x in rows),
        "false_positives":sum(x["false_positive"] for x in rows)}
    # Repeated identical SQL snapshots measure DETERMINISTIC stability only.
    # A native LLM is NOT invoked here; its N-run stability is UNVERIFIED.
    stability=[]
    for stability_case in (dataset["cases"][0],dataset["cases"][-1]):
        repeated=[]
        for ix in range(5):
            v=run_row(stability_case,bases[stability_case["base_code"]])["JUDGE"]
            repeated.append({"classification":v["classification"],
                              "blocking_codes":v["blocking_codes"]})
        varied=len({json.dumps(x,sort_keys=True) for x in repeated})-1
        stability.append({"id":stability_case["id"],"N":5,
                          "variations":varied,"raw":repeated,
                          "mode":"DETERMINISTIC_SQL_NOT_NATIVE_MODEL"})
        print("RAW_STABILITY "+json.dumps(stability[-1],sort_keys=True),flush=True)
    # Real signals: state/status is objective. Normative contradiction is NOT
    # objectively established where scopes differ or policy is only candidate.
    real=[{"id":x["id"],"family":x["family"],
           "label":x["label"],"adjudicated_semantic_defect":False,
           "deterministic_cross_source_scan_supported":False,
           "verdict":"NOT_MEASURED_AS_BLOCK",
           "reason":x["why"]} for x in signals["cases"]]
    result={"schema_version":"LF_L4_DETERMINISTIC_RUNTIME_MEASUREMENT_V1",
            "judge_md5":initial,"data_sha256":hashlib.sha256(DATA.read_bytes()).hexdigest(),
            "synthetic_fixture":True,"native_model_invoked":False,
            "truth":"INJECTED_KNOWN_DEFECT/HEALTHY_CONTROL",
            "totals":totals,"families":summaries,"raw":rows,
            "source_grounded_real_signals":real,
            "deterministic_stability":stability,
            "native_model_stability":{"status":"NOT_TESTED","N":0},
            "limitations":["Does not assess semantic contradictions in real production DB",
             "One synthetic candidate wrapper; real descriptions read-only from live",
             "Unknown real-case applicability is not counted as a false negative",
             "No native model was called by CI",
             "Related-rule split tests operate on synthetic support rule"] }
    OUT.write_text(json.dumps(result,indent=2,ensure_ascii=False)+"\n")
    print("RAW_TOTALS "+json.dumps(totals,sort_keys=True),flush=True)
    print("LF_L4_DETERMINISTIC_MEASUREMENT_COMPLETE "+str(len(rows))+" cases; NOT a reliability PASS",flush=True)
if __name__=="__main__": main()

"""Read-only executable validator for J04 field contracts and J05 observations/errors."""
from __future__ import annotations
import argparse, json
from pathlib import Path
from lf_common import ValidationInputError, duplicate_values, emit, failure, load_json, main_guard, require_object, result_object
J04="J04_FIELD_CONTRACTS"; J05="J05_OBSERVATIONS_ERRORS"; JUDGES=(J04,J05)
POS="E23_FIELD_CONTRACTS_POSITIVE"; NEG="E24_FIELD_CONTRACTS_NEGATIVE"; FIXTURE="evals/fixtures/screen_sensitive_fields.json"
PII={"PII_INDIRECT","PII_DIRECT","PII_SENSITIVE","PII_FINANCIAL"}

def field_checks(pack):
    if "screen_fields" not in pack or "fields" not in pack: raise ValidationInputError("field_inventory_missing")
    sf=pack.get("screen_fields",[]); fs=pack.get("fields",[])
    if not isinstance(sf,list) or not isinstance(fs,list): raise ValidationInputError("screen_fields_and_fields_must_be_arrays")
    if not sf or not fs: raise ValidationInputError("field_inventory_empty")
    codes=[x.get("field_code") for x in fs if isinstance(x,dict)]; declared={x for x in sf if isinstance(x,str)}; contracted={x for x in codes if x}
    c={"fields_without_contract":sorted(declared-contracted),"unexpected_field_contracts":sorted(contracted-declared),"duplicate_field_codes":duplicate_values(x for x in codes if x),"fields_without_visibility_rule":[],"fields_without_editability_rule":[],"pii_fields_without_classification":[],"pii_fields_with_analytics_allowed":[],"pii_fields_with_logs_allowed_without_rule":[],"editable_fields_without_audit_strategy":[],"fields_without_validation_mapping":[]}
    for i,x in enumerate(fs):
        code=x.get("field_code") if isinstance(x,dict) else f"index:{i}"
        if not isinstance(x,dict): c["fields_without_visibility_rule"].append(code); c["fields_without_editability_rule"].append(code); continue
        if not x.get("visibility_mode"): c["fields_without_visibility_rule"].append(code)
        if "editable" not in x: c["fields_without_editability_rule"].append(code)
        cls=x.get("pii_classification")
        if not cls: c["pii_fields_without_classification"].append(code)
        if cls in PII and x.get("analytics_allowed") is not False: c["pii_fields_with_analytics_allowed"].append(code)
        if cls in PII and x.get("logs_allowed") is True and not x.get("masking_rule"): c["pii_fields_with_logs_allowed_without_rule"].append(code)
        if x.get("editable") is True and (x.get("audit_required") is not True or not x.get("previous_value_strategy") or not x.get("new_value_strategy")): c["editable_fields_without_audit_strategy"].append(code)
        if not x.get("validation_codes"): c["fields_without_validation_mapping"].append(code)
    return c,{"screen_fields_count":len(declared),"field_contracts_count":len(fs),"pii_field_count":sum(isinstance(x,dict) and x.get("pii_classification") in PII for x in fs),"editable_field_count":sum(isinstance(x,dict) and x.get("editable") is True for x in fs)}

def oe_checks(pack):
    if "observations" not in pack or "errors" not in pack: raise ValidationInputError("observations_errors_inventory_missing")
    obs=pack.get("observations",[]); errs=pack.get("errors",[])
    if not isinstance(obs,list) or not isinstance(errs,list): raise ValidationInputError("observations_and_errors_must_be_arrays")
    if not obs: raise ValidationInputError("observations_inventory_empty")
    if not errs: raise ValidationInputError("errors_inventory_empty")
    codes=[x.get("error_code") for x in errs if isinstance(x,dict) and x.get("error_code")]
    c={"blocking_conditions_without_error_code":[],"observations_without_user_action":[],"retryable_errors_without_retry_policy":[],"errors_without_correlation_strategy":[],"technical_errors_exposed_to_user":[],"duplicate_error_codes":duplicate_values(codes),"errors_without_message_code":[]}
    for i,x in enumerate(obs):
        code=x.get("observation_code") if isinstance(x,dict) else f"index:{i}"
        if not isinstance(x,dict) or not x.get("user_action"): c["observations_without_user_action"].append(code)
    for i,x in enumerate(errs):
        code=x.get("error_code") if isinstance(x,dict) else f"index:{i}"
        if not isinstance(x,dict): c["blocking_conditions_without_error_code"].append(code); continue
        if x.get("blocking") is True and not x.get("error_code"): c["blocking_conditions_without_error_code"].append(code or f"index:{i}")
        p=x.get("retry_policy")
        if x.get("retryable") is True and (not isinstance(p,dict) or not isinstance(p.get("max_attempts"),int) or p.get("max_attempts",0)<1 or not p.get("backoff")): c["retryable_errors_without_retry_policy"].append(code)
        if x.get("correlation_id_required") is not True and not x.get("trace_code"): c["errors_without_correlation_strategy"].append(code)
        if x.get("technical_detail_visibility")!="INTERNAL_ONLY": c["technical_errors_exposed_to_user"].append(code)
        if not x.get("user_message_code"): c["errors_without_message_code"].append(code)
    return c,{"observation_count":len(obs),"error_count":len(errs),"error_code_count":len(codes),"retry_policy_count":sum(isinstance(x,dict) and isinstance(x.get("retry_policy"),dict) for x in errs),"correlation_strategy_count":sum(isinstance(x,dict) and (x.get("correlation_id_required") is True or bool(x.get("trace_code"))) for x in errs)}

def validate(pack,judge):
    checks,summary=(field_checks(pack) if judge==J04 else oe_checks(pack)); failed=[f"{k}={len(v)}" for k,v in checks.items() if v]
    repairs=[failure(k,"fields" if judge==J04 else ("observations" if k.startswith("observations_") else "errors"),f"Repair objects: {v}") for k,v in checks.items() if v]
    return sorted(failed),repairs,{**summary,"checks":checks}

def positive():
    rows=[("document_number",False,"MASKED","PII_DIRECT","SHOW_LAST_4","VAL-DOCUMENT-FORMAT"),("phone",True,"MASKED","PII_DIRECT","SHOW_LAST_3","VAL-PHONE-FORMAT"),("email",True,"MASKED","PII_DIRECT","MASK_EMAIL","VAL-EMAIL-FORMAT"),("bank_account",True,"MASKED","PII_FINANCIAL","SHOW_LAST_4","VAL-BANK-ACCOUNT"),("monthly_income",False,"SUMMARY","PII_FINANCIAL",None,"VAL-INCOME-RANGE")]; fs=[]
    for code,edit,vis,cls,mask,val in rows:
        x={"field_code":code,"data_type":"DECIMAL" if code=="monthly_income" else "STRING","required":code in {"document_number","phone","email"},"editable":edit,"visibility_mode":vis,"pii_classification":cls,"analytics_allowed":False,"logs_allowed":False,"export_allowed":False,"audit_required":edit,"validation_codes":[val],"source_ref":f"SRC-SENSITIVE#{code}"}
        if mask:x["masking_rule"]=mask
        if edit:x.update(previous_value_strategy="MASKED",new_value_strategy="MASKED")
        fs.append(x)
    return {"screen_fields":[r[0] for r in rows],"fields":fs,"observations":[{"observation_code":"OBS-CONTACT-FORMAT","user_action":"Corregir formato y reenviar","message_code":"MSG-CONTACT-FORMAT"}],"errors":[{"error_code":"ERR-PROFILE-UPDATE-TIMEOUT","blocking":True,"retryable":True,"retry_policy":{"max_attempts":2,"backoff":"EXPONENTIAL"},"user_message_code":"MSG-PROFILE-TEMPORARILY-UNAVAILABLE","correlation_id_required":True,"trace_code":"TRACE-PROFILE-UPDATE","technical_detail_visibility":"INTERNAL_ONLY"}]}

def negative():
    return {"screen_fields":["document_number","phone","bank_account"],"fields":[{"field_code":"document_number","data_type":"STRING","required":True,"editable":False,"visibility_mode":"FULL","pii_classification":"PII_DIRECT","analytics_allowed":True,"logs_allowed":True,"export_allowed":False,"audit_required":False,"validation_codes":[],"source_ref":"SRC-SENSITIVE#document"},{"field_code":"phone","data_type":"STRING","required":True,"editable":True,"visibility_mode":"FULL","pii_classification":"PII_DIRECT","analytics_allowed":False,"logs_allowed":False,"export_allowed":False,"audit_required":False,"validation_codes":[],"source_ref":"SRC-SENSITIVE#phone"}],"observations":[{"observation_code":"OBS-UNKNOWN","message_code":"MSG-UNKNOWN"}],"errors":[{"blocking":True,"retryable":True,"correlation_id_required":False,"technical_detail_visibility":"USER_VISIBLE","technical_detail":"stack trace"}]}

def eval_case(case_id,judge):
    if case_id==POS: pack,expected,must=positive(),"PASS_WITH_EVIDENCE",False
    elif case_id==NEG: pack,expected,must=negative(),"RETURN_TO_WORKER",True
    else: raise ValidationInputError(f"eval_case_not_found:{case_id}")
    failed,_,evidence=validate(pack,judge); actual="PASS_WITH_EVIDENCE" if not failed else "RETURN_TO_WORKER"; mismatch=[] if actual==expected else [f"validator_result_mismatch:{actual}!={expected}"]
    if must and actual=="PASS_WITH_EVIDENCE": mismatch.append("negative_case_not_rejected=1")
    ev={"case_id":case_id,"judge":judge,"fixture_ref":FIXTURE,"expected_validation_result":expected,"actual_validation_result":actual,"matched":not mismatch,"candidate_failed_assertions":failed,"candidate_evidence":evidence,"negative_must_be_rejected":must}
    return emit(result_object(judge,mismatch,ev,[f"file:{FIXTURE}",f"eval:{case_id}"],[] if not mismatch else [failure("validator_result_mismatch",f"evals.{case_id}.{judge}","Align without weakening assertions.")],retry_count=0))

def self_test():
    out=[]; ok=True
    for case,judge,expected in ((POS,J04,"PASS_WITH_EVIDENCE"),(POS,J05,"PASS_WITH_EVIDENCE"),(NEG,J04,"RETURN_TO_WORKER"),(NEG,J05,"RETURN_TO_WORKER")):
        pack=positive() if case==POS else negative(); failed,_,_=validate(pack,judge); actual="PASS_WITH_EVIDENCE" if not failed else "RETURN_TO_WORKER"; out.append({"case_id":case,"judge":judge,"expected":expected,"actual":actual,"matched":actual==expected,"failed_assertions":failed}); ok &= actual==expected
    print(json.dumps({"judge_code":"J04_J05_FIELD_OBSERVATIONS_ERRORS_CHAIN","result":"PASS_WITH_EVIDENCE" if ok else "FAIL","compliance_bit":1 if ok else 0,"outcomes":out},ensure_ascii=False,sort_keys=True)); return 0 if ok else 1

def run():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("input",type=Path,nargs="?"); p.add_argument("--judge",choices=JUDGES,default=J04); p.add_argument("--case-id"); p.add_argument("--self-test",action="store_true"); p.add_argument("--evidence-ref",action="append",default=[]); p.add_argument("--retry-count",type=int,default=0); a=p.parse_args()
    if a.self_test:return self_test()
    if a.case_id:return eval_case(a.case_id,a.judge)
    if a.input is None:raise ValidationInputError("story_pack_input_required")
    pack=require_object(load_json(a.input),"story_pack"); failed,repairs,evidence=validate(pack,a.judge); evidence["input_path"]=str(a.input); return emit(result_object(a.judge,failed,evidence,a.evidence_ref or [f"file:{a.input}"],repairs,retry_count=a.retry_count))
if __name__=="__main__":raise SystemExit(main_guard("J04_J05_FIELD_OBSERVATIONS_ERRORS_CHAIN",run))

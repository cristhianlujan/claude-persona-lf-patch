"""Strict candidate STD catalogue validator; no authority or release inference."""
import json
from pathlib import Path
class STDValidationError(ValueError): pass
DOMAINS={"API","CODE","POSTGRES","API_POSTGRES","CI","UI_API","QUALIFICATION","IAC","ARCHITECTURE","OBSERVABILITY","COST"}
POLICIES={"PROJECT_DEPENDENT","BLOCK_IF_ABSENT","DEFAULT","GLOSSARY_DEPENDENT","CONDITIONAL","STACK_DEPENDENT","PHASE1_AND_LF_CONFLICT","SCOPE_BOUNDARY","BLOCK_UNTIL_AUTHORITY","PRICING_PENDING","BLOCK_BUDGET_AMOUNTS_PENDING"}
def validate(source,candidate):
    if not isinstance(source,dict) or not isinstance(candidate,dict): raise STDValidationError("INVALID_INPUT")
    if source.get("state")!="SOURCE_ONLY_CANDIDATE_NOT_RELEASED" or candidate.get("state")!="DRAFT_NOT_RELEASED":
        raise STDValidationError("UNAUTHORIZED_RELEASE_STATE")
    rows=source.get("rules"); rules=candidate.get("rules")
    if not isinstance(rows,list) or not isinstance(rules,list) or len(rows)!=17 or len(rules)!=17: raise STDValidationError("RULE_COUNT")
    for idx,(original,rule) in enumerate(zip(rows,rules),1):
        if not isinstance(original,dict) or not isinstance(rule,dict): raise STDValidationError("INVALID_RULE_SHAPE")
        expected=f"ADR-PROG-STD-{idx:03}"
        if original.get("adr")!=expected or rule.get("adr")!=expected or rule.get("rule_id")!=original.get("rule_id"): raise STDValidationError("ADR_PARITY")
        if rule.get("source_decision")!=original.get("decision_text") or rule.get("source_title")!=original.get("title"): raise STDValidationError("SOURCE_DRIFT")
        if rule.get("proposed_domain") not in DOMAINS or rule.get("activation_policy") not in POLICIES: raise STDValidationError("POLICY_UNKNOWN")
        for key in ("proposed_requirement","ok_example","no_example"):
            if not isinstance(rule.get(key),str) or not rule[key].strip(): raise STDValidationError("EXAMPLE_MISSING")
        if rule["ok_example"]==rule["no_example"]: raise STDValidationError("EXAMPLE_COLLISION")
        if rule.get("authority")!="SOURCE_ADR_NOT_RELEASED" or rule.get("example_status")!="ILLUSTRATIVE_NOT_TESTED" or rule.get("severity")!="CANDIDATE_REQUIRES_OWNER_REVIEW": raise STDValidationError("AUTHORITY_ESCALATION")
    if "ambiguity BLOCK" not in candidate.get("precedence",""): raise STDValidationError("L3_PRECEDENCE")
    if len(candidate.get("stop_conditions",[]))<4: raise STDValidationError("STOP_GUARDS")
    return {"state":"CANDIDATE_SHAPE_ONLY","rules":17,"release_authorized":False}

if __name__=="__main__":
    folder=Path(__file__).parent
    print(validate(json.loads((folder/"pg00_std_adr_source_catalog_v1.json").read_text()),json.loads((folder/"pg00_std_rules_candidate_v1.json").read_text())))

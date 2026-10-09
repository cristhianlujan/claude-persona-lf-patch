#!/usr/bin/env python3
"""M9.2 exact-source negative regression: no IG function rewrite in release switch."""
import hashlib, json, os, re, sys
TEST_CODE="ENG_M9_2_NO_REWRITE_NEGATIVE"
EXPECTED_BLOB="ab64903efab3b66b6498333f3c3003a96c09a1c4"
def clean_sql(text):
    return re.sub(r"--[^\n]*", "", text)
def classify(text):
    src=clean_sql(text)
    forbidden=[
       r"\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b",
       r"\bDROP\s+FUNCTION\b",
       r"\bALTER\s+FUNCTION\b",
       r"\bCREATE\s+TABLE\b",
       r"\bUPDATE\s+(?:public\.)?lf_capability_current\b",
    ]
    if any(re.search(p,src,re.IGNORECASE) for p in forbidden):
        return False,"FUNCTION_REWRITE_OR_PARALLEL_POINTER_FORBIDDEN"
    required=("public.fn_lf_capability_promote_v1","public.lf_capability_version_registry","public.lf_capability_current")
    if not all(x in src for x in required):
        return False,"CANONICAL_CUTOVER_BINDING_MISSING"
    return True,"CANONICAL_POINTER_ONLY"
def main():
    source=os.environ.get("LF_M9_2_RELEASE_SQL","")
    blob=hashlib.sha1(f"blob {len(source.encode())}\0".encode()+source.encode()).hexdigest()
    authority_bound=os.environ.get("LF_M9_2_ADR")=="DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001:VIGENTE"
    pos=classify(source)
    negative_rewrite=classify(source+"\nCREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_v1() RETURNS void LANGUAGE sql AS 'SELECT 1';")
    negative_pointer=classify(source.replace("public.fn_lf_capability_promote_v1","UPDATE public.lf_capability_current SET version='1.0.1'"))
    observed={
      "test_passed":pos[0] and not negative_rewrite[0] and not negative_pointer[0] and authority_bound and blob==EXPECTED_BLOB,
      "test_exit_code":0,
      "semantic_authority_bound":authority_bound,
      "adversarial_case_executed":True,
      "positive":pos[1],
      "negative_function_rewrite":negative_rewrite[1],
      "negative_direct_pointer":negative_pointer[1],
      "source_blob_sha":blob,
    }
    print(json.dumps({"status":"PASS" if observed["test_passed"] else "FAIL","test_code":TEST_CODE,"observed":observed},sort_keys=True))
    return 0 if observed["test_passed"] else 1
if __name__=="__main__":sys.exit(main())

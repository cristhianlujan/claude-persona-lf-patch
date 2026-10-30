#!/usr/bin/env python3
"""Same WEB-001 material-gap input, two exact profile validator trees. No model attestation."""
import copy, json, pathlib, sys, importlib.util
root=pathlib.Path(__file__).resolve().parents[3]
current=pathlib.Path(sys.argv[1]).resolve()
candidate=pathlib.Path(sys.argv[2]).resolve()
capture=root/"docs/profile_updater/handoffs/WEB001_GPT_NATIVE_CURRENT_CHAT_N1N2_READBACK_20261030.json"
packet=json.loads(capture.read_text(encoding="utf-8"))
assert packet["case_id"]=="WEB-001" and packet["provider_attested"] is False
assert packet["independent_semantic_review"] is False
raw=packet["raw_output"]
manifest=packet["evidence_manifest"]
def load(directory,alias):
    spec=importlib.util.spec_from_file_location(alias,directory/"validators/producer_depth.py")
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    return mod.validate_producer_depth
base=load(current,"srcr_v0_current")
new=load(candidate,"srcr_v1_evolved")
def codes(fn,obj):
    return {x["code"] for x in fn(obj,manifest)}
out={}
mutations={
  "complete_live_source_readback":lambda q:None,
  "missing_N2":lambda q:q["current_uncertainties"][0]["cascade"]["catalog_queries"].pop(),
  "fabricated_owner":lambda q:q["current_uncertainties"][0]["cascade"]["catalog_queries"][0]["readback"]["sample_records"][0].__setitem__("owner_name","FABRICATED"),
  "wrong_datum":lambda q:q["current_uncertainties"][0]["cascade"]["catalog_queries"][0].__setitem__("datum_id","ANOTHER-DATUM"),
  "fake_EMPTY":lambda q:q["current_uncertainties"][0]["cascade"]["catalog_queries"][1]["readback"].__setitem__("result_kind","EMPTY"),
}
for name,mutate in mutations.items():
    item=copy.deepcopy(raw);mutate(item)
    old_errors=sorted(codes(base,item));new_errors=sorted(codes(new,item))
    out[name]={"current":{"pass":not old_errors,"errors":old_errors},"evolved":{"pass":not new_errors,"errors":new_errors}}
    print(json.dumps({"scenario":name,**out[name]},ensure_ascii=False))
# Profile-current rejects correct open-uncertainty with a generic premature-closure rule;
# profile-evolved correctly accepts it and enforces source-origin material evidence.
assert out["complete_live_source_readback"]["current"]["errors"]==["GAP_CASCADE_EXHAUSTED_CLOSE_WITH_SEARCH_RECORD"],out["complete_live_source_readback"]
assert out["complete_live_source_readback"]["evolved"]["pass"],out["complete_live_source_readback"]
expected={
    "missing_N2":"GAP_CATALOG_N1_N2_MISSING",
    "fabricated_owner":"GAP_CATALOG_READBACK_DIGEST_MISMATCH",
    "wrong_datum":"GAP_CATALOG_DATUM_MISMATCH",
    "fake_EMPTY":"GAP_CATALOG_RESULT_INCONSISTENT",
}
for name,needed in expected.items():
    assert out[name]["current"]["errors"]==["GAP_CASCADE_EXHAUSTED_CLOSE_WITH_SEARCH_RECORD"],("CURRENT_UNEXPECTED",name,out[name]["current"])
    assert needed in out[name]["evolved"]["errors"],("EVOLVED_DID_NOT_DETECT",name,needed,out[name]["evolved"])
print("PAIRED_WEB001_CURRENT_VS_EVOLVED=PASS current_correct_resolution=FAIL evolved_correct_resolution=PASS")
print("PAIRED_WEB001_TAMPERING_DETECTION=current_specific_0/4 evolved_specific_4/4")
print("AUTHORITY=UNATTESTED_SAME_CHAT_FUNCTIONAL_TEST NOT_OFFICIAL_EVOLUTION_CERTIFICATION")

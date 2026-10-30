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
assert out["complete_live_source_readback"]["current"]["pass"]
assert out["complete_live_source_readback"]["evolved"]["pass"]
for name in list(mutations)[1:]:
    assert out[name]["current"]["pass"],("BASE_UNEXPECTED_REJECT",name,out[name]["current"])
    assert not out[name]["evolved"]["pass"],("EVOLVED_DID_NOT_REJECT",name)
print("PAIRED_WEB001_CURRENT_VS_EVOLVED=PASS verified_negative_detection=4/4 current_detection=0/4")
print("AUTHORITY=UNATTESTED_SAME_CHAT_FUNCTIONAL_TEST NOT_OFFICIAL_EVOLUTION_CERTIFICATION")

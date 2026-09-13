#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("s31_ir", ROOT / "validate_s31_independent_review_intake_v0_1.py")
m = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = m
SPEC.loader.exec_module(m)

ABC_SHA = "bbcd9056443059cf1da4782551a85b3a70bd2910"
DG_SHA = "d268fd871f2e18588f9b8084e6a3f6c6e07aa438"


def load_pair(bundle_name: str, handoff_name: str):
    bundle_text = (ROOT / bundle_name).read_text(encoding="utf-8")
    return json.loads(bundle_text), (ROOT / handoff_name).read_text(encoding="utf-8"), bundle_text


abc, abc_handoff, abc_text = load_pair("s31_abc_independent_review_bundle_v0_5.json", "S31_ABC_INDEPENDENT_REVIEW_HANDOFF_V0_2.md")
dg, dg_handoff, dg_text = load_pair("s31_dg_independent_review_bundle_v0_3.json", "S31_DG_INDEPENDENT_REVIEW_HANDOFF_V0_1.md")

assert m.evaluate_pair(abc, abc_handoff, abc_text, "S31-ABC-IR-001", ABC_SHA)["status"] == "PASS"
assert m.evaluate_pair(dg, dg_handoff, dg_text, "S31-DG-IR-001", DG_SHA)["status"] == "PASS"

x = copy.deepcopy(abc); x["producer_semantic_verdict"] = "PASS"
assert m.validate_bundle(x, ABC_SHA)["code"] == "BLOCK_PRODUCER_SEMANTIC_VERDICT_PRESENT"

x = copy.deepcopy(abc); x["quality_pack"]["score_rubric_ref"] = "github://cristhianlujan/claude-persona-lf-patch@main/profiles/quality_pack/judges/quality_pack_score_rubric.md"
assert m.validate_bundle(x, ABC_SHA)["code"] == "BLOCK_QUALITY_PACK_REF_NOT_FROZEN"

x = copy.deepcopy(abc); x["candidate_snapshot"]["s31_candidate_head"] = "f" * 40
assert m.validate_bundle(x, ABC_SHA)["code"] == "BLOCK_CANDIDATE_SNAPSHOT_MISMATCH"

x = abc_handoff + '\n"overall_verdict": "PASS"\n'
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_PARALLEL_RECEIPT_CONTRACT_PRESENT"

x = abc_handoff.replace("5fe28054a2320e26da95db494da85126b5323cab", "0" * 40)
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_REVIEW_BUNDLE_SHA_MISMATCH"

x = abc_handoff.replace("reviewer_is_producer = false", "reviewer_is_producer = true")
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_HANDOFF_CANONICAL_TOKENS_MISSING"

x = abc_handoff.replace("@32f73efc8794686ca9d57424d0945af69f3b9358/", "@lf/s31-bootstrap/")
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_REVIEW_ARTIFACT_REF_NOT_IMMUTABLE"

# Scope-specific snapshots are allowed, but cross-scope substitution is not.
assert m.validate_bundle(abc, DG_SHA)["code"] == "BLOCK_CANDIDATE_SNAPSHOT_MISMATCH"
assert m.validate_bundle(dg, ABC_SHA)["code"] == "BLOCK_CANDIDATE_SNAPSHOT_MISMATCH"

print("PASS_S31_INDEPENDENT_REVIEW_INTAKE_V0_1=12/12")

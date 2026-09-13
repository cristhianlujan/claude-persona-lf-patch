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


def load_pair(bundle_name: str, handoff_name: str):
    bundle_text = (ROOT / bundle_name).read_text(encoding="utf-8")
    return json.loads(bundle_text), (ROOT / handoff_name).read_text(encoding="utf-8"), bundle_text


abc, abc_handoff, abc_text = load_pair("s31_abc_independent_review_bundle_v0_3.json", "S31_ABC_INDEPENDENT_REVIEW_HANDOFF_V0_2.md")
dg, dg_handoff, dg_text = load_pair("s31_dg_independent_review_bundle_v0_2.json", "S31_DG_INDEPENDENT_REVIEW_HANDOFF_V0_1.md")

# Positive frozen bundles and handoffs.
assert m.evaluate_pair(abc, abc_handoff, abc_text, "S31-ABC-IR-001")["status"] == "PASS"
assert m.evaluate_pair(dg, dg_handoff, dg_text, "S31-DG-IR-001")["status"] == "PASS"

# Producer semantic verdict must never prime independent review.
x = copy.deepcopy(abc); x["producer_semantic_verdict"] = "PASS"
assert m.validate_bundle(x)["code"] == "BLOCK_PRODUCER_SEMANTIC_VERDICT_PRESENT"

# Quality Pack refs must be immutable and pinned to the governed source revision.
x = copy.deepcopy(abc); x["quality_pack"]["score_rubric_ref"] = "github://cristhianlujan/claude-persona-lf-patch@main/profiles/quality_pack/judges/quality_pack_score_rubric.md"
assert m.validate_bundle(x)["code"] == "BLOCK_QUALITY_PACK_REF_NOT_FROZEN"

# Candidate snapshot drift cannot silently enter the review bundle.
x = copy.deepcopy(abc); x["candidate_snapshot"]["s31_candidate_head"] = "f" * 40
assert m.validate_bundle(x)["code"] == "BLOCK_CANDIDATE_SNAPSHOT_MISMATCH"

# Parallel custom S31 receipt contracts are forbidden.
x = abc_handoff + '\n"overall_verdict": "PASS"\n'
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_PARALLEL_RECEIPT_CONTRACT_PRESENT"

# Bundle digest mismatch is fail-closed.
x = abc_handoff.replace("3042fb6fcc14fea7d2223d91af18c211ada6a94f", "0" * 40)
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_REVIEW_BUNDLE_SHA_MISMATCH"

# Independence metadata cannot be weakened.
x = abc_handoff.replace("reviewer_is_producer = false", "reviewer_is_producer = true")
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_HANDOFF_CANONICAL_TOKENS_MISSING"

# Mutable artifact ref is rejected.
x = abc_handoff.replace("@50b343b8b56e1c7f5ac5497151f9ab11cd7e26a0/", "@lf/s31-bootstrap/")
assert m.validate_handoff(x, abc_text, "S31-ABC-IR-001")["code"] == "BLOCK_REVIEW_ARTIFACT_REF_NOT_IMMUTABLE"

print("PASS_S31_INDEPENDENT_REVIEW_INTAKE_V0_1=10/10")

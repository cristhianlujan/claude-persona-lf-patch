#!/usr/bin/env python3
"""Replay the exact preserved V1 escape against the V0.3 boundaries.

Historical bytes and counterevidence are supplied externally. The production
validators contain no event/domain literals; this harness is evidence-only.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATORS = ROOT / "validators"
sys.path.insert(0, str(VALIDATORS))

import closure_proof
import runtime_validate


def _load_local(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


quality = _load_local("srcr_replay_quality", VALIDATORS / "validate_quality_receipt.py")

INVARIANTS = [
    "SCOPE_AUTHORITY_INTEGRITY",
    "EVIDENCE_INTEGRITY",
    "CAUSAL_CLOSURE",
    "CONTRADICTION_INTEGRITY",
    "MINIMUM_SUFFICIENT_REUSE",
    "INDEPENDENT_DECISION_CLOSURE",
    "FALSIFIABILITY_REGRESSION",
]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--v1-json", required=True)
    p.add_argument("--expected-sha", required=True)
    p.add_argument("--counterevidence", required=True)
    return p.parse_args()


def semantic_pass(candidate):
    candidate_sha = closure_proof.canonical_candidate_digest(candidate).split(":", 1)[1]
    return {
        "verdict": "PASS_INDEPENDENT_SEMANTIC",
        "candidate_sha256": candidate_sha,
        "scope_packet_sha256": "c" * 64,
        "source_refs_inspected": ["replay://historical-evidence"],
        "observed_candidate_changes": [],
        "requirement_reconciliation": [],
        "change_declaration_reconciliation": [],
        "scope_conformance_reconciliation": [],
        "invariant_results": [
            {
                "invariant": name,
                "result": "PASS",
                "evidence_refs": ["replay://historical-evidence"],
                "reason": "Adversarial receipt fixture; closure validator remains authoritative for exact evidence binding.",
            }
            for name in INVARIANTS
        ],
        "open_design_decisions_found": [],
        "unsupported_claims": [],
        "blocking_codes": [],
        "repair_instructions": [],
        "next_gate": "QUALITY_RECEIPT",
    }


def make_pass_receipt(candidate, evidence, semantic, summary):
    return {
        "receipt_version": "SRCR_QUALITY_RECEIPT_V1",
        "profile_pack_id": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3",
        "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        "decision": "PASS_TO_QUALITY_PACK",
        "review_boundary": {
            "issuer": "CANONICAL_SRCR_MINI_JUDGE",
            "execution_mode": "INDEPENDENT_SEMANTIC_REVIEW",
            "reviewer_is_producer": False,
            "producer_context_available": False,
            "semantic_execution_receipt_ref": "replay://independent-semantic/escape-test",
        },
        "candidate_binding": {
            "candidate_revision": "replay-quality-boundary-rev-1",
            "candidate_digest": closure_proof.canonical_candidate_digest(candidate),
        },
        "evidence_binding": {
            "bundle_id": evidence["bundle_id"],
            "bundle_digest": evidence["bundle_digest"],
        },
        "semantic_binding": {
            "semantic_result_digest": quality.canonical_semantic_result_digest(semantic),
            "semantic_verdict": semantic["verdict"],
            "candidate_sha256": semantic["candidate_sha256"],
            "scope_packet_sha256": semantic["scope_packet_sha256"],
        },
        "proof_binding": {
            "required_obligation_ids": summary["required_obligation_ids"],
            "closed_obligation_ids": summary["closed_obligation_ids"],
            "open_obligation_ids": summary["open_obligation_ids"],
        },
        "blocking_codes": [],
        "issued_at": "2026-09-20T00:00:00Z",
    }


def main():
    args = parse_args()
    raw = Path(args.v1_json).read_bytes()
    actual_sha = hashlib.sha256(raw).hexdigest()
    assert actual_sha == args.expected_sha, (actual_sha, args.expected_sha)

    v1 = json.loads(raw)
    counter = json.loads(Path(args.counterevidence).read_text())

    expected_zero_keys = {
        "profile_release_lifecycle_catalog_rows",
        "profile_release_lifecycle_transition_rows",
        "profile_release_reconciliation_registry_rows",
    }
    assert set(counter) == expected_zero_keys, counter
    assert all(counter[k] == 0 for k in expected_zero_keys), counter

    # Historical compatibility is preserved but explicitly capped below quality.
    assert v1.get("profile_pack_id") == "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2"
    historical = runtime_validate.validate(copy.deepcopy(v1))
    assert historical["status"] == "PASS", historical
    assert historical["canonical_quality_accepted"] is False, historical
    assert historical["validation_role"] == "PRE_QUALITY_STRUCTURAL_FLOOR", historical

    # Merely relabeling the escaped payload as V0.3 cannot inherit readiness.
    naive_v03 = copy.deepcopy(v1)
    naive_v03["profile_pack_id"] = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3"
    naive = runtime_validate.validate(naive_v03)
    assert naive["status"] == "FAIL", naive
    assert "SRCR_CLOSURE_PROOF_REQUIRED" in naive["blocking_codes"], naive

    # Build a structurally complete generic V0.3 envelope, then replay the old
    # authority claims into it without external observations for those subjects.
    fixture = runpy.run_path(str(ROOT / "evals" / "v03_deterministic_floor_cases.py"))
    candidate, evidence = fixture["valid_pair"]()

    old_slots = (
        ("origin_asset", v1["origin_asset"]["code"], "EV-HIST-ASSET"),
        ("origin_operation", v1["origin_operation"]["code"], "EV-HIST-OP"),
        ("owner", v1["owner"]["code"], "EV-HIST-OWNER"),
    )
    for index, (field, subject, evidence_id) in enumerate(old_slots):
        candidate[field].update(
            {
                "code": subject,
                "authority_kind": "EXISTING_AUTHORITY",
                "evidence_id": evidence_id,
                "subject": subject,
                "observed_revision": "historical-replay",
            }
        )
        candidate["closure_proof"]["authority_bindings"][index].update(
            {
                "subject": subject,
                "authority_kind": "EXISTING_AUTHORITY",
                "used_as_existing_authority": True,
                "evidence_ids": [evidence_id],
            }
        )

    # The externally resolved manifest intentionally has no evidence entry for
    # those claimed-current historical authorities. This is the old false-
    # authority condition expressed through the generic V0.3 evidence contract.
    candidate, evidence = fixture["rebind"](candidate, evidence)
    replay_gate = runtime_validate.validate(candidate, evidence)
    assert replay_gate["status"] == "FAIL", replay_gate
    replay_codes = set(replay_gate["blocking_codes"])
    assert "SRCR_EXISTING_AUTHORITY_EVIDENCE_UNRESOLVED" in replay_codes, replay_codes
    assert "SRCR_AUTHORITY_EVIDENCE_ID_UNRESOLVED" in replay_codes, replay_codes

    closure_errors, summary = closure_proof.validate_v03_closure(candidate, evidence)
    assert closure_errors, "underclosed replay unexpectedly has clean closure"

    semantic = semantic_pass(candidate)
    receipt = make_pass_receipt(candidate, evidence, semantic, summary)
    quality_gate = quality.validate_quality_receipt(receipt, candidate, evidence, semantic)
    assert quality_gate["status"] == "FAIL", quality_gate
    assert quality_gate["canonical_quality_accepted"] is False, quality_gate
    assert "SRCR_QUALITY_CLOSURE_FLOOR_FAILED" in quality_gate["blocking_codes"], quality_gate

    # Case-specific tokens are confined to this replay harness, never the
    # production validator/quality-verifier implementation.
    production_paths = [
        VALIDATORS / "closure_proof.py",
        VALIDATORS / "runtime_validate.py",
        VALIDATORS / "runtime_semantic_utility.py",
        VALIDATORS / "validate_quality_receipt.py",
    ]
    forbidden = ("PROFILE_RELEASE", "14701")
    hits = {}
    for path in production_paths:
        text = path.read_text()
        found = [token for token in forbidden if token in text]
        if found:
            hits[str(path.relative_to(ROOT))] = found
    assert not hits, hits

    print(
        json.dumps(
            {
                "status": "PASS",
                "case": "EXACT_HISTORICAL_ESCAPE_REPLAY",
                "exact_v1_sha256": actual_sha,
                "exact_v1_bytes": len(raw),
                "historical_v02_contract_status": historical["status"],
                "historical_v02_quality_accepted": historical["canonical_quality_accepted"],
                "naive_v03_status": naive["status"],
                "evidence_bound_v03_status": replay_gate["status"],
                "v03_quality_receipt_status": quality_gate["status"],
                "counterevidence_zero_fields": sorted(expected_zero_keys),
                "production_case_literal_hits": hits,
                "claim_boundary": "ESCAPE_PREVENTION_PROVEN; AUTONOMOUS_SAME_INPUT_PRODUCER_RERUN_NOT_CLAIMED",
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

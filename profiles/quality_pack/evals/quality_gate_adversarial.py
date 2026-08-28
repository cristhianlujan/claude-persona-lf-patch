#!/usr/bin/env python3
import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from validate_gate_bundle import validate_bundle

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
HEAD = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
ORIGIN = subprocess.check_output(["git", "-C", str(ROOT), "remote", "get-url", "origin"], text=True).strip()
if ORIGIN.startswith("git@github.com:"):
    REPO = ORIGIN.split(":", 1)[1]
else:
    REPO = urlparse(ORIGIN).path.lstrip("/")
if REPO.endswith(".git"):
    REPO = REPO[:-4]


def git_bytes(path):
    return subprocess.check_output(["git", "-C", str(ROOT), "show", f"{HEAD}:{path}"])


def ev(path, self_certified=False):
    raw = git_bytes(path)
    return {
        "ref": f"github://{REPO}@{HEAD}/{path}",
        "sha256": hashlib.sha256(raw).hexdigest(),
        "observed": True,
        "self_certified": self_certified,
    }


STRUCTURAL_PATH = "profiles/quality_pack/validators/validate_gate_bundle.py"
OPERATION_RECEIPT_PATH = "sandbox/lf_contract_gate_test/receipts/actualizacion-perfil-quality-pack-20260827-001.json"
SEMANTIC_PATH = "profiles/quality_pack/judges/quality_pack_mini_judge.md"
ARTIFACT_PATH = "profiles/quality_pack/SKILL.md"
UPSTREAM_PATH = "profiles/evidence_lineage_reviewer_lf/SKILL.md"


def base():
    return {
        "final_verdict": "PASS_TO_COMPOSER",
        "gates": {
            "structural": {"applicable": True, "status": "PASS", "evidence": [ev(STRUCTURAL_PATH)]},
            # No genuine PROFILE_EXECUTION_RECEIPT_V1 is asserted by this deterministic fixture.
            # Provenance is therefore honestly N/A in the positive instead of being fabricated.
            "provenance": {"applicable": False, "status": "NOT_APPLICABLE", "evidence": []},
            "semantic": {
                "applicable": True,
                "status": "PASS",
                "evidence": [ev(SEMANTIC_PATH)],
                "producer_oracle_id": "worker-oracle-v1",
                "judge_oracle_id": "independent-judge-v2",
                "decision_supported": True,
                "uncertainty": "NONE",
                "router_direct_equivalent": True,
            },
            "artifact": {
                "applicable": True,
                "status": "PASS",
                "evidence": [ev(ARTIFACT_PATH)],
                "exists": True,
                "readback_ok": True,
                "parseable": True,
            },
            "upstream": {
                "applicable": True,
                "status": "PASS",
                "evidence": [ev(UPSTREAM_PATH)],
                "current": True,
                "sha_match": True,
                "validator_status": "PASS",
            },
        },
        "acceptance_checks": [
            {
                "subject": "selected decision",
                "condition": "observable output satisfies the governed acceptance condition",
                "observable": True,
            }
        ],
        "score": {
            "total": 25,
            "evidence_by_criterion": {
                "contract": [ev(STRUCTURAL_PATH)],
                "evidence": [ev(OPERATION_RECEIPT_PATH)],
                "safety": [ev(SEMANTIC_PATH)],
                "handoff": [ev(ARTIFACT_PATH)],
                "scope": [ev(UPSTREAM_PATH)],
            },
        },
        "blocking_codes": [],
        "remaining_risks": [],
    }


def mutate(path, value):
    data = copy.deepcopy(base())
    cur = data
    keys = path.split(".")
    for key in keys[:-1]:
        cur = cur[key]
    cur[keys[-1]] = value
    return data


def fake_ref_bundle():
    data = base()
    data["gates"]["structural"]["evidence"] = [
        {
            "ref": f"github://{REPO}@{HEAD}/does/not/exist.json",
            "sha256": "0" * 64,
            "observed": True,
            "self_certified": False,
        }
    ]
    return data


def wrong_digest_bundle():
    data = base()
    data["gates"]["artifact"]["evidence"][0]["sha256"] = "0" * 64
    return data


def provenance_pass(receipt_ref, receipt_sha):
    data = base()
    data["gates"]["provenance"] = {
        "applicable": True,
        "status": "PASS",
        "evidence": [ev(OPERATION_RECEIPT_PATH)],
        "receipt_valid": True,
        "receipt_ref": receipt_ref,
        "receipt_sha256": receipt_sha,
        "execution_origin": "MODEL_RUNTIME",
        "raw_output_captured": True,
    }
    return data


def fake_receipt_bundle():
    fake = f"github://{REPO}@{HEAD}/does/not/exist-receipt.json"
    return provenance_pass(fake, "0" * 64)


def wrong_receipt_type_bundle():
    operation_receipt = ev(OPERATION_RECEIPT_PATH)
    return provenance_pass(operation_receipt["ref"], operation_receipt["sha256"])


def missing_provenance_bundle():
    data = base()
    data["gates"]["provenance"] = {"applicable": True, "status": "UNCERTAIN", "evidence": []}
    return data


cases = [
    ("positive_applicable_gates_resolver_backed", "positive", base(), True, None),
    ("gov037_nonexistent_ref_self_declared_observed", "adversarial", fake_ref_bundle(), False, "resolver-backed readback failed"),
    ("gov037_real_ref_wrong_declared_sha", "adversarial", wrong_digest_bundle(), False, "declared digest does not match resolver-derived bytes"),
    ("gov037_receipt_valid_flag_without_resolved_receipt", "adversarial", fake_receipt_bundle(), False, "resolver-backed readback failed"),
    ("gov037_real_but_wrong_receipt_type_cannot_prove_model_runtime", "adversarial", wrong_receipt_type_bundle(), False, "resolved receipt_type is not PROFILE_EXECUTION_RECEIPT_V1"),
    ("receipt_real_semantic_wrong", "crosscheck", mutate("gates.semantic.decision_supported", False), False, "decision_supported"),
    ("correct_missing_provenance", "crosscheck", missing_provenance_bundle(), False, "PASS_TO_COMPOSER requires every applicable gate PASS"),
    ("upstream_stale", "negative", mutate("gates.upstream.current", False), False, "stale upstream"),
    ("artifact_plan_only", "negative", mutate("gates.artifact.exists", False), False, "artifact PASS requires true"),
    ("router_direct_diverge", "adversarial", mutate("gates.semantic.router_direct_equivalent", False), False, "divergence blocks semantic PASS"),
    ("semantic_uncertain", "holdout", mutate("gates.semantic.uncertainty", "UNCERTAIN"), False, "cannot pass"),
    ("correlated_oracle", "adversarial", mutate("gates.semantic.judge_oracle_id", "worker-oracle-v1"), False, "must not reuse producer oracle"),
    ("self_certified_evidence", "adversarial", mutate("gates.semantic.evidence", [ev(SEMANTIC_PATH, True)]), False, "self-certified evidence"),
    ("generic_acceptance", "negative", mutate("acceptance_checks", [{"subject": "", "condition": "PASS", "observable": False}]), False, "concrete subject required"),
    ("score_25_nominal_evidence", "negative", mutate("score", {"total": 25, "evidence_by_criterion": {"contract": ["PASS"], "evidence": ["ok"], "safety": ["PASS"], "handoff": ["ok"], "scope": ["PASS"]}}), False, "evidence must be an object"),
    ("malformed_bundle", "negative", None, False, "bundle: expected object"),
]

results = []
failed = False
for case_id, kind, bundle, expected_valid, expected_error in cases:
    errors = validate_bundle(bundle)
    actual_valid = not errors
    passed = actual_valid == expected_valid and (
        expected_error is None or any(expected_error in error for error in errors)
    )
    failed |= not passed
    results.append(
        {
            "id": case_id,
            "kind": kind,
            "expected_valid": expected_valid,
            "actual_valid": actual_valid,
            "expected_error": expected_error,
            "errors": errors,
            "passed": passed,
        }
    )

digest = hashlib.sha256(json.dumps(results, sort_keys=True).encode()).hexdigest()
print(json.dumps({"passed": not failed, "case_count": len(results), "results_sha256": digest, "results": results}, indent=2))
raise SystemExit(1 if failed else 0)

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
from validate_routing import normalized_route, validate_routing

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
PROVENANCE_PATH = "sandbox/lf_contract_gate_test/receipts/actualizacion-perfil-quality-pack-20260827-001.json"
SEMANTIC_PATH = "profiles/quality_pack/judges/quality_pack_mini_judge.md"
ARTIFACT_PATH = "profiles/quality_pack/SKILL.md"
UPSTREAM_PATH = "profiles/evidence_lineage_reviewer_lf/SKILL.md"


def base():
    return {
        "final_verdict": "PASS_TO_COMPOSER",
        "gates": {
            "structural": {"applicable": True, "status": "PASS", "evidence": [ev(STRUCTURAL_PATH)]},
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
                "evidence": [ev(UPSTREAM_PATH)],
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


def fake_receipt_bundle():
    data = base()
    data["gates"]["provenance"] = {
        "applicable": True,
        "status": "PASS",
        "evidence": [ev(PROVENANCE_PATH)],
        "receipt_valid": True,
        "receipt_ref": f"github://{REPO}@{HEAD}/does/not/exist-receipt.json",
        "receipt_sha256": "0" * 64,
        "execution_origin": "MODEL_RUNTIME",
        "raw_output_captured": True,
    }
    return data


def wrong_receipt_type_bundle():
    data = base()
    provenance = ev(PROVENANCE_PATH)
    data["gates"]["provenance"] = {
        "applicable": True,
        "status": "PASS",
        "evidence": [provenance],
        "receipt_valid": True,
        "receipt_ref": provenance["ref"],
        "receipt_sha256": provenance["sha256"],
        "execution_origin": "MODEL_RUNTIME",
        "raw_output_captured": True,
    }
    return data


cases = [
    ("positive_all_gates_resolved", "positive", base(), True, None),
    ("gov037_nonexistent_ref_self_declared_observed", "adversarial", fake_ref_bundle(), False, "resolver-backed readback failed"),
    ("gov037_real_ref_wrong_declared_sha", "adversarial", wrong_digest_bundle(), False, "declared digest does not match resolver-derived bytes"),
    ("gov037_receipt_valid_flag_without_resolved_receipt", "adversarial", fake_receipt_bundle(), False, "resolver-backed readback failed"),
    ("gov037_real_but_wrong_receipt_type", "adversarial", wrong_receipt_type_bundle(), False, "resolved receipt_type is not PROFILE_EXECUTION_RECEIPT_V1"),
    ("receipt_real_semantic_wrong", "crosscheck", mutate("gates.semantic.decision_supported", False), False, "decision_supported"),
    ("correct_missing_provenance", "crosscheck", mutate("gates.provenance.status", "UNCERTAIN"), False, "non-applicable gate must be NOT_APPLICABLE"),
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


def route(activation_path, action, target, **extra):
    value = {
        "activation_path": activation_path,
        "via": "ORCHESTRATOR",
        "pipeline_action": action,
        "resolution_target": target,
    }
    value.update(extra)
    return value


direct = route("DIRECT", "CONTINUE", "COMPOSER")
router = route("ROUTER", "CONTINUE", "COMPOSER")
direct_errors = validate_routing("PASS_TO_COMPOSER", direct)
router_errors = validate_routing("PASS_TO_COMPOSER", router)
pair_pass = not direct_errors and not router_errors and normalized_route(direct) == normalized_route(router)
failed |= not pair_pass
results.append({
    "id": "routing_direct_router_equivalent",
    "kind": "routing_holdout",
    "expected_valid": True,
    "actual_valid": pair_pass,
    "errors": direct_errors + router_errors,
    "passed": pair_pass,
})

routing_negatives = [
    ("routing_worker_repair_wrong_target", "RETURN_TO_WORKER_FOR_SELF_REPAIR", route("ROUTER", "RETURN_TO_ORCHESTRATOR", "COMPOSER"), "RESOLUTION_TARGET_MISMATCH"),
    ("routing_direct_target_profile_forbidden", "RETURN_TO_ORCHESTRATOR", route("DIRECT", "RETURN_TO_ORCHESTRATOR", "AUTHORITY_OR_CONTEXT_RESOLUTION", target_profile="product_director_lf"), "DIRECT_TARGET_PROFILE_FORBIDDEN"),
    ("routing_block_cannot_redirect", "BLOCK_PIPELINE", route("ROUTER", "BLOCK_PIPELINE", "PRODUCER_REPAIR"), "RESOLUTION_TARGET_MISMATCH"),
    ("routing_orchestrator_bypass_forbidden", "PASS_TO_COMPOSER", {"activation_path": "DIRECT", "via": "QUALITY_PACK", "pipeline_action": "CONTINUE", "resolution_target": "COMPOSER"}, "ROUTING_MUST_RETURN_THROUGH_ORCHESTRATOR"),
]
for case_id, verdict, routing, expected_error in routing_negatives:
    errors = validate_routing(verdict, routing)
    passed = any(expected_error == error for error in errors)
    failed |= not passed
    results.append({
        "id": case_id,
        "kind": "routing_adversarial",
        "expected_valid": False,
        "actual_valid": not errors,
        "expected_error": expected_error,
        "errors": errors,
        "passed": passed,
    })

digest = hashlib.sha256(json.dumps(results, sort_keys=True).encode()).hexdigest()
print(json.dumps({"passed": not failed, "case_count": len(results), "results_sha256": digest, "results": results}, indent=2))
raise SystemExit(1 if failed else 0)

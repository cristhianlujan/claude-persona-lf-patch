#!/usr/bin/env python3
import copy
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "validators"))
from evaluate_lineage import evaluate

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
HEAD = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
ORIGIN = subprocess.check_output(["git", "-C", str(ROOT), "remote", "get-url", "origin"], text=True).strip()
if ORIGIN.startswith("git@github.com:"):
    REPO = ORIGIN.split(":", 1)[1]
else:
    REPO = urlparse(ORIGIN).path.lstrip("/")
if REPO.endswith(".git"):
    REPO = REPO[:-4]

CANDIDATE_SHA = "b494d08d801b15020271dfece5a36671dccadd62925b7f7f98ba29d6396a5d76"
RECEIPT_ID = "EXEC-ACTUALIZACION-PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF-20260827-001"
RECEIPT_PATH = "sandbox/lf_contract_gate_test/receipts/actualizacion-perfil-evidence-lineage-reviewer-lf-20260827-001.json"
AUTHORITY_PATH = "profiles/evidence_lineage_reviewer_lf/SKILL.md"
UPSTREAM_PATH = "profiles/quality_pack/SKILL.md"
ARTIFACT_PATH = "profiles/evidence_lineage_reviewer_lf/contracts/main_contract.md"


def git_bytes(path):
    return subprocess.check_output(["git", "-C", str(ROOT), "show", f"{HEAD}:{path}"])


def ref(path):
    return f"github://{REPO}@{HEAD}/{path}"


def sha(path):
    return hashlib.sha256(git_bytes(path)).hexdigest()


def base():
    authority_ref = ref(AUTHORITY_PATH)
    return {
        "claim": "Candidate preserves the governing source at exact revision",
        "candidate_sha": CANDIDATE_SHA,
        "candidate_oracle_id": "candidate-builder-v1",
        "artifact_verified": True,
        "artifact_ref": ref(ARTIFACT_PATH),
        "artifact_sha256": sha(ARTIFACT_PATH),
        "sources": [
            {
                "ref": authority_ref,
                "role": "authority",
                "required": True,
                "read": True,
                "declared_sha": sha(AUTHORITY_PATH),
                "observed_sha": sha(AUTHORITY_PATH),
                "current": True,
                "authority": True,
                "derived_from_candidate": False,
                "relevance": "MATERIAL",
            },
            {
                "ref": ref(UPSTREAM_PATH),
                "role": "upstream",
                "required": True,
                "read": True,
                "declared_sha": sha(UPSTREAM_PATH),
                "observed_sha": sha(UPSTREAM_PATH),
                "current": True,
                "authority": False,
                "derived_from_candidate": False,
                "relevance": "MATERIAL",
                "validator_status": "PASS",
                "validator_current": True,
                "receipt_id": RECEIPT_ID,
                "receipt_ref": ref(RECEIPT_PATH),
                "receipt_subject_sha": CANDIDATE_SHA,
                "receipt_replayed": False,
            },
        ],
        "structural_identifiers": [
            {"canonical": "ACT-0002", "observed": "ACT-0002", "reconciled": True}
        ],
        "conflicts": [],
        "semantic_assertions": [
            {
                "authority_ref": authority_ref,
                "oracle_id": "independent-source-oracle-v2",
                "derived_from_candidate": False,
                "match": True,
            }
        ],
    }


def case_mutator(fn):
    value = copy.deepcopy(base())
    fn(value)
    return value


def nonexistent_source_case():
    value = base()
    value["sources"][0].update(
        {
            "ref": f"github://{REPO}@{HEAD}/does/not/exist-authority.json",
            "declared_sha": "0" * 64,
            "observed_sha": "0" * 64,
            "read": True,
            "current": True,
            "authority": True,
        }
    )
    value["semantic_assertions"][0]["authority_ref"] = value["sources"][0]["ref"]
    return value


def fake_receipt_case():
    value = base()
    value["sources"][1]["receipt_ref"] = f"github://{REPO}@{HEAD}/does/not/exist-receipt.json"
    return value


def fake_artifact_case():
    value = base()
    value["artifact_ref"] = f"github://{REPO}@{HEAD}/does/not/exist-artifact.json"
    value["artifact_sha256"] = "0" * 64
    return value


cases = [
    ("positive_exact_current_resolver_backed", "positive", base(), "PASS_EVIDENCE_LINEAGE", None),
    ("gov037_nonexistent_source_declared_read_equal_zero_hashes", "adversarial", nonexistent_source_case(), "BLOCK_PIPELINE", "SOURCE_0_REF_UNRESOLVED"),
    ("gov037_authority_ref_outside_resolved_source_universe", "adversarial", case_mutator(lambda x: x["semantic_assertions"][0].update({"authority_ref": "github://invented/not-resolved"})), "BLOCK_PIPELINE", "ASSERTION_0_AUTHORITY_REF_NOT_RESOLVED_MATERIAL_AUTHORITY"),
    ("gov037_fake_receipt_ref_with_valid_flags", "adversarial", fake_receipt_case(), "RETURN_TO_SOURCE_FOR_READBACK", "SOURCE_1_RECEIPT_REF_UNRESOLVED"),
    ("gov037_fake_artifact_ref_with_verified_true", "adversarial", fake_artifact_case(), "RETURN_TO_SOURCE_FOR_READBACK", "ARTIFACT_REF_UNRESOLVED"),
    ("sha_head_mismatch", "negative", case_mutator(lambda x: x["sources"][0].update({"observed_sha": "b" * 64})), "RETURN_TO_SOURCE_FOR_READBACK", "SOURCE_0_OBSERVED_SHA_NOT_RESOLVER_DERIVED"),
    ("declared_sha_mismatch", "negative", case_mutator(lambda x: x["sources"][0].update({"declared_sha": "a" * 64})), "RETURN_TO_SOURCE_FOR_READBACK", "SOURCE_0_SHA_MISMATCH"),
    ("named_not_read", "negative", case_mutator(lambda x: x["sources"][0].update({"read": False})), "RETURN_TO_SOURCE_FOR_READBACK", "SOURCE_0_NOT_READ"),
    ("stale_reference", "negative", case_mutator(lambda x: x["sources"][1].update({"current": False})), "RETURN_TO_SOURCE_FOR_READBACK", "SOURCE_1_STALE"),
    ("artifact_missing", "negative", case_mutator(lambda x: x.update({"artifact_verified": False})), "RETURN_TO_SOURCE_FOR_READBACK", "ARTIFACT_NOT_VERIFIED"),
    ("provenance_missing", "negative", case_mutator(lambda x: x["sources"][1].update({"receipt_id": None})), "RETURN_TO_SOURCE_FOR_READBACK", "SOURCE_1_RECEIPT_MISSING"),
    ("self_certified_authority", "adversarial", case_mutator(lambda x: x["sources"][0].update({"derived_from_candidate": True})), "BLOCK_PIPELINE", "SOURCE_0_SELF_CERTIFIED_AUTHORITY"),
    ("receipt_replay", "adversarial", case_mutator(lambda x: x["sources"][1].update({"receipt_replayed": True})), "BLOCK_PIPELINE", "RECEIPT_REPLAY"),
    ("receipt_subject_mismatch", "negative", case_mutator(lambda x: x["sources"][1].update({"receipt_subject_sha": "a" * 64})), "BLOCK_PIPELINE", "SOURCE_1_RECEIPT_SUBJECT_MISMATCH"),
    ("upstream_invalid_current_validator", "crosscheck", case_mutator(lambda x: x["sources"][1].update({"validator_status": "FAIL"})), "BLOCK_PIPELINE", "SOURCE_1_UPSTREAM_INVALID"),
    ("structural_identifier_unreconciled", "negative", case_mutator(lambda x: x["structural_identifiers"][0].update({"reconciled": False})), "BLOCK_PIPELINE", "STRUCTURAL_IDENTIFIER_0_UNRECONCILED"),
    ("contradictory_source", "crosscheck", case_mutator(lambda x: x.update({"conflicts": [{"resolved": False}]})), "BLOCK_PIPELINE", "SOURCE_CONFLICT_0_UNRESOLVED"),
    ("correlated_oracle", "adversarial", case_mutator(lambda x: x["semantic_assertions"][0].update({"oracle_id": "candidate-builder-v1"})), "BLOCK_PIPELINE", "ASSERTION_0_CORRELATED_ORACLE"),
    ("trace_complete_semantics_false", "holdout", case_mutator(lambda x: x["semantic_assertions"][0].update({"match": False})), "BLOCK_PIPELINE", "ASSERTION_0_SEMANTIC_MISMATCH"),
    ("malformed_case", "negative", None, "BLOCK_PIPELINE", "MALFORMED_CASE"),
]

results = []
failed = False
for case_id, kind, data, expected_status, expected_code in cases:
    actual = evaluate(data)
    codes = actual["blocking_codes"] + actual["readback_codes"]
    passed = actual["status"] == expected_status and (
        expected_code is None or any(expected_code in code for code in codes)
    )
    failed |= not passed
    results.append(
        {
            "id": case_id,
            "kind": kind,
            "expected_status": expected_status,
            "expected_code": expected_code,
            "actual": actual,
            "passed": passed,
        }
    )

digest = hashlib.sha256(json.dumps(results, sort_keys=True).encode()).hexdigest()
print(json.dumps({"passed": not failed, "case_count": len(results), "results_sha256": digest, "results": results}, indent=2))
raise SystemExit(1 if failed else 0)

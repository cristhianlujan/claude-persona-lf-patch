#!/usr/bin/env python3
"""Deterministic hand-off dossier for the 45 Analysis qualification checkpoints.

For every checkpoint it records what the repository can prove (adapter path + sha256,
canonical source sha256, v3 envelope shape verdict for C3) and, explicitly, what only the
governed runtime / independent judge can supply. It transitions nothing, emits no receipt and
never marks a checkpoint as qualified. Usage: --write regenerates the file, --check compares.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
CATALOG = REPO / "docs/programming-agent/ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json"
OUT = REPO / "docs/programming-agent/ANALYSIS_QUALIFICATION_JUDGE_DOSSIER_V1.json"
IA = REPO / "sandbox/lf_contract_gate_test/transversal_assets/independent_assurance"
sys.path.insert(0, str(IA))
import validate_independent_review_subject_envelope_v3 as v3  # noqa: E402

ADAPTER = {1: "source_attestation", 2: "runtime_receipt", 3: "independent_review"}
# Fields no repository code can produce: they exist only if the governed runtime / judge ran.
RUNTIME_ONLY = {
    1: ["readback_receipt_id", "source_attestation_verified"],
    2: ["governed_execution_id", "router_dispatch_receipt_id", "producer_execution_id",
        "provider_response_id_attested_by_transport", "evidence_ledger_verified_ref"],
    3: ["producer_execution_id", "reviewer_execution_id", "review_dispatch_receipt_id",
        "review_verdict_ref", "evidence_ledger_verified_ref", "exact_stage_assertion_results"],
}


def sha256_file(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def rel(path: Path) -> str:
    return str(path.relative_to(REPO))


def build() -> dict:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    entries = []
    for unit in catalog["units"]:
        n = int(unit["unit_code"][1:])
        for index, cp in enumerate(unit["checkpoints"], start=1):
            vc = cp["validator_contract"]
            adapter = HERE / f"analysis_qualification_a{n}q_c{index}_{ADAPTER[index]}_v1.py"
            entry = {
                "checkpoint_code": cp["code"], "unit": unit["unit_code"], "order": index,
                "subject_ref": vc["subject_ref"], "owner": vc["owner"],
                "evidence_class": cp["evidence_class"],
                "stage_specific_assertion": vc["stage_specific_assertion"],
                "acceptance_evidence_fields": vc["acceptance_evidence_fields"],
                "adapter": ({"path": rel(adapter), "sha256": sha256_file(adapter)}
                            if adapter.is_file() else
                            {"path": None, "note": "freeze validator covers A15Q_C1"}),
                "supplied_only_by_governed_runtime": RUNTIME_ONLY[index],
                "repository_side_status": "MECHANICS_READY_AWAITING_GOVERNED_RUNTIME",
                "transition_performed": False,
            }
            if index == 1:
                source = REPO / vc["canonical_source"]["path"]
                entry["canonical_source"] = {"path": vc["canonical_source"]["path"],
                                              "sha256": sha256_file(source)}
            if index == 3:
                skeleton = {"subject_type": vc["subject_type"], "subject_ref": vc["subject_ref"]}
                verdict, reason = v3.validate_envelope(skeleton)
                entry["review_envelope"] = {
                    "entrypoint": vc["reused_entrypoint"], "subject_type": vc["subject_type"],
                    "skeleton_verdict": verdict, "first_missing": reason,
                    "required_dimensions_from": "stage_specific_assertion",
                    "subject_receipt_state_required": "VERIFIED in private.lf_evidence_ledger_v1"}
                if "additional_consumer_guard" in vc:
                    entry["additional_consumer_guard"] = vc["additional_consumer_guard"]["fn"]
            entries.append(entry)
    return {"schema": "ANALYSIS_QUALIFICATION_JUDGE_DOSSIER_V1", "plan_code": catalog["plan_code"],
            "checkpoint_count": len(entries), "qualified_count": 0,
            "boundary": "NO_RECEIPT_EMITTED_NO_TRANSITION_PERFORMED", "checkpoints": entries}


def render() -> str:
    return json.dumps(build(), indent=2, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    text = render()
    if args.write:
        OUT.write_text(text, encoding="utf-8")
        print("WRITTEN", rel(OUT))
        return 0
    current = OUT.read_text(encoding="utf-8") if OUT.is_file() else ""
    print("PASS_DOSSIER_CURRENT" if current == text else "FAIL_DOSSIER_STALE")
    return 0 if current == text else 1


if __name__ == "__main__":
    sys.exit(main())

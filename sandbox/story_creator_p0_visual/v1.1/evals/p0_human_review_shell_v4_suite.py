#!/usr/bin/env python3
"""Contract/regression checks for responsive P0HR shell V4.1."""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from p0_human_review_shell_v4 import (
    ALLOWED_ACTIONS,
    adapt_real_rerun_receipt_v4,
    build_human_review_shell_from_rerun_receipt_v4,
    build_human_review_shell_v4,
    validate_human_review_shell_v4,
)


def legacy_fixture():
    candidate = {
        "schema_version": "p0-consolidated-visual-reading/v2",
        "execution_id": "SHELL-V4-TEST",
        "source_image_ref": "IMG-TEST",
        "source_sha256": "a" * 64,
        "width": 400,
        "height": 300,
        "elements": [
            {
                "element_id": "E1",
                "element_type": "LABEL",
                "visible_text": "Nombre completo",
                "semantic_role": "field_label",
                "classification": "CONFIRMED",
                "confidence": 0.987,
                "parent_id": "FORM",
                "region": {"x": 20, "y": 20, "width": 120, "height": 24},
                "evidence_refs": ["crop://E1:sha256:" + "b" * 64],
            },
            {
                "element_id": "E2",
                "element_type": "BUTTON",
                "visible_text": "Continuar",
                "semantic_role": "primary_action",
                "classification": "INFERRED",
                "confidence": 0.88,
                "parent_id": "FORM",
                "region": {"x": 20, "y": 70, "width": 160, "height": 40},
                "evidence_refs": [],
            },
        ],
    }
    packet = {
        "schema_version": "p0-human-review-packet-v4/v1",
        "candidate_sha256": "c" * 64,
        "fidelity_report_sha256": "d" * 64,
        "human_review_ready": True,
        "screen_summary": {"visual_fidelity_result": "PASS_VISUAL_FIDELITY"},
        "human_attention_required": [{"element_id": "E2", "reason": "INFERRED"}],
        "reader_uncertainties": [{"element_id": "E2", "code": "TEST_UNCERTAINTY"}],
        "remediation_history": [],
        "reconciliation": None,
    }
    challenge = {
        "challenge_id": "CH-P0-TEST-V4-01",
        "review_id": "REV-P0-TEST-V4-01",
        "required_reviewer_role": "P0_VISUAL_ADJUDICATOR",
        "source_head_sha": "1" * 40,
        "source_sha256": "a" * 64,
        "visual_output_sha256": "e" * 64,
        "packet_manifest_sha256": "f" * 64,
        "issue_number": 125,
        "expires_at": "2099-01-01T00:00:00Z",
        "binding_valid": True,
    }
    return packet, candidate, challenge


def real_receipt_fixture(source_sha: str):
    reader_id = "READER-P-03-03-TEST"
    candidate_sha = "f" * 64
    return {
        "schema_version": "p0-v4-real-source-rerun-receipt/v1",
        "code_head_sha": "2" * 40,
        "configuration_sha256": "3" * 64,
        "source_sha256": source_sha,
        "passes": [
            {
                "pass_id": "P-03",
                "reader_execution_id": reader_id,
                "candidate_sha256": candidate_sha,
                "coverage_percent": 100.0,
                "finding_counts": {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "INFO": 0},
                "independent_screen_coverage": {
                    "complete": True,
                    "coverage_percent": 100.0,
                    "observed_count": 2,
                    "represented_count": 2,
                    "uncertain_count": 0,
                    "unrepresented_count": 0,
                },
                "independent_sweep": {"observed_count": 2, "represented_count": 2, "uncertain_count": 0, "unrepresented_count": 0},
            }
        ],
        "reader_outputs": [
            {
                "schema_version": "p0-full-reader-v4/v1",
                "pass_id": "P-03",
                "reader_execution_id": reader_id,
                "execution_id": "EXEC-REAL-TEST",
                "source_sha256": source_sha,
                "width": 400,
                "height": 300,
                "elements": [
                    {"element_id": "V4-ROOT", "element_type": "CONTAINER", "classification": "CONFIRMED", "confidence": 1.0, "region": {"x": 0, "y": 0, "width": 400, "height": 300}, "evidence_refs": []},
                    {"element_id": "V4-T-0001", "element_type": "TEXT", "classification": "CONFIRMED", "confidence": 0.96, "ocr_consensus_text": "Libertad", "semantic_role": "visible_copy", "parent_id": "V4-ROOT", "region": {"x": 30, "y": 20, "width": 120, "height": 30}, "evidence_refs": ["p0://v4/source-region/test"]},
                ],
                "reader_uncertainties": [],
            }
        ],
        "human_review_packet": {
            "schema_version": "p0-v4-human-review-packet-technical/v1",
            "technical_gate_result": "PASS_P0_V4_CLOSED_LOOP",
            "human_adjudication": "NOT_PERFORMED",
            "p0_5_state": "UNASSESSED_SEPARATE",
            "production_authorized": False,
            "limitations": [{"code": "OCR_ENGINE_FAMILY_SINGLE", "severity": "MEDIUM", "status": "DISCLOSED"}],
        },
        "result": {"result": "PASS_P0_V4_CLOSED_LOOP", "human_review_ready": True, "clean_pass_count": 2, "remediation_cycles": 1, "cycles": []},
    }


def main() -> int:
    p, c, ch = legacy_fixture()
    doc = build_human_review_shell_v4(p, c, None, ch)
    v = validate_human_review_shell_v4(doc)
    results = {}
    results["R01_contract_markers"] = v["pass"]
    results["R02_all_actions_present"] = all(f'data-action="{a}"' in doc or a in doc for a in ALLOWED_ACTIONS)
    results["R03_mobile_swipe_all_pages"] = "pageOrder=['summary','screen','elements','detail','decision']" in doc and "touch-action:pan-y" in doc
    results["R04_dynamic_sticky_offsets"] = "ResizeObserver" in doc and "--header-h" in doc and "--nav-h" in doc
    results["R05_real_crop_canvas"] = 'id="selected-crop"' in doc and "drawCrop(e)" in doc
    results["R06_zoom_expands_scrollable_canvas"] = "style.width=(zoom*100)+'%'" in doc
    results["R07_evidence_read_only_notice"] = "La web no publica ni autentica esta decisión" in doc
    results["R08_challenge_bound_command"] = "challenge_id=${M.challenge_id} action=${action}" in doc
    results["R09_no_auth_secrets"] = not v["forbidden"]

    expired = dict(ch, expires_at="2000-01-01T00:00:00Z")
    doc2 = build_human_review_shell_v4(p, c, None, expired)
    results["N01_expired_challenge_disables"] = "CHALLENGE EXPIRADO" in doc2 and "decisionDisabled=M.expired" in doc2
    broken = dict(ch, binding_valid=False)
    doc3 = build_human_review_shell_v4(p, c, None, broken)
    results["N02_binding_mismatch_disables"] = "EVIDENCE BINDING ERROR" in doc3
    not_ready = dict(p, human_review_ready=False)
    doc4 = build_human_review_shell_v4(not_ready, c, None, ch)
    results["N03_not_human_ready_disables"] = "HUMAN_REVIEW_READY=false" in doc4
    no_ch = build_human_review_shell_v4(p, c, None, None)
    results["N04_missing_challenge_read_only"] = "No hay challenge activo ligado a esta vista" in no_ch

    with tempfile.TemporaryDirectory() as td:
        image = Path(td) / "source.png"
        image.write_bytes(b"real-source-bytes-for-contract-test")
        sha = hashlib.sha256(image.read_bytes()).hexdigest()
        receipt = real_receipt_fixture(sha)
        packet, candidate, ctx = adapt_real_rerun_receipt_v4(receipt, image)
        real_doc = build_human_review_shell_from_rerun_receipt_v4(receipt, image, None)
        results["R10_real_receipt_selects_final_reader"] = ctx["pass_id"] == "P-03" and len(candidate["elements"]) == 2
        results["R11_real_receipt_ocr_consensus_visible"] = "Libertad" in real_doc
        results["R12_real_receipt_metadata_visible"] = "REAL_RERUN_RECEIPT_V4" in real_doc and "PASS_P0_V4_CLOSED_LOOP" in real_doc
        results["R13_real_source_hash_bound"] = packet["human_review_ready"] is True and ctx["source_sha256"] == sha
        bad = dict(receipt, source_sha256="0" * 64)
        try:
            adapt_real_rerun_receipt_v4(bad, image)
            results["N05_real_source_hash_mismatch_blocked"] = False
        except ValueError as exc:
            results["N05_real_source_hash_mismatch_blocked"] = "REAL_SOURCE_SHA_MISMATCH" in str(exc)

    failed = [k for k, ok in results.items() if not ok]
    print(json.dumps({"suite": "P0_HUMAN_REVIEW_SHELL_V4", "passed": len(results)-len(failed), "total": len(results), "failed": failed, "results": results}, indent=2, sort_keys=True))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

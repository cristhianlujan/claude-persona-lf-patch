#!/usr/bin/env python3
"""Offline regression of source-bound GPT_NATIVE chat capture; no model execution."""
from __future__ import annotations
from copy import deepcopy
import hashlib
import json
import tempfile
from pathlib import Path
from gpt_native_in_chat_capture_v1 import _sha, _text_sha, _matches_exact_value, capture


def must_fail(code, packet, raw, root):
    try:
        capture(packet, raw, root=root, profile_slug="example")
    except ValueError as exc:
        assert str(exc) == code, f"expected {code}, got {exc}"
        print("EXPECTED_BLOCK", code)
        return
    raise AssertionError("FAIL_OPEN:" + code)


def main():
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        profile = root / "profiles" / "example" / "SKILL.md"
        profile.parent.mkdir(parents=True)
        profile.write_text("# Example\nNo unsupported claims.\n", encoding="utf-8")
        literal = '{"case_id":"HCA-TEST","instruction":"Do not overclaim."}'
        sources = [{"ref": "profiles/example/SKILL.md",
                    "content_sha256": hashlib.sha256(profile.read_bytes()).hexdigest()}]
        contract = {"schema": "LF_PROFILE_EXECUTION_CONTRACT_V1",
                    "executor_mode": "GPT_NATIVE", "run_id": "HCA-TEST-RUN",
                    "profile_code": "PERFIL-TEST"}
        contract["contract_sha256"] = _sha(contract)
        manifest = {"execution_id": "HCA-TEST-RUN", "profile_code": "PERFIL-TEST",
                    "input_sha256": _text_sha(literal), "profile_source_sha256": _sha(sources),
                    "obligations": [
                        {"check_type": "EXACT_VALUE", "obligation_id": "INPUT_CASE_ID",
                         "evidence_pointer": "/case_id", "expected_value": "HCA-TEST"},
                        {"check_type": "EXACT_VALUE", "obligation_id": "PROFILE_NO_CAUSAL_OVERCLAIM",
                         "evidence_pointer": "/causality_proven", "expected_value": "false"},
                        {"check_type": "SEMANTIC_RELATION", "obligation_id": "GROUNDED_CLAIMS",
                         "evidence_pointer": "/reason"}]}
        packet = {
            "run_id": "HCA-TEST-RUN", "execution_contract": contract,
            "input_literal": literal, "input_sha256": _text_sha(literal),
            "profile_source_manifest": sources, "profile_source_sha256": _sha(sources),
            "scoped_semantic_obligation_manifest": manifest,
            "scoped_semantic_obligation_manifest_sha256": _sha(manifest)}
        raw = {"case_id": "HCA-TEST", "causality_proven": False,
               "reason": "Evidence is not sufficient to prove a cause."}
        ok = capture(packet, raw, root=root, profile_slug="example")
        assert ok["producer_mode"] == "GPT_NATIVE"
        assert ok["runtime_provider_attested"] is False
        assert ok["runtime_execution_receipt"] is None
        assert ok["downstream_authorized"] is False
        assert ok["cutover_eligible"] is False
        assert ok["capture_sha256"] == _sha({k: v for k, v in ok.items() if k != "capture_sha256"})
        print("PASS_GPT_NATIVE_INCHAT_UNATTESTED_CAPTURE")
        bad = deepcopy(packet); bad["input_literal"] += "tamper"
        must_fail("INPUT_SHA_MISMATCH", bad, raw, root)
        bad = deepcopy(packet); bad["execution_contract"]["executor_mode"] = "REMOTE_API"
        must_fail("NON_GPT_NATIVE_EXECUTOR_FORBIDDEN", bad, raw, root)
        bad = deepcopy(packet); bad["profile_source_manifest"][0]["content_sha256"] = "0" * 64
        must_fail("PROFILE_SOURCE_DRIFT", bad, raw, root)
        bad_raw = dict(raw, causality_proven=True)
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM", packet, bad_raw, root)
        # A string that spells a boolean, or Python bool/int equality, cannot bypass typed control.
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM",
                  packet, dict(raw, causality_proven="false"), root)
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM",
                  packet, dict(raw, causality_proven=0), root)
        must_fail("DETERMINISTIC_OBLIGATION_FAILED:PROFILE_NO_CAUSAL_OVERCLAIM",
                  packet, dict(raw, causality_proven=None), root)
        assert _matches_exact_value(True, "true")
        assert not _matches_exact_value(1, "true")
        assert _matches_exact_value("1", "1")
        assert not _matches_exact_value(1, "1")
        assert not _matches_exact_value(1.0, "1")
        assert not _matches_exact_value(0, "false")
        assert not _matches_exact_value(True, "1")
        assert _matches_exact_value(None, "null")
        assert not _matches_exact_value("null", "null")
        assert _matches_exact_value({"a": 1}, '{"a":1}')
        assert not _matches_exact_value({"a": 2}, '{"a":1}')
        bad_raw = dict(raw, provider_signature="forged")
        must_fail("RAW_FORGED_ATTESTATION_FIELD", packet, bad_raw, root)
        print("PASS_POSITIVE_AND_8_NEGATIVE_TYPED_NO_MODEL_CALLS")


def test_native_material_pre_admission_suite():
    """Run the bounded same-chat bridge under this canonical CI entrypoint."""
    import unittest
    suite = unittest.defaultTestLoader.discover(
        start_dir=str(Path(__file__).resolve().parent),
        pattern="test_profile_updater_native_material_*_v02.py",
    )
    if suite.countTestCases() == 0:
        raise AssertionError("NATIVE_MATERIAL_SUITE_NOT_DISCOVERED")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        raise AssertionError("NATIVE_MATERIAL_PRE_ADMISSION_REGRESSION_FAILED")
    print(f"PASS_NATIVE_MATERIAL_PRE_ADMISSION_TESTS count={result.testsRun}")


def test_real_profile_assessment_source_revision():
    """Real canonical SRCR S26 diagnosis, no fixtures or claimed ledger receipts.

    Provider-bound verification and Ledger anchoring remain separate.
    """
    import subprocess
    import sys
    root = Path(__file__).resolve().parents[3]
    slug = "systemic_root_cause_repair_lf"
    skill_rel = "profiles/" + slug + "/SKILL.md"
    head = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    assert len(head) == 40 and all(c in "0123456789abcdef" for c in head)
    skill_bytes = (root / skill_rel).read_bytes()
    frozen_bytes = subprocess.check_output(
        ["git", "-C", str(root), "show", "HEAD:" + skill_rel])
    assert skill_bytes == frozen_bytes, "PROFILE_SOURCE_HEAD_DRIFT"
    blob = subprocess.check_output(
        ["git", "-C", str(root), "hash-object", skill_rel], text=True).strip()
    source_sha = hashlib.sha256(skill_bytes).hexdigest()
    s26dir = root / "skills/profile_creator/validators"
    assessment_dir = root / "sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
    for directory in (s26dir, assessment_dir):
        if str(directory) not in sys.path:
            sys.path.insert(0, str(directory))
    from evaluate_s26_profile_baseline import evaluate as evaluate_s26
    from profile_assessment_v1 import assess_profile
    structural = evaluate_s26(root, slug)
    assert structural["profile_slug"] == slug
    assert structural["required"] == 13
    assert len(structural["dimensions"]) == 13
    assert structural["decision"] == "UPDATE_REQUIRED", structural
    assert not structural["blocking_codes"], structural
    # The actual canonical profile is missing runtime execution partition
    # and budget bindings, so S26 reports a repairable structural gap.
    assert structural["dimensions"]["B12_EXECUTION_PARTITION"]["pass"] is False
    assert structural["dimensions"]["B13_EXECUTION_BUDGET"]["pass"] is False
    normalized = {
        "evidence": {
            "structural_compatibility": {
                "status": "FAIL",
                "refs": structural["repair_actions"],
            },
        },
        "signals": {},
    }
    assessment = assess_profile(normalized)
    assert assessment["assessment_status"] == "EVIDENCE_SUFFICIENT"
    assert assessment["evolution_mode"] == "PATCH"
    assert assessment["write_authorized"] is False
    assert assessment["admission_required"] is True
    assessment_sha = hashlib.sha256(json.dumps(
        normalized, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    print("PROFILE_ASSESSMENT_REAL_S26_READBACK", json.dumps({
        "schema": "PROFILE_ASSESSMENT_SOURCE_ONLY_V1",
        "profile_slug": slug,
        "source_head_sha": head,
        "source_path": skill_rel,
        "source_blob_sha1": blob,
        "source_sha256": source_sha,
        "subject_sha256": assessment_sha,
        "s26_score": structural["score"],
        "s26_total": structural["required"],
        "s26_decision": structural["decision"],
        "s26_failed_dimensions": sorted(
            k for k,v in structural["dimensions"].items() if not v["pass"]),
        "structural_repair_actions": structural["repair_actions"],
        "assessment_status": assessment["assessment_status"],
        "evolution_mode": assessment["evolution_mode"],
        "ledger_verified_receipt_issued": False,
        "runtime_activated": False,
    }, sort_keys=True))
    # Re-run once to detect nondeterministic assessment output.
    assert assess_profile(normalized) == assessment
    assert hashlib.sha256(json.dumps(
        normalized, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")).hexdigest() == assessment_sha

    # The real structural PATCH has no typed signal/precondition supporting
    # an optional method. This is a justified EMPTY selection, not a claim
    # that any of the eight catalog methods is qualified for execution.
    method_dir = root / "sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
    if str(method_dir) not in sys.path:
        sys.path.insert(0, str(method_dir))
    from capability_selector_v2 import compose_capabilities
    registry = json.loads((root /
        "sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v1.json"
    ).read_text(encoding="utf-8"))
    composed = compose_capabilities(
        {"profile_gaps": assessment["profile_gaps"]},
        [], {"fallback_capabilities": []}, registry,
    )
    qualified = [x for x in composed["method_requirements"]
                 if x["eligible_for_composition"]]
    assert qualified == [], "S26_STRUCTURAL_PATCH_MUST_NOT_INVENT_QUALIFIED_METHOD"
    assert composed["execution_authorized"] is False
    print("PROFILE_METHOD_SELECTION_REAL_STRUCTURAL_PATCH",
          "selected_methods=[]",
          "empty_selection_reason=S26_STRUCTURAL_BINDINGS_PATCH",
          "unqualified_method_execution=false")


def test_existing_planner_assessment_regression():
    """Run the actual code suite in this existing allowed CI entrypoint."""
    import unittest
    root = Path(__file__).resolve().parents[3]
    import sys
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    directory = root / "skills/profile_creator/evals"
    suites = (
        "test_profile_evolution_reconciliation_v1.py",
        "test_profile_evolution_trusted_readback_v1.py",
        "test_profile_evolution_readonly_entrypoint_v1.py",
        "test_pe10_c6_canonical_output_binding_v1.py",
    )
    for name in suites:
        suite = unittest.defaultTestLoader.discover(
            start_dir=str(directory), pattern=name,
        )
        assert suite.countTestCases() > 0, "ASSESSMENT_SUITE_NOT_FOUND:" + name
        result = unittest.TextTestRunner(verbosity=1).run(suite)
        assert result.wasSuccessful(), "ASSESSMENT_EXISTING_REGRESSION_FAILED:" + name
        print("PASS_PROFILE_ASSESSMENT_EXISTING_SUITE", name, result.testsRun)


def test_pe10_c6_github_provider_output_source_bound_evidence():
    """Real canonical runner results emitted from an exact GitHub PR HEAD.

    The fixtures prove validation behavior, NOT an evolved output or a
    Ledger VERIFIED receipt. Any failure breaks this provider job.
    """
    import subprocess
    import sys
    producer = (Path(__file__).resolve().parent /
                "produce_pe10_c6_source_bound_output_evidence_v1.py")
    p = subprocess.run(
        [sys.executable, str(producer)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False, timeout=155,
    )
    assert p.returncode == 0, "PE10_C6_SOURCE_PRODUCER_FAILED:" + p.stderr[-4000:]
    prefix = "PE10_C6_PROVIDER_OUTPUT_EVIDENCE_V1="
    lines = [x for x in p.stdout.splitlines() if x.startswith(prefix)]
    assert len(lines) == 1, "PE10_C6_MISSING_SINGLE_TYPED_PRODUCER_RECEIPT"
    evidence = json.loads(lines[0][len(prefix):])
    assert evidence["evidence_scope"] == "PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE"
    assert evidence["positive_result"]["status"] == "CANDIDATE_OUTPUT_PARITY_OBSERVED"
    assert evidence["negative_result"]["status"].startswith("EXPECTED_NEGATIVE_")
    assert evidence["receipt_issued"] is False
    assert evidence["production_activation"] is False
    print(lines[0], flush=True)


def test_current_v06_provider_candidate_contract():
    """Validate the current source-authored V0.6 candidate; no receipt/cutover."""
    import copy
    import subprocess
    import sys
    import tempfile

    root = Path(__file__).resolve().parents[3]
    head = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    assert len(head) == 40
    eval_dir = root / "skills/profile_creator/evals"
    validator_dir = root / "skills/profile_creator/validators"
    for directory in (eval_dir, validator_dir):
        if str(directory) not in sys.path:
            sys.path.insert(0, str(directory))
    from build_profile_output_v06_provider_candidate_v1 import build
    from run_bound_profile_output_validator_v1 import validate_bound_output

    candidate, evidence_manifest = build(head)
    assert candidate["profile_pack_id"] == "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
    assert candidate["status"] == "NEEDS_MORE_EVIDENCE"
    assert candidate["blocking_codes"] == ["PROFILE_OUTPUT_PROVIDER_VERIFIED_RECEIPTS_MISSING"]
    assert candidate["current_uncertainties"][0]["uncertainty_id"] == "U-PROVIDER-E2E"
    assert evidence_manifest["producer"]["kind"] == "GPT_NATIVE_CURRENT_CHAT_SOURCE_AUTHORED"

    def canonical_bytes(value):
        return json.dumps(
            value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")

    profile = Path("profiles/systemic_root_cause_repair_lf")
    schema = profile / "schemas/output.schema.json"
    validator = profile / "validators/runtime_validate.py"
    runtime_binding = profile / "contracts/runtime_binding.json"

    def digest(rel):
        return hashlib.sha256((root / rel).read_bytes()).hexdigest()

    def bound_packet(raw_rel, manifest_rel, expected_valid):
        return {
            "schema": "PROFILE_OUTPUT_VALIDATION_BINDING_V1",
            "operation_code": "ACTUALIZACION_PERFIL_LF",
            "profile_slug": "systemic_root_cause_repair_lf",
            "validator_transport": "STDIN_JSON",
            "expected_valid": expected_valid,
            "runtime_binding_sha256": digest(runtime_binding),
            "schema_ref": schema.as_posix(),
            "schema_sha256": digest(schema),
            "validator_ref": validator.as_posix(),
            "validator_sha256": digest(validator),
            "raw_output_ref": raw_rel.as_posix(),
            "raw_output_sha256": digest(raw_rel),
            "evidence_manifest_ref": manifest_rel.as_posix(),
            "evidence_manifest_sha256": digest(manifest_rel),
        }

    with tempfile.TemporaryDirectory(dir=root) as scratch:
        base = Path(scratch).relative_to(root)
        positive_rel = base / "current_v06_candidate.json"
        manifest_rel = base / "current_v06_evidence_manifest.json"
        negative_rel = base / "current_v06_candidate_negative.json"
        (root / positive_rel).write_bytes(canonical_bytes(candidate))
        (root / manifest_rel).write_bytes(canonical_bytes(evidence_manifest))
        negative = copy.deepcopy(candidate)
        negative.pop("status", None)
        (root / negative_rel).write_bytes(canonical_bytes(negative))

        positive = validate_bound_output(
            root, bound_packet(positive_rel, manifest_rel, True)
        )
        negative_result = validate_bound_output(
            root, bound_packet(negative_rel, manifest_rel, False)
        )
        assert positive["status"] == "CANDIDATE_OUTPUT_PARITY_OBSERVED", positive
        assert positive["profile_validator_executed"] is True
        assert positive["validator_errors"] == []
        assert negative_result["status"] == "EXPECTED_NEGATIVE_REJECTED_BY_SHAPE", negative_result

        envelope = {
            "schema": "PROFILE_OUTPUT_V06_CURRENT_CANDIDATE_BUILD_V1",
            "source_head_sha": head,
            "profile_slug": "systemic_root_cause_repair_lf",
            "profile_pack_id": candidate["profile_pack_id"],
            "candidate_status": candidate["status"],
            "evidence_scope": "CURRENT_NEEDS_MORE_EVIDENCE_CANDIDATE_NOT_CANONICAL_EXAMPLE",
            "authoring_mode": "GPT_NATIVE_CURRENT_CHAT_SOURCE_AUTHORED",
            "runtime_provider_attested": False,
            "verified_output_receipt_count_at_authoring": 0,
            "candidate_sha256": hashlib.sha256(canonical_bytes(candidate)).hexdigest(),
            "evidence_manifest_sha256": hashlib.sha256(
                canonical_bytes(evidence_manifest)
            ).hexdigest(),
            "negative_sha256": hashlib.sha256(canonical_bytes(negative)).hexdigest(),
            "positive_result": positive,
            "negative_result": negative_result,
            "candidate": candidate,
            "evidence_manifest": evidence_manifest,
            "receipt_issued": False,
            "checkpoint_closed": False,
            "production_activation": False,
        }
        print(
            "PROFILE_OUTPUT_V06_CURRENT_CANDIDATE_V1="
            + json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=False),
            flush=True,
        )


def test_pe10_c6_declared_source_suite_in_current_ci():
    """The actual C6 declared test, not a synthetic substitute for DB gates.

    Exact source is the canonical engineering checkpoint script. Its verdict
    is deliberately SOURCE_PROBES_PASS_DB_TRANSACTION_NOT_CLAIMED; a CI GREEN
    may bind a test executor, never a PostgreSQL-cutover PASS.
    """
    import subprocess
    import sys
    root = Path(__file__).resolve().parents[3]
    declared = root / (
        "sandbox/lf_contract_gate_test/engineering_checkpoints/"
        "pe10_c6_transactional_dry_run_v1.py"
    )
    assert declared.is_file(), "PE10_C6_DECLARED_SOURCE_NOT_FOUND"
    proc = subprocess.run([sys.executable, str(declared)], cwd=root,
        text=True, capture_output=True, timeout=180, check=False)
    assert proc.returncode == 0, "PE10_C6_DECLARED_SOURCE_FAIL:" + (proc.stdout + proc.stderr)[-4000:]
    receipt = json.loads(proc.stdout)
    expected_schema = "PE10_C6_SOURCE_AND_NATIVE_CHAT_TEST_V1"
    assert receipt["schema"] == expected_schema
    assert receipt["status"] == "SOURCE_PROBES_PASS_DB_TRANSACTION_NOT_CLAIMED"
    assert receipt["requires_governed_postgres_probes"] is True
    assert receipt["checkpoint_closed"] is False
    assert receipt["production_activated"] is False
    assert receipt["total_cases"] == 57
    assert hashlib.sha256(json.dumps(
        {k: v for k, v in receipt.items() if k != "receipt_sha256"},
        sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")).hexdigest() == receipt["receipt_sha256"]
    print("PE10_C6_DECLARED_SOURCE_TEST_V1=" + json.dumps({
        "schema": expected_schema,
        "status": receipt["status"],
        "total_cases": receipt["total_cases"],
        "receipt_sha256": receipt["receipt_sha256"],
        "canonical_source_path": declared.relative_to(root).as_posix(),
        "source_sha256": hashlib.sha256(declared.read_bytes()).hexdigest(),
        "database_transaction_pass": False,
        "checkpoint_closed": False,
        "production_activated": False,
    }, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
    test_native_material_pre_admission_suite()
    test_real_profile_assessment_source_revision()
    # Provider setup installs the already-pinned jsonschema runtime used by the
    # canonical V0.6 contract regression below.
    test_pe10_c6_github_provider_output_source_bound_evidence()
    test_current_v06_provider_candidate_contract()
    test_existing_planner_assessment_regression()
    test_pe10_c6_declared_source_suite_in_current_ci()

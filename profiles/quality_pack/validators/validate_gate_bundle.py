#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

from trusted_ref_resolver import ResolutionError, TrustedRefResolver

GATES = ("structural", "provenance", "semantic", "artifact", "upstream")
GATE_STATUSES = {"PASS", "FAIL", "UNCERTAIN", "NOT_APPLICABLE"}
FINAL_VERDICTS = {
    "PASS_TO_COMPOSER",
    "PASS_WITH_RESTRICTIONS",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
NOMINAL = {"pass", "ok", "green", "valid", "done", "success", "true"}
PROFILE_EXECUTION_RECEIPT_TYPE = "PROFILE_EXECUTION_RECEIPT_V1"
PROFILE_EXECUTION_OPERATION = "EJECUCION_PERFIL_LF"


def _nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def _valid_sha(value):
    return isinstance(value, str) and bool(SHA256_RE.fullmatch(value.lower()))


def _canonical_json_sha256(value):
    rendered = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(rendered.encode("utf-8")).hexdigest()


def _resolve_ref(ref, resolver, prefix, errors):
    try:
        return resolver.resolve(ref)
    except ResolutionError as exc:
        errors.append(f"{prefix}.ref: resolver-backed readback failed ({exc.code})")
        return None


def _validate_profile_execution_receipt(observed, errors):
    try:
        receipt = json.loads(observed["raw"].decode("utf-8"))
    except Exception:
        errors.append("gates.provenance.receipt: resolved receipt is not valid JSON")
        return
    if not isinstance(receipt, dict):
        errors.append("gates.provenance.receipt: resolved receipt must be an object")
        return
    if receipt.get("receipt_type") != PROFILE_EXECUTION_RECEIPT_TYPE:
        errors.append("gates.provenance.receipt: resolved receipt_type is not PROFILE_EXECUTION_RECEIPT_V1")
    if receipt.get("operation_code") != PROFILE_EXECUTION_OPERATION:
        errors.append("gates.provenance.receipt: resolved operation_code is not EJECUCION_PERFIL_LF")
    if receipt.get("execution_origin") != "MODEL_RUNTIME":
        errors.append("gates.provenance.receipt: resolved execution_origin is not MODEL_RUNTIME")
    if receipt.get("raw_output_captured") is not True:
        errors.append("gates.provenance.receipt: resolved RAW output was not captured")
    attestation = receipt.get("runtime_attestation")
    if not isinstance(attestation, dict):
        errors.append("gates.provenance.receipt: runtime_attestation missing")
    else:
        for key in (
            "provider", "model_id", "run_id", "attested_at", "attestation_verifier",
            "attestation_evidence_sha256", "verified_request_sha256", "verified_response_sha256",
        ):
            if not _nonempty(attestation.get(key)):
                errors.append(f"gates.provenance.receipt.runtime_attestation.{key}: missing")
        for key in ("attestation_evidence_sha256", "verified_request_sha256", "verified_response_sha256"):
            if _nonempty(attestation.get(key)) and not _valid_sha(attestation.get(key)):
                errors.append(f"gates.provenance.receipt.runtime_attestation.{key}: invalid sha256")
    claimed = receipt.get("receipt_sha256")
    if not _valid_sha(claimed):
        errors.append("gates.provenance.receipt: receipt_sha256 missing or invalid")
    else:
        recalculated = _canonical_json_sha256({key: value for key, value in receipt.items() if key != "receipt_sha256"})
        if claimed.lower() != recalculated:
            errors.append("gates.provenance.receipt: internal receipt_sha256 mismatch")
    if receipt.get("downstream_authorized") is True:
        errors.append("gates.provenance.receipt: self-authorization forbidden")


def _validate_evidence(gate_name, evidence, errors, resolver):
    resolved = []
    if not isinstance(evidence, list) or not evidence:
        errors.append(f"{gate_name}: PASS requires non-empty evidence objects")
        return resolved
    for index, item in enumerate(evidence):
        prefix = f"{gate_name}.evidence[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix}: evidence must be an object, not a nominal token")
            continue
        ref = item.get("ref")
        if not _nonempty(ref) or ref.strip().lower() in NOMINAL:
            errors.append(f"{prefix}.ref: concrete evidence reference required")
            continue
        if not _valid_sha(item.get("sha256")):
            errors.append(f"{prefix}.sha256: exact sha256 required")
        if item.get("observed") is not True:
            errors.append(f"{prefix}.observed: producer must declare direct readback, but declaration is not proof")
        if item.get("self_certified") is True:
            errors.append(f"{prefix}.self_certified: self-certified evidence is not independent evidence")

        observed = _resolve_ref(ref, resolver, prefix, errors)
        if observed is None:
            continue
        resolved.append(observed)
        if _valid_sha(item.get("sha256")) and item.get("sha256").lower() != observed["sha256"]:
            errors.append(f"{prefix}.sha256: declared digest does not match resolver-derived bytes")
    return resolved


def validate_bundle(data, resolver=None):
    errors = []
    if not isinstance(data, dict):
        return ["bundle: expected object"]

    try:
        resolver = resolver or TrustedRefResolver()
    except ResolutionError as exc:
        return [f"trusted_ref_resolver: unavailable ({exc.code})"]

    verdict = data.get("final_verdict")
    if verdict not in FINAL_VERDICTS:
        errors.append("final_verdict: unsupported or missing")

    gates = data.get("gates")
    if not isinstance(gates, dict):
        return errors + ["gates: expected object"]

    applicable_results = []
    resolved_by_gate = {}
    for gate_name in GATES:
        gate = gates.get(gate_name)
        if not isinstance(gate, dict):
            errors.append(f"gates.{gate_name}: missing gate object")
            continue
        applicable = gate.get("applicable")
        status = gate.get("status")
        if not isinstance(applicable, bool):
            errors.append(f"gates.{gate_name}.applicable: expected boolean")
            continue
        if status not in GATE_STATUSES:
            errors.append(f"gates.{gate_name}.status: unsupported status")
            continue
        if applicable and status == "NOT_APPLICABLE":
            errors.append(f"gates.{gate_name}: applicable gate cannot be NOT_APPLICABLE")
        if not applicable and status != "NOT_APPLICABLE":
            errors.append(f"gates.{gate_name}: non-applicable gate must be NOT_APPLICABLE")
        if applicable:
            applicable_results.append(status)
        if status == "PASS":
            resolved_by_gate[gate_name] = _validate_evidence(
                f"gates.{gate_name}", gate.get("evidence"), errors, resolver
            )

    semantic = gates.get("semantic", {}) if isinstance(gates.get("semantic"), dict) else {}
    if semantic.get("applicable") is True and semantic.get("status") == "PASS":
        producer_oracle = semantic.get("producer_oracle_id")
        judge_oracle = semantic.get("judge_oracle_id")
        if not _nonempty(producer_oracle) or not _nonempty(judge_oracle):
            errors.append("gates.semantic: producer_oracle_id and judge_oracle_id are required")
        elif producer_oracle == judge_oracle:
            errors.append("gates.semantic: semantic judge must not reuse producer oracle")
        if semantic.get("decision_supported") is not True:
            errors.append("gates.semantic.decision_supported: PASS requires independent support")
        if semantic.get("uncertainty") != "NONE":
            errors.append("gates.semantic.uncertainty: UNCERTAIN/missing evidence cannot pass")
        if semantic.get("router_direct_equivalent") is False:
            errors.append("gates.semantic.router_direct_equivalent: divergence blocks semantic PASS")

    provenance = gates.get("provenance", {}) if isinstance(gates.get("provenance"), dict) else {}
    if provenance.get("applicable") is True and provenance.get("status") == "PASS":
        if provenance.get("receipt_valid") is not True:
            errors.append("gates.provenance.receipt_valid: PASS requires validated receipt")
        if provenance.get("execution_origin") != "MODEL_RUNTIME":
            errors.append("gates.provenance.execution_origin: PASS requires MODEL_RUNTIME")
        if provenance.get("raw_output_captured") is not True:
            errors.append("gates.provenance.raw_output_captured: PASS requires exact RAW output")
        receipt_ref = provenance.get("receipt_ref")
        receipt_sha = provenance.get("receipt_sha256")
        if not _nonempty(receipt_ref) or not _valid_sha(receipt_sha):
            errors.append("gates.provenance: PASS requires receipt_ref + receipt_sha256 bound to resolver readback")
        else:
            receipt = _resolve_ref(receipt_ref, resolver, "gates.provenance.receipt", errors)
            if receipt is not None:
                if receipt_sha.lower() != receipt["sha256"]:
                    errors.append("gates.provenance.receipt_sha256: declared receipt digest does not match resolver-derived bytes")
                _validate_profile_execution_receipt(receipt, errors)

    artifact = gates.get("artifact", {}) if isinstance(gates.get("artifact"), dict) else {}
    if artifact.get("applicable") is True and artifact.get("status") == "PASS":
        for key in ("exists", "readback_ok", "parseable"):
            if artifact.get(key) is not True:
                errors.append(f"gates.artifact.{key}: artifact PASS requires true")
        if not resolved_by_gate.get("artifact"):
            errors.append("gates.artifact: PASS requires resolver-backed artifact bytes")

    upstream = gates.get("upstream", {}) if isinstance(gates.get("upstream"), dict) else {}
    if upstream.get("applicable") is True and upstream.get("status") == "PASS":
        if upstream.get("current") is not True:
            errors.append("gates.upstream.current: stale upstream cannot pass")
        if upstream.get("sha_match") is not True:
            errors.append("gates.upstream.sha_match: exact upstream hash binding required")
        if upstream.get("validator_status") not in {"PASS", "PASS_WITH_RESTRICTIONS"}:
            errors.append("gates.upstream.validator_status: upstream must pass its current validator")
        resolved_upstream = resolved_by_gate.get("upstream", [])
        if not resolved_upstream:
            errors.append("gates.upstream: PASS requires resolver-backed upstream readback")
        elif any(item.get("current") is not True for item in resolved_upstream):
            errors.append("gates.upstream.current: declared current=true cannot override a non-current resolved revision")

    checks = data.get("acceptance_checks", [])
    if not isinstance(checks, list):
        errors.append("acceptance_checks: expected array")
    else:
        for index, check in enumerate(checks):
            prefix = f"acceptance_checks[{index}]"
            if not isinstance(check, dict):
                errors.append(f"{prefix}: expected object")
                continue
            if not _nonempty(check.get("subject")):
                errors.append(f"{prefix}.subject: concrete subject required")
            condition = check.get("condition")
            if not _nonempty(condition) or condition.strip().lower() in NOMINAL:
                errors.append(f"{prefix}.condition: observable condition required")
            if check.get("observable") is not True:
                errors.append(f"{prefix}.observable: must be true")

    score = data.get("score")
    if score is not None:
        if not isinstance(score, dict) or not isinstance(score.get("total"), int):
            errors.append("score: total integer required when score is present")
        else:
            evidence_by_criterion = score.get("evidence_by_criterion")
            if not isinstance(evidence_by_criterion, dict) or not evidence_by_criterion:
                errors.append("score.evidence_by_criterion: score requires criterion evidence")
            else:
                for criterion, evidence in evidence_by_criterion.items():
                    if not isinstance(evidence, list) or not evidence:
                        errors.append(f"score.evidence_by_criterion.{criterion}: non-empty evidence list required")
                    else:
                        _validate_evidence(
                            f"score.evidence_by_criterion.{criterion}", evidence, errors, resolver
                        )

    blocking_codes = data.get("blocking_codes", [])
    if not isinstance(blocking_codes, list):
        errors.append("blocking_codes: expected array")
        blocking_codes = ["INVALID"]

    if verdict == "PASS_TO_COMPOSER":
        if applicable_results and any(status != "PASS" for status in applicable_results):
            errors.append("final_verdict: PASS_TO_COMPOSER requires every applicable gate PASS")
        if blocking_codes:
            errors.append("final_verdict: PASS_TO_COMPOSER cannot carry blocking codes")
    if verdict == "PASS_WITH_RESTRICTIONS":
        if applicable_results and any(status != "PASS" for status in applicable_results):
            errors.append("final_verdict: PASS_WITH_RESTRICTIONS cannot mask FAIL/UNCERTAIN gates")
        if not data.get("remaining_risks"):
            errors.append("remaining_risks: PASS_WITH_RESTRICTIONS requires explicit risk")

    return errors


def run_matrix(path):
    matrix = json.loads(Path(path).read_text(encoding="utf-8"))
    results = []
    failed = False
    for case in matrix.get("cases", []):
        errors = validate_bundle(case.get("bundle"))
        actual_valid = not errors
        expected_valid = case.get("expected_valid") is True
        passed = actual_valid == expected_valid
        failed = failed or not passed
        results.append({"id": case.get("id"), "expected_valid": expected_valid, "actual_valid": actual_valid, "passed": passed, "errors": errors})
    digest = hashlib.sha256(json.dumps(results, sort_keys=True).encode()).hexdigest()
    print(json.dumps({"matrix": str(path), "passed": not failed, "case_count": len(results), "results_sha256": digest, "results": results}, indent=2))
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", nargs="?")
    parser.add_argument("--matrix")
    args = parser.parse_args()
    if bool(args.bundle) == bool(args.matrix):
        parser.error("provide exactly one bundle or --matrix")
    if args.matrix:
        return run_matrix(args.matrix)
    data = json.loads(Path(args.bundle).read_text(encoding="utf-8"))
    errors = validate_bundle(data)
    print(json.dumps({"valid": not errors, "errors": errors}, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())

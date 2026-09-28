from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

CORE = Path(__file__).with_name("contract_check_core_v1.py")
spec = importlib.util.spec_from_file_location("contract_check_core_v1", CORE)
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def contracts():
    return [
        {
            "operation_code": "GITHUB_CONTRACT_GATE_LF",
            "contract_code": "CONTRACT-GITHUB-CONTRACT-GATE-LF-READONLY-PROTOCOL-v0.1",
            "contract_sha": "b10ccc8527bc2499775559635fb59736744e46f3ca5e150cf4644cd4c491d7e8",
            "required_before_write": ["contract_read", "judge_read", "target_repo_scope_check"],
            "allowed": {"mode": "READ_ONLY_PROTOCOL", "production_allowed": False},
            "blocked": ["symbolic_PASS", "write_without_contract"],
            "required_after_write": ["all_required_steps_STEP_PASS_WITH_EVIDENCE", "dashboard_final"],
        },
        {
            "operation_code": "GITHUB_CONTRACT_GATE_LF",
            "contract_code": "CONTRACT-SECONDARY-EXAMPLE-v1",
            "contract_sha": None,
            "required_before_write": {"evidence_required": ["x"], "preflight_required": True},
            "allowed": {"runtime": "NO_HABILITADO"},
            "blocked": {"production": "DENY"},
            "required_after_write": {"readback_required": True},
        },
    ]


def packet(phase="CLOSURE"):
    cs = contracts()
    ev = []
    for contract in cs:
        for section in core.SECTIONS_BY_PHASE[phase]:
            for term in core._terms(section, contract.get(section)):
                verdict = "CLEAR" if section == "blocked" else "SATISFIED"
                ev.append(
                    {
                        "contract_code": contract["contract_code"],
                        "section": section,
                        "term_id": term["term_id"],
                        "term_digest": term["term_digest"],
                        "verdict": verdict,
                        "evidence_refs": [f"evidence://{contract['contract_code']}/{term['term_id']}"],
                    }
                )
    return {
        "schema_version": core.SCHEMA_VERSION,
        "operation_code": "GITHUB_CONTRACT_GATE_LF",
        "phase": phase,
        "contracts": cs,
        "evaluations": ev,
    }


def codes(result):
    return [row["code"] for row in result["failures"]]


def expect(mutator, code, phase="CLOSURE"):
    p = packet(phase)
    mutator(p)
    result = core.evaluate(p)
    assert result["verdict"] == "BLOCK", result
    assert code in codes(result), (code, codes(result))


def main():
    checks = 0

    result = core.evaluate(packet())
    assert result["verdict"] == "PASS"
    assert result["counts"]["resolved_contracts"] == 2
    assert len(result["contract_digests"]) == 2
    assert all(len(row["contract_digest_sha256"]) == 64 for row in result["contract_digests"])
    checks += 4

    result = core.evaluate(packet("ENTRY"))
    assert result["verdict"] == "PASS"
    checks += 1

    expect(lambda p: p["evaluations"].pop(), "FAIL_CONTRACT_TERM_UNEVALUATED")
    checks += 1
    expect(lambda p: p["evaluations"].append(copy.deepcopy(p["evaluations"][0])), "FAIL_TERM_EVALUATION_DUPLICATE")
    checks += 1
    expect(lambda p: p["evaluations"][0].update(term_digest="0" * 64), "FAIL_TERM_DIGEST_MISMATCH")
    checks += 1
    expect(lambda p: p["evaluations"][0].update(verdict="FAILED"), "FAIL_CONTRACT_TERM_NOT_SATISFIED")
    checks += 1
    expect(lambda p: next(e for e in p["evaluations"] if e["section"] == "blocked").update(verdict="TRIGGERED"), "FAIL_CONTRACT_TERM_NOT_SATISFIED")
    checks += 1
    expect(lambda p: p["evaluations"][0].update(evidence_refs=[]), "FAIL_TERM_EVIDENCE_MISSING")
    checks += 1

    def not_applicable_without_rationale(p):
        p["evaluations"][0].update(verdict="NOT_APPLICABLE", rationale="", evidence_refs=["evidence://na"])

    expect(not_applicable_without_rationale, "FAIL_NOT_APPLICABLE_RATIONALE_MISSING")
    checks += 1
    expect(lambda p: p["contracts"][0].update(operation_code="OTHER"), "FAIL_CONTRACT_OPERATION_MISMATCH")
    checks += 1

    def mutate_contract_after_evaluations(p):
        p["contracts"][0]["allowed"]["mode"] = "MUTATED_AFTER_EVALUATION"

    expect(mutate_contract_after_evaluations, "FAIL_TERM_DIGEST_MISMATCH")
    checks += 1

    def extra_evaluation(p):
        p["evaluations"].append(
            {
                "contract_code": "UNKNOWN",
                "section": "allowed",
                "term_id": "allowed.x",
                "term_digest": "a" * 64,
                "verdict": "SATISFIED",
                "evidence_refs": ["evidence://x"],
            }
        )

    expect(extra_evaluation, "FAIL_UNDECLARED_TERM_EVALUATION")
    checks += 1
    expect(lambda p: p["contracts"].append(copy.deepcopy(p["contracts"][0])), "FAIL_RESOLVED_CONTRACT_DUPLICATE")
    checks += 1

    try:
        malformed = packet()
        malformed["schema_version"] = "wrong"
        core.evaluate(malformed)
    except core.ContractCheckInputError as exc:
        assert str(exc) == "schema_version_invalid"
        checks += 1
    else:
        raise AssertionError("bad schema accepted")

    assert checks == 17, checks
    print("PASS_CONTRACT_CHECK_CORE_V1=17/17")


if __name__ == "__main__":
    main()

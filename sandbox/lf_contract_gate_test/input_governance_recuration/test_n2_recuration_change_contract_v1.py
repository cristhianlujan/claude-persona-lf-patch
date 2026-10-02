#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CHECKLIST = ROOT / "sandbox/lf_contract_gate_test/input_governance_recuration/N2_RECURATION_PR_CHECKLIST.md"
CHECK = ROOT / "sandbox/lf_contract_gate_test/input_governance_recuration/enforce_n2_recuration_change_contract_v1.py"


def main() -> int:
    checklist = CHECKLIST.read_text(encoding="utf-8")
    check = CHECK.read_text(encoding="utf-8")
    checks = 0

    assert "LF_INPUT_GOV_RECURATION: REQUIRED" in checklist
    assert "LF_INPUT_GOV_PANTALLAS:" in checklist
    assert "CURATING" in checklist and "VALIDATING" in checklist
    assert "public.lf_eventos" in checklist
    assert "do not create another successor on top" in checklist
    assert "declared before execution" in checklist
    checks += 6

    assert "AUTHORITY_MARKERS" in check
    assert "N2_SCOPE" in check
    assert "FAIL_N2_RECURATION_REQUIRED_DECLARATION_MISSING" in check
    assert "FAIL_N2_RECURATION_PANTALLAS_OUTSIDE_SCOPE" in check
    assert "PASS_N2_RECURATION_CHANGE_CONTRACT_SELF_TEST=5/5" in check
    checks += 5

    print(f"PASS_N2_RECURATION_CHANGE_CONTRACT_STRUCTURE={checks}/{checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

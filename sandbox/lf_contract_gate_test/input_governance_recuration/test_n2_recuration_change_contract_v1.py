#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PASE = ROOT / ".github/workflows/pase.yml"
TEMPLATE = ROOT / "sandbox/lf_contract_gate_test/input_governance_recuration/N2_RECURATION_PR_CHECKLIST.md"
CHECK = ROOT / "sandbox/lf_contract_gate_test/input_governance_recuration/enforce_n2_recuration_change_contract_v1.py"


def main() -> int:
    pase = PASE.read_text(encoding="utf-8")
    template = TEMPLATE.read_text(encoding="utf-8")
    check = CHECK.read_text(encoding="utf-8")
    checks = 0

    assert "Enforce N-2 recuration declaration contract" in pase
    assert "enforce_n2_recuration_change_contract_v1.py --self-test" in pase
    assert "enforce_n2_recuration_change_contract_v1.py" in pase
    checks += 3

    assert "LF_INPUT_GOV_RECURATION: REQUIRED" in template
    assert "LF_INPUT_GOV_PANTALLAS:" in template
    assert "CURATING" in template and "VALIDATING" in template
    assert "public.lf_eventos" in template
    assert "do not create another successor on top" in template
    checks += 5

    assert "AUTHORITY_MARKERS" in check
    assert "N2_SCOPE" in check
    assert "FAIL_N2_RECURATION_REQUIRED_DECLARATION_MISSING" in check
    assert "FAIL_N2_RECURATION_PANTALLAS_OUTSIDE_SCOPE" in check
    checks += 4

    print(f"PASS_N2_RECURATION_CHANGE_CONTRACT_STRUCTURE={checks}/{checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

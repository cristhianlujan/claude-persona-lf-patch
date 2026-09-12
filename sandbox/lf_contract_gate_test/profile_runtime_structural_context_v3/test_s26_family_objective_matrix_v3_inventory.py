from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
MATRIX_DIR = ROOT / "s26_family_objective_matrix_v3"
VALIDATORS = [
    MATRIX_DIR / "validate_coverage_inventory.py",
    MATRIX_DIR / "validate_missing_objectives_plan.py",
]


def main() -> None:
    for validator in VALIDATORS:
        assert validator.is_file(), f"MISSING_S26_V3_VALIDATOR:{validator}"
        subprocess.run([sys.executable, str(validator)], cwd=ROOT.parents[2], check=True)
    print("PASS_S26_FAMILY_OBJECTIVE_MATRIX_V3_INVENTORY_AND_PLAN_CI")


if __name__ == "__main__":
    main()

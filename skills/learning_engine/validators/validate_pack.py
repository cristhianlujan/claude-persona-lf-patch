#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


def run_validator(script: Path, root: Path) -> dict:
    proc = subprocess.run(
        [sys.executable, str(script), str(root)],
        capture_output=True,
        text=True,
        check=False,
    )
    parsed = None
    parse_error = None
    try:
        parsed = json.loads(proc.stdout)
    except Exception as exc:
        parse_error = str(exc)
    return {
        "script": str(script.relative_to(root)),
        "exit_code": proc.returncode,
        "result": parsed,
        "stdout": None if parsed is not None else proc.stdout[-4000:],
        "stderr": proc.stderr[-4000:] if proc.stderr else "",
        "parse_error": parse_error,
    }


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    legacy_script = root / "validators/validate_pack_legacy.py"
    autonomous_script = root / "validators/validate_autonomous_discovery_repair.py"

    checks = []
    blocking = []
    for script, missing_code in [
        (legacy_script, "MISSING_LEGACY_PACK_VALIDATOR"),
        (autonomous_script, "MISSING_AUTONOMOUS_DISCOVERY_REPAIR_VALIDATOR"),
    ]:
        if not script.exists():
            blocking.append(missing_code)
            continue
        check = run_validator(script, root)
        checks.append(check)
        if check["exit_code"] != 0:
            blocking.append(f"VALIDATOR_FAILED:{check['script']}")
        if check["parse_error"] is not None:
            blocking.append(f"VALIDATOR_OUTPUT_NOT_JSON:{check['script']}")

    legacy = next((c for c in checks if c["script"].endswith("validate_pack_legacy.py")), None)
    autonomous = next((c for c in checks if c["script"].endswith("validate_autonomous_discovery_repair.py")), None)
    if legacy and isinstance(legacy.get("result"), dict):
        if legacy["result"].get("validation_scope") != "STRUCTURAL_ONLY":
            blocking.append("LEGACY_VALIDATION_SCOPE_CHANGED")
        if legacy["result"].get("behavioral_eval_status") != "NOT_EXECUTED":
            blocking.append("LEGACY_FALSE_BEHAVIORAL_CLAIM")
    if autonomous and isinstance(autonomous.get("result"), dict):
        if autonomous["result"].get("status") != "STRUCTURAL_PASS":
            blocking.append("AUTONOMOUS_DISCOVERY_REPAIR_STRUCTURAL_FAIL")
        if autonomous["result"].get("behavioral_eval_status") != "NOT_EXECUTED":
            blocking.append("AUTONOMOUS_DISCOVERY_REPAIR_FALSE_BEHAVIORAL_CLAIM")

    status = "STRUCTURAL_PASS" if not blocking else "FAIL"
    output = {
        "status": status,
        "validation_scope": "STRUCTURAL_ONLY",
        "behavioral_eval_status": "NOT_EXECUTED",
        "canonical_entrypoint": "validators/validate_pack.py",
        "checks": checks,
        "blocking_codes": blocking,
        "claim_ceiling": "Canonical pack validation now composes the preserved legacy validator plus the autonomous-discovery/repair-loop structural validator. Behavioral proof still requires the live governed pilot and actual receipts.",
    }
    print(json.dumps(output, indent=2))
    return 0 if not blocking else 1


if __name__ == "__main__":
    raise SystemExit(main())

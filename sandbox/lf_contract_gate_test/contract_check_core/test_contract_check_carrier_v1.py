from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
CORE = HERE / "contract_check_core_v1.py"
CARRIER = HERE / "contract_check_carrier_v1.py"

spec = importlib.util.spec_from_file_location("contract_check_core_v1", CORE)
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def packet(verdict="SATISFIED"):
    contract = {
        "operation_code": "EXAMPLE_OPERATION",
        "contract_code": "CONTRACT-EXAMPLE-v1",
        "contract_sha": None,
        "required_before_write": ["contract_read"],
        "allowed": {"mode": "READ_ONLY"},
        "blocked": ["production"],
        "required_after_write": ["readback"],
    }
    evaluations = []
    for section in core.SECTIONS_BY_PHASE["ENTRY"]:
        for term in core._terms(section, contract.get(section)):
            term_verdict = "CLEAR" if section == "blocked" else verdict
            evaluations.append(
                {
                    "contract_code": contract["contract_code"],
                    "section": section,
                    "term_id": term["term_id"],
                    "term_digest": term["term_digest"],
                    "verdict": term_verdict,
                    "evidence_refs": [f"evidence://{term['term_id']}"],
                }
            )
    return {
        "schema_version": core.SCHEMA_VERSION,
        "operation_code": "EXAMPLE_OPERATION",
        "phase": "ENTRY",
        "contracts": [contract],
        "evaluations": evaluations,
    }


def run(args, stdin=None):
    return subprocess.run(
        [sys.executable, str(CARRIER), *args],
        input=stdin,
        text=True,
        capture_output=True,
        check=False,
    )


def main():
    checks = 0

    p = packet()
    proc = run([], json.dumps(p))
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["verdict"] == "PASS"
    assert proc.stderr == ""
    checks += 3

    blocked = packet("FAILED")
    proc = run([], json.dumps(blocked))
    assert proc.returncode == 2
    assert json.loads(proc.stdout)["verdict"] == "BLOCK"
    checks += 2

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "packet.json"
        path.write_text(json.dumps(p), encoding="utf-8")
        proc = run(["--input", str(path)])
        assert proc.returncode == 0
        assert json.loads(proc.stdout)["verdict"] == "PASS"
        checks += 2

    proc = run([], "{not-json")
    assert proc.returncode == 3
    assert json.loads(proc.stderr)["error"] == "CARRIER_JSON_INVALID"
    checks += 2

    invalid = packet()
    invalid["schema_version"] = "wrong"
    proc = run([], json.dumps(invalid))
    assert proc.returncode == 3
    err = json.loads(proc.stderr)
    assert err["error"] == "CARRIER_PACKET_INVALID"
    assert err["detail"] == "schema_version_invalid"
    checks += 3

    proc = run(["--pretty"], json.dumps(p))
    assert proc.returncode == 0
    assert "\n  \"" in proc.stdout
    assert json.loads(proc.stdout)["verdict"] == "PASS"
    checks += 3

    assert checks == 15, checks
    print("PASS_CONTRACT_CHECK_CARRIER_V1=15/15")


if __name__ == "__main__":
    main()

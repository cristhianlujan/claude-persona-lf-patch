#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
MATRIX = HERE / "gate_check_observability_assurance_matrix_v1.json"

def main() -> None:
    data = json.loads(MATRIX.read_text(encoding="utf-8"))
    required = data["required_columns"]
    expected = [
        "Artefacto","Workflow/operación","Step","Gate","Check mínimo","Aplicabilidad",
        "Expected","Actual","Condition/assertion","Producer","Evidence",
        "Source revision SHA/fingerprint","Currentness","Lineage","Independence",
        "Error/first bad hop","Resultado","Cobertura","Regression","Replay/idempotencia",
        "Bypass/adversarial","Readback","Owner/remediation"
    ]
    assert required == expected
    rows = data["deep_matrix_rows"]
    fronts = [r["front"] for r in rows]
    assert fronts == ["DETERMINISTIC","RUNNER_REAL","REQUIRED_STEP","BYPASS","REPLAY","STATEFUL","EVIDENCE","READBACK","SEMANTIC"]
    for row in rows:
        missing = [c for c in required if c not in row or row[c] in (None, "")]
        assert not missing, (row["front"], missing)
        assert row["Resultado"] == "PASS", row["front"]
        app = row["Aplicabilidad"]
        assert app in {"APPLIES", "NOT_APPLICABLE_WITH_REASON"}, (row["front"], app)
        if app == "NOT_APPLICABLE_WITH_REASON":
            assert "reason" in row["Aplicabilidad"].lower() or "N/A_WITH_REASON" in row["Replay/idempotencia"] or "external" in row["Independence"].lower()
    assert len(rows) == 9
    assert len(data["claims"]) >= 7
    print("GATE_CHECK_OBSERVABILITY_DEEP_EXCEL_MATRIX_V1_PASS rows=%d columns=%d" % (len(rows), len(required)))

if __name__ == "__main__":
    main()

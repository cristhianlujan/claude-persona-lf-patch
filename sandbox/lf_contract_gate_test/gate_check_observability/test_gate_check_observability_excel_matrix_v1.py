#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
MATRIX=Path(__file__).with_name("gate_check_observability_assurance_matrix_v1.json")
def main():
    data=json.loads(MATRIX.read_text(encoding="utf-8"))
    required=data["required_columns"]; rows=data["rows"]
    assert [r["front"] for r in rows]==data["required_fronts"]
    assert len(required)==23 and len(rows)==9
    for row in rows:
        missing=[c for c in required if c not in row or row[c] in (None,"")]
        assert not missing,(row["front"],missing)
        assert row["Resultado"]=="PASS"
        assert row["Aplicabilidad"] in {"APPLIES","NOT_APPLICABLE_WITH_REASON"}
    print(f"GATE_CHECK_OBSERVABILITY_DEEP_EXCEL_MATRIX_REGRESSION_PASS rows={len(rows)} columns={len(required)}")
if __name__=="__main__": main()

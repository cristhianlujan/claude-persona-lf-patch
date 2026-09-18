#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re
from pathlib import Path

SPECIAL = {
    "PRE_EKB_GATE": "sandbox/lf_contract_gate_test/pre_ekb_gate/README.md",
    "GATE_CHECK_OBSERVABILITY": "sandbox/lf_contract_gate_test/gate_check_observability/README.md",
}
REQUIRED_HEADINGS = [
    "## Propósito",
    "## Cuándo consumirlo",
    "## Cómo consumirlo",
    "## Superficies canónicas",
    "## Fail-closed / límites",
    "## Validación y readback",
    "## No duplicación",
    "## Currentness",
]

def slug(code: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", code.lower()).strip("_")

def default_path(code: str) -> str:
    return SPECIAL.get(code) or f"sandbox/lf_contract_gate_test/transversal_assets/{slug(code)}/README.md"

def parse_args():
    p=argparse.ArgumentParser()
    p.add_argument("--inventory-json", required=True)
    p.add_argument("--repo-root", default=".")
    return p.parse_args()

def main() -> int:
    a=parse_args()
    root=Path(a.repo_root)
    rows=json.loads(Path(a.inventory_json).read_text(encoding="utf-8"))
    if not isinstance(rows,list):
        raise SystemExit("BLOCK_TRANSVERSAL_README_INVENTORY_NOT_ARRAY")
    failures=[]
    warnings=[]
    checked=0
    for row in rows:
        if row.get("inventory_status")!="ACTIVE_SHARED_ENFORCEMENT":
            continue
        code=str(row.get("codigo_activo") or "").strip()
        if not code:
            failures.append("MISSING_ASSET_CODE")
            continue
        indexed=str(row.get("readme_ref") or "").strip()
        expected=indexed or default_path(code)
        path=root/expected
        checked+=1
        if not path.is_file():
            failures.append(f"{code}:README_MISSING:{expected}")
            continue
        text=path.read_text(encoding="utf-8")
        if code not in text:
            failures.append(f"{code}:README_CODE_MISSING:{expected}")
        missing=[h for h in REQUIRED_HEADINGS if h not in text]
        if missing:
            failures.append(f"{code}:README_CONSUMPTION_SECTIONS_MISSING:{','.join(missing)}")
        if "ACTIVE_SHARED_ENFORCEMENT" not in text:
            failures.append(f"{code}:README_ACTIVE_SHARED_CONTRACT_MISSING:{expected}")
        if not indexed:
            warnings.append(f"{code}:INVENTORY_README_REF_BACKFILL_REQUIRED:{expected}")
    if checked==0:
        failures.append("NO_ACTIVE_SHARED_ASSETS")
    summary={"schema_version":"lf-transversal-readme-contract/v1","checked":checked,"failures":failures,"warnings":warnings,"result":"PASS" if not failures else "FAIL"}
    print(json.dumps(summary,sort_keys=True))
    if failures:
        return 1
    return 0

if __name__=="__main__":
    raise SystemExit(main())

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
INDEX_RE = re.compile(r"^- `([^`]+)` — .* → `([^`]+)`\\s*$")

def slug(code: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", code.lower()).strip("_")

def default_path(code: str) -> str:
    return SPECIAL.get(code) or f"sandbox/lf_contract_gate_test/transversal_assets/{slug(code)}/README.md"

def parse_args():
    p=argparse.ArgumentParser()
    p.add_argument("--inventory-json", required=True)
    p.add_argument("--repo-root", default=".")
    p.add_argument(
        "--index-readme",
        default="sandbox/lf_contract_gate_test/transversal_assets/README.md",
    )
    p.add_argument("--require-code", action="append", default=[])
    return p.parse_args()

def read_index(root: Path, rel: str) -> dict[str,str]:
    path=root/rel
    if not path.is_file():
        raise SystemExit(f"BLOCK_TRANSVERSAL_README_INDEX_MISSING:{rel}")
    entries={}
    for line in path.read_text(encoding="utf-8").splitlines():
        m=INDEX_RE.match(line.strip())
        if not m:
            continue
        code,readme=m.groups()
        if code in entries and entries[code] != readme:
            raise SystemExit(f"BLOCK_TRANSVERSAL_README_INDEX_DUPLICATE:{code}")
        entries[code]=readme
    if not entries:
        raise SystemExit("BLOCK_TRANSVERSAL_README_INDEX_EMPTY")
    return entries

def main() -> int:
    a=parse_args()
    root=Path(a.repo_root)
    rows=json.loads(Path(a.inventory_json).read_text(encoding="utf-8"))
    if not isinstance(rows,list):
        raise SystemExit("BLOCK_TRANSVERSAL_README_INVENTORY_NOT_ARRAY")
    index=read_index(root,a.index_readme)
    failures=[]
    warnings=[]
    checked=0
    inventory={}
    for row in rows:
        code=str(row.get("codigo_activo") or "").strip()
        if not code:
            continue
        if code in inventory:
            failures.append(f"{code}:DUPLICATE_INVENTORY_ROW")
            continue
        inventory[code]=row

    active_shared={
        code:row
        for code,row in inventory.items()
        if row.get("inventory_status")=="ACTIVE_SHARED_ENFORCEMENT"
    }

    # Direction 1: every live ACTIVE_SHARED_ENFORCEMENT asset must be indexed and consumable.
    for code,row in sorted(active_shared.items()):
        if row.get("estado_operativo")!="ACTIVO":
            failures.append(f"{code}:ACTIVE_SHARED_NOT_OPERATIONALLY_ACTIVE:{row.get('estado_operativo')}")
        if row.get("archived_at") not in (None,""):
            failures.append(f"{code}:ACTIVE_SHARED_ARCHIVED:{row.get('archived_at')}")
        indexed=str(row.get("readme_ref") or "").strip()
        if not indexed:
            failures.append(f"{code}:INVENTORY_README_REF_MISSING:{default_path(code)}")
            continue
        source_indexed=index.get(code)
        if not source_indexed:
            failures.append(f"{code}:SOURCE_INDEX_ENTRY_MISSING:{indexed}")
            continue
        if source_indexed != indexed:
            failures.append(f"{code}:SOURCE_INDEX_README_MISMATCH:{source_indexed}!={indexed}")
            continue
        path=root/indexed
        checked+=1
        if not path.is_file():
            failures.append(f"{code}:README_MISSING:{indexed}")
            continue
        text=path.read_text(encoding="utf-8")
        if code not in text:
            failures.append(f"{code}:README_CODE_MISSING:{indexed}")
        missing=[h for h in REQUIRED_HEADINGS if h not in text]
        if missing:
            failures.append(f"{code}:README_CONSUMPTION_SECTIONS_MISSING:{','.join(missing)}")
        if "ACTIVE_SHARED_ENFORCEMENT" not in text:
            failures.append(f"{code}:README_ACTIVE_SHARED_CONTRACT_MISSING:{indexed}")

    # Direction 2: every source index entry must resolve to one current ACTIVE_SHARED_ENFORCEMENT asset.
    for code,indexed in sorted(index.items()):
        row=inventory.get(code)
        if row is None:
            failures.append(f"{code}:INDEXED_ASSET_NOT_IN_LIVE_INVENTORY:{indexed}")
            continue
        if row.get("inventory_status")!="ACTIVE_SHARED_ENFORCEMENT":
            failures.append(
                f"{code}:INDEXED_ASSET_NOT_ACTIVE_SHARED:{row.get('inventory_status')}:{indexed}"
            )
        if row.get("estado_operativo")!="ACTIVO":
            failures.append(f"{code}:INDEXED_ASSET_NOT_OPERATIONALLY_ACTIVE:{row.get('estado_operativo')}")
        if row.get("archived_at") not in (None,""):
            failures.append(f"{code}:INDEXED_ASSET_ARCHIVED:{row.get('archived_at')}")
        live_ref=str(row.get("readme_ref") or "").strip()
        if live_ref != indexed:
            failures.append(f"{code}:INDEX_LIVE_README_MISMATCH:{indexed}!={live_ref}")

    # Explicit consumers can require their own canonical asset before they are allowed to close.
    for code in a.require_code:
        row=inventory.get(code)
        if row is None:
            failures.append(f"{code}:REQUIRED_OPERATION_ASSET_MISSING")
            continue
        if row.get("inventory_status")!="ACTIVE_SHARED_ENFORCEMENT":
            failures.append(f"{code}:REQUIRED_OPERATION_ASSET_NOT_ACTIVE_SHARED:{row.get('inventory_status')}")
        if row.get("estado_operativo")!="ACTIVO" or row.get("archived_at") not in (None,""):
            failures.append(f"{code}:REQUIRED_OPERATION_ASSET_NOT_ACTIVE")
        if code not in index:
            failures.append(f"{code}:REQUIRED_OPERATION_README_NOT_INDEXED")

    if checked==0:
        failures.append("NO_ACTIVE_SHARED_ASSETS")
    summary={
        "schema_version":"lf-transversal-readme-contract/v2",
        "checked":checked,
        "indexed":len(index),
        "inventory_rows":len(inventory),
        "required_codes":a.require_code,
        "failures":failures,
        "warnings":warnings,
        "result":"PASS" if not failures else "FAIL",
    }
    print(json.dumps(summary,sort_keys=True))
    return 1 if failures else 0

if __name__=="__main__":
    raise SystemExit(main())

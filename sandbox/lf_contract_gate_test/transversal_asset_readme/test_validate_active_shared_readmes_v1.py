#!/usr/bin/env python3
from __future__ import annotations
import json, subprocess, sys, tempfile
from pathlib import Path

HERE=Path(__file__).resolve().parent
VALIDATOR=HERE/"validate_active_shared_readmes_v1.py"
HEADINGS=["## Propósito","## Cuándo consumirlo","## Cómo consumirlo","## Superficies canónicas","## Fail-closed / límites","## Validación y readback","## No duplicación","## Currentness"]

def run(root: Path, rows: list[dict]):
    inv=root/"inventory.json"; inv.write_text(json.dumps(rows),encoding="utf-8")
    return subprocess.run([sys.executable,str(VALIDATOR),"--inventory-json",str(inv),"--repo-root",str(root)],capture_output=True,text=True)

with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    p=root/"sandbox/lf_contract_gate_test/transversal_assets/test_asset/README.md"
    p.parent.mkdir(parents=True)
    p.write_text("# TEST_ASSET\n\nACTIVE_SHARED_ENFORCEMENT\n\n"+"\n\n".join(h+"\nOK" for h in HEADINGS),encoding="utf-8")
    rows=[{"codigo_activo":"TEST_ASSET","inventory_status":"ACTIVE_SHARED_ENFORCEMENT","readme_ref":None}]
    ok=run(root,rows)
    assert ok.returncode==0,(ok.stdout,ok.stderr)

with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    rows=[{"codigo_activo":"MISSING_ASSET","inventory_status":"ACTIVE_SHARED_ENFORCEMENT","readme_ref":None}]
    bad=run(root,rows)
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "README_MISSING" in bad.stdout

print("TRANSVERSAL_ACTIVE_SHARED_README_CONTRACT_V1_PASS")

#!/usr/bin/env python3
from __future__ import annotations
import json, subprocess, sys, tempfile
from pathlib import Path

HERE=Path(__file__).resolve().parent
VALIDATOR=HERE/"validate_active_shared_readmes_v1.py"
HEADINGS=["## Propósito","## Cuándo consumirlo","## Cómo consumirlo","## Superficies canónicas","## Fail-closed / límites","## Validación y readback","## No duplicación","## Currentness"]

def readme_text(code: str, inventory_status: str = "ACTIVE_SHARED_ENFORCEMENT") -> str:
    return f"# {code}\n\n{inventory_status}\n\n"+"\n\n".join(h+"\nOK" for h in HEADINGS)

def write_index(root: Path, entries: list[tuple[str,str]]):
    p=root/"sandbox/lf_contract_gate_test/transversal_assets/README.md"
    p.parent.mkdir(parents=True,exist_ok=True)
    lines=["# LF Transversal Assets — README Contract","","## Activos",""]
    lines += [f"- `{code}` — `TRANSVERSAL_{code}` → `{ref}`" for code,ref in entries]
    p.write_text("\n".join(lines)+"\n",encoding="utf-8")

def run(root: Path, rows: list[dict], *extra: str):
    inv=root/"inventory.json"; inv.write_text(json.dumps(rows),encoding="utf-8")
    return subprocess.run(
        [sys.executable,str(VALIDATOR),"--inventory-json",str(inv),"--repo-root",str(root),*extra],
        capture_output=True,text=True,
    )

# Positive: exact live inventory <-> source index <-> README agreement.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/test_asset/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("TEST_ASSET"),encoding="utf-8")
    write_index(root,[("TEST_ASSET",ref)])
    rows=[{
        "codigo_activo":"TEST_ASSET",
        "inventory_status":"ACTIVE_SHARED_ENFORCEMENT",
        "readme_ref":ref,
        "estado_operativo":"ACTIVO",
        "archived_at":None,
    }]
    ok=run(root,rows,"--require-code","TEST_ASSET")
    assert ok.returncode==0,(ok.stdout,ok.stderr)
    assert '"schema_version": "lf-transversal-readme-contract/v3"' in ok.stdout

# Live asset cannot be ACTIVE_SHARED_ENFORCEMENT without an indexed README ref.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/missing_index/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("MISSING_INDEX"),encoding="utf-8")
    write_index(root,[("OTHER_ASSET","sandbox/lf_contract_gate_test/transversal_assets/other_asset/README.md")])
    rows=[{
        "codigo_activo":"MISSING_INDEX",
        "inventory_status":"ACTIVE_SHARED_ENFORCEMENT",
        "readme_ref":None,
        "estado_operativo":"ACTIVO",
        "archived_at":None,
    }]
    bad=run(root,rows)
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "INVENTORY_README_REF_MISSING" in bad.stdout

# Live reference to a missing file fails closed.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/missing_asset/README.md"
    write_index(root,[("MISSING_ASSET",ref)])
    rows=[{
        "codigo_activo":"MISSING_ASSET",
        "inventory_status":"ACTIVE_SHARED_ENFORCEMENT",
        "readme_ref":ref,
        "estado_operativo":"ACTIVO",
        "archived_at":None,
    }]
    bad=run(root,rows)
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "README_MISSING" in bad.stdout

# Reverse direction: source index cannot claim an asset absent from live inventory.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/source_only/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("SOURCE_ONLY"),encoding="utf-8")
    write_index(root,[("SOURCE_ONLY",ref)])
    bad=run(root,[])
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "INDEXED_ASSET_NOT_IN_LIVE_INVENTORY" in bad.stdout

# Indexed asset must be operationally ACTIVO, not merely documented.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/not_active/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("NOT_ACTIVE"),encoding="utf-8")
    write_index(root,[("NOT_ACTIVE",ref)])
    rows=[{
        "codigo_activo":"NOT_ACTIVE",
        "inventory_status":"ACTIVE_SHARED_ENFORCEMENT",
        "readme_ref":ref,
        "estado_operativo":"READ_ONLY",
        "archived_at":None,
    }]
    bad=run(root,rows)
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "INDEXED_ASSET_NOT_OPERATIONALLY_ACTIVE" in bad.stdout

# Explicit operation closure requirement cannot be bypassed by omitting it from the inventory.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/other/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("OTHER"),encoding="utf-8")
    write_index(root,[("OTHER",ref)])
    rows=[{
        "codigo_activo":"OTHER",
        "inventory_status":"ACTIVE_SHARED_ENFORCEMENT",
        "readme_ref":ref,
        "estado_operativo":"ACTIVO",
        "archived_at":None,
    }]
    bad=run(root,rows,"--require-code","GITHUB_CONTRACT_GATE_LF")
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "REQUIRED_OPERATION_ASSET_MISSING" in bad.stdout


# Active transversal policies are first-class documented assets too.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/policy_asset/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("POLICY_ASSET","ACTIVE_TRANSVERSAL_POLICY"),encoding="utf-8")
    write_index(root,[("POLICY_ASSET",ref)])
    rows=[{
        "codigo_activo":"POLICY_ASSET",
        "inventory_status":"ACTIVE_TRANSVERSAL_POLICY",
        "readme_ref":ref,
        "estado_operativo":"ACTIVO",
        "archived_at":None,
    }]
    ok=run(root,rows,"--require-code","POLICY_ASSET")
    assert ok.returncode==0,(ok.stdout,ok.stderr)

# A policy README must declare the same live inventory status.
with tempfile.TemporaryDirectory() as td:
    root=Path(td)
    ref="sandbox/lf_contract_gate_test/transversal_assets/policy_status_mismatch/README.md"
    p=root/ref; p.parent.mkdir(parents=True)
    p.write_text(readme_text("POLICY_STATUS_MISMATCH","ACTIVE_SHARED_ENFORCEMENT"),encoding="utf-8")
    write_index(root,[("POLICY_STATUS_MISMATCH",ref)])
    rows=[{
        "codigo_activo":"POLICY_STATUS_MISMATCH",
        "inventory_status":"ACTIVE_TRANSVERSAL_POLICY",
        "readme_ref":ref,
        "estado_operativo":"ACTIVO",
        "archived_at":None,
    }]
    bad=run(root,rows)
    assert bad.returncode==1,(bad.stdout,bad.stderr)
    assert "README_INVENTORY_STATUS_MISSING" in bad.stdout

print("TRANSVERSAL_DOCUMENTED_ACTIVE_README_CONTRACT_V3_PASS")

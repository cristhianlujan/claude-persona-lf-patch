#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / "scripts/pack_validation/resolve_affected_packs_v1.py"
VALIDATION = ROOT / "gobernanza/contratos/pack_validation_define_contract_v1.json"
DISCOVERY = ROOT / "gobernanza/contratos/pack_discovery_resolve_affected_packs_v1.json"

spec = importlib.util.spec_from_file_location("resolve_affected_packs_v1", MODULE)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

validation_contract = json.loads(VALIDATION.read_text(encoding="utf-8"))
discovery_contract = json.loads(DISCOVERY.read_text(encoding="utf-8"))
BASE = "a" * 40
HEAD = "b" * 40
checks = 0


def run(repo: Path, changed: list[str], *, base: str = BASE, head: str = HEAD):
    return mod.resolve_affected_packs(
        repo_root=repo,
        validation_contract=validation_contract,
        discovery_contract=discovery_contract,
        base_sha=base,
        head_sha=head,
        changed_paths=changed,
    )


with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp)
    for rel in (
        "profiles/alpha",
        "profiles/beta",
        "profiles/_internal",
        "skills/profile_creator",
        "skills/payments",
    ):
        (repo / rel).mkdir(parents=True, exist_ok=True)

    result = run(repo, ["profiles/alpha/SKILL.md"])
    assert result["status"] == "PASS"
    assert [(p["pack_type"], p["pack_root"]) for p in result["affected_packs"]] == [
        ("PROFILE_PACK", "profiles/alpha")
    ]
    checks += 1

    result = run(repo, ["skills/payments/validators/validate_pack.py"])
    assert [(p["pack_type"], p["pack_root"]) for p in result["affected_packs"]] == [
        ("SKILL_PACK", "skills/payments")
    ]
    checks += 1

    result = run(repo, ["skills/profile_creator/SKILL.md"])
    observed = {(p["pack_type"], p["pack_root"]) for p in result["affected_packs"]}
    assert observed == {
        ("PROFILE_PACK", "profiles/alpha"),
        ("PROFILE_PACK", "profiles/beta"),
        ("SKILL_PACK", "skills/profile_creator"),
    }
    assert not any("_internal" in root for _, root in observed)
    checks += 1

    result = run(repo, ["profiles/gone/SKILL.md"])
    assert result["affected_packs"][0]["pack_root"] == "profiles/gone"
    assert result["affected_packs"][0]["exists_at_head"] is False
    checks += 1

    result = run(repo, ["docs/readme.md"])
    assert result["status"] == "SKIP" and result["affected_packs"] == []
    checks += 1

    result = run(repo, ["profiles/README.md", "skills/README.md"])
    assert result["status"] == "SKIP"
    checks += 1

    result = run(repo, ["profiles/alpha/SKILL.md", "profiles/alpha/manifest.json"])
    assert len(result["affected_packs"]) == 1
    assert result["affected_packs"][0]["trigger_paths"] == [
        "profiles/alpha/SKILL.md",
        "profiles/alpha/manifest.json",
    ]
    checks += 1

    result = run(repo, ["profiles/../secrets.txt"])
    assert result["status"] == "FAIL" and result["blocking_codes"] == ["PATH_INVALID"]
    checks += 1

    result = run(repo, ["profiles/alpha/SKILL.md"], head="not-a-sha")
    assert result["status"] == "FAIL" and result["blocking_codes"] == ["HEAD_SHA_INVALID"]
    checks += 1

    result = run(repo, ["profiles/alpha/SKILL.md", "skills/payments/SKILL.md"])
    assert result["validators_executed"] is False
    assert result["runtime_authorized"] is False
    assert result["git_write_authorized"] is False
    assert result["db_write_authorized"] is False
    assert result["deployment_authorized"] is False
    assert result["production_authorized"] is False
    assert result["handoff"] == "PACK_VALIDATION_EXECUTE_PACK_CHECKS"
    checks += 1

assert checks == 10
print("PASS_PACK_DISCOVERY_RESOLVE_AFFECTED_PACKS=10/10")

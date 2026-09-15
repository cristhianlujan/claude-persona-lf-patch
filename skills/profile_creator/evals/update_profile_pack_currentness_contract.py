#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = json.loads((ROOT / "contracts" / "update_profile_pack_currentness_v1.json").read_text(encoding="utf-8"))

def fingerprint(rows):
    normalized = sorted({(r["path"], r["blob_sha"]) for r in rows})
    raw = json.dumps([{"path": p, "blob_sha": s} for p, s in normalized], sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()

def resolve_declared(target_path, baseline_files, tree_rows):
    if not target_path.startswith("profiles/"):
        raise ValueError("PROFILE_PACK_TARGET_PATH_INVALID")
    if not isinstance(baseline_files, list) or not baseline_files:
        raise ValueError("PROFILE_PACK_BASELINE_FILES_REQUIRED")
    tree = {r["path"]: r for r in tree_rows if r.get("type") == "blob"}
    resolved = {}
    target_prefix = target_path.rstrip("/") + "/"
    for declared in baseline_files:
        if not isinstance(declared, str) or not declared.strip():
            raise ValueError("PROFILE_PACK_BASELINE_FILE_INVALID")
        item = declared.strip().rstrip("/")
        if item != target_path and not item.startswith(target_prefix):
            raise ValueError("PROFILE_PACK_BASELINE_FILE_OUTSIDE_TARGET")
        matched = []
        if item in tree:
            matched = [tree[item]]
        else:
            prefix = item + "/"
            matched = [row for path, row in tree.items() if path.startswith(prefix)]
        if not matched:
            raise ValueError("PROFILE_PACK_BASELINE_FILE_UNRESOLVED")
        for row in matched:
            resolved[row["path"]] = {"path": row["path"], "blob_sha": row["sha"]}
    if not resolved:
        raise ValueError("PROFILE_PACK_EMPTY")
    rows = list(resolved.values())
    return {"file_count": len(rows), "fingerprint": fingerprint(rows), "files": sorted(rows, key=lambda x: x["path"])}

checks = {
    "operation_unchanged": CONTRACT["operation_code"] == "ACTUALIZACION_PERFIL_LF",
    "step_unchanged": CONTRACT["step_id"] == "pre_write_execution_binding_gate",
    "dual_mode": set(CONTRACT["binding_modes"]) == {"EXACT_FILE", "PROFILE_PACK"},
    "pack_uses_baseline_files": "baseline_files" in CONTRACT["binding_modes"]["PROFILE_PACK"]["required_currentness_fields"],
    "pack_has_fingerprint": "target_pack_fingerprint_sha256" in CONTRACT["binding_modes"]["PROFILE_PACK"]["required_currentness_fields"],
    "one_target_preserved": CONTRACT["preservation"]["one_target_per_execution"] is True,
    "no_mass_authority": CONTRACT["activation_gate"]["mass_fanout_authorized"] is False,
    "runtime_not_claimed": CONTRACT["activation_gate"]["runtime_patch_materialized"] is False,
}

tree = [
    {"path":"profiles/product_director_lf/SKILL.md","type":"blob","sha":"a"*40},
    {"path":"profiles/product_director_lf/contracts/a.md","type":"blob","sha":"b"*40},
    {"path":"profiles/product_director_lf/contracts/b.json","type":"blob","sha":"c"*40},
    {"path":"profiles/product_director_lf/evals/evals.json","type":"blob","sha":"d"*40},
    {"path":"profiles/quality_pack/SKILL.md","type":"blob","sha":"e"*40},
]
case = resolve_declared(
    "profiles/product_director_lf",
    ["profiles/product_director_lf/SKILL.md", "profiles/product_director_lf/contracts"],
    tree,
)
case_reordered = resolve_declared(
    "profiles/product_director_lf",
    ["profiles/product_director_lf/contracts", "profiles/product_director_lf/SKILL.md"],
    list(reversed(tree)),
)
checks["directory_expands"] = case["file_count"] == 3
checks["fingerprint_deterministic"] = case["fingerprint"] == case_reordered["fingerprint"]
checks["dedupe_deterministic"] = fingerprint(case["files"] + case["files"]) == case["fingerprint"]

negatives=[]
for name, target, declared, expected in [
    ("outside", "profiles/product_director_lf", ["profiles/quality_pack/SKILL.md"], "PROFILE_PACK_BASELINE_FILE_OUTSIDE_TARGET"),
    ("missing", "profiles/product_director_lf", ["profiles/product_director_lf/missing"], "PROFILE_PACK_BASELINE_FILE_UNRESOLVED"),
    ("empty", "profiles/product_director_lf", [], "PROFILE_PACK_BASELINE_FILES_REQUIRED"),
]:
    try:
        resolve_declared(target, declared, tree)
        negatives.append((name, False, "NO_ERROR"))
    except ValueError as exc:
        negatives.append((name, str(exc) == expected, str(exc)))
checks["negative_fail_closed"] = all(ok for _,ok,_ in negatives)

failed=[name for name,ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL_UPDATE_PROFILE_PACK_CURRENTNESS:"+",".join(failed)+";negative="+repr(negatives))
print(f"PASS_UPDATE_PROFILE_PACK_CURRENTNESS={sum(checks.values())}/{len(checks)}")
print("EXACT_FILE_MODE=PRESERVED")
print("PROFILE_PACK_MODE=SPECIFIED_NOT_DEPLOYED")
print("MASS_FANOUT_AUTHORIZED=false")

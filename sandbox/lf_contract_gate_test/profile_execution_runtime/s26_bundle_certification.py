#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

SPEC_SCHEMA = "S26_REVIEW_BUNDLE_SPEC_V1"
MANIFEST_SCHEMA = "S26_REVIEW_BUNDLE_MANIFEST_V1"
REPLAY_SCHEMA = "S26_REVIEW_BUNDLE_REPLAY_V1"
DEPENDENCY_MAP_SCHEMA = "S26_REVIEW_BUNDLE_DEPENDENCY_MAP_V1"
REQUIRED_CATEGORIES = {
    "artifact",
    "input",
    "authority",
    "cards_context",
    "validator",
    "receipt",
    "evidence",
    "run_metadata",
    "replay_plan",
}
ALLOWED_REPLAY_EXECUTABLES = {"python", "python3"}


class BundleError(RuntimeError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def safe_rel(value: str, code: str = "UNSAFE_BUNDLE_PATH") -> str:
    if not isinstance(value, str) or not value.strip():
        raise BundleError(f"{code}:{value!r}")
    value = value.replace("\\", "/")
    p = PurePosixPath(value)
    if p.is_absolute() or ".." in p.parts or "." in p.parts or value.startswith("/"):
        raise BundleError(f"{code}:{value}")
    return str(p)


def resolve_field(value, dotted_path: str):
    cur = value
    for part in dotted_path.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            raise BundleError(f"RECEIPT_ARTIFACT_FIELD_MISSING:{dotted_path}")
    return cur


def _copy(repo_root: Path, source: str, bundle_root: Path, bundle_path: str) -> Path:
    source_rel = safe_rel(source, "UNSAFE_SOURCE_PATH")
    dest_rel = safe_rel(bundle_path)
    src = (repo_root / source_rel).resolve()
    rr = repo_root.resolve()
    if rr not in src.parents and src != rr:
        raise BundleError(f"SOURCE_OUTSIDE_REPO:{source}")
    if not src.is_file():
        raise BundleError(f"SOURCE_MISSING:{source}")
    dst = bundle_root / dest_rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        raise BundleError(f"DUPLICATE_BUNDLE_PATH:{dest_rel}")
    shutil.copyfile(src, dst)
    return dst


def _iter_string_refs(value, jpath="$"):
    if isinstance(value, dict):
        for key, item in value.items():
            yield from _iter_string_refs(item, f"{jpath}.{key}")
    elif isinstance(value, list):
        for idx, item in enumerate(value):
            yield from _iter_string_refs(item, f"{jpath}[{idx}]")
    elif isinstance(value, str) and (
        value.startswith("bundle://")
        or value.startswith("run://")
        or value.startswith("github://")
    ):
        yield jpath, value


def _manifest_entries(bundle_root: Path, provenance: dict[str, dict]) -> list[dict]:
    entries = []
    for path in sorted(bundle_root.rglob("*")):
        if not path.is_file() or path.name == "bundle_manifest.json":
            continue
        rel = path.relative_to(bundle_root).as_posix()
        prov = provenance.get(rel)
        if prov is None:
            raise BundleError(f"UNTRACKED_BUILDER_OUTPUT:{rel}")
        item = {
            "path": rel,
            "category": prov["category"],
            "source": prov["source"],
            "source_run_id": prov["source_run_id"],
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        }
        if prov.get("source_revision"):
            item["source_revision"] = prov["source_revision"]
        entries.append(item)
    return entries


def _normalize_replay_command(validator: dict) -> tuple[str, list[str]]:
    validator_rel = safe_rel(validator.get("bundle_path"), "UNSAFE_VALIDATOR_PATH")
    argv = validator.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(x, str) and x for x in argv):
        raise BundleError(f"VALIDATOR_ARGV_INVALID:{validator_rel}")
    if argv[0] not in ALLOWED_REPLAY_EXECUTABLES:
        raise BundleError(f"REPLAY_EXECUTABLE_FORBIDDEN:{argv[0]}")
    safe_argv = [argv[0]]
    for arg in argv[1:]:
        if arg.startswith("-"):
            safe_argv.append(arg)
        else:
            safe_argv.append(safe_rel(arg, "UNSAFE_REPLAY_ARG"))
    if len(safe_argv) < 2 or safe_argv[1] != validator_rel:
        actual = safe_argv[1] if len(safe_argv) > 1 else "<missing>"
        raise BundleError(f"VALIDATOR_ARGV_MISMATCH:{validator_rel}!={actual}")
    return validator_rel, safe_argv


def build_bundle(spec_path: Path, repo_root: Path, out_dir: Path, zip_path: Path | None = None) -> dict:
    spec = load_json(spec_path)
    if spec.get("schema") != SPEC_SCHEMA:
        raise BundleError(f"SPEC_SCHEMA_INVALID:{spec.get('schema')}")
    run_id = spec.get("run_id")
    if not isinstance(run_id, str) or not run_id.strip():
        raise BundleError("RUN_ID_MISSING")
    metadata = spec.get("run_metadata")
    if not isinstance(metadata, dict):
        raise BundleError("RUN_METADATA_MISSING")
    for key in ("run_id", "base_sha", "branch", "head_sha"):
        if not isinstance(metadata.get(key), str) or not metadata[key].strip():
            raise BundleError(f"RUN_METADATA_FIELD_MISSING:{key}")
    if metadata["run_id"] != run_id:
        raise BundleError(f"RUN_METADATA_RUN_MISMATCH:{metadata['run_id']}!={run_id}")

    artifact = spec.get("artifact")
    if not isinstance(artifact, dict):
        raise BundleError("ARTIFACT_SPEC_MISSING")
    items = [{**artifact, "category": "artifact"}] + list(spec.get("items") or [])
    receipts = list(spec.get("receipts") or [])
    generated_receipts = list(spec.get("generated_receipts") or [])
    validators = list(spec.get("validators") or [])
    for item in receipts:
        items.append({**item, "category": "receipt"})
    for item in validators:
        items.append({**item, "category": "validator"})

    out_dir = out_dir.resolve()
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    provenance: dict[str, dict] = {}

    for item in items:
        if not isinstance(item, dict):
            raise BundleError("ITEM_NOT_OBJECT")
        category = item.get("category")
        if category not in REQUIRED_CATEGORIES - {"run_metadata", "replay_plan"}:
            raise BundleError(f"CATEGORY_INVALID:{category}")
        source_run_id = item.get("source_run_id", run_id)
        if source_run_id != run_id:
            raise BundleError(f"CROSS_RUN_SOURCE:{source_run_id}!={run_id}:{item.get('source')}")
        rel = safe_rel(item.get("bundle_path"))
        _copy(repo_root, item.get("source"), out_dir, rel)
        provenance[rel] = {
            "category": category,
            "source": safe_rel(item.get("source"), "UNSAFE_SOURCE_PATH"),
            "source_run_id": source_run_id,
            "source_revision": item.get("source_revision"),
        }

    dump_json(out_dir / "run_metadata.json", metadata)
    provenance["run_metadata.json"] = {
        "category": "run_metadata",
        "source": "generated://run_metadata",
        "source_run_id": run_id,
    }

    artifact_rel = safe_rel(artifact.get("bundle_path"))
    artifact_sha = sha256_file(out_dir / artifact_rel)

    for receipt in receipts:
        field = receipt.get("artifact_sha256_field")
        if not isinstance(field, str) or not field:
            raise BundleError(f"RECEIPT_BINDING_FIELD_UNDECLARED:{receipt.get('bundle_path')}")
        receipt_obj = load_json(out_dir / safe_rel(receipt.get("bundle_path")))
        bound_sha = resolve_field(receipt_obj, field)
        if isinstance(bound_sha, str):
            bound_sha = bound_sha.replace("sha256:", "")
        if bound_sha != artifact_sha:
            raise BundleError(
                f"RECEIPT_ARTIFACT_MISMATCH:{receipt.get('bundle_path')}:{bound_sha}!={artifact_sha}"
            )

    for receipt in generated_receipts:
        if not isinstance(receipt, dict):
            raise BundleError("GENERATED_RECEIPT_NOT_OBJECT")
        rel = safe_rel(receipt.get("bundle_path"), "UNSAFE_GENERATED_RECEIPT_PATH")
        if (out_dir / rel).exists():
            raise BundleError(f"DUPLICATE_BUNDLE_PATH:{rel}")
        payload = {
            "schema": receipt.get("schema", "S26_GENERATED_ARTIFACT_BINDING_RECEIPT_V1"),
            "run_id": run_id,
            "artifact_path": artifact_rel,
            "artifact_sha256": artifact_sha,
        }
        if isinstance(receipt.get("metadata"), dict):
            payload["metadata"] = receipt["metadata"]
        dump_json(out_dir / rel, payload)
        provenance[rel] = {
            "category": "receipt",
            "source": "generated://artifact_binding_receipt",
            "source_run_id": run_id,
        }

    external_ref_map = spec.get("external_ref_map") or {}
    if not isinstance(external_ref_map, dict):
        raise BundleError("EXTERNAL_REF_MAP_INVALID")
    normalized_map: dict[str, str] = {}
    for ref, target in external_ref_map.items():
        if not isinstance(ref, str) or not ref.startswith("github://"):
            raise BundleError(f"EXTERNAL_REF_INVALID:{ref}")
        normalized_map[ref] = safe_rel(target, "UNSAFE_EXTERNAL_REF_TARGET")
    if normalized_map:
        dump_json(
            out_dir / "dependency_map.json",
            {"schema": DEPENDENCY_MAP_SCHEMA, "run_id": run_id, "dependencies": normalized_map},
        )
        provenance["dependency_map.json"] = {
            "category": "evidence",
            "source": "generated://dependency_map",
            "source_run_id": run_id,
        }

    replay_commands = []
    for validator in validators:
        validator_rel, safe_argv = _normalize_replay_command(validator)
        replay_commands.append({"validator": validator_rel, "argv": safe_argv})
    replay_plan = {"schema": REPLAY_SCHEMA, "run_id": run_id, "commands": replay_commands}
    dump_json(out_dir / "replay_plan.json", replay_plan)
    provenance["replay_plan.json"] = {
        "category": "replay_plan",
        "source": "generated://replay_plan",
        "source_run_id": run_id,
    }

    categories = {meta["category"] for meta in provenance.values()}
    missing_categories = sorted(REQUIRED_CATEGORIES - categories)
    if missing_categories:
        raise BundleError(f"REQUIRED_CATEGORY_MISSING:{','.join(missing_categories)}")

    entries = _manifest_entries(out_dir, provenance)
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "run_id": run_id,
        "artifact_path": artifact_rel,
        "artifact_sha256": artifact_sha,
        "file_count": len(entries),
        "files": entries,
    }
    dump_json(out_dir / "bundle_manifest.json", manifest)

    errors = validate_bundle(out_dir)
    if errors:
        raise BundleError("BUILD_VALIDATION_FAILED:" + "|".join(errors))
    if zip_path is not None:
        write_deterministic_zip(out_dir, zip_path)
    return manifest


def _load_dependency_map(bundle_root: Path, run_id: str, errors: list[str]) -> dict[str, str]:
    path = bundle_root / "dependency_map.json"
    if not path.is_file():
        return {}
    try:
        obj = load_json(path)
    except Exception as exc:
        errors.append(f"DEPENDENCY_MAP_PARSE_FAIL:{type(exc).__name__}")
        return {}
    if obj.get("schema") != DEPENDENCY_MAP_SCHEMA:
        errors.append(f"DEPENDENCY_MAP_SCHEMA_INVALID:{obj.get('schema')}")
    if obj.get("run_id") != run_id:
        errors.append(f"DEPENDENCY_MAP_RUN_MISMATCH:{obj.get('run_id')}!={run_id}")
    deps = obj.get("dependencies")
    if not isinstance(deps, dict):
        errors.append("DEPENDENCY_MAP_INVALID")
        return {}
    clean = {}
    for ref, target in deps.items():
        if not isinstance(ref, str) or not ref.startswith("github://"):
            errors.append(f"DEPENDENCY_REF_INVALID:{ref}")
            continue
        try:
            clean[ref] = safe_rel(target, "UNSAFE_EXTERNAL_REF_TARGET")
        except BundleError as exc:
            errors.append(str(exc))
    return clean


def validate_bundle(bundle_root: Path) -> list[str]:
    bundle_root = bundle_root.resolve()
    errors: list[str] = []
    manifest_path = bundle_root / "bundle_manifest.json"
    if not manifest_path.is_file():
        return ["MANIFEST_MISSING"]
    try:
        manifest = load_json(manifest_path)
    except Exception as exc:
        return [f"MANIFEST_PARSE_FAIL:{type(exc).__name__}"]
    if manifest.get("schema") != MANIFEST_SCHEMA:
        errors.append(f"MANIFEST_SCHEMA_INVALID:{manifest.get('schema')}")
    run_id = manifest.get("run_id")
    files = manifest.get("files")
    if not isinstance(files, list):
        return errors + ["MANIFEST_FILES_INVALID"]

    listed: dict[str, dict] = {}
    for item in files:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            errors.append("MANIFEST_ENTRY_INVALID")
            continue
        try:
            rel = safe_rel(item["path"])
        except BundleError as exc:
            errors.append(str(exc))
            continue
        if rel in listed:
            errors.append(f"MANIFEST_DUPLICATE_PATH:{rel}")
        listed[rel] = item
        if item.get("source_run_id") != run_id:
            errors.append(f"CROSS_RUN_MANIFEST_ENTRY:{rel}:{item.get('source_run_id')}!={run_id}")

    actual = {
        p.relative_to(bundle_root).as_posix()
        for p in bundle_root.rglob("*")
        if p.is_file() and p.name != "bundle_manifest.json"
    }
    listed_set = set(listed)
    if listed_set != actual:
        errors.append(f"MANIFEST_SET_MISMATCH:missing={sorted(listed_set-actual)}:extra={sorted(actual-listed_set)}")
    if manifest.get("file_count") != len(files) or len(files) != len(listed):
        errors.append(f"MANIFEST_FILE_COUNT_MISMATCH:{manifest.get('file_count')}:{len(files)}:{len(listed)}")

    categories = set()
    for rel, item in listed.items():
        categories.add(item.get("category"))
        path = bundle_root / rel
        if not path.is_file():
            errors.append(f"MANIFEST_FILE_MISSING:{rel}")
            continue
        if path.is_symlink():
            errors.append(f"SYMLINK_FORBIDDEN:{rel}")
        if item.get("bytes") != path.stat().st_size:
            errors.append(f"MANIFEST_BYTES_MISMATCH:{rel}")
        if item.get("sha256") != sha256_file(path):
            errors.append(f"MANIFEST_SHA_MISMATCH:{rel}")
    missing_categories = sorted(REQUIRED_CATEGORIES - categories)
    if missing_categories:
        errors.append(f"REQUIRED_CATEGORY_MISSING:{','.join(missing_categories)}")

    artifact_rel = manifest.get("artifact_path")
    if isinstance(artifact_rel, str) and (bundle_root / artifact_rel).is_file():
        artifact_sha = sha256_file(bundle_root / artifact_rel)
        if manifest.get("artifact_sha256") != artifact_sha:
            errors.append("MANIFEST_ARTIFACT_SHA_MISMATCH")
    else:
        errors.append(f"ARTIFACT_FILE_MISSING:{artifact_rel}")
        artifact_sha = None

    metadata_path = bundle_root / "run_metadata.json"
    if metadata_path.is_file():
        try:
            metadata = load_json(metadata_path)
            if metadata.get("run_id") != run_id:
                errors.append(f"RUN_METADATA_RUN_MISMATCH:{metadata.get('run_id')}!={run_id}")
            for key in ("base_sha", "branch", "head_sha"):
                if not isinstance(metadata.get(key), str) or not metadata[key].strip():
                    errors.append(f"RUN_METADATA_FIELD_MISSING:{key}")
        except Exception as exc:
            errors.append(f"RUN_METADATA_PARSE_FAIL:{type(exc).__name__}")

    dependency_map = _load_dependency_map(bundle_root, run_id, errors)
    for ref, target in dependency_map.items():
        if not (bundle_root / target).is_file():
            errors.append(f"EXTERNAL_REF_TARGET_MISSING:{ref}:{target}")

    for rel in sorted(actual):
        path = bundle_root / rel
        if path.suffix.lower() != ".json" or path.name == "dependency_map.json":
            continue
        try:
            refs = list(_iter_string_refs(load_json(path)))
        except Exception:
            continue
        for jpath, ref in refs:
            if ref.startswith("bundle://"):
                target = ref[len("bundle://"):].split("#", 1)[0]
                try:
                    target = safe_rel(target, "UNSAFE_BUNDLE_REF")
                except BundleError as exc:
                    errors.append(f"{exc}:{rel}:{jpath}")
                    continue
                if not (bundle_root / target).is_file():
                    errors.append(f"BUNDLE_REF_UNRESOLVED:{rel}:{jpath}:{ref}")
            elif ref.startswith("run://"):
                rest = ref[len("run://"):]
                ref_run, sep, target = rest.partition("/")
                if not sep or ref_run != run_id:
                    errors.append(f"CROSS_RUN_REF:{rel}:{jpath}:{ref}")
                    continue
                try:
                    target = safe_rel(target, "UNSAFE_RUN_REF")
                except BundleError as exc:
                    errors.append(f"{exc}:{rel}:{jpath}")
                    continue
                if not (bundle_root / target).is_file():
                    errors.append(f"RUN_REF_UNRESOLVED:{rel}:{jpath}:{ref}")
            else:
                target = dependency_map.get(ref)
                if target is None:
                    errors.append(f"EXTERNAL_REF_UNMAPPED:{rel}:{jpath}:{ref}")
                elif not (bundle_root / target).is_file():
                    errors.append(f"EXTERNAL_REF_TARGET_MISSING:{rel}:{jpath}:{ref}:{target}")

    if artifact_sha:
        for rel, item in listed.items():
            if item.get("category") != "receipt":
                continue
            try:
                obj = load_json(bundle_root / rel)
            except Exception as exc:
                errors.append(f"RECEIPT_PARSE_FAIL:{rel}:{type(exc).__name__}")
                continue
            candidates = []

            def walk(v):
                if isinstance(v, dict):
                    for k, x in v.items():
                        if k in {"artifact_sha256", "artifact_canonical_sha256", "artifact_sha_or_digest"} and isinstance(x, str):
                            candidates.append(x.replace("sha256:", ""))
                        walk(x)
                elif isinstance(v, list):
                    for x in v:
                        walk(x)

            walk(obj)
            if not candidates:
                errors.append(f"RECEIPT_ARTIFACT_BINDING_MISSING:{rel}")
            elif artifact_sha not in candidates:
                errors.append(f"RECEIPT_ARTIFACT_MISMATCH:{rel}")

    replay_path = bundle_root / "replay_plan.json"
    if replay_path.is_file():
        try:
            replay = load_json(replay_path)
            if replay.get("schema") != REPLAY_SCHEMA:
                errors.append(f"REPLAY_SCHEMA_INVALID:{replay.get('schema')}")
            if replay.get("run_id") != run_id:
                errors.append(f"REPLAY_RUN_MISMATCH:{replay.get('run_id')}!={run_id}")
            commands = replay.get("commands")
            if not isinstance(commands, list) or not commands:
                errors.append("REPLAY_COMMANDS_MISSING")
            else:
                for idx, cmd in enumerate(commands):
                    argv = cmd.get("argv") if isinstance(cmd, dict) else None
                    validator = cmd.get("validator") if isinstance(cmd, dict) else None
                    if not isinstance(argv, list) or not argv or argv[0] not in ALLOWED_REPLAY_EXECUTABLES:
                        errors.append(f"REPLAY_COMMAND_INVALID:{idx}")
                        continue
                    try:
                        validator_rel = safe_rel(validator, "UNSAFE_VALIDATOR_PATH")
                    except BundleError as exc:
                        errors.append(str(exc))
                        continue
                    if not (bundle_root / validator_rel).is_file():
                        errors.append(f"VALIDATOR_MISSING:{validator_rel}")
                    if len(argv) < 2:
                        errors.append(f"VALIDATOR_ARGV_MISMATCH:{validator_rel}=><missing>")
                    else:
                        try:
                            argv_validator = safe_rel(argv[1], "UNSAFE_REPLAY_ARG")
                        except BundleError as exc:
                            errors.append(str(exc))
                            continue
                        if argv_validator != validator_rel:
                            errors.append(f"VALIDATOR_ARGV_MISMATCH:{validator_rel}!={argv_validator}")
        except Exception as exc:
            errors.append(f"REPLAY_PLAN_PARSE_FAIL:{type(exc).__name__}")
    return sorted(set(errors))


def replay_validators(bundle_root: Path) -> list[str]:
    errors = validate_bundle(bundle_root)
    if errors:
        return errors
    replay = load_json(bundle_root / "replay_plan.json")
    failures = []
    env = {"PATH": os.environ.get("PATH", ""), "PYTHONPATH": "", "S26_BUNDLE_ROOT": str(bundle_root.resolve())}
    for idx, cmd in enumerate(replay["commands"]):
        proc = subprocess.run(cmd["argv"], cwd=bundle_root, env=env, text=True, capture_output=True, timeout=30)
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "").strip().replace("\n", " ")[:240]
            failures.append(f"REPLAY_FAILED:{idx}:{cmd['validator']}:{proc.returncode}:{detail}")
    return failures


def write_deterministic_zip(bundle_root: Path, zip_path: Path) -> None:
    zip_path = zip_path.resolve()
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(bundle_root.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(bundle_root).as_posix()
            info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            zf.writestr(info, path.read_bytes())


def certify_zip(zip_path: Path, replay: bool = True) -> dict:
    zip_sha = sha256_file(zip_path)
    with tempfile.TemporaryDirectory(prefix="s26_bundle_cert_") as td:
        root = Path(td) / "bundle"
        root.mkdir()
        with zipfile.ZipFile(zip_path, "r") as zf:
            for info in zf.infolist():
                rel = safe_rel(info.filename, "ZIP_ENTRY_UNSAFE")
                target = (root / rel).resolve()
                if root.resolve() not in target.parents:
                    raise BundleError(f"ZIP_ENTRY_OUTSIDE_ROOT:{info.filename}")
            zf.extractall(root)
        validation_errors = validate_bundle(root)
        replay_errors = replay_validators(root) if replay and not validation_errors else []
        return {
            "schema": "S26_BUNDLE_CERTIFICATION_RECEIPT_V1",
            "status": "PASS" if not validation_errors and not replay_errors else "FAIL",
            "bundle_zip_sha256": zip_sha,
            "manifest_reconciled": not any(e.startswith(("MANIFEST_", "REQUIRED_CATEGORY_")) for e in validation_errors),
            "hashes_verified": not any("SHA_MISMATCH" in e or "BYTES_MISMATCH" in e for e in validation_errors),
            "cross_run_refs_blocked": not any(
                e.startswith(("CROSS_RUN_REF", "CROSS_RUN_MANIFEST_ENTRY", "EXTERNAL_REF_UNMAPPED"))
                for e in validation_errors
            ),
            "fresh_unpack_pass": not validation_errors,
            "replay_pass": replay and not validation_errors and not replay_errors,
            "errors": validation_errors + replay_errors,
        }


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--spec", type=Path, required=True)
    b.add_argument("--repo-root", type=Path, required=True)
    b.add_argument("--out-dir", type=Path, required=True)
    b.add_argument("--zip", dest="zip_path", type=Path, required=True)
    c = sub.add_parser("certify")
    c.add_argument("--zip", dest="zip_path", type=Path, required=True)
    c.add_argument("--receipt-out", type=Path)
    args = ap.parse_args()
    try:
        if args.cmd == "build":
            manifest = build_bundle(args.spec, args.repo_root, args.out_dir, args.zip_path)
            print(json.dumps({"status": "BUILT", "manifest": manifest}, indent=2, ensure_ascii=False))
            return 0
        receipt = certify_zip(args.zip_path, replay=True)
        if args.receipt_out:
            dump_json(args.receipt_out, receipt)
        print(json.dumps(receipt, indent=2, ensure_ascii=False))
        return 0 if receipt["status"] == "PASS" else 1
    except (BundleError, OSError, json.JSONDecodeError, zipfile.BadZipFile, subprocess.SubprocessError) as exc:
        print(json.dumps({"status": "FAIL", "errors": [str(exc)]}, indent=2, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

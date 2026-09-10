#!/usr/bin/env python3
from __future__ import annotations

import stat
import zipfile
from pathlib import Path, PurePosixPath

from s26_bundle_certification import certify_zip, sha256_file


def _safe_zip_rel(name: str) -> str:
    if not isinstance(name, str) or not name.strip():
        raise ValueError("ZIP_ENTRY_NAME_INVALID")
    normalized = name.replace("\\", "/")
    p = PurePosixPath(normalized)
    if p.is_absolute() or normalized.startswith("/") or ".." in p.parts or "." in p.parts:
        raise ValueError(f"ZIP_ENTRY_UNSAFE:{name}")
    rel = str(p)
    if not rel or rel == ".":
        raise ValueError(f"ZIP_ENTRY_UNSAFE:{name}")
    return rel


def validate_zip_archive_structure(zip_path: Path) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    seen_casefold: dict[str, str] = {}
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            infos = zf.infolist()
            if not infos:
                return ["ZIP_EMPTY"]
            for info in infos:
                try:
                    rel = _safe_zip_rel(info.filename)
                except ValueError as exc:
                    errors.append(str(exc))
                    continue

                if rel in seen:
                    errors.append(f"ZIP_DUPLICATE_ENTRY:{rel}")
                else:
                    seen.add(rel)

                folded = rel.casefold()
                prior = seen_casefold.get(folded)
                if prior is not None and prior != rel:
                    errors.append(f"ZIP_CASE_COLLISION:{prior}:{rel}")
                else:
                    seen_casefold[folded] = rel

                if info.is_dir():
                    errors.append(f"ZIP_DIRECTORY_ENTRY_FORBIDDEN:{rel}")
                mode = (info.external_attr >> 16) & 0xFFFF
                if stat.S_ISLNK(mode):
                    errors.append(f"ZIP_SYMLINK_FORBIDDEN:{rel}")
                if info.flag_bits & 0x1:
                    errors.append(f"ZIP_ENCRYPTED_ENTRY_FORBIDDEN:{rel}")
    except zipfile.BadZipFile:
        return ["ZIP_BAD_ARCHIVE"]
    return sorted(set(errors))


def certify_zip_strict(zip_path: Path, replay: bool = True) -> dict:
    structural_errors = validate_zip_archive_structure(zip_path)
    if structural_errors:
        return {
            "schema": "S26_BUNDLE_CERTIFICATION_RECEIPT_V1",
            "status": "FAIL",
            "bundle_zip_sha256": sha256_file(zip_path) if Path(zip_path).is_file() else None,
            "manifest_reconciled": False,
            "hashes_verified": False,
            "cross_run_refs_blocked": False,
            "fresh_unpack_pass": False,
            "replay_pass": False,
            "errors": structural_errors,
        }
    return certify_zip(zip_path, replay=replay)

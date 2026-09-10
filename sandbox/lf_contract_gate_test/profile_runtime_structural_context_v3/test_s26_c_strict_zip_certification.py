#!/usr/bin/env python3
from __future__ import annotations

import stat
import sys
import tempfile
import warnings
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RUNTIME = REPO / "sandbox/lf_contract_gate_test/profile_execution_runtime"
if str(RUNTIME) not in sys.path:
    sys.path.insert(0, str(RUNTIME))

from s26_strict_zip_certification import certify_zip_strict, validate_zip_archive_structure  # noqa: E402


def write_zip(path: Path, entries: list[tuple[str, str]]) -> None:
    with zipfile.ZipFile(path, "w") as zf:
        for name, value in entries:
            zf.writestr(name, value)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="s26-c-zip-guard-") as td:
        root = Path(td)

        good = root / "good.zip"
        write_zip(good, [("a.txt", "a"), ("nested/b.txt", "b")])
        assert validate_zip_archive_structure(good) == []

        duplicate = root / "duplicate.zip"
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            write_zip(duplicate, [("artifact/raw.json", "first"), ("artifact/raw.json", "second")])
        errors = validate_zip_archive_structure(duplicate)
        assert "ZIP_DUPLICATE_ENTRY:artifact/raw.json" in errors, errors
        receipt = certify_zip_strict(duplicate)
        assert receipt["status"] == "FAIL", receipt
        assert any(e.startswith("ZIP_DUPLICATE_ENTRY:") for e in receipt["errors"]), receipt

        collision = root / "case-collision.zip"
        write_zip(collision, [("Evidence/A.json", "a"), ("evidence/a.json", "b")])
        errors = validate_zip_archive_structure(collision)
        assert any(e.startswith("ZIP_CASE_COLLISION:") for e in errors), errors

        traversal = root / "traversal.zip"
        write_zip(traversal, [("../escape.txt", "x")])
        errors = validate_zip_archive_structure(traversal)
        assert any(e.startswith("ZIP_ENTRY_UNSAFE:") for e in errors), errors

        symlink = root / "symlink.zip"
        info = zipfile.ZipInfo("link")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(symlink, "w") as zf:
            zf.writestr(info, "artifact/raw.json")
        errors = validate_zip_archive_structure(symlink)
        assert "ZIP_SYMLINK_FORBIDDEN:link" in errors, errors

    print("S26_C_STRICT_ZIP_CERTIFICATION_PASS positive=1 duplicate=1 case_collision=1 traversal=1 symlink=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

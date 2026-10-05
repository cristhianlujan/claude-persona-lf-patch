#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_migration_assign_version.py"
spec = importlib.util.spec_from_file_location("lf_migration_assign_version", TARGET)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
assert spec.loader is not None
spec.loader.exec_module(module)


def main() -> int:
    checks = 0

    # UTC now is above both surfaces.
    assert module.choose_version(
        current_version="20261005200000",
        main_max_version="20261005201000",
        ledger_max_version="20261005202000",
        utc_now_version="20261005203000",
    ) == "20261005203000"
    checks += 1

    # Floor is ahead of now -> floor + 1 second.
    assert module.choose_version(
        current_version="20261005200000",
        main_max_version="20261005201000",
        ledger_max_version="20261005202000",
        utc_now_version="20261005201500",
    ) == "20261005202001"
    checks += 1

    # Ledger can be the floor.
    assert module.choose_version(
        current_version="20261005200000",
        main_max_version="20261005201000",
        ledger_max_version="20261005202500",
        utc_now_version="20261005202000",
    ) == "20261005202501"
    checks += 1

    # Main can be the floor.
    assert module.choose_version(
        current_version="20261005200000",
        main_max_version="20261005202500",
        ledger_max_version="20261005201000",
        utc_now_version="20261005202000",
    ) == "20261005202501"
    checks += 1

    # Idempotent retry: already strictly above both is untouched.
    assert module.choose_version(
        current_version="20261005210000",
        main_max_version="20261005202500",
        ledger_max_version="20261005203000",
        utc_now_version="20261005204000",
    ) == "20261005210000"
    checks += 1

    # Rename preserves bytes.
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source = root / "20261005200000_probe.sql"
        source.write_bytes(b"select 1;\n")
        result = module.assign_path(
            source,
            main_max_version="20261005202500",
            ledger_max_version="20261005203000",
            utc_now_version="20261005204000",
        )
        assert result.changed
        assert result.new_path.name == "20261005204000_probe.sql"
        assert result.new_path.read_bytes() == b"select 1;\n"
        assert not source.exists()
    checks += 1

    # Retry is no-op and leaves same path.
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source = root / "20261005210000_probe.sql"
        source.write_bytes(b"select 1;\n")
        result = module.assign_path(
            source,
            main_max_version="20261005202500",
            ledger_max_version="20261005203000",
            utc_now_version="20261005204000",
        )
        assert not result.changed
        assert result.new_path == source
        assert source.read_bytes() == b"select 1;\n"
    checks += 1

    # Target collision fails closed.
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source = root / "20261005200000_probe.sql"
        target = root / "20261005204000_probe.sql"
        source.write_text("select 1;\n", encoding="utf-8")
        target.write_text("select 2;\n", encoding="utf-8")
        try:
            module.assign_path(
                source,
                main_max_version="20261005202500",
                ledger_max_version="20261005203000",
                utc_now_version="20261005204000",
            )
        except FileExistsError as exc:
            assert str(exc).startswith("MIGRATION_TARGET_COLLISION:")
        else:
            raise AssertionError("collision accepted")
    checks += 1

    print(f"PASS_MIGRATION_ASSIGN_VERSION_TESTS={checks}/8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

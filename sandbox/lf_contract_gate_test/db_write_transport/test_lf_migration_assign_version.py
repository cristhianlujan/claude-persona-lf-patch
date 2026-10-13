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
        current_version="20261005204500",
        main_max_version="20261005202500",
        ledger_max_version="20261005203000",
        utc_now_version="20261005204000",
    ) == "20261005204500"
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
        source = root / "20261005204500_probe.sql"
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


    # Future clock skew: cap a +2h candidate to UTC now when floor is past.
    assert module.choose_version(
        current_version="20261005120000",
        main_max_version="20261005090000",
        ledger_max_version="20261005100000",
        utc_now_version="20261005100000",
    ) == "20261005100001"
    checks += 1

    # A +2h candidate with a floor before UTC now is assigned exactly at now.
    assert module.choose_version(
        current_version="20261005140000",
        main_max_version="20261005090000",
        ledger_max_version="20261005100000",
        utc_now_version="20261005120000",
    ) == "20261005120000"
    checks += 1

    # A future floor advances by exactly one second, not by hours.
    assert module.choose_version(
        current_version="20261005170000",
        main_max_version="20261005140000",
        ledger_max_version="20261005163004",
        utc_now_version="20261005120000",
    ) == "20261005163005"
    checks += 1

    # Within +5 minutes skew, an above-floor retry stays unchanged.
    assert module.choose_version(
        current_version="20261005120500",
        main_max_version="20261005110000",
        ledger_max_version="20261005115900",
        utc_now_version="20261005120000",
    ) == "20261005120500"
    checks += 1

    # Beyond the +15m boundary even if above floor must be clamped.
    assert module.choose_version(
        current_version="20261005121600",
        main_max_version="20261005110000",
        ledger_max_version="20261005115900",
        utc_now_version="20261005120000",
    ) == "20261005120000"
    checks += 1

    # Adding a second at midnight must roll over to the next calendar day.
    assert module.choose_version(
        current_version="20261015020000",
        main_max_version="20261013000000",
        ledger_max_version="20261013235959",
        utc_now_version="20261013120000",
    ) == "20261014000000"
    checks += 1

    # Never return at or below the maximum known version.
    cases = [
        ("20261005110000", "20261005100000", "20261005103000", "20261005120000"),
        ("20261005170000", "20261005140000", "20261005163004", "20261005120000"),
        ("20261005204500", "20261005202500", "20261005203000", "20261005204000"),
    ]
    for current, main, ledger, now in cases:
        result = module.choose_version(
            current_version=current,
            main_max_version=main,
            ledger_max_version=ledger,
            utc_now_version=now,
        )
        assert result > max(main, ledger), (current, main, ledger, now, result)
    checks += 1

    # CLI output includes an explicit audit reason, UTC now, and assigned value.
    import subprocess
    with tempfile.TemporaryDirectory() as td:
        source = Path(td) / "20261005140000_probe.sql"
        source.write_text("select 1;\n", encoding="utf-8")
        output = subprocess.check_output([
            sys.executable, str(TARGET), str(source),
            "--main-max", "20261005090000",
            "--ledger-max", "20261005100000",
            "--utc-now", "20261005120000",
            "--dry-run",
        ], text=True)
        assert "reason=FUTURE_VERSION_REASSIGNED" in output, output
        assert "current=20261005140000" in output, output
        assert "assigned=20261005120000" in output, output
        assert "now=20261005120000" in output, output
    checks += 1

    print(f"PASS_MIGRATION_ASSIGN_VERSION_TESTS={checks}/16")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

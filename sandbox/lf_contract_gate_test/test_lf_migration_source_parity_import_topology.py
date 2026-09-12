#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest


class LfMigrationParityImportTopologyTests(unittest.TestCase):
    def test_repo_root_importlib_loader_resolves_transport_dependency(self):
        repo_root = Path(__file__).resolve().parents[2]
        target = repo_root / "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
        code = (
            "import importlib.util; "
            f"p=r'{target}'; "
            "s=importlib.util.spec_from_file_location('lf_migration_source_parity_canary', p); "
            "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "assert m.managed('lf_input_governance_probe')"
        )
        proc = subprocess.run(
            [sys.executable, "-c", code],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)

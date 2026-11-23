"""SALY V08 B25/B28: two mutant behaviors must fail target assertions.

The mutants are written ONLY inside disposable local directories, never to
a repository file and never to a production database. They run with actual
pre-dispatch archiver source, not a fake host.
"""
from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = (HERE / "native_archive_bridge_v1.py").read_text()
TESTS = HERE / "test_native_archive_bridge_v1.py"
V07 = ROOT / "sandbox" / "creative_factory" / "queue_v07" / "native_source_preflight_v1.py"
ARCHIVER = ROOT / "sandbox" / "creative_factory" / "native_transport_capture_v1.py"


class NativeArchiveMutants(unittest.TestCase):
    def killed(self, name: str, original: str, mutant: str, test: str) -> None:
        self.assertEqual(SOURCE.count(original), 1, "mutation anchor drift")
        patched = SOURCE.replace(original, mutant)
        with tempfile.TemporaryDirectory(prefix="saly-v08-mutant-") as temp:
            root = pathlib.Path(temp)
            dest = root / "sandbox" / "creative_factory"
            (dest / "queue_v07").mkdir(parents=True)
            (dest / "queue_v08").mkdir(parents=True)
            shutil.copy2(V07, dest / "queue_v07" / V07.name)
            shutil.copy2(ARCHIVER, dest / ARCHIVER.name)
            shutil.copy2(TESTS, dest / "queue_v08" / TESTS.name)
            (dest / "queue_v08" / "native_archive_bridge_v1.py").write_text(patched)
            env = dict(os.environ)
            env["PYTHONPATH"] = str(root)
            cmd = [
                sys.executable, "-m", "unittest", "-v",
                "sandbox.creative_factory.queue_v08.test_native_archive_bridge_v1"
                + ".ArchiveBridgeTests." + test,
            ]
            r = subprocess.run(cmd, cwd=root, env=env, capture_output=True,
                               text=True, timeout=20)
        self.assertNotEqual(r.returncode, 0, "mutant survived: " + name)
        self.assertIn("AssertionError: NativeArchiveRejected not raised", r.stderr,
                      "wrong failure or a parser/import/runtime error: " + name)
        self.assertNotIn("SyntaxError", r.stderr)
        print("MUTANT_KILLED_BY_EXPECTED_ASSERTION:" + name, flush=True)

    def test_required_protected_assets_mutant(self):
        self.killed(
            "protected_assets_required",
            "set(protected_assets) == required_protected_components,",
            "True,",
            "test_required_protected_missing",
        )

    def test_private_archive_parent_mutant(self):
        self.killed(
            "private_archive_parent",
            "and (stat.S_IMODE(out.parent.stat().st_mode) & 0o077) == 0,",
            "and True,",
            "test_world_readable_destination_parent_denied",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

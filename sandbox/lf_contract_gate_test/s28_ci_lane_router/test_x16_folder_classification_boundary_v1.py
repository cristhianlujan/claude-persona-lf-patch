from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import lf_ci_lane_router  # noqa: E402

EXCEPTIONS_PATH = HERE / "lf_x16_folder_classification_exceptions_v1.json"


def evaluate_folder_paths(folder_names: list[str], exceptions: dict[str, str]) -> tuple[list[str], list[str]]:
    unknown: list[str] = []
    stale: list[str] = []
    seen: set[str] = set()
    for name in sorted(set(folder_names)):
        path = f"sandbox/lf_contract_gate_test/{name}/"
        seen.add(path)
        probe = f"{path}__x16_folder_probe__.py"
        decision = lf_ci_lane_router.classify([probe])
        if decision.mode == "CLASSIFICATION_REQUIRED":
            if path not in exceptions or not exceptions[path].strip():
                unknown.append(path)
        elif path in exceptions:
            stale.append(path)
    stale.extend(sorted(set(exceptions) - seen))
    return unknown, stale


class X16FolderClassificationBoundaryTest(unittest.TestCase):
    def test_every_existing_first_level_folder_is_classified_or_documented(self):
        data = json.loads(EXCEPTIONS_PATH.read_text(encoding="utf-8"))
        self.assertEqual(data.get("schema_version"), "LF_X16_FOLDER_CLASSIFICATION_EXCEPTIONS_V1")
        rows = data.get("exceptions")
        self.assertIsInstance(rows, list)
        exceptions: dict[str, str] = {}
        for row in rows:
            self.assertEqual(set(row), {"path", "reason"})
            self.assertIsInstance(row["path"], str)
            self.assertTrue(row["reason"].strip())
            self.assertNotIn(row["path"], exceptions)
            exceptions[row["path"]] = row["reason"]

        scan_root = ROOT / "sandbox/lf_contract_gate_test"
        folder_names = sorted(path.name for path in scan_root.iterdir() if path.is_dir())
        unknown, stale = evaluate_folder_paths(folder_names, exceptions)
        self.assertEqual(unknown, [], f"new unregistered folders: {unknown}")
        self.assertEqual(stale, [], f"remove exceptions for now-classified or removed folders: {stale}")

    def test_new_unregistered_folder_fails_closed(self):
        path = "sandbox/lf_contract_gate_test/x16_new_folder_canary/"
        decision = lf_ci_lane_router.classify([path + "probe.py"])
        self.assertEqual(decision.mode, "CLASSIFICATION_REQUIRED")
        unknown, _ = evaluate_folder_paths(["x16_new_folder_canary"], {})
        self.assertEqual(unknown, [path])


if __name__ == "__main__":
    unittest.main(verbosity=2)

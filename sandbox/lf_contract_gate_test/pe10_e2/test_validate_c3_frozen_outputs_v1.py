import json
import shutil
import tempfile
import unittest
from pathlib import Path

from validate_c3_frozen_outputs_v1 import validate

ROOT = Path(__file__).parents[3] / "docs/profile_updater/experiments/pe10_e2/c3_cleanroom"


class FrozenOutputValidatorTests(unittest.TestCase):
    def _copy(self):
        d = Path(tempfile.mkdtemp())
        shutil.copytree(ROOT, d / "c3_cleanroom")
        return d / "c3_cleanroom"

    def test_positive_full_data(self):
        r = validate(ROOT / "frozen_run")
        self.assertEqual(r["status"], "PASS")
        self.assertTrue(r["same_common_p0"])

    def test_tampered_raw_is_rejected(self):
        c = self._copy()
        p = c / "frozen_run/b29/RAW_B29_INNOVATION.md"
        p.write_text(p.read_text() + "x")
        with self.assertRaises(AssertionError):
            validate(c / "frozen_run")

    def test_extra_file_is_rejected(self):
        c = self._copy()
        (c / "frozen_run/b18/extra.txt").write_text("x")
        with self.assertRaises(AssertionError):
            validate(c / "frozen_run")

    def test_different_common_envelope_is_rejected(self):
        c = self._copy()
        p = c / "COMMON_P0_INPUT_ENVELOPE_V1.json"
        d = json.loads(p.read_text())
        d["source_cutoff_utc"] = "2026-10-16T00:00:00Z"
        p.write_text(json.dumps(d, indent=2))
        with self.assertRaises(AssertionError):
            validate(c / "frozen_run")

    def test_unlisted_denylist_exposure_is_rejected(self):
        c = self._copy()
        m = c / "frozen_run/C3_FROZEN_OUTPUT_MANIFEST_V1.json"
        d = json.loads(m.read_text())
        d["known_exceptions"]["denylist_exposure_files"] = []
        m.write_text(json.dumps(d))
        with self.assertRaises(AssertionError):
            validate(c / "frozen_run")


if __name__ == "__main__":
    unittest.main()

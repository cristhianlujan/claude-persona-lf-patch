import json
import shutil
import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent))
import validate_c4_evaluation_v1 as v

SRC = Path(__file__).resolve().parents[3] / "docs/profile_updater/experiments/pe10_e2/c4_evaluation"


class T(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        shutil.copytree(SRC, self.d / "c", dirs_exist_ok=True)
        self.c = self.d / "c"

    def tearDown(self):
        shutil.rmtree(self.d)

    def test_pass(self):
        self.assertEqual(v.validate(self.c)["status"], "PASS")

    def test_tampered_candidate_fails(self):
        p = self.c / "CANDIDATE_X1.md"
        p.write_bytes(p.read_bytes() + b"x")
        with self.assertRaises(AssertionError):
            v.validate(self.c)

    def test_mapping_change_fails(self):
        p = self.c / "C4_BLIND_MAPPING_COORDINATOR_ONLY.json"
        m = json.loads(p.read_text()); m["X1"], m["X2"] = m["X2"], m["X1"]
        p.write_text(json.dumps(m))
        with self.assertRaises(AssertionError):
            v.validate(self.c)

    def test_extra_file_fails(self):
        (self.c / "extra.txt").write_text("x")
        with self.assertRaises(AssertionError):
            v.validate(self.c)

    def test_wrong_raw_hash_fails(self):
        p = self.c / "C4_EVALUATION_SUMMARY_V1.json"
        s = json.loads(p.read_text()); s["evaluator_raw"]["sha256"] = "0" * 64
        p.write_text(json.dumps(s))
        with self.assertRaises(AssertionError):
            v.validate(self.c)


if __name__ == "__main__":
    unittest.main()

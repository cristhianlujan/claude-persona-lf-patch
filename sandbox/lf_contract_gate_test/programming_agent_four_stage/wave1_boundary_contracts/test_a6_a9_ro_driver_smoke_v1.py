from __future__ import annotations
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

import test_analysis_a6_a9_readonly_caller_v1 as caller_fixtures
from analysis_a6_a9_readonly_caller_v1 import READ_SQL
from run_a6_a9_ro_driver_smoke_v1 import read_json, run_smoke

class DriverSmokeTest(unittest.TestCase):
    def setUp(self):
        self.fixture=caller_fixtures.ReadOnlyCallerTests();self.fixture.setUp()

    def test_synthetic_smoke_returns_only_metadata_and_preserves_packet(self):
        original=deepcopy(self.fixture.packet)
        result=run_smoke(self.fixture.read,self.fixture.expected)
        self.assertTrue(result["read_verified"]);self.assertFalse(result["operational_admission"])
        self.assertNotIn("context",result);self.assertNotIn("resolution",result)
        self.assertEqual(self.fixture.packet,original)
        self.assertEqual(self.fixture.calls,[(READ_SQL,(self.fixture.expected.consumer_code,self.fixture.expected.subject_ref,self.fixture.expected.as_of))])

    def test_mismatch_is_not_successful_smoke(self):
        self.fixture.resolution["context_id"]="22222222-2222-2222-2222-222222222222"
        result=run_smoke(self.fixture.read,self.fixture.expected)
        self.assertFalse(result["read_verified"]);self.assertEqual(result["state"],"INPUT_REJECTED")

    def test_unknown_is_not_successful_smoke(self):
        self.fixture.resolution["state"]="UNKNOWN"
        self.assertFalse(run_smoke(self.fixture.read,self.fixture.expected)["read_verified"])

    def test_exception_never_exposes_credentials(self):
        def fail(*_):raise RuntimeError("password=synthetic-private-secret")
        result=run_smoke(fail,self.fixture.expected)
        self.assertEqual(result["state"],"ERROR");self.assertNotIn("secret",json.dumps(result))

    def test_connection_file_must_be_private_regular_and_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/"connection.json";p.write_text('{"user":"test"}');p.chmod(0o600)
            self.assertEqual(read_json(p,secret=True),{"user":"test"})
            p.chmod(0o644)
            with self.assertRaises(ValueError):read_json(p,secret=True)
            link=Path(directory)/"link";link.symlink_to(p)
            with self.assertRaises(ValueError):read_json(link,secret=True)

if __name__=="__main__":unittest.main()

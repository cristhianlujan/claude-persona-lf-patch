#!/usr/bin/env python3
"""Actual F1 verify_rows lane against a SELECT-snapshotted ledger fixture."""
import json
import os
import pathlib
import subprocess
import sys
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/"sandbox/lf_contract_gate_test/migration_source_parity"))
from reconcile_source_only import verify_rows
from migration_transport_normalization import canonical,sha256
FIXTURE=ROOT/"sandbox/lf_contract_gate_test/migration_source_parity/f1_batch1b_ledger_fixture.json"
class RealBatchLaneTests(unittest.TestCase):
    def test_exact_62(self):
        if not os.environ.get("BASE_SHA"):
            self.skipTest("Only the dedicated F1 batch lane provides exact BASE_SHA and ledger evidence")
        data=json.loads(FIXTURE.read_text())["items"]
        self.assertEqual(len(data),62)
        records={x["version"]: {"name":x["ledger_name"],"sha256":x["sha256"],"statement_count":x["statement_count"]} for x in data}
        base=os.environ["BASE_SHA"]
        def read_source(path,old=False):
            if old:
                return subprocess.check_output(["git","show",base+":"+path],cwd=ROOT).decode()
            return (ROOT/path).read_text()
        self.assertEqual(len(verify_rows(data,read_source,lambda version:records.get(version))["migrations"]),62)
        for x in data:
            self.assertEqual(x["sha256"],sha256(canonical(read_source(x["filename"]))))
        print("PASS_F1_REAL_BATCH_62_OF_62")
if __name__=="__main__":unittest.main()

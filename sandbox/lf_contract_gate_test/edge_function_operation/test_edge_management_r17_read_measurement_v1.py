"""R17 measured read collector positive, adversarial, and no-effects tests."""
import json
import unittest
from unittest.mock import patch
from edge_management_r17_read_measurement_v1 import collect, CanaryBlocked, SAMPLE_COUNT, TARGET_SLUG

def good_reply(version=23):
    return {
        "result":"EDGE_MANAGEMENT_READ_PASS", "target":TARGET_SLUG,
        "method":"GET", "version":version, "deployed":False,
        "r17_authorized":False, "cp2_runs_started":0,
    }

def fake_clock_ms(durations):
    moments=[]
    t=0.0
    for d in durations:
        moments.append(t)
        t+=d/1000
        moments.append(t)
        t+=0.0001
    v=iter(moments)
    return lambda: next(v)

class ReadMeasurementTests(unittest.TestCase):
    def test_five_gets_and_real_quantiles_without_deploy_authority(self):
        durations=[13,23,15,19,17]
        reads=[]
        def get():
            reads.append(1)
            return good_reply()
        with patch.dict("os.environ",{"GITHUB_RUN_ID":"RUN-TEST","GITHUB_SHA":"a"*40}):
            v=collect(get,fake_clock_ms(durations))
        self.assertEqual(len(reads),SAMPLE_COUNT)
        self.assertEqual(v["sample_count"],5)
        self.assertAlmostEqual(v["p50_ms"],17,places=2)
        self.assertAlmostEqual(v["p90_ms"],23,places=2)
        self.assertAlmostEqual(v["max_ms"],23,places=2)
        self.assertEqual(v["read_transport"],"PASS")
        self.assertEqual(v["r17_verdict"],"INCOMPLETE_NOT_AUTHORIZED")
        self.assertFalse(v["deploy_executed"])
        self.assertEqual(v["cp2_runs_started"],0)
        self.assertEqual(v["rollback_drill"],"NOT_EXECUTED")
        self.assertEqual(v["runtime_deploy_timing"],"NOT_MEASURED")
        self.assertEqual(v["github_run_id"],"RUN-TEST")

    def test_drift_blocks(self):
        versions=iter([23,23,24,23,23])
        with self.assertRaisesRegex(CanaryBlocked,"R17_READ_VERSION_DRIFT"):
            collect(lambda:good_reply(next(versions)),fake_clock_ms([10]*5))

    def test_forged_effect_claim_blocks(self):
        a=good_reply()
        a["deployed"]=True
        with self.assertRaisesRegex(CanaryBlocked,"R17_READ_RECEIPT_NOT_CANONICAL"):
            collect(lambda:a, fake_clock_ms([10]*5))

    def test_forged_r17_pass_claim_blocks(self):
        a=good_reply()
        a["r17_authorized"]=True
        with self.assertRaisesRegex(CanaryBlocked,"R17_READ_RECEIPT_NOT_CANONICAL"):
            collect(lambda:a, fake_clock_ms([10]*5))

    def test_cp2_jobs_claim_blocks(self):
        a=good_reply()
        a["cp2_runs_started"]=1
        with self.assertRaisesRegex(CanaryBlocked,"R17_READ_RECEIPT_NOT_CANONICAL"):
            collect(lambda:a, fake_clock_ms([10]*5))

    def test_wrong_method_blocks(self):
        a=good_reply()
        a["method"]="POST"
        with self.assertRaisesRegex(CanaryBlocked,"R17_READ_RECEIPT_NOT_CANONICAL"):
            collect(lambda:a, fake_clock_ms([10]*5))

    def test_read_timeout_above_budget_not_success(self):
        v=collect(lambda:good_reply(),fake_clock_ms([10,20,30,40,21000]))
        self.assertFalse(v["read_within_timeout"])
        self.assertEqual(v["read_transport"],"FAIL")
        self.assertEqual(v["r17_verdict"],"INCOMPLETE_NOT_AUTHORIZED")

if __name__=="__main__":
    unittest.main()

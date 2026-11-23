"""Regression for governed social convergence before DB admission. No network or DB."""
import sys
import unittest
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from social_convergence_v1 import CandidateEngine,normalize

class TestSocialInsertPreparation(unittest.TestCase):
    def candidate(self,**kwargs):
        row=dict(business_key="GARDEN_KIDS_SFC",source="INSTAGRAM",external_ref="DdZ66MRoDLD",
            url="https://www.instagram.com/p/DdZ66MRoDLD/",event_key="alianza_universidad_pacifico",
            claim_key="visita_universidad",summary_non_personal="Visita institucional de universidad",
            claim_state="REALIZADO",published_at="2026-09-17T22:20:57Z",
            company_identity_verified=True,matching_reviewed=True,duration_ms=4012.0)
        row.update(kwargs);return row
    def engine(self):
        return CandidateEngine(datetime(2026,9,1,tzinfo=timezone.utc),
                               datetime(2026,11,23,tzinfo=timezone.utc))
    def test_retry_new_latency_same_identity(self):
        a=self.candidate(duration_ms=4012.0)
        b=self.candidate(duration_ms=5859.0)
        self.assertEqual(normalize(a)["sha256"],normalize(b)["sha256"])
        e=self.engine();self.assertEqual(e.add(a),"ADMITTED_CANDIDATE")
        self.assertEqual(e.add(b),"SAME_SOURCE_REPLAY")
        self.assertEqual(len(e.records),1)
    def test_changed_content_rejected(self):
        e=self.engine();e.add(self.candidate())
        self.assertEqual(e.add(self.candidate(summary_non_personal="Texto empresarial diferente")),
                         "SOURCE_VERSION_CONFLICT")
    def test_cross_channel_same_event_not_reinserted(self):
        e=self.engine();a=self.candidate()
        b=self.candidate(source="FACEBOOK",external_ref="fb1",
            url="https://www.facebook.com/reel/123456789/",
            published_at="2026-11-10T10:00:00Z")
        self.assertEqual(e.add(a),"ADMITTED_CANDIDATE")
        self.assertEqual(e.add(b),"CROSS_CHANNEL_DUPLICATE")
        self.assertEqual(len(e.records),1)
        self.assertEqual(len(e.concurrency),1)
    def test_unknown_date_not_admitted(self):
        e=self.engine();self.assertEqual(e.add(self.candidate(published_at=None)),"HOLD_NO_DATE")
    def test_no_false_write_receipt(self):
        e=self.engine();e.add(self.candidate())
        self.assertFalse(e.receipt()["db_write_confirmed"])

if __name__=="__main__":unittest.main()

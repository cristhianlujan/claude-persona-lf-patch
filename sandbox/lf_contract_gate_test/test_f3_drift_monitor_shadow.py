import unittest
from f3_drift_monitor_shadow import compare

class TestShadow(unittest.TestCase):
    def test_two_directions(self):
        source={"supabase/migrations/20261010000000_one.sql":"select 1;"}
        ledger={"20261010010000":{"name":"two","statements":["select 2;"]}}
        result=compare(source,ledger)
        self.assertEqual(result["counts"]["SOURCE_ONLY"],1)
        self.assertEqual(result["counts"]["LEDGER_ONLY"],1)
        self.assertTrue(result["read_only"])
    def test_match(self):
        source={"supabase/migrations/20261010000000_one.sql":"select 1;"}
        ledger={"20261010000000":{"name":"one","statements":["select 1;"]}}
        self.assertEqual(compare(source,ledger)["counts"]["MATCH"],1)
    def test_mismatch_never_fails(self):
        source={"supabase/migrations/20261010000000_one.sql":"select 2;"}
        ledger={"20261010000000":{"name":"one","statements":["select 1;"]}}
        self.assertEqual(compare(source,ledger)["counts"]["MISMATCH"],1)
if __name__=="__main__": unittest.main()

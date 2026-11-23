"""Static contract checks only. PG17 SQL/ROLLBACK tests still required before merge."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261122233000_lf_saly_social_evidence_schema_v1.sql"
CONTRACT=ROOT/"skills/ai_sales_discovery/contracts/SOCIAL_MULTIFUENTE_V1_20261122.md"

class TestSocialSchemaCandidate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql=MIG.read_text()
        cls.doc=CONTRACT.read_text()

    def test_seven_tables(self):
        self.assertEqual(self.sql.count("CREATE TABLE saly.ventas_social_"),7)

    def test_no_runtime_writer(self):
        self.assertNotIn("CREATE FUNCTION",self.sql)
        self.assertNotIn("INSERT INTO",self.sql)

    def test_no_runtime_grants(self):
        self.assertNotIn("GRANT ",self.sql)
        self.assertIn("REVOKE ALL ON TABLE",self.sql)

    def test_rls_seven(self):
        self.assertEqual(self.sql.count("ENABLE ROW LEVEL SECURITY"),7)

    def test_unique_event_per_business(self):
        self.assertIn("UNIQUE (business_key,event_key)",self.sql)

    def test_unique_channel_publication(self):
        self.assertIn("UNIQUE (business_key,source_id,external_ref)",self.sql)

    def test_unique_channel_claim(self):
        self.assertIn("UNIQUE (event_id,source_id,claim_key,claim_state)",self.sql)

    def test_cross_channel_link(self):
        self.assertIn("original_claim_id uuid",self.sql)
        self.assertIn("confirming_source_id text",self.sql)

    def test_source_authority(self):
        self.assertIn("REFERENCES saly.ventas_discovery_catalogo(catalog_version,source_id)",self.sql)

    def test_semantic_no_predictive_probability(self):
        self.assertIn("predictive_probability numeric CHECK (predictive_probability IS NULL)",self.sql)

    def test_governed_substeps(self):
        for n in range(1,14):
            self.assertIn(f"SOC-{n:02d}",self.doc)

    def test_no_false_coverage(self):
        self.assertIn("no se acreditan meses completos",self.doc.lower())

if __name__=="__main__":
    unittest.main()

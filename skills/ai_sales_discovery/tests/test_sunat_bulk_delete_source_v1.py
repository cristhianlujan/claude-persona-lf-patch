#!/usr/bin/env python3
"""Static pre-PG17 fail-closed guard for physical SUNAT bulk delete.

This is NOT a substitute for executing the migration on an isolated PG17
with positive and negative cases. It catches source drift before that test.
"""
from pathlib import Path
import unittest

SQL = (Path(__file__).resolve().parents[3] / "supabase/migrations" /
       "20261122222000_lf_saly_sunat_bulk_delete_v1.sql")

class TestBulkDeleteSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SQL.read_text(encoding="utf-8")

    def test_prerequisite_commercial_view(self):
        self.assertIn("to_regclass('saly.ventas_sunat_elegibilidad_v1') IS NULL", self.sql)

    def test_one_specific_historical_run(self):
        self.assertIn("p_run_ref IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'", self.sql)

    def test_cannot_delete_with_open_run(self):
        self.assertIn("v_run_status IS DISTINCT FROM 'HOLD'",self.sql)
        self.assertIn("v_op_status NOT IN ('CANCELLED','ABANDONED','SUPERSEDED')",self.sql)
        self.assertIn("v_op_status IS NULL",self.sql)

    def test_disabled_writer_required(self):
        self.assertIn("v_config->'enabled' IS DISTINCT FROM 'false'::jsonb",self.sql)

    def test_guard_dependent_units(self):
        self.assertIn("IF EXISTS(SELECT 1 FROM saly.ventas_unidades_operativas)",self.sql)

    def test_no_automatic_delete_on_migration(self):
        before=self.sql.split("CREATE FUNCTION saly.ventas_sunat_purge_step_v1")[0]
        self.assertNotIn("DELETE FROM saly.ventas_hallazgos",before)

    def test_limit_before_delete(self):
        self.assertIn("p_max_rows>v_limit",self.sql)
        self.assertIn("v_config->>'max_rows'",self.sql)
        self.assertIn("ORDER BY hallazgo_id LIMIT p_max_rows FOR UPDATE",self.sql)

    def test_physical_delete_limited_to_hallazgos(self):
        self.assertEqual(self.sql.count("DELETE FROM saly.ventas_hallazgos"),1)
        self.assertNotIn("TRUNCATE ",self.sql)
        self.assertNotIn("CASCADE",self.sql)

    def test_batch_atomic_receipt_and_verification(self):
        self.assertIn("UPDATE saly.ventas_sunat_purge_queue_v1 p SET removed_at=now()",self.sql)
        self.assertIn("v_target<>v_deleted OR v_target<>v_marked",self.sql)
        self.assertIn("'remaining',v_remaining",self.sql)

    def test_public_roles_cannot_execute(self):
        self.assertIn("REVOKE ALL ON FUNCTION",self.sql)
        self.assertIn("FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user",self.sql)

if __name__=="__main__":
    unittest.main()

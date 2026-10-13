#!/usr/bin/env python3
from __future__ import annotations
import unittest
import lf_db_write_transport as transport

class DBWriteTransportV22Tests(unittest.TestCase):
    def test_train_owns_execution_without_owner_request(self):
        route = transport.select_route("FUNCTION", router_operation="ACTUALIZACION_DB_LF")
        self.assertEqual(route.execution_request, "NONE_TRAIN_RESERVES_AND_CLOSES_EXECUTION")
        self.assertNotIn("OWNER", route.execution_request)
        self.assertNotIn("REQUEST_IT_FROM_OWNER", route.execution_request)

    def test_manual_fallback_is_absent_and_prohibited(self):
        decision = transport.select_transport("MIGRATION", "20261013170000_lf_test_v1.sql")
        self.assertIsNone(decision.fallback_executor)
        self.assertIn("SUPABASE_MCP_APPLY_MIGRATION", decision.forbidden)
        self.assertIn("MANUAL_LEDGER_DML", decision.forbidden)
        self.assertIn("DIRECT_MIGRATION_EXECUTOR_OUTSIDE_MERGE_TRAIN", decision.forbidden)

    def test_edit_of_applied_migration_blocks(self):
        route = transport.select_route(
            "MIGRATION", "supabase/migrations/20261013170000_lf_applied_v1.sql",
            router_operation="ACTUALIZACION_DB_LF", migration_change_status="modified",
            migration_present_in_main=True,
        )
        self.assertEqual(route.route, "BLOCK_APPLIED_MIGRATION_IMMUTABLE")
        self.assertIsNone(route.executor)
        self.assertEqual(route.steps, ("NEW_MIGRATION_FAIL_FORWARD_VIA_MERGE_TRAIN",))

    def test_rename_of_ledger_migration_blocks(self):
        route = transport.select_route(
            "MIGRATION", "supabase/migrations/20261013170001_lf_renamed_v1.sql",
            router_operation="ACTUALIZACION_DB_LF", migration_change_status="renamed",
            migration_present_in_ledger=True,
        )
        self.assertEqual(route.route, "BLOCK_APPLIED_MIGRATION_IMMUTABLE")

    def test_new_added_migration_uses_train_route(self):
        route = transport.select_route(
            "MIGRATION", "supabase/migrations/20261013170002_lf_new_v1.sql",
            router_operation="ACTUALIZACION_DB_LF", migration_change_status="added",
        )
        self.assertEqual(route.route, "MIGRATION_VIA_MERGE_TRAIN")
        self.assertEqual(route.executor, "LF_MIGRATION_MERGE_TRAIN")
        decision = transport.select_transport(
            "MIGRATION", "20261013170002_lf_new_v1.sql", migration_change_status="added",
        )
        self.assertEqual(decision.route, "MIGRATION_VIA_MERGE_TRAIN")
        self.assertIsNone(decision.fallback_executor)

if __name__ == "__main__":
    unittest.main()

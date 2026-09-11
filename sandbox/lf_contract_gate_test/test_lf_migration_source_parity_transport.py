#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import unittest
from unittest import mock

import lf_migration_source_parity as subject
import migration_transport_normalization as transport


class LfMigrationTransportParityTests(unittest.TestCase):
    def test_lf_input_governance_owner_names_are_managed(self):
        self.assertTrue(subject.managed("lf_input_governance_downstream_graph_reuse_candidate_v1"))
        self.assertTrue(subject.managed("lf_input_governance_iga_perf_repeat_rollback_v1"))
        self.assertFalse(subject.managed("input_governance_probe"))
        self.assertTrue(subject.classified("input_governance_probe"))


    def test_strategy_family_names_are_managed_fail_closed_and_parity_bound(self):
        positives = [
            "s26_profile_runtime_readiness_v1",
            "s30_c05_generic_execution_reliability_v1",
            "s30_c05_effect_guard_acl_hardening_v1",
            "s31_future_strategy_contract_v1",
            "s100_long_horizon_strategy_v1",
        ]
        for name in positives:
            with self.subTest(name=name):
                self.assertTrue(subject.managed(name))
                self.assertTrue(subject.classified(name))

        negatives = [
            "s0_invalid_strategy",
            "s01_leading_zero_strategy",
            "s30-invalid-strategy",
            "S30_uppercase_strategy",
            "strategy_s30_wrong_direction",
            "s30_",
        ]
        for name in negatives:
            with self.subTest(name=name):
                self.assertFalse(subject.managed(name))

        version = "20260911025454"
        name = "s30_c05_generic_execution_reliability_v1"
        sql = "select 30;\n"
        local = {version: (name, hashlib.sha256(subject.canonical(sql)).hexdigest(), sql)}
        remote = {version: (name, transport.direct_source_hash(sql))}
        direct_count, cli_count, comparisons = subject.evaluate_managed_transport(
            local, remote, {version: 1}
        )
        self.assertEqual((direct_count, cli_count), (1, 0))
        self.assertEqual(comparisons[version].representation, "DIRECT_SOURCE")

    def test_direct_and_cli_representations_pass(self):
        v1 = "20260907010101"
        v2 = "20260907010102"
        n1 = "lf_direct_v1"
        n2 = "lf_cli_v1"
        sql1 = "select 1;\n"
        sql2 = "-- header\n\nselect 2;\n"
        local = {
            v1: (n1, hashlib.sha256(subject.canonical(sql1)).hexdigest(), sql1),
            v2: (n2, hashlib.sha256(subject.canonical(sql2)).hexdigest(), sql2),
        }
        remote = {
            v1: (n1, transport.direct_source_hash(sql1)),
            v2: (n2, transport.cli_statement_storage_hash(sql2)),
        }
        direct_count, cli_count, comparisons = subject.evaluate_managed_transport(
            local, remote, {v1: 1, v2: 1}
        )
        self.assertEqual(direct_count, 1)
        self.assertEqual(cli_count, 1)
        self.assertEqual(comparisons[v1].representation, "DIRECT_SOURCE")
        self.assertEqual(comparisons[v2].representation, "CLI_STATEMENT_STORAGE")

    def test_statement_boundary_collision_fails_closed(self):
        version = "20260907010103"
        name = "lf_boundary_v1"
        valid = "select 1;\nselect 2;"
        mutated = "select 1\nselect 2;"
        self.assertEqual(
            transport.cli_statement_storage_hash(valid),
            transport.cli_statement_storage_hash(mutated),
        )
        local = {
            version: (
                name,
                hashlib.sha256(subject.canonical(mutated)).hexdigest(),
                mutated,
            )
        }
        remote = {version: (name, transport.cli_statement_storage_hash(valid))}
        with self.assertRaisesRegex(SystemExit, "FAIL_LF_MIGRATION_CONTENT_PARITY"):
            subject.evaluate_managed_transport(local, remote, {version: 2})

    def test_statement_count_set_must_match_remote(self):
        version = "20260907010104"
        name = "lf_count_v1"
        sql = "select 1;"
        local = {
            version: (name, hashlib.sha256(subject.canonical(sql)).hexdigest(), sql)
        }
        remote = {version: (name, transport.direct_source_hash(sql))}
        with self.assertRaisesRegex(SystemExit, "FAIL_LF_MIGRATION_STATEMENT_COUNT_SET"):
            subject.evaluate_managed_transport(local, remote, {})

    def test_name_mismatch_fails_closed(self):
        version = "20260907010105"
        sql = "select 1;"
        local = {
            version: ("lf_a", hashlib.sha256(subject.canonical(sql)).hexdigest(), sql)
        }
        remote = {version: ("lf_b", transport.direct_source_hash(sql))}
        with self.assertRaisesRegex(SystemExit, "FAIL_LF_MIGRATION_NAME_PARITY"):
            subject.evaluate_managed_transport(local, remote, {version: 1})

    def test_live_count_query_requires_explicit_pg_environment(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(SystemExit, "FAIL_LF_MIGRATION_STATEMENT_COUNT_ENV_MISSING"):
                subject.query_remote_statement_counts(["20260907010106"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

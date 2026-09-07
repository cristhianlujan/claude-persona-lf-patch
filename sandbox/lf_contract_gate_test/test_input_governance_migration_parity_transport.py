#!/usr/bin/env python3
from __future__ import annotations

import unittest

import input_governance_migration_parity_compact as input_subject
import lf_migration_source_parity as lf_subject


class MigrationParityOwnershipRoutingTests(unittest.TestCase):
    def test_lf_prefixed_input_governance_name_routes_to_lf_parity(self):
        name = "lf_input_governance_downstream_graph_reuse_candidate_v1"
        self.assertTrue(lf_subject.managed(name))
        self.assertFalse(input_subject.is_scoped(name))

    def test_non_lf_input_governance_name_remains_external_to_lf_parity(self):
        name = "input_governance_probe"
        self.assertFalse(lf_subject.managed(name))
        self.assertTrue(lf_subject.classified(name))
        self.assertTrue(input_subject.is_scoped(name))


if __name__ == "__main__":
    unittest.main(verbosity=2)

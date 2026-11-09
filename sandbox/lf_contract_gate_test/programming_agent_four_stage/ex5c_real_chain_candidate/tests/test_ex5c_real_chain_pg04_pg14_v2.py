"""EX5C real PG04-PG14 V2 chain and fail-closed N:M negatives.

Original V1 producers and tests are unchanged. This module calls original
PG04-PG10 constructors after w.install() and genuine independently named V2
producers from PG11 onward. PG12/PG14 readback tests require isolated local PG.
No tests in this file claim production authority, model inference or Testing.
"""
from __future__ import annotations

import base64
import hashlib
import json
import tempfile
import copy
import os
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import ex5c_real_world_v1 as w  # noqa: E402

w.setup_paths()
import test_pg11_integrity_chain_v1 as t11  # noqa: E402
import ex5c_real_chain_v2 as chain  # noqa: E402
from pg11_c1_diff_hygiene_candidate_v2 import (  # noqa: E402
    prepare_pg11_c1, PG11C1Blocked,
)
from pg11_c4_diff_requirement_batch_trace_candidate_v2 import (  # noqa: E402
    prepare_pg11_c4, PG11C4Blocked,
)
from pg11_c5_independent_reviewer_candidate_v2 import (  # noqa: E402
    prepare_pg11_c5 as prepare_pg11_c5_v2, PG11C5Blocked as C5V2Blocked,
)
from pg11_c5_independent_reviewer_candidate_v1 import (  # noqa: E402
    prepare_pg11_c5 as prepare_pg11_c5_v1, PG11C5Blocked as C5V1Blocked,
)
from pg11_pg10_handoff_bridge_candidate_v2 import (  # noqa: E402
    bridge_pg10_c5_to_pg11_c1, PG10PG11BridgeBlocked,
)
from pg12_disposable_postgres_readback_v2 import persist_readback as pg12_readback  # noqa: E402
from pg14_disposable_testing_readback_v2 import persist_readback as pg14_readback  # noqa: E402
from ex5c_source_truth_v2 import (check_controller_repository_boundary_v2, smoke_v3_provenance_v2, SOURCE_ONLY_EXCEPTIONS)
from pg07_ex5c_format_remediation_v3_adapter_v1 import load_v3, V3_FIXTURE, V3_SHA, EX5CV3Blocked, decode  # noqa: E402


class EX5CRealN2V2(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original_fixture = t11.fixture
        w.install()
        cls.addClassCleanup(w.uninstall)
        cls.pg11 = chain.make_pg11_v2()

    @classmethod
    def _c4(cls, *, scope=None, traces=None, c1=None, c2=None, c3=None):
        obj = cls.pg11
        return prepare_pg11_c4(
            pg11_c1=c1 or obj["c1"], pg11_c2=c2 or obj["c2"],
            pg11_c3=c3 or obj["c3"],
            declared_diff=obj["diff"],
            authorized_scope=scope if scope is not None else obj["authorization"],
            trace_observations=traces if traces is not None else obj["traces"],
        )

    def test_pg04_to_pg11_nm_real_links_are_traceable(self):
        pg = self.pg11
        self.assertEqual(pg["upstream"]["upstream"]["pg08"]["final"]["target_repo"], w.REPO)
        for stage in ("c1", "c2", "c3", "c4", "c5", "bridge"):
            self.assertIs(pg[stage]["production_authority"], False)
            self.assertIs(pg[stage]["handoff_allowed"], False)
        shared = w.J + "/reminder/InMemoryReminderRepository.java"
        scope = next(item for item in pg["authorization"] if item["path"] == shared)
        self.assertGreater(len(scope["authorized_links"]), 1)
        batches = {x["batch_ref"] for x in scope["authorized_links"]}
        self.assertTrue({"ex5c://batch/ex5c-SOL-001",
                         "ex5c://batch/ex5c-SOL-002"} <= batches)
        self.assertEqual(pg["c4"]["source_pg11_c1_sha256"], pg["c1"]["candidate_sha256"])
        self.assertEqual(pg["c5"]["source_pg11_c4_sha256"], pg["c4"]["candidate_sha256"])
        self.assertEqual(pg["bridge"]["expected_head_sha"], w.N1)
        self.assertEqual(pg["bridge"]["lineage"][-1]["head"], w.N1)
        print("EX5C_V2_PG11_NM_TWO_BATCHES_REAL_HUNKS_SOURCE_ONLY_PASS")

    def test_extra_trace_link_rejected_c4(self):
        traces = copy.deepcopy(self.pg11["traces"])
        traces[0]["links"].append({
            "requirement_ref": w.SPEC + "#FORGED",
            "batch_ref": "ex5c://batch/forged",
            "scope_ref": "ex5c://scope/forged",
            "evidence_ref": w.RUN_V3,
            "change_reason_ref": w.RUN_V3,
        })
        with self.assertRaisesRegex(PG11C4Blocked, r"^PG11_C4_LINK_NOT_AUTHORIZED_SCOPE$"):
            self._c4(traces=traces)
        print("EX5C_V2_C4_FORGED_TRACE_LINK_BLOCK")

    def test_omitted_authorized_link_rejected_c4(self):
        traces = copy.deepcopy(self.pg11["traces"])
        shared = w.J + "/reminder/InMemoryReminderRepository.java"
        row = next(item for item in traces if item["path"] == shared)
        self.assertGreater(len(row["links"]), 1)
        row["links"].pop()
        with self.assertRaisesRegex(
            PG11C4Blocked, r"^PG11_C4_V2_AUTHORIZED_LINK_UNCOVERED$"
        ):
            self._c4(traces=traces)
        print("EX5C_V2_C4_UNCOVERED_LINK_BLOCK")

    def test_rehashed_falsified_authorization_breaks_upstream_lineage(self):
        scope = copy.deepcopy(self.pg11["authorization"])
        scope[0]["authorized_links"][0]["requirement_ref"] = w.SPEC + "#FORGED"
        args = {
            "expected_base_sha": w.BASE, "expected_head_sha": w.N1,
            "declared_diff": self.pg11["diff"],
            "authorized_scope": scope,
            "residue_observations": [], "dependency_observations": [],
            "compatibility_observations": [{
                "surface": "MODULE_CONTRACT",
                "contract_ref": w.SPEC + "#lote-c",
                "baseline_ref": "github://" + w.REPO + "/tree/" + w.BASE + "/apps/time-service",
                "evidence_ref": w.RUN_V3 + "#maven_verify",
                "compatible_reported": True,
            }],
        }
        falsified = prepare_pg11_c1(**args)  # correctly rehashed by producer
        with self.assertRaisesRegex(PG11C4Blocked, r"^PG11_C4_UPSTREAM_CHAIN_DRIFT$"):
            self._c4(scope=scope, c1=falsified)
        print("EX5C_V2_C4_REHASHED_SCOPE_INCONSISTENCY_BLOCK")

    def test_duplicate_authorization_rejected_c1(self):
        scope = copy.deepcopy(self.pg11["authorization"])
        scope[0]["authorized_links"].append(copy.deepcopy(scope[0]["authorized_links"][0]))
        with self.assertRaisesRegex(
            PG11C1Blocked, r"^PG11_C1_V2_DUPLICATE_AUTHORIZED_LINK$"
        ):
            prepare_pg11_c1(
                expected_base_sha=w.BASE, expected_head_sha=w.N1,
                declared_diff=self.pg11["diff"], authorized_scope=scope,
                residue_observations=[], dependency_observations=[],
                compatibility_observations=[],
            )

    def test_head_not_in_pg08_lineage_blocks(self):
        x = self.pg11
        args = {
            "pg10_c5": x["upstream"]["c5"],
            "pg10_c4": x["upstream"]["c4"],
            "pg09_c4": x["pg09"]["c4"],
            "pg08_final": x["pg08"]["final"],
            "pg08_c1": x["pg08"]["c1"],
            "lineage_solution_ids": ["SOL-002", "SOL-001"],
            "pg11_c1": x["c1"],
            "run_binding": {
                "run_ref": x["upstream"]["c5"]["run_ref"],
                "target_repo": w.REPO,
                "base_head_sha": w.BASE,
                "expected_head_sha": w.N1,
            },
        }
        with self.assertRaisesRegex(
            PG10PG11BridgeBlocked, r"^PG10_PG11_V2_HEAD_LINEAGE_DRIFT$"
        ):
            bridge_pg10_c5_to_pg11_c1(**args)
        print("EX5C_V2_PG10_PG11_HEAD_LINEAGE_DRIFT_BLOCK")

    def test_schema_v1_to_v2_and_v2_to_v1_both_block(self):
        v1 = self.original_fixture()
        with self.assertRaisesRegex(C5V2Blocked, r"^PG11_C5_UPSTREAM_SCHEMA_INVALID$"):
            prepare_pg11_c5_v2(
                pg11_c4=v1["c4"], review_observations=v1["reviews"],
                review_policy_ref="ex5c://policy/reviewer-distinct-from-builder",
            )
        reviews = [{
            "path": rec["path"],
            "builder_principal_ref": rec["builder_principal_ref_reported"],
            "reviewer_principal_ref": rec["reviewer_principal_ref_reported"],
            "reviewer_role_ref": rec["reviewer_role_ref_reported"],
            "builder_provenance_ref": rec["builder_provenance_ref_reported"],
            "reviewer_provenance_ref": rec["reviewer_provenance_ref_reported"],
            "review_scope_ref": rec["review_scope_ref_reported"],
            "reviewer_is_builder_reported": False,
            "reviewer_independence_reported": True,
        } for rec in self.pg11["c5"]["reviews"]]
        with self.assertRaisesRegex(C5V1Blocked, r"^PG11_C5_UPSTREAM_SCHEMA_INVALID$"):
            prepare_pg11_c5_v1(
                pg11_c4=self.pg11["c4"], review_observations=reviews,
                review_policy_ref="ex5c://policy/reviewer-distinct-from-builder",
            )
        print("EX5C_V2_C5_STRICT_VERSION_BOUNDARIES_BLOCK")

    def test_pg12_v2_real_n_to_n1_git_and_identity(self):
        pg12 = chain.make_pg12_v2(self.pg11)
        self.assertEqual(pg12["c1"]["base_commit_sha_reported"], w.N)
        self.assertEqual(pg12["c1"]["candidate_commit_sha_reported"], w.N1)
        self.assertEqual(pg12["c1"]["candidate_tree_sha_reported"], pg12["v3"]["git"]["tree"])
        self.assertEqual(pg12["bridge"]["candidate_commit_sha"], w.N1)
        self.assertTrue(all(
            pg12["v2"]["snapshots"][1]["commit"] == w.N
            for _ in [0]
        ))
        self.assertIs(pg12["c4"]["persisted"], False)
        self.assertIs(pg12["c4"]["readback_matched"], False)
        print("EX5C_V2_PG12_N_TO_N1_GIT_OBJECTS_AND_SOURCE_CHAIN_PASS")

    def test_pg12_v2_disposable_postgres_readback(self):
        if not os.getenv("PG12_TEST_DSN"):
            self.skipTest("PG12_TEST_DSN missing: readback NOT VERIFIED")
        pg12 = chain.make_pg12_v2(self.pg11)
        pg12_readback(pg12["c4"])

    def test_pg13_v2_freeze_and_five_mutation_blocks(self):
        pg12 = chain.make_pg12_v2(self.pg11)
        pg13 = chain.make_pg13_v2(pg12)
        self.assertEqual(pg13["c3"]["candidate_commit_sha_reported"], w.N1)
        actual = chain.local_freeze_and_attacks()
        self.assertEqual(actual["source_commit"], w.N1)
        self.assertEqual(actual["blocked_mutation_count"], 5)
        self.assertEqual(actual["subtree_oid"], pg12["v3"]["git"]["subtree"])
        self.assertIs(actual["production_authority"], False)
        print("EX5C_V2_PG13_N1_FREEZE_FIVE_MUTATION_BLOCKS_PASS")

    def test_pg14_local_accept_and_tampered_block(self):
        pg13 = chain.make_pg13_v2(chain.make_pg12_v2(self.pg11))
        actual = chain.local_freeze_and_attacks()
        pg14 = chain.make_pg14_v2(pg13, actual)
        self.assertEqual(pg14["verdict"]["verdict"], "ACCEPT")
        self.assertEqual(pg14["blocked"]["verdict"], "BLOCK")
        self.assertFalse(pg14["verdict"]["testing_real_invoked"])
        self.assertFalse(pg14["blocked"]["testing_real_invoked"])
        self.assertIs(pg14["c3"]["handoff_allowed"], False)
        self.assertNotIn("fixture://", json.dumps(pg14["c3"], sort_keys=True))
        print("EX5C_V2_PG14_LOCAL_ACCEPT_AND_TAMPERED_DIGEST_BLOCK_PASS")

    def test_pg14_v2_disposable_postgres_accept_block_readbacks(self):
        if not os.getenv("PG14_TEST_DSN"):
            self.skipTest("PG14_TEST_DSN missing: readback NOT VERIFIED")
        pg13 = chain.make_pg13_v2(chain.make_pg12_v2(self.pg11))
        actual = chain.local_freeze_and_attacks()
        pg14 = chain.make_pg14_v2(pg13, actual)
        self.assertEqual(pg14["verdict"]["verdict"], "ACCEPT")
        self.assertEqual(pg14["blocked"]["verdict"], "BLOCK")
        pg14_readback(pg14["verdict"], pg14["blocked"])

    def test_controller_repository_dependency_executed_from_v3(self):
        result = check_controller_repository_boundary_v2()
        self.assertEqual(result["commands"][0]["exit_code"], 0)
        self.assertEqual(result["commands"][1]["exit_code"], 1)
        self.assertEqual(result["commands"][1]["findings"], [])
        self.assertFalse(result["production_authority"])
        print("EX5C_V2_PG08_CONTROLLER_INTERFACE_ONLY_GREP_PASS")

    def test_smoke_and_pricing_assumptions_are_explicit(self):
        observations = smoke_v3_provenance_v2()
        self.assertFalse(observations["process_exit_code_authenticated"])
        self.assertEqual(observations["http_steps_observed_from_v3"], 5)
        self.assertIn("pg07.cached_input_price_per_million", SOURCE_ONLY_EXCEPTIONS)
        self.assertIn("pg07.context_window_tokens", SOURCE_ONLY_EXCEPTIONS)
        self.assertIn("pg04.validation_registry", SOURCE_ONLY_EXCEPTIONS)
        print("EX5C_V2_SOURCE_ONLY_EXCEPTIONS_DECLARED_PASS")

    def test_one_v3_file_byte_mutation_blocks_even_when_bundle_is_rehashed(self):
        real = load_v3(V3_FIXTURE, V3_SHA)
        altered = copy.deepcopy(real)
        entry = next(f for f in altered["git"]["files"] if f["path"].endswith("ReminderController.java"))
        payload = bytearray(decode(entry["content_base64"]))
        payload[0] ^= 1
        entry["content_base64"] = base64.b64encode(payload).decode("ascii")
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "v3.json"
            raw = (json.dumps(altered, sort_keys=True, separators=(",", ":")) + "\n").encode()
            file.write_bytes(raw)
            with self.assertRaisesRegex(EX5CV3Blocked, "V3_GIT_BLOB_OID_BLOCK"):
                load_v3(file, hashlib.sha256(raw).hexdigest())
        print("EX5C_V2_N1_BLOB_ONE_BYTE_TAMPER_BLOCK")

    def test_v3_source_remains_unattested(self):
        v3 = load_v3(V3_FIXTURE, V3_SHA)
        self.assertEqual(v3["git"]["commit"], w.N1)
        self.assertIs(v3["production_authority"], False)
        self.assertIs(v3["receipt_authenticated"], False)


if __name__ == "__main__":
    unittest.main()

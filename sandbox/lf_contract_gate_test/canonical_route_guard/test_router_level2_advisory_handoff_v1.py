#!/usr/bin/env python3
"""Contract tests; fixtures never claim real GPT Native or profile dispatch."""
from __future__ import annotations

import copy
import hashlib
import unittest

from router_level2_advisory_handoff_v1 import prepare_handoff

REQUEST = (
    "Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B "
    "a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla."
)
EXECUTOR = "PERFIL-UI-ARCHITECT"
ROUTER = {
    "router": "ACT-0001",
    "source": "SUPABASE",
    "status": "BLOCKED",
    "blocking_code": "BLOCK_EXECUTOR_CAPABILITY_UNATTESTED",
    "operation_code": None,
    "downstream_execution_allowed": False,
    "request_sha256": hashlib.sha256(REQUEST.encode("utf-8")).hexdigest(),
    "subject_binding_state": "RESOLVED",
    "subject_candidates": [{
        "screen_code": "B2B-AUTH-001",
        "screen_state": "CANDIDATO",
        "module_code": "B2B_AUTENTICACION",
    }],
    "executor_candidates": [{
        "asset_code": EXECUTOR,
        "asset_type": "PERFIL",
        "operational_status": "READ_ONLY",
        "matching_keywords": ["pantalla"],
    }],
}
CATALOG = {
    "revision_sha256": "a" * 64,
    "subjects": {
        "B2B-AUTH-001": {
            "type": "PANTALLA",
            "active": True,
            "state": "CANDIDATO",
            "module_code": "B2B_AUTENTICACION",
        },
    },
    "executors": {
        EXECUTOR: {
            "type": "PERFIL",
            "operational_status": "READ_ONLY",
            "runtime_enabled": False,
        },
    },
    "released_capabilities": {
        "CAPABILITY_SELECTOR": {
            "release_state": "RELEASED",
            "manifest_sha256": "b" * 64,
        }
    },
}


def check(req=REQUEST, router=None, catalog=None, selection=None):
    return prepare_handoff(
        req,
        copy.deepcopy(ROUTER if router is None else router),
        copy.deepcopy(CATALOG if catalog is None else catalog),
        capability_selection=selection,
    )


class Level2AdvisoryTests(unittest.TestCase):
    def assert_blocked(self, value, code):
        self.assertEqual(value["status"], "BLOCKED")
        self.assertEqual(value["blocking_code"], code)
        self.assertIs(value["downstream_execution_allowed"], False)
        self.assertIs(value["profile_execution_authorized"], False)

    def test_original_request_is_byte_preserved_with_negations(self):
        p = check()
        self.assertEqual(p["status"], "ADVISORY_ONLY")
        self.assertEqual(p["input_literal"], REQUEST)
        self.assertEqual(p["request_sha256"], ROUTER["request_sha256"])
        self.assertIs(p["downstream_execution_allowed"], False)
        self.assertIs(p["profile_execution_authorized"], False)
        self.assertIs(p["native_runtime_executed"], False)
        self.assertIsNone(p["execution_receipt"])
        self.assertEqual(p["executor_candidates"][0]["code"], EXECUTOR)
        self.assertEqual(p["subject_candidates"][0]["code"], "B2B-AUTH-001")
        self.assertEqual(p["read_only_consultation_candidates"], [EXECUTOR])
        self.assertEqual(p["read_only_consultation_mode"], "ADVISORY_NO_EFFECTS")
        self.assertTrue(p["executor_candidates"][0]["read_only_consultation_eligible"])

    def test_runtime_disabled_does_not_block_advisory_consultation(self):
        c = copy.deepcopy(CATALOG)
        c["executors"][EXECUTOR]["runtime_enabled"] = False
        c["executors"][EXECUTOR]["documentary_status"] = "CANDIDATO"
        p = check(catalog=c)
        self.assertEqual(p["read_only_consultation_candidates"], [EXECUTOR])
        self.assertFalse(p["profile_execution_authorized"])
        self.assertFalse(p["downstream_execution_allowed"])

    def test_cancelled_profile_never_consultable(self):
        for terminal in ("CANCELADO", "ELIMINADO", "RETIRADO", "BLOQUEADO"):
            r = copy.deepcopy(ROUTER)
            c = copy.deepcopy(CATALOG)
            r["executor_candidates"][0]["operational_status"] = terminal
            c["executors"][EXECUTOR]["operational_status"] = terminal
            p = check(router=r, catalog=c)
            self.assertEqual(p["read_only_consultation_candidates"], [])
            self.assertFalse(p["executor_candidates"][0]["read_only_consultation_eligible"])
            self.assertFalse(p["downstream_execution_allowed"])

    def test_deleted_documentary_state_excludes_consultation(self):
        c = copy.deepcopy(CATALOG)
        c["executors"][EXECUTOR]["documentary_status"] = "ELIMINADO"
        p = check(catalog=c)
        self.assertEqual(p["read_only_consultation_candidates"], [])
        self.assertFalse(p["profile_execution_authorized"])

    def test_non_profile_candidates_never_consultable_as_profiles(self):
        r = copy.deepcopy(ROUTER)
        c = copy.deepcopy(CATALOG)
        r["executor_candidates"][0]["asset_type"] = "SKILL"
        c["executors"][EXECUTOR]["type"] = "SKILL"
        p = check(router=r, catalog=c)
        self.assertEqual(p["read_only_consultation_candidates"], [])

    def test_determinism(self):
        self.assertEqual(check(), check())

    def test_changed_original_request_rejected(self):
        self.assert_blocked(check(req=REQUEST+" modificación"), "BLOCK_ORIGINAL_REQUEST_DRIFT")

    def test_empty_request_rejected(self):
        self.assert_blocked(check(req=" "), "BLOCK_EMPTY_REQUEST")

    def test_wrong_router_source_rejected(self):
        r=copy.deepcopy(ROUTER)
        r["source"]="CHAT_MEMORY"
        self.assert_blocked(check(router=r), "BLOCK_ROUTER_RECEIPT_NOT_ADVISORY")

    def test_router_ready_not_relabelled_as_advisory(self):
        r=copy.deepcopy(ROUTER)
        r["status"]="READY_TO_EXECUTE"
        self.assert_blocked(check(router=r), "BLOCK_ROUTER_RECEIPT_NOT_ADVISORY")

    def test_router_allow_exec_not_silently_accepted(self):
        r=copy.deepcopy(ROUTER)
        r["downstream_execution_allowed"]=True
        self.assert_blocked(check(router=r), "BLOCK_ROUTER_RECEIPT_NOT_ADVISORY")

    def test_unsupported_router_block_rejected(self):
        r=copy.deepcopy(ROUTER)
        r["blocking_code"]="BLOCK_UNKNOWN"
        self.assert_blocked(check(router=r), "BLOCK_ROUTER_RECEIPT_NOT_ADVISORY")

    def test_unresolved_subject_can_be_frozen_without_invention(self):
        r=copy.deepcopy(ROUTER)
        r["subject_binding_state"]="UNRESOLVED"
        r["subject_candidates"]=[]
        p=check(router=r)
        self.assertEqual(p["status"], "ADVISORY_ONLY")
        self.assertEqual(p["subject_candidates"], [])
        self.assertFalse(p["downstream_execution_allowed"])

    def test_actual_router_blocked_shape_keeps_literal_without_inventing_screen(self):
        # 2026-10-16 real ACT-0001 readback: subject is UNRESOLVED
        # even though the canonical screen exists in the catalog.
        # This tests the current route shape, not a runtime handoff receipt.
        r=copy.deepcopy(ROUTER)
        r["subject_binding_state"]="UNRESOLVED"
        r.pop("subject_candidates")
        p=check(router=r)
        self.assertEqual(p["status"], "ADVISORY_ONLY")
        self.assertEqual(p["input_literal"], REQUEST)
        self.assertEqual(p["request_sha256"], ROUTER["request_sha256"])
        self.assertEqual(p["subject_binding_state"], "UNRESOLVED")
        self.assertEqual(p["subject_candidates"], [])
        self.assertEqual(p["executor_candidates"][0]["code"], EXECUTOR)
        self.assertIs(p["executor_candidates"][0]["runtime_enabled"], False)
        self.assertIs(p["downstream_execution_allowed"], False)
        self.assertIs(p["native_runtime_executed"], False)

    def test_false_unique_subject_rejected(self):
        r=copy.deepcopy(ROUTER)
        r["subject_candidates"]=[]
        self.assert_blocked(check(router=r), "BLOCK_SUBJECT_CARDINALITY_DRIFT")

    def test_screen_currentness_drift_rejected(self):
        c=copy.deepcopy(CATALOG)
        c["subjects"]["B2B-AUTH-001"]["module_code"]="OTHER"
        self.assert_blocked(check(catalog=c), "BLOCK_SUBJECT_CURRENTNESS_DRIFT")

    def test_noncanonical_screen_rejected(self):
        r=copy.deepcopy(ROUTER)
        r["subject_candidates"][0]["screen_code"]="PANTALLA-B2B-LOGIN"
        self.assert_blocked(check(router=r), "BLOCK_SUBJECT_CURRENTNESS_DRIFT")

    def test_wrong_executor_kind_rejected(self):
        r=copy.deepcopy(ROUTER)
        r["executor_candidates"][0]["asset_type"]="ADAPTER"
        self.assert_blocked(check(router=r), "BLOCK_EXECUTOR_CURRENTNESS_DRIFT")

    def test_unknown_executor_rejected(self):
        r=copy.deepcopy(ROUTER)
        r["executor_candidates"][0]["asset_code"]="UNREGISTERED"
        self.assert_blocked(check(router=r), "BLOCK_EXECUTOR_CURRENTNESS_DRIFT")

    def test_no_catalog_revision_rejected(self):
        c=copy.deepcopy(CATALOG)
        c["revision_sha256"]=""
        self.assert_blocked(check(catalog=c), "BLOCK_CATALOG_CURRENTNESS_MISSING")

    def test_capability_selection_is_only_advisory(self):
        selection={"selected_capabilities":["CAPABILITY_SELECTOR"],"fallback_state":"CLEAR"}
        p=check(selection=selection)
        self.assertEqual(p["selected_capability_candidates"], ["CAPABILITY_SELECTOR"])
        self.assertFalse(p["profile_execution_authorized"])
        self.assertFalse(p["downstream_execution_allowed"])

    def test_unreleased_capability_rejected(self):
        selection={"selected_capabilities":["NOT_CURRENT"],"fallback_state":"CLEAR"}
        self.assert_blocked(check(selection=selection), "BLOCK_CAPABILITY_RELEASE_NOT_CURRENT")

    def test_duplicate_capability_rejected(self):
        selection={"selected_capabilities":["CAPABILITY_SELECTOR","CAPABILITY_SELECTOR"],
                   "fallback_state":"MULTI"}
        self.assert_blocked(check(selection=selection), "BLOCK_CAPABILITY_SELECTION_INVALID")


if __name__ == "__main__":
    unittest.main(verbosity=2)

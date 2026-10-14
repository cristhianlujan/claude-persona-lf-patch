#!/usr/bin/env python3
"""Positive/negative checks: existing governed Router receipt -> existing Updater."""
import copy
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "skills/profile_creator/validators"))

from skills.profile_creator.validators.governed_profile_evolution_bootstrap_v1 import (
    bootstrap, git_blob_sha1, UntrustedOperationReceipt,
)

REVISION = "a" * 40
CODE = "PERFIL-QUALITY-PACK"
TARGET = "profiles/quality_pack/SKILL.md"


class BootstrapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        src = self.root / TARGET
        src.parent.mkdir(parents=True)
        src.write_text("Frozen profile source\n", encoding="utf-8")
        blob = git_blob_sha1(src.read_bytes())
        self.response = {
            "outcome": "INITIALIZED",
            "execution": {
                "operation_code": "ACTUALIZACION_PERFIL_LF",
                "target_type": "PERFIL", "target_code": CODE,
                "target_repo": "cristhianlujan/claude-persona-lf-patch",
                "target_path": TARGET, "status": "IN_PROGRESS",
                "execution_id": "EXEC-ACTUALIZACION-PERFIL-LF-OIDC-test-integration",
                "manifest": {
                    "router": "ACT-0001",
                    "governed_caller_method": "GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1",
                    "caller_repository": "cristhianlujan/claude-persona-lf-patch",
                    "runtime_write_executed": False, "github_write_executed": False,
                    "automatic_runtime_promotion": False,
                    "initial_main_revision": REVISION,
                    "initial_target_blob_sha": blob,
                },
            },
            "snapshot": {
                "operation_code": "ACTUALIZACION_PERFIL_LF",
                "target_code": CODE, "target_path": TARGET,
                "next_step": {"step_id": "router"}
            }
        }

    def tearDown(self):
        self.tmp.cleanup()

    def run_bootstrap(self, data=None, **kwargs):
        with patch("skills.profile_creator.validators.governed_profile_evolution_bootstrap_v1.evaluate_s26",
                   return_value={"decision": "NO_UPDATE_REQUIRED", "score": 13, "required": 13}):
            return bootstrap(data or self.response, self.root,
                             target_code=kwargs.get("target_code", CODE),
                             target_path=kwargs.get("target_path", TARGET),
                             checkout_sha=kwargs.get("checkout_sha", REVISION))

    def assertBlocked(self, fn, code):
        with self.assertRaisesRegex(UntrustedOperationReceipt, code):
            fn()

    def test_positive_authentic_shape_executes_existing_assessment(self):
        result=self.run_bootstrap()
        self.assertEqual(result["stage_status"],"EVIDENCE_ACQUISITION_REQUIRED")
        self.assertEqual(result["execution_id"],self.response["execution"]["execution_id"])
        self.assertEqual(result["structural_baseline"]["score"],13)
        self.assertEqual(result["profile_assessment"]["assessment_status"],"NEEDS_MORE_EVIDENCE")
        self.assertFalse(result["profile_source_write_allowed"])
        self.assertFalse(result["runtime_activation_allowed"])

    def test_no_authority_if_not_initialized(self):
        d=copy.deepcopy(self.response);d["outcome"]="READY_TO_EXECUTE"
        self.assertBlocked(lambda:self.run_bootstrap(d),"GOVERNED_UPDATE_NOT_INITIALIZED")

    def test_no_wrong_caller(self):
        d=copy.deepcopy(self.response);d["execution"]["manifest"]["governed_caller_method"]="USER_JSON"
        self.assertBlocked(lambda:self.run_bootstrap(d),"UNVERIFIED_ROUTER_OR_CALLER")

    def test_no_profile_execution_substitution(self):
        d=copy.deepcopy(self.response);d["execution"]["operation_code"]="EJECUCION_PERFIL_LF"
        self.assertBlocked(lambda:self.run_bootstrap(d),"GOVERNED_EXECUTION_IDENTITY_MISMATCH")

    def test_no_other_target(self):
        self.assertBlocked(lambda:self.run_bootstrap(target_code="PERFIL-UI-ARCHITECT"),
                           "GOVERNED_EXECUTION_IDENTITY_MISMATCH")

    def test_reject_source_drift(self):
        d=copy.deepcopy(self.response);d["execution"]["manifest"]["initial_target_blob_sha"]="b"*40
        self.assertBlocked(lambda:self.run_bootstrap(d),"PROFILE_TARGET_SOURCE_DRIFT")

    def test_reject_stale_checkout(self):
        self.assertBlocked(lambda:self.run_bootstrap(checkout_sha="b"*40),
                           "PROFILE_UPDATE_CHECKOUT_STALE")

    def test_reject_stale_next_step(self):
        d=copy.deepcopy(self.response);d["snapshot"]["next_step"]["step_id"]="github_write"
        self.assertBlocked(lambda:self.run_bootstrap(d),"GOVERNED_NEXT_STEP_NOT_ROUTER")

    def test_cannot_promote_runtime_by_request(self):
        d=copy.deepcopy(self.response);d["execution"]["manifest"]["automatic_runtime_promotion"]=True
        self.assertBlocked(lambda:self.run_bootstrap(d),"UNVERIFIED_ROUTER_OR_CALLER")

    def test_reject_non_skill_target(self):
        self.assertBlocked(lambda:self.run_bootstrap(target_path="profiles/quality_pack/README.md"),
                           "INVALID_TARGET_PATH")

if __name__=="__main__":
    unittest.main(verbosity=2)

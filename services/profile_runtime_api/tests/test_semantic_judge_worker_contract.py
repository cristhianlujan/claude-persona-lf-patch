from __future__ import annotations

import importlib.util
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
WORKER = REPO_ROOT / "services/profile_runtime_api/scripts/semantic_judge_worker.py"
SERVICE = REPO_ROOT / "services/profile_runtime_api/deploy/lf-profile-semantic-judge-worker.service"
INSTALL = REPO_ROOT / "services/profile_runtime_api/scripts/install.sh"
MIGRATION = REPO_ROOT / "supabase/migrations/20260922234500_lf_profile_semantic_judge_worker_binding_v1.sql"
BINDING = REPO_ROOT / "profiles/systemic_root_cause_repair_lf/contracts/semantic_judge_binding.json"


def _module():
    spec = importlib.util.spec_from_file_location("semantic_judge_worker_contract_test", WORKER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_semantic_judge_binding_is_explicit_and_independent() -> None:
    binding = json.loads(BINDING.read_text(encoding="utf-8"))
    assert binding["schema"] == "LF_PROFILE_SEMANTIC_JUDGE_BINDING_V1"
    assert binding["pass_verdict"] == "PASS_INDEPENDENT_SEMANTIC"
    assert binding["independence"] == {
        "separate_model_call_required": True,
        "producer_prompt_reuse_forbidden": True,
        "producer_self_verdict_forbidden": True,
    }


def test_worker_is_generic_not_m14_hardcoded() -> None:
    source = WORKER.read_text(encoding="utf-8")
    assert "EXEC-M14" not in source
    assert "MR02" not in source
    assert "semantic_judge_binding.json" in source
    assert "LlamaHTTPClient" in source
    assert '"model_call_count": 1' in source
    assert "lf_record_profile_execution_step_v1" in source
    assert "output_validate" in source


def test_worker_recomputes_candidate_identity_before_judging() -> None:
    module = _module()
    candidate = {"status": "SYSTEMIC_REPAIR_SPEC", "value": [2, 1]}
    digest = module._canonical_json_sha256(candidate)
    assert len(digest) == 64
    claimed = {
        "execution_id": "EXEC-TEST-SEMANTIC-JUDGE-001",
        "target_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        "target_path": "profiles/systemic_root_cause_repair_lf/SKILL.md",
        "manifest": {},
        "input_payload": {
            "scope_authority_packet": {"packet_version": "LF_SCOPE_AUTHORITY_PACKET_V1"},
            "scope_authority_packet_sha256": "sha256:" + "a" * 64,
        },
        "execute_payload": {
            "profile_output": candidate,
            "candidate_digest": "sha256:" + digest,
        },
        "output_payload": {"blocking_codes": [], "output_contract_result": {"status": "PASS"}},
    }
    prepared = module._prepare(claimed)
    assert prepared["candidate_sha"] == digest
    assert prepared["scope_sha"] == "a" * 64
    assert prepared["binding"]["pass_verdict"] == "PASS_INDEPENDENT_SEMANTIC"


def test_physical_service_is_installed_and_bound_from_supabase_contract() -> None:
    service = SERVICE.read_text(encoding="utf-8")
    install = INSTALL.read_text(encoding="utf-8")
    migration = MIGRATION.read_text(encoding="utf-8")
    assert "semantic_judge_worker.py --daemon" in service
    assert "PYTHONPATH=/opt/lf-profile-runtime-api/current/services/profile_runtime_api" in service
    assert "lf-profile-semantic-judge-worker.service" in install
    assert "systemctl enable lf-profile-runtime-api.service lf-profile-semantic-judge-worker.service" in install
    assert "HETZNER_INDEPENDENT_SEMANTIC_JUDGE_WORKER_V1" in migration
    assert "EXEC-M14" not in migration
    assert "profiles/*/contracts/semantic_judge_binding.json" in migration

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

DEPS_AVAILABLE = all(
    importlib.util.find_spec(name) is not None for name in ("jsonschema", "pydantic")
)

if DEPS_AVAILABLE:
    from profile_runtime_api.engine import ProfileRuntimeEngine
    from profile_runtime_api.hashing import canonical_json_sha256, sha256_text
    from profile_runtime_api.models import SemanticJudgeRequest
    from profile_runtime_api.settings import Settings


class FakeSemanticJudgeLlama:
    def __init__(self, *, complete_scope: bool = True) -> None:
        self.chat_calls = 0
        self.complete_scope = complete_scope

    def health(self) -> dict[str, Any]:
        return {"ready": True, "status": "READY", "model_ids": ["semantic-test-model"]}

    def chat(self, **kwargs: Any) -> dict[str, Any]:
        self.chat_calls += 1
        user = json.loads(kwargs["user_prompt"])
        candidate_sha = kwargs["schema"]["properties"]["candidate_sha256"]["const"]
        scope_sha = kwargs["schema"]["properties"]["scope_packet_sha256"]["const"]
        scope = user["scope_authority_packet"]
        scope_ids = []
        for key in ("authorized_requirements", "constraints", "forbidden_changes"):
            for row in scope.get(key) or []:
                scope_ids.append(row["id"])
        if not self.complete_scope:
            scope_ids = scope_ids[:-1]
        invariants = [
            "SCOPE_AUTHORITY_INTEGRITY",
            "EVIDENCE_INTEGRITY",
            "CAUSAL_CLOSURE",
            "CONTRADICTION_INTEGRITY",
            "MINIMUM_SUFFICIENT_REUSE",
            "INDEPENDENT_DECISION_CLOSURE",
            "FALSIFIABILITY_REGRESSION",
        ]
        result = {
            "verdict": "PASS_INDEPENDENT_SEMANTIC",
            "candidate_sha256": candidate_sha,
            "scope_packet_sha256": scope_sha,
            "source_refs_inspected": ["scope://packet", "candidate://exact"],
            "observed_candidate_changes": [
                {
                    "change_id": "CHG-1",
                    "action_class": "BIND",
                    "target": "runtime semantic judge",
                    "candidate_paths": ["$.implementation_delta"],
                    "statement": "Bind the semantic judge through the existing runtime.",
                    "materiality": "MATERIAL",
                    "evidence_refs": ["candidate://exact"],
                }
            ],
            "requirement_reconciliation": [
                {
                    "scope_item_id": item,
                    "disposition": "SATISFIED",
                    "reason": "Preserved by the candidate.",
                    "evidence_refs": ["scope://packet"],
                }
                for item in scope_ids
            ],
            "change_declaration_reconciliation": [
                {
                    "change_id": "CHG-1",
                    "disposition": "DECLARED_EQUIVALENT",
                    "reason": "Declared in implementation delta.",
                    "evidence_refs": ["candidate://exact"],
                }
            ],
            "scope_conformance_reconciliation": [
                {
                    "change_id": "CHG-1",
                    "disposition": "IN_SCOPE",
                    "reason": "Matches the authorized runtime repair scope.",
                    "evidence_refs": ["scope://packet"],
                }
            ],
            "invariant_results": [
                {
                    "invariant": name,
                    "result": "PASS",
                    "reason": "Evidence-bound and closed.",
                    "evidence_refs": ["candidate://exact", "scope://packet"],
                }
                for name in invariants
            ],
            "open_design_decisions_found": [],
            "unsupported_claims": [],
            "blocking_codes": [],
            "repair_instructions": [],
            "next_gate": "report_output",
        }
        return {
            "content": json.dumps(result),
            "id": "semantic-judge-1",
            "model": "semantic-test-model",
            "usage": {"prompt_tokens": 20, "completion_tokens": 20},
            "timings": {"predicted_ms": 1.0},
            "finish_reason": "stop",
            "generation_schema_sha256": "a" * 64,
            "generation_schema_policy": "CANONICAL",
        }


@unittest.skipUnless(DEPS_AVAILABLE, "runtime dependencies unavailable")
class IndependentSemanticJudgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(__file__).resolve().parents[3]
        self.settings = Settings(
            repo_root=self.repo,
            state_dir=Path(self.temp.name),
            api_token="test-token",
            source_sha="8" * 40,
        )
        self.profile_path = "profiles/systemic_root_cause_repair_lf/SKILL.md"
        content = (self.repo / self.profile_path).read_text(encoding="utf-8")
        manifest = [{"ref": self.profile_path, "content_sha256": sha256_text(content)}]
        self.source_digest = "sha256:" + canonical_json_sha256(manifest)
        self.candidate = {
            "status": "SYSTEMIC_REPAIR_SPEC",
            "profile_pack_id": "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3",
            "implementation_delta": [
                {
                    "target": "services/profile_runtime_api",
                    "action": "BIND",
                    "rationale": "Physical semantic judge wiring.",
                    "evidence_refs": ["scope://packet"],
                }
            ],
        }
        self.candidate_sha = canonical_json_sha256(self.candidate)
        self.scope_sha = "b" * 64
        self.scope = {
            "packet_version": "LF_SCOPE_AUTHORITY_PACKET_V1",
            "execution_id": "EXEC-SEMANTIC-TEST-001",
            "subject_ref": "profile://test",
            "authorized_requirements": [
                {"id": "REQ-1", "statement": "Wire independent judge.", "source_ref": "input://1", "materiality": "MATERIAL"}
            ],
            "constraints": [
                {"id": "CON-1", "statement": "No parallel authority.", "source_ref": "policy://1", "materiality": "BLOCKING"}
            ],
            "forbidden_changes": [
                {"id": "FORBID-1", "statement": "No automatic promotion.", "source_ref": "policy://1", "materiality": "BLOCKING"}
            ],
            "authority_precedence": [{"rank": 1, "source_ref": "input://1", "reason": "Exact execution scope."}],
            "related_context_refs": [],
            "source_refs": ["input://1", "policy://1"],
            "compiled_at": "2026-09-22T00:00:00Z",
            "canonicalization_rule": "POSTGRES_JSONB_TEXT_UTF8_SHA256_V1",
            "sha256": "sha256:" + self.scope_sha,
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def request(self, *, candidate_sha: str | None = None) -> "SemanticJudgeRequest":
        return SemanticJudgeRequest(
            request_id="11111111-2222-3333-4444-555555555555",
            execution_id="EXEC-SEMANTIC-TEST-001",
            profile_code="PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
            profile_slug="systemic_root_cause_repair_lf",
            profile_source_paths=[self.profile_path],
            profile_source_digest=self.source_digest,
            input_literal="Wire the governed independent semantic judge.",
            exact_candidate=self.candidate,
            candidate_sha256=candidate_sha or self.candidate_sha,
            scope_authority_packet=self.scope,
            scope_packet_sha256=self.scope_sha,
            deterministic_validation={"status": "PASS"},
            evidence_manifest=None,
        )

    def test_independent_pass_is_hash_bound_and_validator_accepted(self) -> None:
        client = FakeSemanticJudgeLlama()
        engine = ProfileRuntimeEngine(self.settings, llama_client=client)  # type: ignore[arg-type]
        result = engine.run_semantic_judge(self.request())["result"]
        self.assertEqual(result["status"], "PASS")
        self.assertTrue(result["canonical_quality_accepted"])
        self.assertTrue(result["producer_independence_proven"])
        self.assertEqual(result["semantic_model_call_count"], 1)
        self.assertEqual(client.chat_calls, 1)
        self.assertEqual(result["candidate_sha256"], self.candidate_sha)
        self.assertEqual(result["scope_packet_sha256"], self.scope_sha)

    def test_candidate_digest_mismatch_blocks_before_model(self) -> None:
        client = FakeSemanticJudgeLlama()
        engine = ProfileRuntimeEngine(self.settings, llama_client=client)  # type: ignore[arg-type]
        result = engine.run_semantic_judge(self.request(candidate_sha="c" * 64))["result"]
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("SEMANTIC_JUDGE_CANDIDATE_SHA_MISMATCH", result["blocking_codes"])
        self.assertEqual(client.chat_calls, 0)

    def test_incomplete_scope_reconciliation_cannot_accept_quality(self) -> None:
        client = FakeSemanticJudgeLlama(complete_scope=False)
        engine = ProfileRuntimeEngine(self.settings, llama_client=client)  # type: ignore[arg-type]
        result = engine.run_semantic_judge(self.request())["result"]
        self.assertEqual(result["status"], "FAIL")
        self.assertFalse(result["canonical_quality_accepted"])
        self.assertIn(
            "REQUIREMENT_SCOPE_COVERAGE_INCOMPLETE",
            result["semantic_result_validation"]["blocking_codes"],
        )
        self.assertEqual(client.chat_calls, 1)


if __name__ == "__main__":
    unittest.main()

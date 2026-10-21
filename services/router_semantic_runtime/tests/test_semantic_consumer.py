from __future__ import annotations

import unittest

from services.router_semantic_runtime.semantic_consumer import (
    SemanticConsumerBlocked,
    consume_shadow,
    literal_sha256,
    normalize_result,
)


def request_fixture() -> dict:
    literal = "Actualizar ACT-0053 pero no ACT-0052 solo si sigue CURRENT"
    return {
        "schema_version": "LF_ROUTER_SEMANTIC_REQUEST_V1",
        "router": "ACT-0001",
        "literal_request": literal,
        "request_sha256": literal_sha256(literal),
        "reference_kind": "CANONICAL_ASSET",
        "candidate_subjects": [
            {"asset_code": "ACT-0053", "asset_type": "SKILL"},
            {"asset_code": "ACT-0052", "asset_type": "SKILL"},
        ],
        "positive_target_refs": [],
        "excluded_target_refs": ["ACT-0052"],
        "allowed_scope": ["ACT-0053", "ACT-0052"],
        "forbidden_scope": ["ACT-0052"],
        "conditions": [{"kind": "ONLY_IF", "value": "CURRENT"}],
        "source_currentness": {
            "status": "CURRENT",
            "router_source_md5": "8cffdd7403c0ae40d5db19890ea4f944",
            "authority": "ACT-0001_DB_CURRENT",
        },
    }


def resolved_draft() -> dict:
    return {
        "decision": "RESOLVED",
        "positive_target_refs": ["ACT-0053"],
        "excluded_target_refs": ["ACT-0052"],
        "allowed_scope": ["ACT-0053"],
        "forbidden_scope": ["ACT-0052"],
        "conditions": [{"kind": "ONLY_IF", "value": "CURRENT"}],
        "material_ambiguities": [],
        "clarification_question": None,
    }


class Specialist:
    def __init__(self, value: dict):
        self.value = value
        self.calls = 0

    def normalize(self, _request: dict) -> dict:
        self.calls += 1
        return dict(self.value)


class SemanticShadowConsumerTest(unittest.TestCase):
    def test_resolved_result_is_revalidated_then_router_rederives(self) -> None:
        request = request_fixture()
        specialist = Specialist(resolved_draft())
        resume_calls = []
        route_calls = []

        def resume(req, result):
            resume_calls.append((req, result))
            return {
                "schema_version": "LF_ROUTER_SEMANTIC_RESUME_VALIDATION_V1",
                "status": "VALID",
                "router_resume_allowed": True,
                "route_authority": False,
                "effect_authority": False,
                "downstream_execution_allowed": False,
                "next_action": "ACT0001_REDERIVE_ROUTE_AND_AUTHORITY",
            }

        def rederive(literal):
            route_calls.append(literal)
            return {"status": "READY_TO_EXECUTE", "router": "ACT-0001", "operation_code": "TEST_ONLY"}

        out = consume_shadow(
            request, specialist=specialist, resume_validator=resume, router_rederive=rederive
        )
        self.assertEqual(out["status"], "SHADOW_REDERIVED")
        self.assertEqual(out["next_action"], "OBSERVE_ONLY_NO_EFFECT")
        self.assertFalse(out["route_authority"])
        self.assertFalse(out["effect_authority"])
        self.assertFalse(out["downstream_execution_allowed"])
        self.assertEqual(route_calls, [request["literal_request"]])
        self.assertEqual(len(resume_calls), 1)
        self.assertEqual(specialist.calls, 1)
        self.assertEqual(len(out["semantic_result"]["semantic_receipt_sha256"]), 64)

    def test_material_ambiguity_asks_one_question_without_rederive(self) -> None:
        request = request_fixture()
        draft = resolved_draft() | {
            "decision": "CLARIFICATION_REQUIRED",
            "positive_target_refs": [],
            "allowed_scope": ["ACT-0053"],
            "material_ambiguities": [{"field": "ACT-0053", "reason": "version ambiguous"}],
            "clarification_question": "¿Debo usar la versión vigente de ACT-0053?",
        }
        route_calls = []
        out = consume_shadow(
            request,
            specialist=Specialist(draft),
            resume_validator=lambda _q, _r: {
                "status": "VALID",
                "router_resume_allowed": False,
                "route_authority": False,
                "effect_authority": False,
                "downstream_execution_allowed": False,
                "next_action": "CALLER_INTERACTION_REQUIRED",
            },
            router_rederive=lambda literal: route_calls.append(literal) or {},
        )
        self.assertEqual(out["status"], "WAITING_CLARIFICATION")
        self.assertEqual(out["caller_interaction"]["question_count"], 1)
        self.assertFalse(out["caller_interaction"]["effect_authority"])
        self.assertEqual(route_calls, [])

    def test_specialist_cannot_add_candidate(self) -> None:
        draft = resolved_draft() | {"positive_target_refs": ["ACT-9999"]}
        with self.assertRaisesRegex(SemanticConsumerBlocked, "TARGET_OUTSIDE_ROUTER_CANDIDATES"):
            normalize_result(request_fixture(), draft)

    def test_specialist_cannot_drop_exclusion(self) -> None:
        draft = resolved_draft() | {"excluded_target_refs": []}
        with self.assertRaisesRegex(SemanticConsumerBlocked, "EXCLUSION_DROPPED"):
            normalize_result(request_fixture(), draft)

    def test_specialist_cannot_widen_scope(self) -> None:
        draft = resolved_draft() | {"allowed_scope": ["ACT-0053", "ACT-9999"]}
        with self.assertRaisesRegex(SemanticConsumerBlocked, "SCOPE_WIDENED"):
            normalize_result(request_fixture(), draft)

    def test_specialist_cannot_return_operation_or_effect_authority(self) -> None:
        for field, value in (
            ("operation_code", "ACTUALIZACION_DB_LF"),
            ("executor", "service_role"),
            ("effect_authority", True),
            ("downstream_execution_allowed", True),
            ("route_authority", True),
        ):
            with self.subTest(field=field):
                with self.assertRaisesRegex(SemanticConsumerBlocked, "AUTHORITY_FIELD_FORBIDDEN"):
                    normalize_result(request_fixture(), resolved_draft() | {field: value})

    def test_stale_source_blocks_before_specialist(self) -> None:
        request = request_fixture()
        request["source_currentness"]["status"] = "STALE"
        specialist = Specialist(resolved_draft())
        with self.assertRaisesRegex(SemanticConsumerBlocked, "SOURCE_NOT_CURRENT"):
            consume_shadow(
                request,
                specialist=specialist,
                resume_validator=lambda _q, _r: {},
                router_rederive=lambda _literal: {},
            )
        self.assertEqual(specialist.calls, 0)

    def test_invalid_resume_never_rederives(self) -> None:
        calls = []
        out = consume_shadow(
            request_fixture(),
            specialist=Specialist(resolved_draft()),
            resume_validator=lambda _q, _r: {
                "status": "BLOCKED",
                "router_resume_allowed": False,
                "route_authority": False,
                "effect_authority": False,
                "downstream_execution_allowed": False,
                "next_action": "STAY_BLOCKED",
            },
            router_rederive=lambda literal: calls.append(literal) or {},
        )
        self.assertEqual(out["status"], "BLOCKED")
        self.assertEqual(calls, [])

    def test_valid_resume_with_claimed_authority_is_rejected(self) -> None:
        with self.assertRaisesRegex(SemanticConsumerBlocked, "AUTHORITY_CONTRACT_MISMATCH"):
            consume_shadow(
                request_fixture(),
                specialist=Specialist(resolved_draft()),
                resume_validator=lambda _q, _r: {
                    "status": "VALID",
                    "router_resume_allowed": True,
                    "route_authority": True,
                    "effect_authority": False,
                    "downstream_execution_allowed": False,
                    "next_action": "ACT0001_REDERIVE_ROUTE_AND_AUTHORITY",
                },
                router_rederive=lambda _literal: {},
            )

    def test_conditions_cannot_be_weakened(self) -> None:
        draft = resolved_draft() | {"conditions": []}
        with self.assertRaisesRegex(SemanticConsumerBlocked, "CONDITIONS_WEAKENED"):
            normalize_result(request_fixture(), draft)


if __name__ == "__main__":
    unittest.main()

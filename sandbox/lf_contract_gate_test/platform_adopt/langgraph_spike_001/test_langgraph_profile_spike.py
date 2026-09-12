#!/usr/bin/env python3
"""Executable contract tests for LF_LANGGRAPH_SPIKE_001."""
from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
RUNTIME = REPO / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
for path in (str(RUNTIME), str(HERE)):
    if path not in sys.path:
        sys.path.insert(0, path)

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command

from langgraph_profile_spike import build_spike_graph
from profile_runtime_runner import execute_profile_runtime
from validate_profile_execution import canonical_json_sha256


FIXED_AT = "2026-09-12T05:30:00+00:00"


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class DeterministicAdapter:
    adapter_id = "SPIKE-DETERMINISTIC-ADAPTER"
    is_test_double = True

    def __init__(self, failures_before_success: int = 0, failure_type: type[Exception] = RuntimeError):
        self.calls = 0
        self.failures_before_success = failures_before_success
        self.failure_type = failure_type

    def execute(self, request: dict[str, Any]) -> dict[str, Any]:
        self.calls += 1
        if self.calls <= self.failures_before_success:
            raise self.failure_type("simulated transient")
        return {
            "response_type": "PROFILE_RUNTIME_RESPONSE_V1",
            "raw_output": {
                "artifact": "LANGGRAPH_SPIKE_PARITY",
                "profile_code": request["profile_code"],
                "semantic_delta": {
                    "decisions": [],
                    "proposals": [],
                    "rationale": ["deterministic spike"],
                    "unresolved": [],
                },
            },
            "runtime_attestation": {
                "provider": "SPIKE",
                "model_id": "NO_MODEL_CALL",
                "run_id": "SPIKE-RUN-001",
                "attested_at": FIXED_AT,
                "adapter_id": self.adapter_id,
                "request_sha256": request["request_sha256"],
                "profile_source_sha256": request["profile_source_sha256"],
                "input_sha256": request["input_sha256"],
                "operation_code": request["operation_code"],
                "profile_code": request["profile_code"],
                "profile_slug": request["profile_slug"],
            },
        }


class DeterministicVerifier:
    verifier_id = "SPIKE-DETERMINISTIC-VERIFIER"
    is_test_double = True

    def verify(self, *, request: dict[str, Any], response: dict[str, Any], adapter: Any) -> dict[str, Any]:
        response_sha = canonical_json_sha256(response)
        evidence_sha = sha256_text(
            "|".join([request["request_sha256"], response_sha, adapter.adapter_id])
        )
        return {
            "verified": True,
            "verifier_id": self.verifier_id,
            "request_sha256": request["request_sha256"],
            "response_sha256": response_sha,
            "evidence_sha256": evidence_sha,
        }


class TemporaryProviderError(Exception):
    pass


def payload(*, requires_human: bool = False) -> dict[str, Any]:
    return {
        "execution_id": "EJECUCION_PERFIL_LF:LANGGRAPH-SPIKE-001",
        "profile_code": "PERFIL-UI-ARCHITECT",
        "profile_slug": "ui_architect",
        "profile_sources": [
            {
                "ref": "profiles/ui_architect/SKILL.md",
                "content": "# UI Architect\nGoverned spiike source.",
            }
        ],
        "input_literal": "Produce a governed deterministic spike output.",
        "requires_human": requires_human,
    }


def baseline(adapter: Any, verifier: Any) -> dict[str, Any]:
    p = payload()
    return execute_profile_runtime(
        execution_id=p["execution_id"],
        profile_code=p["profile_code"],
        profile_slug=p["profile_slug"],
        profile_sources=p["profile_sources"],
        input_literal=p["input_literal"],
        adapter=adapter,
        attestation_verifier=verifier,
        allow_test_doubles=True,
    )


class LangGraphSpikeTests(unittest.TestCase):
    def test_01_exact_runtime_payload_parity_without_hitl(self) -> None:
        current_adapter = DeterministicAdapter()
        graph_adapter = DeterministicAdapter()
        verifier = DeterministicVerifier()

        current = baseline(current_adapter, verifier)
        graph = build_spike_graph(
            adapter=graph_adapter,
            attestation_verifier=verifier,
            checkpointer=InMemorySaver(),
        )
        result = graph.invoke(
            payload(),
            config={"configurable": {"thread_id": "parity-001"}},
        )

        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["runtime_result"], current)
        self.assertEqual(current_adapter.calls, 1)
        self.assertEqual(graph_adapter.calls, 1)
        self.assertTrue(all(result["post_checks"].values()))

    def test_02_preflight_is_fail_closed_before_runtime(self) -> None:
        adapter = DeterministicAdapter()
        graph = build_spiike_graph(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        bad = payload()
        bad["input_literal"] = ""
        result = graph.invoke(
            bad,
            config={"configurable": {"thread_id": "preflight-001"}},
        )
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocking_code"], "LANGGRAPH_SPIKE_PREFLIGHT_MISSING")
        self.assertEqual(adapter.calls, 0)

    def test_03_transient_provider_failure_is_retried_by_graph(self) -> None:
        adapter = DeterministicAdapter(
            failures_before_success=1,
            failure_type=TemporaryProviderError,
        )
        graph = build_spike_graph(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        result = graph.invoke(
            payload(),
            config={"configurable": {"thread_id": "retry-001"}},
        )
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(adapter.calls, 2)

    def test_04_nontransient_provider_failure_stays_blocked(self) -> None:
        adapter = DeterministicAdapter(
            failures_before_success=5,
            failure_type=ValueError,
        )
        graph = build_spike_graph(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        result = graph.invoke(
            payload(),
            config={"configurable": {"thread_id": "retry-negative-001"}},
        )
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocking_code"], "RUNTIME_ADAPTER_EXCEPTION")
        self.assertEqual(adapter.calls, 1)

    def test_05_hitl_interrupt_resumes_same_thread(self) -> None:
        adapter = DeterministicAdapter()
        graph = build_spike_graph(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
      )
        config = {"configurable": {"thread_id": "hitl-001"}}
        initial = graph.invoke(payload(requires_human=True), config=config)

        self.assertIn("__interrupt__", initial)
        self.assertEqual(adapter.calls, 0)

        resumed = graph.invoke(Command(resume=True), config=config)
        self.assertEqual(resumed["status"], "PASS")
        self.assertEqual(adapter.calls, 1)
        self.assertIn("HITL_APPROVED", resumed["orchestration_events"])

    def test_06_hitl_rejection_blocks_without_runtime(self) -> None:
        adapter = DeterministicAdapter()
        graph = build_spike_graph(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        config = {"configurable": {"thread_id": "hitl-reject-001"}}
        graph.invoke(payload(requires_human=True), config=config)
        resumed = graph.invoke(Command(resume=False), config=config)

        self.assertEqual(resumed["status"], "BLOCKED")
        self.assertEqual(resumed["blocking_code"], "LANGGRAPH_SPIKE_HITL_REJECTED")
        self.assertEqual(adapter.calls, 0)

    def test_07_checkpoints_create_replayable_state_history(self) -> None:
        saver = InMemorySaver()
        graph = build_spiike_graph(
            adapter=DeterministicAdapter(),
            attestation_verifier=DeterministicVerifier(),
            checkpointer=saver,
      )
        config = {"configurable": {"thread_id": "history-001"}}
        result = graph.invoke(payload(), config=config)
        history = list(graph.get_state_history(config))

        self.assertEqual(result["status"], "PASS")
        self.assertGreaterEqual(len(history), 4)
        self.assertTrue(any(snapshot.next == ("execute_runtime",) for snapshot in history))
        self.assertTrue(any(snapshot.next == ("post_validate",) for snapshot in history))

    def test_08_receipt_stays_owned_by_lf_runner(self) -> None:
        graph = build_spike_graph(
            adapter=DeterministicAdapter(),
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
      )
        result = graph.invoke(
            payload(),
            config={"configurable": {"thread_id": "receipt-001"}},
        )
        receipt = result["runtime_result"]["receipt"]
        self.assertEqual(receipt["operation_code"], "EJECUCION_PERFIL_LF")
        self.assertEqual(receipt["execution_origin"], "MODEL_RUNTIME")
        self.assertFalse(receipt["downstream_authorized"])
        self.assertEqual(
            receipt["receipt_sha256"],
            canonical_json_sha256(
                {k: v for k, v in receipt.items() if k != "receipt_sha256"}
            ),
        )


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(LangGraphSpikeTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("LF_LANGGRAPH_SPIKE_001_PASS 8/8")

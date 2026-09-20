#!/usr/bin/env python3
"""R02-B contract tests: LangGraph Functional API vs LF and StateGraph."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
RUNTIME = REPO / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime"
for path in (str(RUNTIME), str(HERE)):
    if path not in sys.path:
        sys.path.insert(0, path)

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command

from langgraph_functional_spike import build_functional_workflow
from langgraph_profile_spike import build_spike_graph
from test_langgraph_profile_spike import (
    DeterministicAdapter,
    DeterministicVerifier,
    TemporaryProviderError,
    baseline,
    payload,
)
from validate_profile_execution import canonical_json_sha256


class LangGraphFunctionalSpikeTests(unittest.TestCase):
    def test_01_exact_runtime_payload_parity(self) -> None:
        verifier = DeterministicVerifier()
        current = baseline(DeterministicAdapter(), verifier)
        workflow = build_functional_workflow(
            adapter=DeterministicAdapter(),
            attestation_verifier=verifier,
            checkpointer=InMemorySaver(),
        )
        result = workflow.invoke(
            payload(),
            config={"configurable": {"thread_id": "func-parity-001"}},
        )
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["runtime_result"], current)
        self.assertTrue(all(result["post_checks"].values()))

    def test_02_preflight_is_fail_closed(self) -> None:
        adapter = DeterministicAdapter()
        workflow = build_functional_workflow(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        bad = payload()
        bad["input_literal"] = ""
        result = workflow.invoke(
            bad,
            config={"configurable": {"thread_id": "func-preflight-001"}},
        )
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(
            result["blocking_code"], "LANGGRAPH_SPIKE_PREFLIGHT_MISSING"
        )
        self.assertEqual(adapter.calls, 0)

    def test_03_transient_failure_is_retried_by_task(self) -> None:
        adapter = DeterministicAdapter(
            failures_before_success=1,
            failure_type=TemporaryProviderError,
        )
        workflow = build_functional_workflow(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        result = workflow.invoke(
            payload(),
            config={"configurable": {"thread_id": "func-retry-001"}},
        )
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(adapter.calls, 2)

    def test_04_nontransient_failure_remains_blocked(self) -> None:
        adapter = DeterministicAdapter(
            failures_before_success=5,
            failure_type=ValueError,
        )
        workflow = build_functional_workflow(
            adapter=adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        result = workflow.invoke(
            payload(),
            config={"configurable": {"thread_id": "func-retry-negative-001"}},
        )
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocking_code"], "RUNTIME_ADAPTER_EXCEPTION")
        self.assertEqual(adapter.calls, 1)

    def test_05_hitl_resume_and_reject(self) -> None:
        approve_adapter = DeterministicAdapter()
        approve = build_functional_workflow(
            adapter=approve_adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        approve_config = {"configurable": {"thread_id": "func-hitl-approve"}}
        initial = approve.invoke(payload(requires_human=True), config=approve_config)
        self.assertIn("__interrupt__", initial)
        self.assertEqual(approve_adapter.calls, 0)
        resumed = approve.invoke(Command(resume=True), config=approve_config)
        self.assertEqual(resumed["status"], "PASS")
        self.assertEqual(approve_adapter.calls, 1)
        self.assertIn("HITL_APPROVED", resumed["orchestration_events"])

        reject_adapter = DeterministicAdapter()
        reject = build_functional_workflow(
            adapter=reject_adapter,
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        reject_config = {"configurable": {"thread_id": "func-hitl-reject"}}
        reject.invoke(payload(requires_human=True), config=reject_config)
        rejected = reject.invoke(Command(resume=False), config=reject_config)
        self.assertEqual(rejected["status"], "BLOCKED")
        self.assertEqual(
            rejected["blocking_code"], "LANGGRAPH_SPIKE_HITL_REJECTED"
        )
        self.assertEqual(reject_adapter.calls, 0)

    def test_06_checkpoint_history_exists(self) -> None:
        workflow = build_functional_workflow(
            adapter=DeterministicAdapter(),
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        config = {"configurable": {"thread_id": "func-history-001"}}
        result = workflow.invoke(payload(), config=config)
        history = list(workflow.get_state_history(config))
        self.assertEqual(result["status"], "PASS")
        self.assertGreaterEqual(len(history), 1)

    def test_07_receipt_stays_owned_by_lf_runner(self) -> None:
        workflow = build_functional_workflow(
            adapter=DeterministicAdapter(),
            attestation_verifier=DeterministicVerifier(),
            checkpointer=InMemorySaver(),
        )
        result = workflow.invoke(
            payload(),
            config={"configurable": {"thread_id": "func-receipt-001"}},
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

    def test_08_stategraph_and_functional_preserve_same_lf_result(self) -> None:
        verifier = DeterministicVerifier()
        graph = build_spike_graph(
            adapter=DeterministicAdapter(),
            attestation_verifier=verifier,
            checkpointer=InMemorySaver(),
        )
        functional = build_functional_workflow(
            adapter=DeterministicAdapter(),
            attestation_verifier=verifier,
            checkpointer=InMemorySaver(),
        )
        graph_result = graph.invoke(
            payload(),
            config={"configurable": {"thread_id": "api-compare-graph"}},
        )
        functional_result = functional.invoke(
            payload(),
            config={"configurable": {"thread_id": "api-compare-functional"}},
        )
        self.assertEqual(graph_result["status"], "PASS")
        self.assertEqual(functional_result["status"], "PASS")
        self.assertEqual(
            graph_result["runtime_result"], functional_result["runtime_result"]
        )
        self.assertEqual(graph_result["post_checks"], functional_result["post_checks"])
        self.assertEqual(
            graph_result["orchestration_events"],
            functional_result["orchestration_events"],
        )


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        LangGraphFunctionalSpikeTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("LF_LANGGRAPH_FUNCTIONAL_SPIKE_R02B_PASS 8/8")

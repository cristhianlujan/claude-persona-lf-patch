from __future__ import annotations

from copy import deepcopy
from dataclasses import replace
import unittest
from unittest.mock import patch

from profile_runtime_api.execution_binding import ResolvedExecutionBinding
from profile_runtime_api.hashing import canonical_json_sha256
from profile_runtime_api.llama import PersistentLlamaServerAdapter
from profile_runtime_api.models import ExecuteRequest, QueueExecuteRequest
from tests import test_engine as engine_tests
from tests.runtime_execution_binding_fixture import SyntheticExecutionBindingProvider


class MutatedProvider(SyntheticExecutionBindingProvider):
    def __init__(self, mutate):self.mutate=mutate
    def resolve(self, descriptor):
        binding=super().resolve(descriptor)
        return self.mutate(binding, descriptor)


def signed_contract_change(binding, **changes):
    contract=deepcopy(binding.execution_contract);contract.update(changes)
    contract["contract_sha256"]=canonical_json_sha256({k:v for k,v in contract.items() if k!="contract_sha256"})
    return replace(binding,execution_contract=contract,expected_contract_sha256=contract["contract_sha256"])


class ExecutionBindingTest(unittest.TestCase):
    def setUp(self):
        self.harness=engine_tests.EngineGateTest();self.harness.setUp()
    def tearDown(self):self.harness.tearDown()
    def run_case(self,provider,*,allow=True,queue=False):
        engine,_=self.harness.engine(engine_tests.valid_quality_output())
        engine.execution_binding_provider=provider;engine.allow_test_execution_bindings=allow
        task=self.harness.quality_task("bound-engine-test")
        with patch.object(engine.llama_client,"health",wraps=engine.llama_client.health) as health:
            if queue:result=engine.run_queue_execute(QueueExecuteRequest(profile=task))["result"]
            else:result=engine.run_execute(ExecuteRequest(artifact=self.harness.artifact,input_governance=self.harness.governance,profile=task))["result"]
            calls=health.call_count
        return result,engine,calls
    def rejected(self,provider,code,**kwargs):
        result,engine,health=self.run_case(provider,**kwargs)
        self.assertEqual(result["runtime_completion"]["blocking_codes"],[code])
        self.assertEqual(result["profile_contract_valid"]["status"],"NOT_EVALUATED")
        self.assertEqual(engine.llama_client.chat_calls,0);self.assertEqual(health,0)
        self.assertFalse(result["downstream_authorized"])

    def test_missing_contract_blocks_before_health_and_model_both_paths(self):
        self.rejected(None,"RUNTIME_EXECUTION_BINDING_REQUIRED")
        self.rejected(None,"RUNTIME_EXECUTION_BINDING_REQUIRED",queue=True)

    def test_synthetic_provider_forbidden_without_test_opt_in(self):
        self.rejected(SyntheticExecutionBindingProvider(),"RUNTIME_TEST_EXECUTION_BINDING_FORBIDDEN",allow=False)

    def test_provider_failure_does_not_fall_back_to_generic_runner(self):
        def fail(*_):raise RuntimeError("sensitive-test-detail")
        self.rejected(MutatedProvider(fail),"RUNTIME_EXECUTION_BINDING_RESOLUTION_FAILED")

    def test_contract_digest_tamper_rejected(self):
        def mutate(binding,_):
            binding.execution_contract["objective"]="altered without resigning";return binding
        self.rejected(MutatedProvider(mutate),"RUNTIME_EXECUTION_CONTRACT_DIGEST_MISMATCH")

    def test_wrong_request_binding_rejected(self):
        self.rejected(MutatedProvider(lambda b,_:replace(b,request_binding_sha256="c"*64)),"RUNTIME_EXECUTION_REQUEST_BINDING_MISMATCH")

    def test_resigned_wrong_context_run_or_profile_rejected(self):
        for changes in ({"run_id":"OTHER"},{"profile_code":"OTHER"},{"context_fingerprint":"c"*64}):
            with self.subTest(changes=changes):self.rejected(MutatedProvider(lambda b,_,c=changes:signed_contract_change(b,**c)),"RUNTIME_EXECUTION_CONTRACT_CONTEXT_MISMATCH")

    def test_wrong_mode_does_not_call_model(self):
        self.rejected(MutatedProvider(lambda b,_:signed_contract_change(b,executor_mode="GPT_NATIVE")),"RUNTIME_EXECUTION_CONTRACT_MODE_MISMATCH")

    def test_structurally_invalid_resigned_contract_rejected_by_existing_wrapper(self):
        self.rejected(MutatedProvider(lambda b,_:signed_contract_change(b,allowed_actions=[])),"EXECUTION_CONTRACT_INVALID")

    def test_wrong_adapter_identity_rejected_before_model(self):
        with patch.object(PersistentLlamaServerAdapter,"adapter_id","unregistered-adapter"):
            self.rejected(SyntheticExecutionBindingProvider(),"EXECUTOR_ADAPTER_IDENTITY_UNREGISTERED")

    def test_request_hash_covers_mode_contract_and_sources(self):
        seen=[];original=PersistentLlamaServerAdapter.execute
        def capture(adapter,request):seen.append(deepcopy(request));return original(adapter,request)
        with patch.object(PersistentLlamaServerAdapter,"execute",capture):
            result,engine,_=self.run_case(SyntheticExecutionBindingProvider())
        request=seen[0]
        self.assertEqual(request["request_sha256"],canonical_json_sha256({k:v for k,v in request.items() if k!="request_sha256"}))
        self.assertEqual(request["executor_mode"],"REMOTE_API")
        self.assertEqual(request["execution_contract_sha256"],request["execution_contract"]["contract_sha256"])
        receipt=result["runtime_completion"]["receipt"]
        self.assertEqual(receipt["execution_contract_sha256"],request["execution_contract_sha256"])
        self.assertEqual(receipt["receipt_sha256"],canonical_json_sha256({k:v for k,v in receipt.items() if k!="receipt_sha256"}))
        self.assertTrue(result["runtime_completion"]["execution_binding"]["test_binding"])
        self.assertEqual(engine.llama_client.chat_calls,1);self.assertFalse(result["downstream_authorized"])

    def test_wrong_attested_mode_is_rejected_after_response(self):
        original=PersistentLlamaServerAdapter.execute
        def wrong_mode(adapter,request):
            response=original(adapter,request);response["runtime_attestation"]["executor_mode"]="CLAUDE_NATIVE";return response
        with patch.object(PersistentLlamaServerAdapter,"execute",wrong_mode):
            result,_,_=self.run_case(SyntheticExecutionBindingProvider())
        self.assertEqual(result["runtime_completion"]["blocking_codes"],["EXECUTOR_MODE_ATTESTATION_MISMATCH"])

    def test_changed_input_cannot_reuse_previous_binding(self):
        engine,_=self.harness.engine(engine_tests.valid_quality_output())
        class CachedProvider(SyntheticExecutionBindingProvider):
            cached=None
            def resolve(self,descriptor):
                if self.cached is None:self.cached=super().resolve(descriptor)
                return self.cached
        engine.execution_binding_provider=CachedProvider()
        task=self.harness.quality_task("cached-binding")
        first=engine.run_queue_execute(QueueExecuteRequest(profile=task))["result"]
        self.assertEqual(first["runtime_completion"]["status"],"PASS")
        changed=task.model_copy(update={"input_literal":"A different request with the same id"})
        second=engine.run_queue_execute(QueueExecuteRequest(profile=changed))["result"]
        self.assertEqual(second["runtime_completion"]["blocking_codes"],["RUNTIME_EXECUTION_REQUEST_BINDING_MISMATCH"])
        self.assertEqual(engine.llama_client.chat_calls,1)

if __name__=="__main__":unittest.main()

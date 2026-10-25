"""Synthetic authority for unit tests only; never operational provider evidence."""
from profile_runtime_api.execution_binding import ResolvedExecutionBinding
from profile_runtime_api.hashing import canonical_json_sha256


class SyntheticExecutionBindingProvider:
    is_test_double = True

    def resolve(self, descriptor):
        from profile_execution_contract import build_execution_contract
        contract = build_execution_contract(
            run_id=descriptor["execution_id"], profile_code=descriptor["profile_code"],
            profile_version="fixture-source-sha256:" + descriptor["profile_source_sha256"],
            objective="Synthetic unit-test execution, not an admitted producer",
            authorized_scope=["fixture:runtime-engine-unit-test"], current_gate="UNIT_TEST_ONLY",
            allowed_actions=["READ_TEST_INPUT", "EMIT_TEST_OUTPUT"],
            forbidden_actions=["WRITE_HOSTED_DATABASE", "ADMIT_OPERATION", "DEPLOY"],
            required_checks=["UNIT_TEST_CONTRACT", "UNIT_TEST_IDENTITY"],
            required_evidence=["unit_test_fixture"], closure_conditions=["UNIT_TEST_ASSERTIONS"],
            input_governance_ref="fixture://input-governance/not-operational",
            card_refs_and_hashes=[], adapter_ref="fixture://hetzner-local-llamacpp-http-v1",
            context_fingerprint=descriptor["context_fingerprint"],
            tool_permissions=["READ_UNIT_TEST_FIXTURE"], executor_mode="REMOTE_API",
            card_resolution={"mode":"GENERIC_SAFE","critical_authority_missing":False,
                             "unresolved_capabilities":[],"core_policy_ref":"fixture://core-policy",
                             "core_policy_sha256":"b"*64,"fallback_reason":"Synthetic test only"})
        return ResolvedExecutionBinding(
            execution_contract=contract, expected_contract_sha256=contract["contract_sha256"],
            request_binding_sha256=canonical_json_sha256(descriptor),
            source_ref="fixture://runtime-execution-binding/not-operational")

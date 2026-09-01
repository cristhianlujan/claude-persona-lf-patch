#!/usr/bin/env python3
from __future__ import annotations
from typing import Any

from build_learning_profile_precanary_request_v1 import build_precanary_request
from profile_input_governance_binding_v1 import validate_bound_governance_receipt


def build_governed_precanary_v2(*,
    request_id: str,
    execution_id: str,
    profile_code: str,
    profile_slug: str,
    profile_sources: list[dict[str,str]],
    input_literal: str,
    base_obligation_manifest: dict[str,Any],
    learning_envelope: dict[str,Any],
    input_governance_binding: dict[str,Any],
    governance_consumer: str = 'CONTEXT_PACK',
    lf_adapter_sources: list[dict[str,Any]] | None = None,
) -> dict[str,Any]:
    bound = validate_bound_governance_receipt(
        input_governance_binding,
        request_id=request_id,
        profile_code=profile_code,
        input_literal=input_literal,
        governance_consumer=governance_consumer,
    )
    if bound.get('pantalla_id') != 21 or bound.get('screen_code') != 'CHECKOUT_CUOTAS_MEDIO_PAGO':
        raise ValueError('PRODUCT_DIRECTOR_GOVERNANCE_SUBJECT_MISMATCH')
    if learning_envelope.get('consumer_id') != profile_code:
        raise ValueError('LEARNING_CONSUMER_PROFILE_MISMATCH')
    built = build_precanary_request(
        execution_id=execution_id,
        profile_code=profile_code,
        profile_slug=profile_slug,
        profile_sources=profile_sources,
        input_literal=input_literal,
        base_obligation_manifest=base_obligation_manifest,
        learning_envelope=learning_envelope,
        lf_adapter_sources=lf_adapter_sources,
    )
    built['input_governance_binding_sha256'] = bound['binding_sha256']
    built['input_governance_run_id'] = bound['run_id']
    built['input_governance_currentness'] = bound['currentness']
    built['input_governance_consumer'] = bound['governance_consumer']
    built['behavioral_runtime_allowed_by_this_builder'] = False
    built['status'] = 'GOVERNED_PRECANARY_READY_RUNTIME_EXECUTION_STILL_SEPARATE'
    return built

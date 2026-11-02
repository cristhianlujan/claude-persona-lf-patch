#!/usr/bin/env python3
"""Bounded validator/builder for the EXISTING LF profile-owned BEGIN Issue body.

Pure preparation: no RPC, Github writes, role secret, Router modification, or
claim of admission. The signed GitHub OIDC/Edge runner remains sole writer.
"""
import argparse
import hashlib
import json
import sys

SCHEMA = 'LF_ROUTER_EXECUTION_PIPELINE_V1'
BEGIN = 'LF_PROFILE_NATIVE_BEGIN_REQUEST_V1'


def nonempty(x):
    return isinstance(x, str) and bool(x.strip())


def prepare(context, mode='GPT_NATIVE'):
    if not isinstance(context, dict):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_CONTEXT_NOT_OBJECT')
    if mode not in ('GPT_NATIVE', 'CLAUDE_NATIVE'):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_EXECUTOR_MODE_INVALID')

    # Do not accept a model-made, merely plausible Gate2 object as authority.
    # Full authoritative verification is server-side in the existing Edge.
    v = context.get('semantic_validation')
    s = context.get('stage1_payload')
    gate = context.get('gate2_derivation')
    if not all(isinstance(a, dict) for a in (v, s, gate)):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_CONTEXT_INCOMPLETE')
    name = v.get('selected_profile_code')
    original = s.get('texto_original')
    result = gate.get('gate2_result')
    if not isinstance(result, dict):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_GATE2_RECEIPT_MISSING')
    if (context.get('schema_version') != SCHEMA
        or context.get('status') != 'GATE2_DERIVED_PENDING_GOVERNED_ADMISSION'
        or context.get('transport_mode') != 'CONTEXT_TRANSPORT'
        or context.get('next_action') != 'HANDOFF_CONTEXT_TO_SELECTED_PROFILE'
        or context.get('terminal') is not False
        or context.get('effect_authority') is not False
        or context.get('downstream_execution_allowed') is not False
        or s.get('schema_version') != 'LF_ROUTER_STAGE1_V2'
        or s.get('negocio_codigo') != 'LF'
        or not nonempty(original)
        or v.get('status') != 'VALID'
        or v.get('decision') != 'SELECTED'
        or not nonempty(name)
        or gate.get('status') != 'READY'
        or result.get('decision') != 'RESOLVED'
        or result.get('positive_target_refs') != [name]
        or result.get('allowed_scope') != [name]):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_GATE2_INVALID')

    # Check exact request lineage, not a substituted prompt or an old run.
    digest = hashlib.sha256(original.encode('utf-8')).hexdigest()
    if (v.get('request_sha256') != digest
        or result.get('request_sha256') != digest):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_REQUEST_SHA_MISMATCH')

    # Fail closed rather than transporting credentials by accident.
    forbidden = {'service_role', 'service_role_key', 'supabase_service_role_key',
                 'access_token', 'api_key', 'authorization', 'password',
                 'secret', 'bearer_token', 'private_key'}
    def has_secrets(x):
        if isinstance(x, dict):
            return any(str(k).lower() in forbidden or has_secrets(v) for k, v in x.items())
        if isinstance(x, list):
            return any(has_secrets(v) for v in x)
        return False
    if has_secrets(context):
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_FORBIDDEN_CREDENTIAL_FIELD')

    # Same length guard as the CURRENT GitHub runner; preserve context exactly.
    if len(json.dumps(context)) > 55000:
        raise ValueError('LF_PROFILE_NATIVE_BEGIN_CONTEXT_TOO_LARGE')
    return {'schema_version': BEGIN, 'router_context': context, 'executor_mode': mode}


def main():
    parser = argparse.ArgumentParser(description='Validate canonical LF Gate2 for governed BEGIN')
    parser.add_argument('--mode', choices=('GPT_NATIVE', 'CLAUDE_NATIVE'), default='GPT_NATIVE')
    mode = parser.parse_args().mode
    context = json.load(sys.stdin)
    print(json.dumps(prepare(context, mode), ensure_ascii=False, separators=(',', ':')))

if __name__ == '__main__':
    try:
        main()
    except (TypeError, ValueError, json.JSONDecodeError) as ex:
        print(str(ex), file=sys.stderr)
        sys.exit(2)

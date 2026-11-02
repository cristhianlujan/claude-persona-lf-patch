import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

M = Path(__file__).with_name('lf_profile_begin_payload.py')
spec = importlib.util.spec_from_file_location('lf_begin', M)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def valid():
    original = 'entra por el router y revisa login B2B LF'
    sha = hashlib.sha256(original.encode()).hexdigest()
    name = 'PERFIL-PRODUCT-DIRECTOR-LF'
    return {
        'schema_version': 'LF_ROUTER_EXECUTION_PIPELINE_V1',
        'status': 'GATE2_DERIVED_PENDING_GOVERNED_ADMISSION',
        'transport_mode': 'CONTEXT_TRANSPORT',
        'next_action': 'HANDOFF_CONTEXT_TO_SELECTED_PROFILE',
        'terminal': False, 'effect_authority': False, 'downstream_execution_allowed': False,
        'stage1_payload': {'schema_version': 'LF_ROUTER_STAGE1_V2',
                           'negocio_codigo': 'LF', 'texto_original': original},
        'semantic_validation': {'status': 'VALID', 'decision': 'SELECTED',
                                'request_sha256': sha, 'selected_profile_code': name},
        'gate2_derivation': {'status': 'READY', 'gate2_result': {
            'decision': 'RESOLVED', 'request_sha256': sha,
            'positive_target_refs': [name], 'allowed_scope': [name]}},
    }


class BeginPayloadTest(unittest.TestCase):
    def test_context_is_unchanged(self):
        x = valid()
        before = copy.deepcopy(x)
        out = module.prepare(x)
        self.assertEqual(out, {'schema_version': 'LF_PROFILE_NATIVE_BEGIN_REQUEST_V1',
                               'router_context': before, 'executor_mode': 'GPT_NATIVE'})
        self.assertIs(out['router_context'], x)

    def test_claude_native(self):
        self.assertEqual(module.prepare(valid(), 'CLAUDE_NATIVE')['executor_mode'], 'CLAUDE_NATIVE')

    def test_invalid_fields_are_rejected(self):
        scenarios = [
            (('status',), 'COMPLETED'),
            (('transport_mode',), 'DIRECT'),
            (('next_action',), 'RETURN_TO_ROUTER'),
            (('terminal',), True),
            (('effect_authority',), True),
            (('downstream_execution_allowed',), True),
            (('stage1_payload', 'schema_version'), 'LF_ROUTER_STAGE1_V1'),
            (('stage1_payload', 'negocio_codigo'), 'SALY'),
            (('semantic_validation', 'status'), 'BLOCKED'),
            (('semantic_validation', 'decision'), 'AMBIGUOUS'),
            (('semantic_validation', 'selected_profile_code'), ''),
            (('gate2_derivation', 'status'), 'BLOCKED'),
            (('gate2_derivation', 'gate2_result', 'decision'), 'BLOCKED'),
            (('gate2_derivation', 'gate2_result', 'allowed_scope'), ['OTHER_PROFILE']),
            (('gate2_derivation', 'gate2_result', 'positive_target_refs'), []),
        ]
        for path, value in scenarios:
            with self.subTest(path=path):
                c = valid()
                d = c
                for p in path[:-1]:
                    d = d[p]
                d[path[-1]] = value
                with self.assertRaises(ValueError):
                    module.prepare(c)

    def test_broken_hash_cannot_be_transported(self):
        for path in (('semantic_validation', 'request_sha256'),
                     ('gate2_derivation', 'gate2_result', 'request_sha256')):
            c = valid()
            d = c
            for p in path[:-1]: d = d[p]
            d[path[-1]] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'SHA_MISMATCH'):
                module.prepare(c)

    def test_missing_structure_has_controlled_error(self):
        for key in ('stage1_payload', 'semantic_validation', 'gate2_derivation'):
            c = valid()
            c[key] = None
            with self.assertRaisesRegex(ValueError, 'CONTEXT_INCOMPLETE'):
                module.prepare(c)
        c = valid()
        c['gate2_derivation']['gate2_result'] = None
        with self.assertRaisesRegex(ValueError, 'RECEIPT_MISSING'):
            module.prepare(c)

    def test_no_credential_transport(self):
        for value in ({'service_role': 'FAKE'}, {'nested': {'authorization': 'Bearer EXAMPLE'}},
                      {'deep': [{'api_key': 'EXAMPLE'}]}):
            c = valid()
            c['extra'] = value
            with self.assertRaisesRegex(ValueError, 'CREDENTIAL_FIELD'):
                module.prepare(c)

    def test_readonly_source_and_mode(self):
        with self.assertRaises(ValueError): module.prepare(valid(), 'service_role')
        for name in ('UPDATE lf_ops', 'lf_router_pipeline_context_profile_admit_v2('):
            self.assertNotIn(name, M.read_text())


if __name__ == '__main__': unittest.main()

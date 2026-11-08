"""Offline, source-only behavioral tests; no real judge, A3 or inventory."""
import copy
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1] / 'adapters'
spec = importlib.util.spec_from_file_location('a2_unresolved', HERE / 'unresolved_research_preview_v1.py')
impl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(impl)


def make(case='02'):
    if case == '02':
        raw = 'Necesito una vista para que las empresas entren al portal'
        op, target, cap, mention = 'IMPLEMENT', 'SCREEN', 'ENTERPRISE_PORTAL_ACCESS', 'vista para que las empresas entren al portal'
        constraint = []
        code = 'PORTAL_ENTRY_MODE_UNRESOLVED'
        statement = 'La solicitud no determina si la entrada requiere autenticación o si consiste en navegación/acceso al portal.'
        spans = [('OPERATION', 'Necesito'), ('ARTIFACT', 'vista'),
                 ('CAPABILITY', 'entren al portal'), ('ACTOR_SCOPE', 'empresas')]
    else:
        raw = 'No crees otra pantalla; usa la existente'
        op, target, cap, mention = 'REUSE', 'SCREEN', 'UNKNOWN', 'pantalla'
        constraint = ['No crees otra pantalla']
        code = 'FUNCTIONAL_CAPABILITY_UNSPECIFIED'
        statement = 'La funcionalidad de la pantalla existente no está especificada.'
        spans = [('OPERATION', 'usa la existente'), ('ARTIFACT', 'pantalla'),
                 ('ASSUMPTION', 'existente'), ('NEGATION', 'No crees otra pantalla')]
    intent = {
        'operation': {'kind': op},
        'target': {'artifact_kind': target, 'canonical_capability': cap,
                   'raw_mentions': [mention]},
        'evidence_spans': [{'dimension': kind, 'quote': quote,
                            'start': raw.index(quote), 'end': raw.index(quote)+len(quote)}
                           for kind, quote in spans],
        'material_ambiguities': [{'code': code, 'statement': statement, 'materiality': 'MATERIAL'}],
        'dimensions_to_investigate': ['EXISTING_ARTIFACT_INVENTORY', code],
    }
    digest = hashlib.sha256(raw.encode('utf-8')).hexdigest()
    return {
        'schema_version': 'A1_INTERNAL_STEP_CANDIDATE_RESULT_V1',
        'skill_code': 'PROGRAMMING_ANALYSIS_LF', 'step_code': 'A1',
        'status': 'REQUIRES_DECISION', 'business': 'LF',
        'next_capability': None, 'external_authority_verified': False,
        'operationally_integrated': False, 'effects_executed': False,
        'semantic_review_identity_verified': False,
        'interpretation_state': 'SEMANTIC_CANDIDATE_UNATTESTED',
        'semantic_reviewer_ref': 'fixture://not-an-independent-review',
        'original_request_sha256': digest,
        'semantic_candidate_sha256': impl._hash(intent),
        'intent_analysis': intent,
        'payload': {
            'objective': {'problem_statement': raw, 'desired_outcome': 'Reutilizar existente' if case=='04' else 'Acceso portal'},
            'source_refs': ['user://a1-raw-'+digest[:20]],
            'target_hints': [mention],
            'constraints': constraint,
            'ambiguities': [{'code': code, 'statement': statement,
                             'materiality': 'MATERIAL', 'resolution_state': 'OPEN'}],
        },
    }


class PendingResearchTests(unittest.TestCase):
    def test_02_access_does_not_infer_auth(self):
        r = impl.prepare(make('02'))
        self.assertEqual(r['status'], 'RESEARCH_PLAN_ONLY')
        self.assertEqual(r['research_plan']['functional_capability_hint'], 'ENTERPRISE_PORTAL_ACCESS')
        self.assertEqual(r['research_plan']['unresolved_ambiguities'][0]['code'], 'PORTAL_ENTRY_MODE_UNRESOLVED')
        self.assertEqual(r['research_plan']['source_research_tasks'][0]['priority_order'], list(impl.RESOLUTION_ORDER))
        self.assertFalse(r['a3_dispatch_allowed'])
        self.assertIsNone(r['a2_classification'])

    def test_04_reuse_and_negation_preserved(self):
        r = impl.prepare(make('04'))
        self.assertEqual(r['status'], 'RESEARCH_PLAN_ONLY')
        self.assertEqual(r['research_plan']['operation_hint'], 'REUSE')
        self.assertEqual(r['research_plan']['constraints'], ['No crees otra pantalla'])
        self.assertEqual(r['research_plan']['functional_capability_hint'], 'UNKNOWN')
        self.assertFalse(r['a2_depth_classified'])
        self.assertFalse(r['source_authenticated'])

    def test_no_mutation(self):
        x = make('04'); original = copy.deepcopy(x)
        impl.prepare(x)
        self.assertEqual(x, original)

    def test_no_semantic_judge_identity_claim(self):
        r=impl.prepare(make('02'))
        self.assertFalse(r['independent_judge_attested'])
        self.assertFalse(r['runtime_integrated'])
        self.assertIsNone(r['a3_canonical_inputs'])

    def test_status_valid_output_is_not_decision_preview(self):
        x = make('02'); x['status'] = 'VALID_OUTPUT'
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_A1_DECISION_REQUIRED'])

    def test_semantic_candidate_hash_tamper(self):
        x = make('02'); x['intent_analysis']['target']['canonical_capability']='AUTH_FLOW'
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_A1_DIGEST_MISMATCH'])

    def test_raw_request_hash_tamper(self):
        x = make('04'); x['original_request_sha256'] = '0' * 64
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_A1_DIGEST_MISMATCH'])

    def test_constraint_negation_removed(self):
        x = make('04'); x['intent_analysis']['evidence_spans'] = [s for s in x['intent_analysis']['evidence_spans'] if s['dimension']!='NEGATION']
        x['semantic_candidate_sha256']=impl._hash(x['intent_analysis'])
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_CONSTRAINT_SPAN_MISSING'])

    def test_mismatch_declared_ambiguity(self):
        x = make('02'); x['payload']['ambiguities'][0]['code'] = 'NEW_NOT_DECLARED'
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_MATERIAL_AMBIGUITY_DRIFT'])

    def test_closed_ambiguity_cannot_generate_preview(self):
        x = make('04'); x['payload']['ambiguities'][0]['resolution_state'] = 'RESOLVED_FROM_SOURCE'
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_MATERIAL_AMBIGUITY_DRIFT'])

    def test_false_authority_refused(self):
        x=make('02'); x['external_authority_verified'] = True
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_A1_FALSE_AUTHORITY'])

    def test_target_drift_refused(self):
        x=make('02'); x['payload']['target_hints'] = ['NOT_IN_RAW']
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_SOURCE_OR_CONSTRAINT_DRIFT'])

    def test_semantic_span_index_drift_refused(self):
        x=make('02'); x['intent_analysis']['evidence_spans'][0]['end'] -= 1
        x['semantic_candidate_sha256']=impl._hash(x['intent_analysis'])
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_SEMANTIC_EVIDENCE_DRIFT'])

    def test_missing_source_refs_refused(self):
        x=make('04'); x['payload']['source_refs'] = []
        self.assertEqual(impl.prepare(x)['blocking_codes'], ['A2_RESEARCH_SOURCE_OR_CONSTRAINT_DRIFT'])

    def test_cannot_escalate_owner_question_automatically(self):
        r=impl.prepare(make('04'))
        self.assertEqual(r['research_plan']['source_research_tasks'][0]['owner_decision'],
                         'ONLY_IF_MATERIAL_UNRESOLVED_AFTER_SOURCE_REVIEW')
        self.assertIsNone(r['next_step'])


if __name__ == '__main__':
    unittest.main(verbosity=2)

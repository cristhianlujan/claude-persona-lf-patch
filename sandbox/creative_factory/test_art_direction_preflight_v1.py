import copy
import unittest
from art_direction_preflight_v1 import ArtBlocked, preflight, sha


def fixture(mode='FULL_SCENE', business='DEMO', names=None):
    names = names or ['Header', 'Balance', 'Services', 'Navigation']
    text = 'Premium UI, soft background, clear hierarchy. Exact copy: Balance 100. Services. Navigation.'
    design = {'hierarchy': names}
    source = 'Registered fixed header and navigation assets; Balance 100.'
    return {'business_code': business, 'literal_request': text,
            'blueprint': {'schema_version': 'CREATIVE_VISUAL_BLUEPRINT_V1', 'brand': business, 'mode': 'PLAN_ONLY',
                          'intent': 'Design the requested asset', 'art': 'Premium clear design',
                          'hierarchy': names, 'guided': [], 'free': [],
                          'design_lock': {'LOCK': design, 'GUIDED': [], 'FREE': []}},
            'presentation': {'mode': mode, 'destination': 'Requested visual output'},
            'direction': {k: {'instruction': 'Premium UI, soft background, clear hierarchy.',
                              'rationale': 'Matches requested context', 'requirements': ['R1']}
                          for k in ('scene','style','background','typography','hierarchy','visual_impact')},
            'components': [{'name': n, 'owner': 'COMPOSITOR' if n in ('Header','Navigation') else 'NATIVE',
                            'freedom': 'LOCK', 'instruction': 'Preserve required component',
                            'copy': ['Balance 100'] if n == 'Balance' else [],
                            'source_ids': ['S1'] if n in ('Header','Navigation') else ['REQUEST'],
                            'requirements': ['R1']} for n in names],
            'sources': [{'id':'S1','business_code':business,'ref':'fixture:asset','version':'1',
                         'status':'APPROVED','text':source,'sha256':sha(source.encode())}],
            'requirements': [{'id':'R1','source':'REQUEST','quote':'Premium UI'}]}


class ArtPreflightTest(unittest.TestCase):
    def test_full_scene(self):
        p = fixture()
        r = preflight(p)
        self.assertEqual(r['status'], 'STRUCTURAL_PASS_SEMANTIC_PENDING')
        self.assertEqual(r['component_count'], 4)
        self.assertEqual(r['semantic_qa'], 'NOT_EVALUATED')
        self.assertIsNone(r['native_payload'])
        self.assertFalse(r['image_generation_allowed'])
        self.assertEqual(r, preflight(copy.deepcopy(p)))
    def test_body(self):
        self.assertEqual(preflight(fixture('BODY_ONLY', names=['Balance']))['component_count'], 1)
    def test_other_brand_other_asset(self):
        self.assertEqual(preflight(fixture('OTHER_ASSET','OTHER',['Hero']))['business_code'], 'OTHER')
    def test_negative_matrix(self):
        cases = [
            ('PLAN_FIELDS', lambda p: p.update(render_authorized=True)),
            ('BLUEPRINT_SCOPE', lambda p: p['blueprint'].update(brand='OTHER')),
            ('BLUEPRINT_LOCK_DRIFT', lambda p: p['blueprint'].update(hierarchy=['Different'])),
            ('PRESENTATION_INVALID', lambda p: p['presentation'].update(mode='PRODUCTION')),
            ('ART_DIRECTION_INCOMPLETE', lambda p: p['direction'].pop('background')),
            ('DIRECTION_EMPTY', lambda p: p['direction']['style'].update(instruction='')),
            ('COMPONENT_COVERAGE_DRIFT', lambda p: p['components'].pop()),
            ('COMPONENT_OWNER', lambda p: p['components'][0].update(owner='BOTH')),
            ('COMPONENT_SOURCE_MISSING', lambda p: p['components'][0].update(source_ids=['MISSING'])),
            ('FIXED_COMPONENT_UNPINNED', lambda p: p['components'][0].update(source_ids=['REQUEST'])),
            ('FIXED_COMPONENT_UNPINNED', lambda p: p['components'][0].update(freedom='FREE')),
            ('COPY_UNGROUNDED', lambda p: p['components'][1].update(copy=['Balance 999'])),
            ('COPY_NOT_LOCKED', lambda p: p['components'][1].update(freedom='GUIDED')),
            ('SOURCE_CROSS_BUSINESS', lambda p: p['sources'][0].update(business_code='OTHER')),
            ('SOURCE_BYTES_DRIFT', lambda p: p['sources'][0].update(text='Altered')),
            ('SOURCE_STATUS', lambda p: p['sources'][0].update(status='UNKNOWN')),
            ('REQUIREMENT_UNGROUNDED', lambda p: p['requirements'][0].update(quote='invented')),
            ('REQUIREMENT_LINK_INVALID', lambda p: p['components'][0].update(requirements=['R99'])),
            ('REQUIREMENT_COVERAGE_GAP', lambda p: p['requirements'].append({'id':'R2','source':'REQUEST','quote':'soft background'})),
        ]
        for code, mutate in cases:
            with self.subTest(code=code):
                p = fixture()
                mutate(p)
                with self.assertRaisesRegex(ArtBlocked, '^'+code+'$'):
                    preflight(p)
    def test_candidate_not_promoted(self):
        p=fixture()
        p['sources'][0]['status']='CANDIDATE'
        r=preflight(p)
        self.assertEqual(r['source_authenticity'],'NOT_ATTESTED_BY_LOCAL_GATE')
        self.assertFalse(r['production_approved'])


if __name__ == '__main__':
    unittest.main()

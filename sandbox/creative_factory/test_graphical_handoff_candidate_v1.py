import copy
import json
import unittest
from pathlib import Path
from test_compositor_blueprint_layers_v2 import LayerTests as _LayerTests
from graphical_handoff_candidate_v1 import build_candidate, sha, ArtBlocked, DIRECTION


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.fx=_LayerTests();self.fx.setUp();self.addCleanup(self.fx.tmp.cleanup)
        self.plan=copy.deepcopy(self.fx.m['plan'])
        self.projection={'direction':{k:'Refined studio product composition' for k in DIRECTION},'components':{'Scene':'Compose full scene','Card':'Draw the balance card'},'references':[]}
        self.files={}
    def build(self):return build_candidate(self.plan,self.projection,self.files)
    def test_full_scene_reserves_fixed(self):
        r=self.build(); t=r['payload']['prompt']
        self.assertIn('240 × 400',t);self.assertIn('Card: Draw the balance card',t)
        self.assertIn('Action: reserva el rectángulo [30, 250, 180, 40]',t);self.assertNotIn('Continue',t)
        self.assertNotIn('fixture:',t);self.assertFalse(r['native_transmitted']);self.assertFalse(r['canonical_wire']);self.assertEqual(r,self.build())
    def test_component_coverage(self):
        for change in (lambda x:x.pop('Card'),lambda x:x.update(Action='Draw button')):
            with self.subTest(change=change):
                before=copy.deepcopy(self.projection);change(self.projection['components'])
                with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_COMPONENT_COVERAGE'):self.build()
                self.projection=before
    def test_metadata_blocked(self):
        self.projection['direction']['scene']='Merge Train SHA256'
        with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_OPERATIONAL_METADATA'):self.build()
    def test_wrong_geometry(self):
        self.plan['blueprint']['composition_layout']['regions'][3]['box']=[230,390,40,40]
        self.plan['blueprint']['design_lock']['LOCK']['composition_layout']=copy.deepcopy(self.plan['blueprint']['composition_layout'])
        with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_RESERVED_BOX'):self.build()
    def reference(self):
        path=Path(self.fx.files['LOGO']);meta=json.dumps({'role':'previous_generated_visual_reference_only','file_sha256':sha(path.read_bytes())});self.plan['sources'].append({'id':'REF','business_code':'DEMO','ref':'fixture:reference','version':'1','status':'CANDIDATE','text':meta,'sha256':sha(meta.encode())});self.plan['components'][0]['source_ids'].append('REF');self.projection['references']=[{'source_id':'REF','guidance':'Use only framing and visual balance'}];self.files={'REF':str(path)}
        return path
    def test_reference_check(self):
        path=self.reference();r=self.build();self.assertEqual(r['payload']['attachments'][0]['sha256'],sha(path.read_bytes()));self.assertIn('Referencia visual adjunta 1',r['payload']['prompt']);self.assertNotIn(str(path),r['payload']['prompt'])
        path.write_bytes(b'changed')
        with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_ATTACHMENT_HASH_DRIFT'):self.build()
    def test_unbound_reference(self):
        self.reference();self.plan['components'][0]['source_ids'].remove('REF')
        with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_REFERENCE_UNBOUND'):self.build()
    def test_direction_missing(self):
        self.projection['direction'].pop('background')
        with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_DIRECTION_COVERAGE'):self.build()
    def test_attachment_missing(self):
        self.reference();self.files={}
        with self.assertRaisesRegex(ArtBlocked,'GRAPHICAL_ATTACHMENT_SET'):self.build()

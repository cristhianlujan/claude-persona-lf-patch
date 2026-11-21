import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from compositor_core_v1 import digest
from test_compositor_blueprint_layers_v2 import LayerTests as _LayerTests
from skill_blueprint_review_v2 import run_blueprint_review, LocalCompositorReceiver, REQUEST


class PipelineTests(unittest.TestCase):
    def setUp(self):
        fx = _LayerTests(); fx.setUp(); self.addCleanup(fx.tmp.cleanup)
        self.fx = fx
        self.root = Path(fx.tmp.name)
        self.plan = self.root/'plan.json'
        self.plan.write_text(json.dumps(fx.m['plan']), encoding='utf-8')
        self.body = self.root/'body.png'; fx.body(fx.m).save(self.body)
        self.request = {'schema_version':REQUEST, 'mode':'BLUEPRINT_REVIEW_ONLY','business_code':'DEMO',
                        'plan_path':str(self.plan), 'plan_sha256':digest(self.plan.read_bytes()),
                        'body_path':str(self.body), 'body_sha256':digest(self.body.read_bytes()),
                        'body_origin':'SYNTHETIC_REVIEW','files':fx.m['files'],
                        'output_dir':str(self.root/'output')}
        self.events=[]
    def run_it(self):
        return run_blueprint_review(self.request,self.events.append)
    def test_success_auto_order(self):
        r=self.run_it(); self.assertEqual(r['status'],'LOCAL_REVIEW_COMPLETE_SEMANTIC_PENDING')
        self.assertEqual([e['stage'] for e in self.events],['PREPARED_NOT_SENT','LOCAL_HANDOFF_RECEIVED','TECHNICAL_QA_COMPLETE'])
        out=Path(self.request['output_dir']); wire=(out/'local_handoff.json').read_bytes()
        self.assertEqual(wire,self.events[0]['handoff_utf8'].encode())
        self.assertEqual(digest(wire),r['local_readback_sha256'])
        self.assertEqual(digest((out/'composition_review.png').read_bytes()),r['artifact_sha256'])
        self.assertFalse(r['final_delivery_allowed']); self.assertFalse(r['native_transmitted'])
        self.assertEqual(r['semantic_qa'],'PENDING_INDEPENDENT_REVIEW')
    def test_no_intermediate_confirmation(self):
        steps=[]
        original=LocalCompositorReceiver.receive
        def observed(receiver,*args):
            self.assertEqual(steps,['PREPARED_NOT_SENT']); steps.append('INVOKED')
            return original(receiver,*args)
        with patch.object(LocalCompositorReceiver,'receive',observed):
            r=run_blueprint_review(self.request,lambda e:steps.append(e['stage']))
        self.assertEqual(steps,['PREPARED_NOT_SENT','INVOKED','LOCAL_HANDOFF_RECEIVED','TECHNICAL_QA_COMPLETE'])
        self.assertEqual(r['technical_qa'],'PASS_LOCAL')
    def test_auto_readback_on_actual_compositor_rejection(self):
        with Image.open(self.body) as im: bad=im.copy()
        bad.putpixel((40,260),(255,0,0,255));bad.save(self.body)
        self.request['body_sha256']=digest(self.body.read_bytes())
        r=self.run_it(); self.assertEqual(r['blocking_code'],'BODY_OVERWRITES_FIXED')
        self.assertEqual([e['stage'] for e in self.events],['PREPARED_NOT_SENT','REJECTION_READBACK'])
        self.assertEqual(self.events[0]['handoff_utf8'],self.events[-1]['received_handoff_utf8'])
        self.assertEqual(r['prepared_sha256'],r['received_sha256']);self.assertFalse((self.root/'output').exists())
    def test_pre_send_rejections(self):
        for key,val,code in [('body_origin','PROVIDER_IMAGE','BLUEPRINT_REVIEW_AUTHORITY'),
                             ('business_code','LF','BLUEPRINT_BUSINESS_DRIFT'),
                             ('body_sha256','0'*64,'BLUEPRINT_INPUT_HASH_DRIFT')]:
            with self.subTest(key=key):
                original=copy.deepcopy(self.request);self.request[key]=val;self.events=[]
                r=self.run_it();self.assertEqual(r['blocking_code'],code)
                self.assertEqual(r['local_handoff_status'],'HANDOFF_NOT_SENT');self.assertEqual(len(self.events),1)
                self.assertFalse((self.root/'output').exists());self.request=original
    def test_wire_drift(self):
        original=LocalCompositorReceiver.receive
        with patch.object(LocalCompositorReceiver,'receive',lambda s,w,h,b:original(s,w+b' ',h,b)):
            r=self.run_it()
        self.assertEqual(r['blocking_code'],'BLUEPRINT_HANDOFF_WIRE_DRIFT')
        self.assertNotEqual(r['prepared_sha256'],r['received_sha256'])
        self.assertFalse((self.root/'output').exists())
    def test_no_overwrite(self):
        self.run_it(); before=(self.root/'output'/'receipt.json').read_bytes()
        r=self.run_it();self.assertEqual(r['blocking_code'],'BLUEPRINT_OUTPUT_NOT_NEW')
        self.assertEqual(before,(self.root/'output'/'receipt.json').read_bytes())


if __name__=='__main__': unittest.main()

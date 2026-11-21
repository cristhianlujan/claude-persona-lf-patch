import copy
import json
from pathlib import Path
from PIL import Image
from compositor_core_v1 import digest
from test_skill_blueprint_review_v2 import PipelineTests as _PipelineTests


class RGBTests(_PipelineTests):
    # Exercise the integrated receiver and masks, not a standalone conversion.
    def prepare_rgb(self):
        p = copy.deepcopy(self.fx.m['plan'])
        im = self.fx.body(self.fx.m).convert('RGB')
        im.save(self.body)
        raw = self.body.read_bytes()
        meta = json.dumps({'file_sha256':digest(raw),'dimensions':list(im.size),'mode':'RGB','role':'previous_generated_visual_reference_only'})
        p['sources'].append({'id':'REF','business_code':'DEMO','ref':'fixture:rgb','version':'1','status':'CANDIDATE','text':meta,'sha256':digest(meta.encode())})
        binding={'source_id':'REF','pixel_sha256':digest(im.tobytes()),'alignment':'CANDIDATE_MANUAL_REVIEW'}
        p['blueprint']['rgb_reference_binding']=binding
        p['blueprint']['design_lock']['LOCK']['rgb_reference_binding']=copy.deepcopy(binding)
        self.request.update(body_origin='RGB_REFERENCE_REVIEW',body_sha256=digest(raw))
        self.write_plan(p)
        return p
    def write_plan(self,p):
        self.plan.write_text(json.dumps(p),encoding='utf-8')
        self.request['plan_sha256']=digest(self.plan.read_bytes())
    def test_rgb_preserves_outside(self):
        self.prepare_rgb(); r=self.run_it(); self.assertEqual(r['technical_qa'],'PASS_LOCAL')
        e=r['compositor']['rgb_reference_review']; self.assertEqual(e['outside_changed_pixels'],0)
        self.assertEqual(e['fixed_pixel_count'],100*30+180*40); self.assertEqual(e['preserved_pixel_count'],240*400-e['fixed_pixel_count'])
        self.assertEqual(e['provider_provenance'],'UNVERIFIED_REFERENCE');self.assertFalse(r['final_delivery_allowed'])
    def test_rgb_binding_drift(self):
        self.prepare_rgb(); im=Image.open(self.body).copy(); im.putpixel((0,0),(123,123,123)); im.save(self.body)
        self.request['body_sha256']=digest(self.body.read_bytes());r=self.run_it()
        self.assertEqual(r['blocking_code'],'RGB_REFERENCE_FILE_BINDING_DRIFT'); self.assertEqual(r['prepared_sha256'],r['received_sha256'])
    def test_rgb_pixel_drift(self):
        p=self.prepare_rgb(); binding=p['blueprint']['rgb_reference_binding'];binding['pixel_sha256']='0'*64
        p['blueprint']['design_lock']['LOCK']['rgb_reference_binding']=copy.deepcopy(binding);self.write_plan(p)
        self.assertEqual(self.run_it()['blocking_code'],'RGB_REFERENCE_BINDING_DRIFT')
    def test_rgb_wrong_size(self):
        p=self.prepare_rgb(); Image.open(self.body).resize((200,400)).save(self.body); raw=self.body.read_bytes(); self.request['body_sha256']=digest(raw)
        meta=json.loads(p['sources'][-1]['text']);meta['file_sha256']=digest(raw);p['sources'][-1]['text']=json.dumps(meta);p['sources'][-1]['sha256']=digest(p['sources'][-1]['text'].encode()); self.write_plan(p)
        self.assertEqual(self.run_it()['blocking_code'],'BODY_FORMAT')
    def test_rgb_missing_clean_plate(self):
        p=self.prepare_rgb();layout=p['blueprint']['composition_layout'];layout['backdrop']={'kind':'TRANSPARENT','source_id':None};p['blueprint']['design_lock']['LOCK']['composition_layout']=copy.deepcopy(layout);self.write_plan(p)
        self.assertEqual(self.run_it()['blocking_code'],'RGB_REFERENCE_CLEAN_PLATE_REQUIRED')
    def test_rgb_incomplete_canvas(self):
        p=self.prepare_rgb(); layout=p['blueprint']['composition_layout'];layout['regions'][0]['box']=[0,0,10,10];p['blueprint']['design_lock']['LOCK']['composition_layout']=copy.deepcopy(layout);self.write_plan(p)
        self.assertEqual(self.run_it()['blocking_code'],'RGB_REFERENCE_INCOMPLETE_CANVAS')
    def test_rgb_alpha_overlay_not_allowed(self):
        p=self.prepare_rgb();layout=p['blueprint']['composition_layout'];layout['regions'][1]['coverage']='ALPHA';p['blueprint']['design_lock']['LOCK']['composition_layout']=copy.deepcopy(layout);self.write_plan(p)
        self.assertEqual(self.run_it()['blocking_code'],'RGB_REFERENCE_ALPHA_OVERLAY_UNSAFE')
    def test_rgb_requires_alignment(self):
        p=self.prepare_rgb();binding=p['blueprint']['rgb_reference_binding'];binding['alignment']='AUTO';p['blueprint']['design_lock']['LOCK']['rgb_reference_binding']=copy.deepcopy(binding);self.write_plan(p)
        self.assertEqual(self.run_it()['blocking_code'],'RGB_REFERENCE_ALIGNMENT_PENDING')

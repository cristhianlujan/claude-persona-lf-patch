import copy
import json
import tempfile
import unittest
from pathlib import Path
from PIL import Image, ImageDraw
from art_direction_preflight_v1 import preflight
from compositor_core_v1 import compose, digest, CompositionError
from compositor_blueprint_layers_v2 import SCHEMA


class LayerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        root=Path(self.tmp.name)
        logo=root/'logo.png'; Image.new('RGBA',(80,20),'#102030').save(logo)
        f=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
        self.assertTrue(f.is_file())
        self.files={'LOGO':str(logo),'FONT':str(f)}
        values={'LOGO':{'file_sha256':digest(logo.read_bytes()),'mime_type':'image/png'},
                'FONT':{'file_sha256':digest(f.read_bytes()),'weight':700},
                'CTA':{'value':'#008200'},'WHITE':{'value':'#FFFFFF'}}
        sources=[]
        for sid,val in values.items():
            s=json.dumps(val,sort_keys=True)
            sources.append({'id':sid,'business_code':'DEMO','ref':'synthetic:'+sid,'version':'1','status':'CANDIDATE','text':s,'sha256':digest(s.encode())})
        names=['Scene','Logo','Card','Action','Reference']
        request='Show a refined scene. Draw the balance card and the exact action: Continue.'
        components=[]
        for name,owner,ids,text in [('Scene','NATIVE',['REQUEST'],[]),('Logo','COMPOSITOR',['LOGO'],[]),('Card','NATIVE',['REQUEST'],[]),('Action','COMPOSITOR',['REQUEST','CTA','WHITE','FONT'],['Continue']),('Reference','REFERENCE_ONLY',['REQUEST'],[])]:
            components.append({'name':name,'owner':owner,'freedom':'LOCK','instruction':'Preserve specified structure','copy':text,'source_ids':ids,'requirements':['R1']})
        self.plan={'business_code':'DEMO','literal_request':request,
          'blueprint':{'schema_version':'CREATIVE_VISUAL_BLUEPRINT_V1','brand':'DEMO','mode':'PLAN_ONLY','intent':'Scene review','art':'Composed product scene','hierarchy':names,'guided':[],'free':[],'design_lock':{'LOCK':{'hierarchy':names},'GUIDED':[],'FREE':[]}},
          'presentation':{'mode':'FULL_SCENE','destination':'Review image'},
          'direction':{k:{'instruction':'Refined scene','rationale':'User request','requirements':['R1']} for k in ('scene','style','background','typography','hierarchy','visual_impact')},
          'components':components,'sources':sources,'requirements':[{'id':'R1','source':'REQUEST','quote':'refined scene'}]}
        self.m=self.manifest(False)
    def manifest(self, wide):
        dims=[360,220] if wide else [240,400]
        logo=[20,20,100,30] if wide else [20,36,100,30]
        card=[120,65,220,130] if wide else [12,96,216,208]
        action=[140,140,180,40] if wide else [30,250,180,40]
        regions=[{'name':'Scene','owner':'NATIVE','box':[0,0,*dims],'ops':[]},
          {'name':'Logo','owner':'COMPOSITOR','box':logo,'ops':[{'kind':'ASSET','box':[0,0,100,30],'source_id':'LOGO'}]},
          {'name':'Card','owner':'NATIVE','box':card,'ops':[]},
          {'name':'Action','owner':'COMPOSITOR','box':action,'ops':[{'kind':'FILL','box':[0,0,180,40],'color_source':'CTA','radius':20},{'kind':'TEXT','box':[4,4,172,32],'copy':'Continue','size':17,'weight':700,'font_source':'FONT','color_source':'WHITE'}]},
          {'name':'Reference','owner':'REFERENCE_ONLY','box':None,'ops':[]}]
        return {'schema_version':SCHEMA,'review_only':True,'render_authorized':False,'body_origin':'SYNTHETIC_REVIEW','plan':copy.deepcopy(self.plan),'proposal_sha256':preflight(self.plan)['proposal_sha256'],'canvas':dims,'backdrop':{'kind':'COLOR','source_id':'WHITE'},'regions':regions,'files':copy.deepcopy(self.files)}
    def body(self,m):
        im=Image.new('RGBA',tuple(m['canvas']),'#F2F6F5'); d=ImageDraw.Draw(im)
        def r(b): x,y,w,h=b;return x,y,x+w-1,y+h-1
        d.rounded_rectangle(r(m['regions'][2]['box']),radius=16,fill='white')
        for reg in m['regions']:
            if reg['owner']=='COMPOSITOR': d.rectangle(r(reg['box']),fill=(0,0,0,0))
        return im
    def test_two_layouts(self):
        for wide in (False,True):
            with self.subTest(wide=wide):
                m=self.manifest(wide); body=self.body(m); out,r=compose(m,body)
                self.assertEqual(out.size,tuple(m['canvas']));self.assertEqual(r['fixed_components'],['Logo','Action'])
                self.assertEqual(out.getpixel((m['regions'][3]['box'][0]+10,m['regions'][3]['box'][1]+20)),(0,130,0,255))
                self.assertEqual(r['qa_verdict'],'NOT_EVALUATED'); self.assertFalse(r['production_approved'])
                self.assertEqual(out.tobytes(),compose(m,body)[0].tobytes())
    def test_rejection_matrix(self):
        cases=[('LAYER_REVIEW_ONLY',lambda m:m.update(render_authorized=True)),
          ('LAYER_REVIEW_ONLY',lambda m:m.update(body_origin='PROVIDER_IMAGE')),
          ('LAYER_PLAN_HASH_DRIFT',lambda m:m.update(proposal_sha256='0'*64)),
          ('LAYER_COMPONENT_COVERAGE',lambda m:m['regions'].pop()),
          ('LAYER_COMPONENT_BINDING',lambda m:m['regions'][1].update(owner='NATIVE')),
          ('LAYER_FIXED_OVERLAP',lambda m:m['regions'][1].update(box=m['regions'][3]['box'])),
          ('LAYER_SOURCE_UNBOUND',lambda m:m['regions'][1]['ops'][0].update(source_id='CTA')),
          ('LAYER_TEXT_UNBOUND',lambda m:m['regions'][3]['ops'][1].update(copy='Invented')),
          ('LAYER_RADIUS',lambda m:m['regions'][3]['ops'][0].update(radius=80)),
          ('LAYER_FONT_WEIGHT',lambda m:m['regions'][3]['ops'][1].update(weight=400)),
          ('LAYER_TEXT_OVERFLOW',lambda m:m['regions'][3]['ops'][1].update(box=[1,1,2,30])),
          ('LAYER_REFERENCE_DRAW',lambda m:m['regions'][4].update(box=[0,0,10,10])),
          ('LAYER_UNUSED_FILE',lambda m:m['files'].update(EXTRA=m['files']['LOGO'])),
          ('BOX_BOUNDS:Action',lambda m:m['regions'][3].update(box=[230,390,40,40])),
          ('LAYER_FIXED_EMPTY',lambda m:m['regions'][3].update(ops=[]))]
        for code,change in cases:
            with self.subTest(code=code):
                m=copy.deepcopy(self.m);change(m)
                with self.assertRaisesRegex(CompositionError,'^'+code+'$'): compose(m,self.body(self.m))
    def test_native_cannot_overwrite_nested_action(self):
        body=self.body(self.m);body.putpixel((40,260),(255,0,0,255))
        with self.assertRaisesRegex(CompositionError,'^BODY_OVERWRITES_FIXED$'):compose(self.m,body)
    def test_asset_byte_tamper(self):
        Path(self.files['LOGO']).write_bytes(b'changed')
        with self.assertRaisesRegex(CompositionError,'^LAYER_FILE_HASH_DRIFT$'):compose(self.m,self.body(self.m))
    def test_legacy_dispatch_unchanged(self):
        with self.assertRaisesRegex(CompositionError,'^REVIEW_AUTHORITY$'):
            compose({'schema_version':'CREATIVE_COMPOSITION_REVIEW_V1','review_only':False},None)


if __name__=='__main__':unittest.main()

"""Synthetic test: no brand secrets, fonts or source assets committed."""
import copy
import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from PIL import Image, ImageDraw
from compositor_core_v1 import CompositionError, compose, digest

class DeterministicCompositorTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root=Path(self.tmp.name)
        logo=Image.new('RGBA',(100,30),(0,0,0,0))
        ImageDraw.Draw(logo).rectangle((2,2,97,27),fill='#14233A')
        path=root/'logo.png';logo.save(path)
        sources={'logo':path,
            'frame':root/'frame.svg',
            'A':root/'a.svg','B':root/'b.svg'}
        sources['frame'].write_text('<svg xmlns="http://www.w3.org/2000/svg" width="260" height="440"><rect width="260" height="5" fill="#202020"/><rect x="0" width="5" height="440" fill="#202020"/></svg>')
        icon='<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="7" fill="currentColor"/></svg>'
        sources['A'].write_text(icon);sources['B'].write_text(icon)
        font=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
        self.assertTrue(font.is_file())
        self.m={'schema_version':'CREATIVE_COMPOSITION_REVIEW_V1','review_only':True,'render_authorized':False,
            'contract_sha256':'a'*64,'prompt_sha256':'b'*64,
            'geometry':{'viewport':[240,400],'origin':'top_left','units':'logical_px',
                'header':[0,0,240,50],'primary':[0,50,240,100],
                'cta':[20,150,200,40],'details':[0,190,240,160],
                'footer':[0,350,240,50],'logo':[10,10,50,20],'footer_columns':2},
            'frame_outer':[260,440],'frame_app_opening':[10,20,240,400],
            'navigation_labels':['A','B'],'navigation_active':'A',
            'icon_size':18,'icon_top_offset':4,'label_top_offset':24,
            'cta_copy':'Pedir','cta_radius':12,'cta_font_size':14,'cta_font_weight':600,
            'nav_font_size':11,'nav_font_weight':400,
            'tokens':{'cta_bg':'#008200','cta_text':'#FFFFFF','nav_bg':'#FFFFFF','nav_active':'#008200','nav_inactive':'#5C6577'},
            'assets':{k:{'path':str(p),'sha256':digest(p.read_bytes())} for k,p in sources.items()},
            'font_files':{'400':{'path':str(font),'sha256':digest(font.read_bytes())},
                          '600':{'path':str(font),'sha256':digest(font.read_bytes())}}}
        self.body=Image.new('RGBA',(240,400))
        d=ImageDraw.Draw(self.body)
        d.rectangle((0,50,239,149),fill='#FAFBFD')
        d.rectangle((0,190,239,349),fill='#EEF5EE')
    def reject(self,m=None,body=None,err='.*'):
        with self.assertRaisesRegex(CompositionError,err):compose(m or self.m,body or self.body)
    def change(self,key,value):
        m=copy.deepcopy(self.m);m[key]=value;return m
    def test_positive(self):
        img,r=compose(self.m,self.body)
        self.assertEqual(img.size,(260,440));self.assertEqual(r['status'],'LOCAL_COMPOSITOR_PASS')
        self.assertFalse(r['production_approved']);self.assertFalse(r['native_transmitted'])
        self.assertEqual(r['qa_verdict'],'NOT_EVALUATED')
    def test_determinism(self):
        a,_=compose(self.m,self.body);b,_=compose(self.m,self.body)
        self.assertEqual(a.tobytes(),b.tobytes())
    def test_authority(self):self.reject(self.change('render_authorized',True),err='REVIEW_AUTHORITY')
    def test_unreviewed(self):self.reject(self.change('review_only',False),err='REVIEW_AUTHORITY')
    def test_body_opaque(self):self.reject(body=Image.new('RGBA',(240,400),'white'),err='BODY_OVERWRITES_FIXED')
    def test_body_cta_injection(self):
        x=self.body.copy();x.putpixel((50,165),(3,4,5,255));self.reject(body=x,err='BODY_OVERWRITES_FIXED')
    def test_logo_hash(self):
        m=copy.deepcopy(self.m);m['assets']['logo']['sha256']='c'*64;self.reject(m,err='ASSET_SHA256')
    def test_svg_hash(self):
        m=copy.deepcopy(self.m);m['assets']['frame']['sha256']='c'*64;self.reject(m,err='ASSET_SHA256')
    def test_font_hash(self):
        m=copy.deepcopy(self.m);m['font_files']['600']['sha256']='c'*64;self.reject(m,err='FONT_SHA256')
    def test_bad_token(self):
        m=copy.deepcopy(self.m);m['tokens']['cta_bg']='green';self.reject(m,err='COLOR_TOKEN')
    def test_bad_active_nav(self):self.reject(self.change('navigation_active','C'),err='NAV_CONTRACT')
    def test_svg_unsafe(self):
        m=copy.deepcopy(self.m);p=Path(self.tmp.name)/'bad.svg';p.write_text('<svg><script /></svg>')
        m['assets']['frame']={'path':str(p),'sha256':digest(p.read_bytes())}
        self.reject(m,err='SVG_UNSAFE')
if __name__=='__main__':unittest.main()

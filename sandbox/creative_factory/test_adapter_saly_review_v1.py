"""Adapter cases: synthetic L2C contract, no provider transmission or DB writes."""
import copy
import json
from pathlib import Path
from adapter_saly_review_v1 import ReviewPacketError,from_packet,sha
from compositor_core_v1 import compose
from test_compositor_core_v1 import DeterministicCompositorTest

class ReviewPacketIntegration(DeterministicCompositorTest):
    def setUp(self):
        super().setUp()
        refs={k:{'provider':'SUPABASE_INLINE_SVG','sha256':v['sha256'],'asset_id':n,'version':1}
              for n,(k,v) in enumerate(self.m['assets'].items(),1) if k!='logo'}
        comp={'render_ready':False,'asset_state':'CANDIDATE_REVIEW_ONLY','pending_assets':[],
           'geometry':self.m['geometry'],'frame_outer':self.m['frame_outer'],
           'frame_app_opening':self.m['frame_app_opening'],
           'navigation_labels':self.m['navigation_labels'],
           'navigation_layout':{'columns':2,'color_mode':'RESOLVED_TOKEN_CURRENT_COLOR',
              'icon_size_px':18,'icon_top_offset_px':4,'label_top_offset_px':24},
           'asset_refs':refs,'logo_ref':{'sha256':self.m['assets']['logo']['sha256']}}
        traces=[]
        def t(component,prop,value,status='CANDIDATE'):
            traces.append({'consumer':'composition','component':component,'property':prop,
                           'value':value,'status':status,'chain':['synthetic']})
        t('cta','fondo','#008200','APPROVED');t('cta','texto','#FFFFFF')
        t('cta','fuente base','Synthetic, system-ui, sans-serif')
        t('cta','radio botón (px)',12)
        t('cta','tipografía botón',{'size_px':14,'weight':600})
        t('navegacion','fondo','#FFFFFF');t('navegacion','activa','#008200','APPROVED')
        t('navegacion','inactiva','#5C6577')
        t('navegacion','fuente base','Synthetic, system-ui, sans-serif')
        t('navegacion','tipografía etiqueta',{'size_px':11,'weight':400})
        prompt='Body only, omit all fixed controls.'
        h={'item_id':9,'mode':'REVIEW_ONLY','native_prompt':prompt,
           'prompt_sha256':sha(prompt.encode()),'attachments':[],
           'composition':comp,'trace':traces,'cta_copy':'Pedir','navigation_active':'A'}
        self.packet={'schema_version':'SALY_WORK_PACKET_L2C_V1','readiness_code':'READY_FOR_REVIEW_ONLY',
          'native_execution_authorized':False,'image_generation_allowed':False,'item_id':9,
          'review_contract':{'state':'REVIEW_CONTRACT_PREPARED','contract_sha256':'a'*64,
              'contract':{'handoff':h,'qa_verdict':'NOT_EVALUATED'}},
          'native_transport':{'schema_version':'SALY_NATIVE_TRANSPORT_V2','item_id':9,
              'contract_sha256':'a'*64,'prompt_sha256':h['prompt_sha256'],
              'payload':{'prompt':prompt,'attachments':[]}},
          'composition_svg_assets':{k:{'ref':refs[k],
              'svg_utf8':Path(self.m['assets'][k]['path']).read_text()} for k in refs}}
        self.fonts={'family':'Synthetic','files':self.m['font_files']}
        self.logo=self.m['assets']['logo']['path']
        self.out=Path(self.tmp.name)/'staged'
    def prepare(self,p=None,fonts=None,logo=None):
        return from_packet(self.packet if p is None else p,
          self.logo if logo is None else logo,self.fonts if fonts is None else fonts,self.out)
    def deny(self,changes,err):
        p=copy.deepcopy(self.packet)
        changes(p)
        with self.assertRaisesRegex(ReviewPacketError,err):self.prepare(p)
        self.assertFalse(self.out.exists(),'invalid packet must not materialize sources')
    def test_adapter_positive(self):
        m=self.prepare()
        pic,receipt=compose(m,self.body)
        self.assertEqual(pic.size,(260,440))
        self.assertFalse(receipt['native_transmitted'])
        self.assertEqual(m['tokens'],self.m['tokens'])
    def test_adapter_prompt_rewrite(self):
        self.deny(lambda p:p['native_transport']['payload'].__setitem__('prompt','include frame'), 'TRANSPORT_REWRITE')
    def test_adapter_hash_drift(self):
        self.deny(lambda p:p['native_transport'].__setitem__('prompt_sha256','0'*64),'TRANSPORT_HASH_DRIFT')
    def test_adapter_extra_attachment(self):
        self.deny(lambda p:p['native_transport']['payload']['attachments'].append('logo'),'TRANSPORT_REWRITE')
    def test_adapter_wrong_authority(self):
        self.deny(lambda p:p.__setitem__('image_generation_allowed',True),'PACKET_AUTHORITY')
    def test_adapter_wrong_handoff_mode(self):
        self.deny(lambda p:p['review_contract']['contract']['handoff'].__setitem__('mode','NATIVE'),'HANDOFF_MODE')
    def test_adapter_contract_drift(self):
        self.deny(lambda p:p['native_transport'].__setitem__('contract_sha256','0'*64),'CONTRACT_BINDING_DRIFT')
    def test_adapter_corrupt_svg(self):
        self.deny(lambda p:p['composition_svg_assets']['A'].__setitem__('svg_utf8','<svg/>'),'SVG_BYTES_DRIFT')
    def test_adapter_extra_svg(self):
        self.deny(lambda p:p['composition_svg_assets'].__setitem__('unknown',{}),'SVG_SET_DRIFT')
    def test_adapter_font_family(self):
        f=copy.deepcopy(self.fonts);f['family']='Other'
        with self.assertRaisesRegex(ReviewPacketError,'FONT_FAMILY_DRIFT'):self.prepare(fonts=f)
        self.assertFalse(self.out.exists())
    def test_adapter_duplicate_trace(self):
        self.deny(lambda p:p['review_contract']['contract']['handoff']['trace'].append(
          dict(p['review_contract']['contract']['handoff']['trace'][0])),'TRACE_UNIQUE_REQUIRED')
    def test_adapter_invalid_logo(self):
        self.deny(lambda p:p['review_contract']['contract']['handoff']['composition']['logo_ref'].__setitem__('sha256','0'*64),'LOGO_BYTES_DRIFT')
    def test_adapter_invalid_font_file(self):
        f=copy.deepcopy(self.fonts);f['files']['600']['sha256']='0'*64
        with self.assertRaisesRegex(ReviewPacketError,'FONT_FILE_HASH_DRIFT'):self.prepare(fonts=f)
        self.assertFalse(self.out.exists())
if __name__=='__main__':__import__('unittest').main()

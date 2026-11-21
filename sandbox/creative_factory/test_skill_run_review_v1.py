"""Real isolated skill integration: existing SALY adapter + compositor + Native preflight."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw
from skill_run_review_v1 import SkillBlocked, run_review, SCHEMA, hash_bytes


class CreativeSkillStandaloneTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        logo = Image.new('RGBA', (100, 30), (0, 0, 0, 0))
        ImageDraw.Draw(logo).rectangle((2, 2, 97, 27), fill='#14233A')
        self.logo = self.root / 'logo.png'
        logo.save(self.logo)
        frame_svg = '<svg xmlns="http://www.w3.org/2000/svg" width="260" height="440"><rect width="260" height="5" fill="#202020"/><rect x="0" width="5" height="440" fill="#202020"/></svg>'
        icon_svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="7" fill="currentColor"/></svg>'
        svgs = {'frame': frame_svg, 'A': icon_svg, 'B': icon_svg}
        refs = {name: {'provider': 'SUPABASE_INLINE_SVG', 'sha256': hash_bytes(svg.encode()), 'asset_id': i, 'version': 1}
                for i, (name, svg) in enumerate(svgs.items(), start=1)}
        font = Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
        self.assertTrue(font.is_file())
        self.fonts = {'family': 'Synthetic', 'files': {
            '400': {'path': str(font), 'sha256': hash_bytes(font.read_bytes())},
            '600': {'path': str(font), 'sha256': hash_bytes(font.read_bytes())},
        }}
        self.font_path = self.root / 'fonts.json'
        self.font_path.write_text(json.dumps(self.fonts), encoding='utf-8')
        self.geometry = {
            'viewport': [240, 400], 'origin': 'top_left', 'units': 'logical_px',
            'header': [0, 0, 240, 50], 'primary': [0, 50, 240, 100],
            'cta': [20, 150, 200, 40], 'details': [0, 190, 240, 160],
            'footer': [0, 350, 240, 50], 'logo': [10, 10, 50, 20], 'footer_columns': 2,
        }
        trace = []
        def t(component, prop, value, status='CANDIDATE'):
            trace.append({'consumer': 'composition', 'component': component, 'property': prop,
                          'value': value, 'status': status, 'chain': ['fixture source']})
        t('cta', 'fondo', '#008200', 'APPROVED')
        t('cta', 'texto', '#FFFFFF')
        t('cta', 'fuente base', 'Synthetic, system-ui, sans-serif')
        t('cta', 'radio botón (px)', 12)
        t('cta', 'tipografía botón', {'size_px': 14, 'weight': 600})
        t('navegacion', 'fondo', '#FFFFFF')
        t('navegacion', 'activa', '#008200', 'APPROVED')
        t('navegacion', 'inactiva', '#5C6577')
        t('navegacion', 'fuente base', 'Synthetic, system-ui, sans-serif')
        t('navegacion', 'tipografía etiqueta', {'size_px': 11, 'weight': 400})
        comp = {
            'render_ready': False, 'asset_state': 'CANDIDATE_REVIEW_ONLY', 'pending_assets': [],
            'geometry': self.geometry, 'frame_outer': [260, 440],
            'frame_app_opening': [10, 20, 240, 400], 'navigation_labels': ['A', 'B'],
            'navigation_layout': {'columns': 2, 'color_mode': 'RESOLVED_TOKEN_CURRENT_COLOR',
                                  'icon_size_px': 18, 'icon_top_offset_px': 4, 'label_top_offset_px': 24},
            'asset_refs': refs, 'logo_ref': {'sha256': hash_bytes(self.logo.read_bytes())},
        }
        prompt = 'Synthetic body only. Do not include logo, CTA, footer or frame.'
        prompt_hash = hash_bytes(prompt.encode())
        handoff = {'item_id': 9, 'mode': 'REVIEW_ONLY', 'transmitted': False,
                   'native_prompt': prompt, 'prompt_sha256': prompt_hash, 'attachments': [],
                   'composition': comp, 'trace': trace, 'cta_copy': 'Pedir', 'navigation_active': 'A'}
        self.packet = {
            'schema_version': 'SALY_WORK_PACKET_L2C_V1', 'readiness_code': 'READY_FOR_REVIEW_ONLY',
            'native_execution_authorized': False, 'image_generation_allowed': False, 'item_id': 9,
            'review_contract': {'state': 'REVIEW_CONTRACT_PREPARED', 'contract_sha256': 'a'*64,
                                'contract': {'qa_verdict': 'NOT_EVALUATED', 'render_ready': False,
                                             'native_execution_authorized': False, 'image_generation_allowed': False,
                                             'handoff': handoff}},
            'native_transport': {'schema_version': 'SALY_NATIVE_TRANSPORT_V2', 'item_id': 9,
                                 'contract_sha256': 'a'*64, 'prompt_sha256': prompt_hash,
                                 'payload': {'prompt': prompt, 'attachments': []}},
            'composition_svg_assets': {k: {'ref': refs[k], 'svg_utf8': v} for k, v in svgs.items()},
        }
        self.packet_path = self.root / 'packet.json'
        self.save_packet()
        self.body_path = self.root / 'body.png'
        self.body = Image.new('RGBA', (240, 400))
        d = ImageDraw.Draw(self.body)
        d.rectangle((0, 50, 239, 149), fill='#FAFBFD')
        d.rectangle((0, 190, 239, 349), fill='#EEF5EE')
        self.body.save(self.body_path)
        self.output = self.root / 'review-out'
        self.request = {
            'schema_version': SCHEMA, 'mode': 'COMPOSE_REVIEW_ONLY', 'business_code': 'SALY',
            'packet_path': str(self.packet_path),
            'packet_sha256': hash_bytes(self.packet_path.read_bytes()),
            'logo_path': str(self.logo), 'fonts_path': str(self.font_path),
            'body_path': str(self.body_path), 'output_dir': str(self.output),
            'body_origin': 'SYNTHETIC_REVIEW',
        }

    def save_packet(self):
        self.packet_path.write_text(json.dumps(self.packet, ensure_ascii=False, sort_keys=True), encoding='utf-8')
        if hasattr(self, 'request'):
            self.request['packet_sha256'] = hash_bytes(self.packet_path.read_bytes())

    def mutate(self, f):
        f(self.packet)
        self.save_packet()

    def denied(self, expected):
        old = ({f.name: f.read_bytes() for f in self.output.iterdir()}
               if self.output.exists() else None)
        with self.assertRaises(SkillBlocked) as exc:
            run_review(self.request)
        self.assertEqual(exc.exception.code, expected)
        current = ({f.name: f.read_bytes() for f in self.output.iterdir()}
                   if self.output.exists() else None)
        self.assertEqual(current, old, 'failure may not publish or mutate output')

    def test_01_positive_review(self):
        result = run_review(self.request)
        self.assertEqual(result['status'], 'LOCAL_TECHNICAL_REVIEW_PASS')
        self.assertEqual(result['business_code'], 'SALY')
        self.assertFalse(result['router_invoked'])
        self.assertFalse(result['profile_invoked'])
        self.assertFalse(result['native_transmitted'])
        self.assertFalse(result['production_approved'])
        self.assertEqual(result['semantic_qa'], 'NOT_EVALUATED')
        self.assertEqual(set(p.name for p in self.output.iterdir()), {'composition_review.png','receipt.json'})
        self.assertEqual(hash_bytes((self.output/'composition_review.png').read_bytes()), result['file_sha256'])
    def test_02_deterministic_output(self):
        first = run_review(self.request)
        self.request['output_dir'] = str(self.root/'review-out-second')
        second = run_review(self.request)
        self.assertEqual(first['file_sha256'], second['file_sha256'])
        self.assertEqual(first['image_pixel_sha256'], second['image_pixel_sha256'])
    def test_03_no_rewrite_existing_output(self):
        run_review(self.request)
        self.denied('SKILL_OUTPUT_MUST_BE_NEW_DIRECTORY')
    def test_04_business_lf_not_supported_without_adapter(self):
        self.request['business_code'] = 'LF'
        self.denied('SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE')
    def test_05_future_business_not_silently_saly(self):
        self.request['business_code'] = 'NUEVO_NEGOCIO'
        self.denied('SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE')
    def test_06_business_mismatch(self):
        self.mutate(lambda p:p.__setitem__('schema_version', 'LF_WORK_PACKET_L2C_V1'))
        self.denied('SKILL_BUSINESS_PACKET_MISMATCH')
    def test_07_packet_byte_tampering(self):
        self.packet_path.write_bytes(self.packet_path.read_bytes()+b' ')
        self.denied('SKILL_PACKET_BYTES_DRIFT')
    def test_08_extra_request_authority(self):
        self.request['profile_code'] = 'PERFIL-UI-ARCHITECT'
        self.denied('SKILL_REQUEST_FIELDS_INVALID')
    def test_09_router_in_request_rejected(self):
        self.request['router_context'] = {'business': 'SALY'}
        self.denied('SKILL_REQUEST_FIELDS_INVALID')
    def test_10_render_permission_rejected(self):
        self.mutate(lambda p:p.__setitem__('image_generation_allowed', True))
        self.denied('SKILL_RENDER_AUTHORITY_FORBIDDEN')
    def test_11_handoff_requires_review(self):
        self.mutate(lambda p:p['review_contract']['contract']['handoff'].__setitem__('transmitted', True))
        self.denied('SKILL_NATIVE_CONTRACT_NATIVE_CAPTURE_HANDOFF_STATE')
    def test_12_prompt_rewrite_rejected(self):
        self.mutate(lambda p:p['native_transport']['payload'].__setitem__('prompt','New prompt with logo included'))
        self.denied('SKILL_NATIVE_CONTRACT_NATIVE_CAPTURE_PAYLOAD_DRIFT')
    def test_13_extra_attachment_rejected(self):
        self.mutate(lambda p:p['native_transport']['payload']['attachments'].append({'logo': 'injection'}))
        self.denied('SKILL_NATIVE_CONTRACT_NATIVE_CAPTURE_PAYLOAD_DRIFT')
    def test_14_logo_hash_rejected(self):
        self.mutate(lambda p:p['review_contract']['contract']['handoff']['composition']['logo_ref'].__setitem__('sha256','c'*64))
        self.denied('LOGO_BYTES_DRIFT')
    def test_15_icon_hash_rejected(self):
        self.mutate(lambda p:p['composition_svg_assets']['A'].__setitem__('svg_utf8','<svg/>'))
        self.denied('SVG_BYTES_DRIFT')
    def test_16_font_hash_rejected(self):
        f = copy.deepcopy(self.fonts)
        f['files']['600']['sha256'] = 'd'*64
        self.font_path.write_text(json.dumps(f))
        self.denied('FONT_FILE_HASH_DRIFT')
    def test_17_body_overlays_fixed_cta(self):
        corrupted = self.body.copy()
        corrupted.putpixel((50,165),(255,0,0,255))
        corrupted.save(self.body_path)
        self.denied('BODY_OVERWRITES_FIXED')
    def test_18_non_png_body(self):
        self.body_path.write_bytes(b'not a png')
        self.denied('SKILL_BODY_DECODE_FAILED')
    def test_19_fake_provider_mode(self):
        self.request['mode']='NATIVE_GENERATION'
        self.denied('SKILL_MODE_NOT_AUTHORIZED')
    def test_20_unverified_generated_body(self):
        self.request['body_origin']='PROVIDER_IMAGE'
        self.denied('SKILL_BODY_PROVENANCE_NOT_VERIFIED')
    def test_21_duplicate_json_keys(self):
        self.packet_path.write_text('{"schema_version":"a","schema_version":"b"}')
        self.request['packet_sha256'] = hash_bytes(self.packet_path.read_bytes())
        self.denied('SKILL_DUPLICATE_JSON_KEY')
    def test_22_reject_symlink_to_packet(self):
        alias = self.root/'alias.json'
        alias.symlink_to(self.packet_path)
        self.request['packet_path']=str(alias)
        self.denied('SKILL_SOURCE_NOT_REGULAR_FILE')
    def test_23_bad_contract_sha(self):
        self.mutate(lambda p:p['native_transport'].__setitem__('contract_sha256','0'*64))
        self.denied('SKILL_NATIVE_CONTRACT_NATIVE_CAPTURE_CONTRACT_BINDING')
    def test_24_bad_font_family(self):
        f=copy.deepcopy(self.fonts)
        f['family']='Other'
        self.font_path.write_text(json.dumps(f))
        self.denied('FONT_FAMILY_DRIFT')
    def test_25_contract_invalid_nav(self):
        self.mutate(lambda p:p['review_contract']['contract']['handoff'].__setitem__('navigation_active','C'))
        self.denied('NAV_CONTRACT')

if __name__=='__main__':unittest.main()

import base64
import copy
import json
import unittest
from native_transport_capture_v1 import (
    CaptureRejected, capture_review_only, parse_wire, sealed_envelope,
    sha, strict_json_bytes, validate_provider_ack,
)

class EchoSink:
    def __init__(self):self.invocations=[]
    def capture(self,request_id,wire):
        self.invocations.append((request_id,wire))
        return wire

class MutatingSink(EchoSink):
    def capture(self,request_id,wire):
        super().capture(request_id,wire)
        return wire+b' '

class MissingReadback(EchoSink):
    def capture(self,request_id,wire):
        super().capture(request_id,wire)
        return None

class CaptureTest(unittest.TestCase):
    def setUp(self):
        p='Diseña una Home móvil SALY para que el empleado vea su disponible.\nOmite marco, logo, botón, navegación y adornos.'
        h=sha(p.encode('utf-8'));c='a'*64
        self.packet={'schema_version':'SALY_WORK_PACKET_L2C_V1','readiness_code':'READY_FOR_REVIEW_ONLY',
          'native_execution_authorized':False,'image_generation_allowed':False,'item_id':9,
          'review_contract':{'state':'REVIEW_CONTRACT_PREPARED','contract_sha256':c,
             'contract':{'qa_verdict':'NOT_EVALUATED','native_execution_authorized':False,
                'image_generation_allowed':False,'handoff':{'item_id':9,'mode':'REVIEW_ONLY',
                    'transmitted':False,'native_prompt':p,'prompt_sha256':h,'attachments':[]}}},
          'native_transport':{'schema_version':'SALY_NATIVE_TRANSPORT_V2','item_id':9,
             'contract_sha256':c,'prompt_sha256':h,'payload':{'prompt':p,'attachments':[]}},
          'composition_svg_assets':{'frame':{'ref':{'asset_id':1},'svg_utf8':'<svg/>'}}}
        self.sink=EchoSink();self.used=set();self.oracle_calls=0
    def oracle(self,envelope):
        self.oracle_calls+=1
        # A test double for PG jsonb::text; the real wire must come from SQL.
        wire=json.dumps(envelope['payload'],ensure_ascii=False,separators=(', ',': ')).encode('utf8')
        return {'schema_version':'SALY_CANONICAL_NATIVE_WIRE_V1','status':'CANONICAL_WIRE_REVIEW_ONLY',
                'item_id':envelope['item_id'],'prompt_sha256':envelope['prompt_sha256'],
                'contract_sha256':envelope['contract_sha256'],'native_transmitted':False,
                'qa_verdict':'NOT_EVALUATED','provider_receipt':None,'render_authorized':False,
                'wire_base64':base64.b64encode(wire).decode('ascii'),
                'wire_sha256':sha(wire),'payload_sha256':sha(wire)}
    def capture(self,packet=None,oracle=None,sink=None,request_id='capture-1'):
        return capture_review_only(self.packet if packet is None else packet,
                                   self.oracle if oracle is None else oracle,
                                   self.sink if sink is None else sink,request_id,self.used)
    def deny(self,mutation,code):
        packet=copy.deepcopy(self.packet);mutation(packet)
        with self.assertRaises(CaptureRejected) as e:self.capture(packet)
        self.assertEqual(e.exception.code,code)
        self.assertEqual(len(self.sink.invocations),0)
    def test_happy_local_capture(self):
        e=self.capture()
        self.assertEqual(e.status,'LOCAL_READBACK_MATCH_REVIEW_ONLY')
        self.assertEqual(e.captured_bytes,len(self.sink.invocations[0][1]))
        self.assertEqual(e.wire_sha256,sha(self.sink.invocations[0][1]))
        self.assertFalse(e.transmitted_to_native)
        self.assertIsNone(e.provider_receipt)
        self.assertEqual(e.qa_verdict,'NOT_EVALUATED')
    def test_unicode_wire_roundtrip(self):
        packet=copy.deepcopy(self.packet)
        text='Café Ñ ∑ 🚀'
        packet['native_transport']['payload']['prompt']=text
        packet['review_contract']['contract']['handoff']['native_prompt']=text
        h=sha(text.encode('utf-8'))
        packet['native_transport']['prompt_sha256']=h
        packet['review_contract']['contract']['handoff']['prompt_sha256']=h
        self.assertEqual(self.capture(packet).prompt_sha256,h)
    def test_repeat_id_block(self):
        self.capture()
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_REPLAY'):
            self.capture()
        self.assertEqual(len(self.sink.invocations),1)
    def test_bad_work_packet(self):self.deny(lambda p:p.__setitem__('schema_version','v0'),'NATIVE_CAPTURE_PACKET_SCHEMA')
    def test_render_authority(self):self.deny(lambda p:p.__setitem__('image_generation_allowed',True),'NATIVE_CAPTURE_AUTHORITY')
    def test_qa_authority(self):self.deny(lambda p:p['review_contract']['contract'].__setitem__('qa_verdict','PASS'),'NATIVE_CAPTURE_QA_AUTHORITY')
    def test_handoff_sent_claim(self):self.deny(lambda p:p['review_contract']['contract']['handoff'].__setitem__('transmitted',True),'NATIVE_CAPTURE_HANDOFF_STATE')
    def test_extra_wire_field(self):self.deny(lambda p:p['native_transport']['payload'].__setitem__('composition',{}),'NATIVE_CAPTURE_PAYLOAD_SHAPE')
    def test_logo_attachment_injection(self):self.deny(lambda p:p['native_transport']['payload']['attachments'].append({'logo':'not_authorized'}),'NATIVE_CAPTURE_PAYLOAD_DRIFT')
    def test_prompt_rewrite(self):self.deny(lambda p:p['native_transport']['payload'].__setitem__('prompt','add frame'),'NATIVE_CAPTURE_PAYLOAD_DRIFT')
    def test_prompt_trailing_space(self):self.deny(lambda p:p['native_transport']['payload'].__setitem__('prompt',p['native_transport']['payload']['prompt']+' '),'NATIVE_CAPTURE_PAYLOAD_DRIFT')
    def test_contract_sha_drift(self):self.deny(lambda p:p['native_transport'].__setitem__('contract_sha256','b'*64),'NATIVE_CAPTURE_CONTRACT_BINDING')
    def test_invalid_prompt_sha(self):self.deny(lambda p:p['native_transport'].__setitem__('prompt_sha256','0'*64),'NATIVE_CAPTURE_PROMPT_BINDING')
    def test_item_mutation(self):self.deny(lambda p:p['native_transport'].__setitem__('item_id',8),'NATIVE_CAPTURE_ITEM_BINDING')
    def test_missing_assets(self):self.deny(lambda p:p.pop('composition_svg_assets'),'NATIVE_CAPTURE_ASSET_SNAPSHOT_MISSING')
    def test_unknown_envelope_version(self):self.deny(lambda p:p['native_transport'].__setitem__('schema_version','v3'),'NATIVE_CAPTURE_ENVELOPE_SCHEMA')
    def test_db_preflight_missing(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_PREFLIGHT_MISMATCH'):
            self.capture(oracle=lambda _:None)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_preflight_forged_transmitted(self):
        def oracle(e):return self.oracle(e)|{'native_transmitted':True}
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_PREFLIGHT_MISMATCH'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_wire_transport_authority(self):
        def oracle(e):return self.oracle(e)|{'render_authorized':True}
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_PREFLIGHT_MISMATCH'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_wire_missing_provider_receipt(self):
        def oracle(e):
            r=self.oracle(e)
            r.pop('provider_receipt')
            return r
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_PREFLIGHT_MISMATCH'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_wire_base64_linebreak(self):
        def oracle(e):
            r=self.oracle(e)
            r['wire_base64']=r['wire_base64'][:76]+'\n'+r['wire_base64'][76:]
            return r
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_WIRE_BASE64'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_bad_request_id(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_REQUEST_ID'):
            self.capture(request_id='Ñ local')
        self.assertEqual(self.oracle_calls,0)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_wire_digest_mismatch(self):
        def oracle(e):return self.oracle(e)|{'wire_sha256':'0'*64,'payload_sha256':'0'*64}
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_WIRE_HASH'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_wire_wrong_payload(self):
        def oracle(e):
            r=self.oracle(e)
            payload={'prompt':'not the sealed prompt','attachments':[]}
            wire=json.dumps(payload,ensure_ascii=False,separators=(', ',': ')).encode('utf8')
            r.update(wire_base64=base64.b64encode(wire).decode(),wire_sha256=sha(wire),payload_sha256=sha(wire))
            return r
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_WIRE_PAYLOAD_DRIFT'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_db_wire_invalid_base64(self):
        def oracle(e):return self.oracle(e)|{'wire_base64':'#invalid!'}
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DB_WIRE_BASE64'):
            self.capture(oracle=oracle)
        self.assertEqual(len(self.sink.invocations),0)
    def test_sink_mutation(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_RECEIVER_BYTES_DRIFT'):
            self.capture(sink=MutatingSink())
        self.assertEqual(len(self.used),0)
    def test_sink_no_readback(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_RECEIVER_BYTES_DRIFT'):
            self.capture(sink=MissingReadback())
        self.assertEqual(len(self.used),0)
    def test_json_duplicate_key(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_DUPLICATE_JSON_KEY'):
            parse_wire(b'{"prompt":"abc","prompt":"fake"}')
    def test_json_noncanonical(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_NONCANONICAL_WIRE'):
            parse_wire(b'{ "a": 1 }')
    def test_provider_fake_ack(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE'):
            validate_provider_ack({'provider_receipt':{'provider_id':'forged'},'transmitted':True})
    def test_invalid_surrogate_prompt(self):
        self.deny(lambda p:(p['native_transport']['payload'].__setitem__('prompt','\ud800'),
            p['review_contract']['contract']['handoff'].__setitem__('native_prompt','\ud800')),
            'NATIVE_CAPTURE_UTF8_INVALID')
    def test_non_json_attachment_value(self):
        packet=copy.deepcopy(self.packet)
        packet['native_transport']['payload']['attachments'].append(float('inf'))
        packet['review_contract']['contract']['handoff']['attachments'].append(float('inf'))
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_CAPTURE_WIRE_SERIALIZATION_INVALID'):
            self.capture(packet)
        self.assertEqual(len(self.sink.invocations),0)
    def test_native_provider_receipt_never_accepted(self):
        with self.assertRaisesRegex(CaptureRejected,'NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE'):
            validate_provider_ack(None, {'native_execution_authorized':True}, b'fake-image')
    def test_no_oracle_after_invalid(self):
        self.deny(lambda p:p['native_transport']['payload'].__setitem__('prompt','changed'), 'NATIVE_CAPTURE_PAYLOAD_DRIFT')
        self.assertEqual(self.oracle_calls,0)
if __name__=='__main__':unittest.main()

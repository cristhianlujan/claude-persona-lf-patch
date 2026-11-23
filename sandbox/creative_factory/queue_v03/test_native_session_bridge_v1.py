"""Contract tests of native current-chat cursor; not provider or host evidence."""
import base64
import copy
import hashlib
import json
import unittest

from native_session_bridge_v1 import (NativeBridgeRejected,
                                     prepare_native_session_cursor,
                                     classify_native_chat_artifact)

PAYLOAD = {'prompt': 'Pantalla SALY — sin logo inventado', 'attachments': []}
WIRE = json.dumps(PAYLOAD, ensure_ascii=False, separators=(',', ':')).encode()
H = lambda b: hashlib.sha256(b).hexdigest()
MODES = {'GPT_NATIVE':'OPENAI_CHATGPT_NATIVE', 'CLAUDE_NATIVE':'ANTHROPIC_CLAUDE_NATIVE'}


def fixture(mode='GPT_NATIVE'):
    executor = dict(mode=mode, provider_identity=MODES[mode],
                    conversation_scope='EXISTING_CONVERSATION_ONLY',
                    native_api_invocation=False, native_session_creation=False,
                    remote_api_fallback='FORBIDDEN', host_execution='FORBIDDEN',
                    provider_attested=False)
    wire = dict(schema_version='SALY_CANONICAL_NATIVE_WIRE_V1',
                status='CANONICAL_WIRE_REVIEW_ONLY',item_id=9,
                render_authorized=False, native_transmitted=False,
                wire_base64=base64.b64encode(WIRE).decode(),
                wire_sha256=H(WIRE),prompt_sha256=H(PAYLOAD['prompt'].encode()))
    archive = dict(status='HANDOFF_PREPARED_NOT_SENT',invocation_recorded=False,
                   provider_receipt=None,reception_status='NOT_SENT',production_approved=False,
                   payload_sha256=H(WIRE),prompt_sha256=H(PAYLOAD['prompt'].encode()))
    binding = dict(order_id=2,run_id=None,claim_id=None,item_id=9,render_authorized=False,
                   review_only=True,prompt_sha256=H(PAYLOAD['prompt'].encode()))
    return executor,wire,archive,binding


class NativeTests(unittest.TestCase):
    def test_gpt_native(self):
        result=prepare_native_session_cursor(executor=fixture()[0],canonical_wire=fixture()[1],archive=fixture()[2],binding=fixture()[3])
        self.assertEqual(result['continuation_target'],'CURRENT_GPT_NATIVE_CONVERSATION')
        self.assertFalse(result['db_done_allowed'])

    def test_claude_native(self):
        e,w,a,b=fixture('CLAUDE_NATIVE')
        out=prepare_native_session_cursor(executor=e,canonical_wire=w,archive=a,binding=b)
        self.assertEqual(out['executor_provider'],'ANTHROPIC_CLAUDE_NATIVE')
        self.assertFalse(out['image_generation_allowed'])

    def negative(self,code,change):
        e,w,a,b=fixture()
        change(e,w,a,b)
        with self.assertRaises(NativeBridgeRejected) as cm:
            prepare_native_session_cursor(executor=e,canonical_wire=w,archive=a,binding=b)
        self.assertEqual(cm.exception.code,code)

    def test_mode_invalid(self): self.negative('CREATIVE_NATIVE_MODE_INVALID',lambda e,w,a,b:e.update(mode='REMOTE_API'))
    def test_provider_mismatch(self): self.negative('CREATIVE_NATIVE_PROVIDER_MODE_MISMATCH',lambda e,w,a,b:e.update(provider_identity='ANTHROPIC_CLAUDE_NATIVE'))
    def test_remote_fallback(self): self.negative('CREATIVE_NATIVE_SESSION_TRANSPORT_INVALID',lambda e,w,a,b:e.update(remote_api_fallback='ALLOWED'))
    def test_new_session(self): self.negative('CREATIVE_NATIVE_SESSION_TRANSPORT_INVALID',lambda e,w,a,b:e.update(native_session_creation=True))
    def test_fake_attestation(self): self.negative('CREATIVE_NATIVE_PROVIDER_ATTESTATION_FORGED',lambda e,w,a,b:e.update(provider_attested=True))
    def test_review_no_authorization(self): self.negative('CREATIVE_NATIVE_PLAN_AUTHORITY_MISMATCH',lambda e,w,a,b:b.update(render_authorized=True))
    def test_fake_run_in_plan(self): self.negative('CREATIVE_NATIVE_PLAN_BINDING_INVALID',lambda e,w,a,b:b.update(run_id=12))
    def test_bad_wire_hash(self): self.negative('CREATIVE_NATIVE_WIRE_HASH_MISMATCH',lambda e,w,a,b:w.update(wire_sha256=H(b'another')))
    def test_bad_base64(self): self.negative('CREATIVE_NATIVE_WIRE_BASE64_INVALID',lambda e,w,a,b:w.update(wire_base64='@!'))
    def test_wrong_item(self): self.negative('CREATIVE_NATIVE_CANONICAL_WIRE_INVALID',lambda e,w,a,b:w.update(item_id=123))
    def test_duplicate_wire_key(self):
        e,w,a,b=fixture()
        wire=b'{"prompt":"A","prompt":"B","attachments":[]}'
        w.update(wire_base64=base64.b64encode(wire).decode(),wire_sha256=H(wire))
        with self.assertRaises(NativeBridgeRejected) as cm:
            prepare_native_session_cursor(executor=e,canonical_wire=w,archive=a,binding=b)
        self.assertEqual(cm.exception.code,'CREATIVE_NATIVE_DUPLICATE_WIRE_KEY')

    def test_missing_plan_source_scope(self):
        self.negative('CREATIVE_NATIVE_PLAN_AUTHORITY_MISMATCH',lambda e,w,a,b:b.update(review_only=False))

    def test_archive_missing(self): self.negative('CREATIVE_NATIVE_PREDISPATCH_ARCHIVE_MISMATCH',lambda e,w,a,b:a.update(status='NOT_ARCHIVED'))
    def test_archive_not_sent(self): self.negative('CREATIVE_NATIVE_PREDISPATCH_ARCHIVE_MISMATCH',lambda e,w,a,b:a.update(reception_status='DELIVERED'))
    def test_prompt_hash_drift(self): self.negative('CREATIVE_NATIVE_RUN_PROMPT_DRIFT',lambda e,w,a,b:b.update(prompt_sha256=H(b'bad')))
    def test_review_wire_only(self): self.negative('CREATIVE_NATIVE_CANONICAL_WIRE_INVALID',lambda e,w,a,b:w.update(render_authorized=True))
    def test_local_image_evidence_not_delivery(self):
        e,w,a,b=fixture()
        cursor=prepare_native_session_cursor(executor=e,canonical_wire=w,archive=a,binding=b)
        img=b'fake-binary-just-tests'
        result=classify_native_chat_artifact(cursor=cursor,image_bytes=img,
            report={'order_id':2,'run_id':None,'claim_id':None,'item_id':9,'image_sha256':H(img)})
        self.assertEqual(result['status'],'LOCAL_ARTIFACT_HASH_VERIFIED_NO_DELIVERY_ATTESTATION')
        self.assertFalse(result['db_done_allowed'])

    def test_local_image_hash_negative(self):
        e,w,a,b=fixture(); c=prepare_native_session_cursor(executor=e,canonical_wire=w,archive=a,binding=b)
        with self.assertRaises(NativeBridgeRejected) as cm:
            classify_native_chat_artifact(cursor=c,image_bytes=b'a',report={'order_id':2,'run_id':None,'claim_id':None,'item_id':9,'image_sha256':H(b'b')})
        self.assertEqual(cm.exception.code,'CREATIVE_NATIVE_ARTIFACT_HASH_MISMATCH')

    def test_local_cross_run_negative(self):
        e,w,a,b=fixture(); c=prepare_native_session_cursor(executor=e,canonical_wire=w,archive=a,binding=b)
        with self.assertRaises(NativeBridgeRejected) as cm:
            classify_native_chat_artifact(cursor=c,image_bytes=b'a',report={'order_id':2,'run_id':99,'claim_id':None,'item_id':9,'image_sha256':H(b'a')})
        self.assertEqual(cm.exception.code,'CREATIVE_NATIVE_ARTIFACT_BINDING_MISMATCH')


if __name__=='__main__':
    unittest.main(verbosity=2)

"""Synthetic preflight tests: real Drive byte hashes tested separately."""
import base64
import copy
import hashlib
import json
import unittest
from native_source_preflight_v1 import NativeSourceRejected, verify_native_source_bytes

PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/tfoAAAAASUVORK5CYII=")
sha = lambda b: hashlib.sha256(b).hexdigest()
MODE = {"GPT_NATIVE":"OPENAI_CHATGPT_NATIVE","CLAUDE_NATIVE":"ANTHROPIC_CLAUDE_NATIVE"}


class Case:
    def __init__(self, mode="GPT_NATIVE"):
        self.content = PNG
        self.entry = {
            "filename":"saly.png","sha256":sha(PNG),"asset_code":"SALY-SCREEN",
            "provider":"GOOGLE_DRIVE","file_ref":"source-1","mime_type":"image/png",
        }
        self.payload = {"prompt":"Pantalla SALY con fuente oficial", "attachments":[self.entry]}
        self.wire = {
            "schema_version":"SALY_NATIVE_RENDER_WIRE_V1",
            "status":"RENDER_WIRE_FROZEN_AUTHORIZED",
            "render_authorized":True,"native_transmitted":False,
            "provider_receipt":None,"host_delivery_verified":False,
            "db_done_allowed":False,
            "executor_mode":mode,"executor_provider":MODE[mode],
            "order_id":10,"item_id":20,"run_id":30,"claim_id":40,
            "input_snapshot_sha256":sha(b"snapshot"),
            "contract_sha256":sha(b"visual"),
        }
        self.pack()
        self.binding = {k:self.wire[k] for k in (
            "order_id","item_id","run_id","claim_id","wire_sha256",
            "prompt_sha256","input_snapshot_sha256","contract_sha256")}
        self.calls = 0
    def pack(self, raw=None):
        data = raw if raw is not None else json.dumps(
            self.payload,ensure_ascii=False,separators=(",",":")).encode()
        self.wire.update(wire_base64=base64.b64encode(data).decode(),
                         wire_sha256=sha(data),
                         prompt_sha256=sha(self.payload["prompt"].encode()))
    def read(self, file_ref):
        self.calls += 1
        if file_ref!="source-1": raise RuntimeError("not found")
        return self.content
    def go(self,reader=None):
        return verify_native_source_bytes(wire=self.wire,binding=self.binding,
            read_registered_file=self.read if reader is None else reader)


class NativeSourceTests(unittest.TestCase):
    def fail(self,code,alter,reader=None):
        c=Case();alter(c)
        with self.assertRaises(NativeSourceRejected) as cm:
            c.go(reader)
        self.assertEqual(cm.exception.code,code)
        return c

    def test_gpt_native(self):
        x=Case().go()
        self.assertEqual(x["status"],"ALL_REGISTERED_SOURCE_BYTES_VERIFIED_NOT_SENT")
        self.assertEqual(x["attachment_count"],1)
        self.assertEqual(x["attachments"][0]["width_px"],1)
        self.assertEqual(x["attachments"][0]["height_px"],1)
        self.assertFalse(x["native_transmitted"])
        self.assertFalse(x["db_done_allowed"])

    def test_claude_native(self):
        c=Case("CLAUDE_NATIVE")
        x=c.go()
        self.assertEqual(x["executor_mode"],"CLAUDE_NATIVE")
        self.assertFalse(x["provider_attested"])

    def test_reader_missing(self):
        self.fail("SALY_NATIVE_SOURCE_READER_MISSING",lambda c:None,reader=False)

    def test_spoofed_delivered_state(self):
        self.fail("SALY_NATIVE_SOURCE_WIRE_NOT_READY",
                  lambda c:c.wire.update(host_delivery_verified=True))
    def test_wrong_executor_pair(self):
        self.fail("SALY_NATIVE_SOURCE_EXECUTOR_MISMATCH",
                  lambda c:c.wire.update(executor_provider="ANTHROPIC_CLAUDE_NATIVE"))
    def test_wrong_executor_type(self):
        self.fail("SALY_NATIVE_SOURCE_EXECUTOR_MISMATCH",
                  lambda c:c.wire.update(executor_mode=[]))
    def test_wrong_claim(self):
        self.fail("SALY_NATIVE_SOURCE_BINDING_MISMATCH:claim_id",
                  lambda c:c.wire.update(claim_id=66))
    def test_wrong_wire_sha(self):
        self.fail("SALY_NATIVE_SOURCE_WIRE_HASH_DRIFT",
                  lambda c:c.wire.update(wire_sha256="f"*64) or c.binding.update(wire_sha256="f"*64))
    def test_corrupt_base64(self):
        self.fail("SALY_NATIVE_SOURCE_BASE64_INVALID",
                  lambda c:c.wire.update(wire_base64="%%%"))
    def test_prompt_pin_mismatch(self):
        self.fail("SALY_NATIVE_SOURCE_PROMPT_DRIFT",
                  lambda c:c.wire.update(prompt_sha256="b"*64) or c.binding.update(prompt_sha256="b"*64))
    def test_missing_png(self):
        self.fail("SALY_NATIVE_SOURCE_READ_FAILED",
                  lambda c:None,reader=lambda ref:(_ for _ in ()).throw(RuntimeError("missing")))
    def test_modified_actual_bytes(self):
        self.fail("SALY_NATIVE_SOURCE_BYTES_DRIFT",
                  lambda c:setattr(c,"content",c.content+b"x"))
    def test_wrong_actual_file_type(self):
        # No synthetic non-PNG may pass the SHA or MIME gate.
        self.fail("SALY_NATIVE_SOURCE_BYTES_DRIFT",
                  lambda c:setattr(c,"content",b"not a png"+b"x"*35))
    def test_fake_png_with_correct_sha(self):
        def mutate(c):
            c.content=b"x"*40
            c.entry["sha256"]=sha(c.content)
            c.pack()
            c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_PNG_INVALID", mutate)
    def test_invalid_dimensions(self):
        def mutate(c):
            x=bytearray(c.content);x[16:20]=b"\0\0\0\0"
            c.content=bytes(x)
            c.entry["sha256"]=sha(c.content)
            c.pack();c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_DIMENSIONS_INVALID", mutate)
    def test_wrong_mime(self):
        def mutate(c):
            c.entry["mime_type"]="image/jpeg"
            c.pack();c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_MIME_NOT_SUPPORTED", mutate)
    def test_duplicate_filename(self):
        def mutate(c):
            c.payload["attachments"].append(copy.deepcopy(c.entry))
            c.pack();c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_FILENAME_INVALID", mutate)
    def test_path_traversal(self):
        def mutate(c):
            c.entry["filename"]="../private.png"
            c.pack();c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_FILENAME_INVALID", mutate)
    def test_foreign_provider(self):
        def mutate(c):
            c.entry["provider"]="FAKE_CDN"
            c.pack();c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_REF_INVALID", mutate)
    def test_empty_attachments(self):
        def mutate(c):
            c.payload["attachments"]=[]
            c.pack();c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_PAYLOAD_SHAPE", mutate)
    def test_duplicate_wire_key(self):
        def mutate(c):
            raw=b'{"prompt":"abc","prompt":"xyz","attachments":[]}'
            c.pack(raw);c.binding["wire_sha256"]=c.wire["wire_sha256"]
        self.fail("SALY_NATIVE_SOURCE_DUPLICATE_WIRE_FIELD", mutate)
    def test_forged_response_not_qa(self):
        c=Case()
        x=c.go()
        self.assertNotIn("delivery_receipt",x)
        self.assertNotIn("qa_verdict",x)
        self.assertEqual(c.calls,1)
    def test_original_wire_unchanged(self):
        c=Case();before=copy.deepcopy(c.wire)
        c.go()
        self.assertEqual(before,c.wire)
    def test_no_host_adapter_without_source(self):
        c=Case()
        with self.assertRaises(NativeSourceRejected) as x:
            verify_native_source_bytes(wire=c.wire,binding=c.binding,read_registered_file=None)
        self.assertEqual(x.exception.code,"SALY_NATIVE_SOURCE_READER_MISSING")

if __name__=="__main__":
    unittest.main(verbosity=2)

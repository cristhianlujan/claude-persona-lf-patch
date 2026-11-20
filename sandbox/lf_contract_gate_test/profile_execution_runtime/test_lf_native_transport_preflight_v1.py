"""Deterministic no-dispatch tests: fields and RAW metadata, no credential or API."""
import importlib.util
import json
import os
import pathlib
import unittest
from unittest.mock import patch

ROOT=pathlib.Path(__file__).resolve().parents[3]
os.environ.setdefault("LF_PROFILE_EDGE_URL","https://example.test/functions/v1/lf-profiles-governance-caller-v1")
spec=importlib.util.spec_from_file_location("lf_profile_native_resume_guard",ROOT/"scripts/lf_profile_native_resume.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TestNativePreflight(unittest.TestCase):
    def test_gate2_required_each_field(self):
        base={"action":"profile_native_begin_from_phrase_v1","request_text":"Revisar carga masiva B2B",
              "stage1_decision":{"action":"PERFIL"},"profile_semantic_decision":{"selected":"PRODUCT_DIRECTOR"},
              "executor_mode":"GPT_NATIVE"}
        for field in ("action","request_text","stage1_decision","profile_semantic_decision","executor_mode"):
            for bad in (None,"","  ","{}",{}):
                with self.subTest(field=field,bad=bad):
                    p={**base,field:bad}
                    self.assertEqual(mod.transport_preflight_fault(p),field)
                    with patch.object(mod.urllib.request,"urlopen") as outbound:
                        with self.assertRaisesRegex(ValueError,"PROFILE_TRANSPORT_PRECALL_INVALID:"+field):
                            mod.call_json("https://example.test",p)
                        outbound.assert_not_called()

    def test_skill_runtime_ticket_fields(self):
        base={"action":"profile_skill_runtime_v1",
              "execution_id":"EXEC-PROFILE-GATE2-1234567890ABCDEF12345678",
              "skill_code":"INPUT_GOVERNANCE_CONTEXT_PACK"}
        self.assertIsNone(mod.transport_preflight_fault(base))
        for field in ("execution_id","skill_code"):
            with self.subTest(field=field):
                p={**base,field:"{}"}
                self.assertEqual(mod.transport_preflight_fault(p),field)

    def test_each_semantic_key_forbidden_in_raw(self):
        valid={"action":"profile_native_continue_v1","execution_id":"EXEC-PROFILE-GATE2-ABCDEF",
               "source_revision":"a"*40,"source_digest":"sha256:"+"b"*64}
        for key in ("semantic_receipt_sha256","catalog_sha256","request_sha256"):
            for rawpath in ("raw","raw_output","raw_payload","raw_input","profile_output","RAW"):
                with self.subTest(key=key,rawpath=rawpath):
                    body={**valid,rawpath:{"original":"read-only","nested":{key:"semantic"}}}
                    self.assertEqual(mod.transport_preflight_fault(body),rawpath+".nested."+key)
                    with patch.object(mod.urllib.request,"urlopen") as outbound:
                        with self.assertRaises(ValueError):
                            mod.call_json("https://example.test",body)
                        outbound.assert_not_called()
            self.assertIsNone(mod.transport_preflight_fault({**valid,key:"allowed_metadata_outside_raw"}))
        self.assertEqual(mod.transport_preflight_fault({**valid,"profile_output":"{}"}),"profile_output")

    def test_valid_payload_prepares_network_once(self):
        payload={"action":"profile_native_continue_v1","execution_id":"EXEC-PROFILE-GATE2-ABCDEF",
                 "source_revision":"a"*40,"source_digest":"sha256:"+"b"*64,
                 "profile_output":{"text":"evidence-bound content"}}
        self.assertIsNone(mod.transport_preflight_fault(payload))
        class Res:
            status=200
            def __enter__(self):return self
            def __exit__(self,*_):return None
            def read(self):return b'{"outcome":"OK"}'
        with patch.object(mod.urllib.request,"urlopen",return_value=Res()) as outbound:
            code,response=mod.call_json("https://example.test",payload)
            self.assertEqual(code,200)
            self.assertEqual(response["outcome"],"OK")
            self.assertEqual(outbound.call_count,1)

if __name__=="__main__":
    unittest.main()

"""PE10 C5 actual frozen GPT Native material SHA/currentness regression.

Reads the real frozen source and real authoring artifact in the checked-out
source tree. It does NOT provide an independent semantic verdict.
"""
import hashlib
import json
import unittest
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/"validators"))
from profile_updater_native_material_bridge_v02 import _sha, MaterialBridgeBlocked
from profile_updater_native_material_operational_v02 import verify_native_material_pre_admission

ROOT=HERE.parents[2]
SNAPSHOT=HERE/"results"/"pe10_c6_same_chat_gpt_material_authoring_20261016.json"


class FrozenSameChatEvidenceTest(unittest.TestCase):
    def load_pair(self):
        frozen=json.loads(SNAPSHOT.read_text(encoding="utf-8"))
        return frozen["handoff"], frozen["capture"]

    def test_frozen_gpt_material_has_exact_hash_and_source(self):
        h,c=self.load_pair()
        self.assertEqual(h["schema"],"LF_PE10_V02_SAME_CHAT_NATIVE_HANDOFF_V1")
        self.assertEqual(c["schema"],"LF_PE10_V02_SAME_CHAT_RAW_CAPTURE_V1")
        self.assertEqual(h["handoff_sha256"],_sha({k:v for k,v in h.items() if k!="handoff_sha256"}))
        self.assertEqual(c["capture_sha256"],_sha({k:v for k,v in c.items() if k!="capture_sha256"}))
        self.assertEqual(c["raw_output_sha256"],_sha(c["raw_output"]))
        self.assertEqual(h["source_manifest_sha256"],_sha(h["source_manifest"]))
        self.assertEqual(h["executor_mode"],"GPT_NATIVE")
        self.assertEqual(h["conversation_scope"],"EXISTING_CONVERSATION_ONLY")
        self.assertIs(h["api_invocation"],False)
        self.assertIs(h["session_creation"],False)
        self.assertEqual(h["selected_method_ids"],c["raw_output"]["methods_applied"])
        self.assertEqual(h["handoff_sha256"],c["handoff_sha256"])
        self.assertIs(c["method_execution_certified"],False)
        self.assertIs(c["cutover_eligible"],False)
        self.assertEqual(len(h["source_manifest"]),1)
        item=h["source_manifest"][0]
        expected_ref="profiles/"+h["profile_slug"]+"/SKILL.md"
        self.assertEqual(item["ref"],expected_ref)
        p=ROOT/item["ref"]
        self.assertTrue(p.is_file(), "FROZEN_NATIVE_PROFILE_SOURCE_ABSENT")
        current=hashlib.sha256(p.read_bytes()).hexdigest()
        self.assertEqual(current,item["sha256"],
            "FROZEN_NATIVE_PROFILE_SOURCE_CURRENTNESS_DRIFT")

    def test_missing_real_independent_review_fails_closed(self):
        h,c=self.load_pair()
        def read_source(ref):
            p=ROOT/ref
            return p.read_bytes() if p.is_file() else None
        with self.assertRaises(MaterialBridgeBlocked):
            verify_native_material_pre_admission(
                handoff=h,capture=c,
                current_surface="CHATGPT_CURRENT_CONVERSATION",
                independent_review_receipt_id="00000000-0000-4000-8000-000000000000",
                github_source_readback=read_source,
                supabase_read_one=lambda sql,params: None,
            )

if __name__=="__main__":
    unittest.main()

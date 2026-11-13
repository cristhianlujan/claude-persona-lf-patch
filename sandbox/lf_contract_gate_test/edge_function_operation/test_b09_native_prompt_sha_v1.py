"""B09 prompt byte-level evidence, EKB source-bound. No network, no DB."""
import hashlib
import json
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
PROMPTS=ROOT/"docs/input-governance/b09-native-chat/prompts"
FILES=("B09_EXECUTOR_GPT_NATIVE_V1.txt","B09_JUEZ_MISMO_LLM_V1.txt")
MANIFEST=ROOT/"docs/input-governance/b09-native-chat/prompt_sha256_manifest_v1.json"

class B09NativePromptSHA(unittest.TestCase):
    def test_versioned_prompt_digest_and_distinct_instructions(self):
        digests={}
        for name in FILES:
            path=PROMPTS/name
            self.assertTrue(path.is_file(),str(path))
            content=path.read_bytes()
            self.assertTrue(content.endswith(b"\n"),"PROMPT_LF_FINAL_REQUIRED")
            self.assertIn(name[:-4].encode(),content,"VERSIONED_PROMPT_ID_MISSING")
            digests[name]=hashlib.sha256(content).hexdigest()
        self.assertNotEqual(*digests.values(),"JUDGE_AND_PRODUCER_PROMPT_IDENTICAL")
        if MANIFEST.is_file():
            data=json.loads(MANIFEST.read_text(encoding="utf-8"))
            self.assertEqual(data.get("status"),"DOCUMENTAL_ONLY_NO_PROVIDER_ATTESTATION")
            self.assertEqual(data.get("algorithm"),"SHA-256")
            self.assertEqual(data.get("prompts"),digests,"PROMPT_SHA_READBACK_DRIFT")
        for name,value in digests.items():
            print("PASS_B09_PROMPT_SHA256_READBACK "+name+" "+value,flush=True)

if __name__=="__main__":
    unittest.main()

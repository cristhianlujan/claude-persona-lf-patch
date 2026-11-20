"""No-network negative and positive tests for GET /body source readback."""
import importlib.util
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("edge_ig_v58_governed_readback_v1.py")
spec = importlib.util.spec_from_file_location("ig_v58_body", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
VALIDATOR = "input-governance-validator-v1"
AGENT = "input-governance-agent-v1"

class ManagementBodyReadbackTests(unittest.TestCase):
    def meta(self, slug=VALIDATOR, version=19, jwt=True):
        # Contract GET /functions/{slug} DOES NOT contain "files".
        return {"slug":slug, "version":version, "verify_jwt":jwt,
                "status":"ACTIVE", "ezbr_sha256":"bundle-not-source"}
    def test_sha_from_body_not_metadata_and_jwt(self):
        source=b"const x = 'not version metadata';\n"
        h=hashlib.sha256(source).hexdigest()
        result=mod.inspect_metadata(self.meta(), VALIDATOR, source)
        self.assertEqual(result["source_sha256"],h)
        self.assertEqual(result["source_transport"],"MANAGEMENT_BODY_UNBUNDLED_PINNED_CLI")
        self.assertTrue(result["verify_jwt"])
    def test_fail_closed_on_drift_jwt_target_and_source(self):
        source=b"const x=1;"
        h=hashlib.sha256(source).hexdigest()
        with self.assertRaisesRegex(mod.ReadbackBlocked,"SHA_MISMATCH"):
            mod.inspect_metadata(self.meta(), VALIDATOR, source, "0"*64)
        with self.assertRaisesRegex(mod.ReadbackBlocked,"JWT_DRIFT"):
            mod.inspect_metadata(self.meta(jwt=False), VALIDATOR, source)
        with self.assertRaisesRegex(mod.ReadbackBlocked,"VERSION_NOT_ADVANCED"):
            mod.inspect_metadata(self.meta(), VALIDATOR, source, min_version=20)
        with self.assertRaisesRegex(mod.ReadbackBlocked,"TARGET_NOT_ALLOWED"):
            mod.inspect_metadata(self.meta(), "other-function", source)
        with self.assertRaisesRegex(mod.ReadbackBlocked,"BODY_SOURCE_INVALID"):
            mod.inspect_metadata(self.meta(), VALIDATOR, b"")
        with self.assertRaisesRegex(mod.ReadbackBlocked,"IG_V58_VALIDATOR_NEGATIVE_NOT_DEPLOYED"):
            mod.inspect_metadata(self.meta(), VALIDATOR, source, h)
    def test_download_get_body_in_temp_and_no_repo_mutation(self):
        with tempfile.TemporaryDirectory() as d, patch.dict(os.environ,{"SUPABASE_ACCESS_TOKEN":"test-only-not-real"}):
            original=os.getcwd()
            os.chdir(d)
            self.addCleanup(os.chdir,original)
            Path("supabase").mkdir()
            Path("supabase/config.toml").write_text("[functions]\n")
            calls=[]
            def fake_cli(cmd, **kw):
                calls.append((cmd,kw))
                remote=Path(kw["cwd"])/mod.TARGETS[AGENT]
                remote.parent.mkdir(parents=True)
                remote.write_bytes(b"CURATOR_RECURATION_SUCCESSOR")
                return subprocess.CompletedProcess(cmd,0,stdout=b"",stderr=b"")
            source=mod.read_body_index(AGENT,runner=fake_cli)
            self.assertEqual(source,b"CURATOR_RECURATION_SUCCESSOR")
            self.assertEqual(len(calls),1)
            self.assertIn("--use-api",calls[0][0])
            self.assertIn("mhwmirqcgxxukpctffuv",calls[0][0])
            self.assertTrue(Path("supabase/config.toml").exists())
            self.assertFalse(Path(mod.TARGETS[AGENT]).exists())
    def test_download_failure_fails_closed(self):
        with tempfile.TemporaryDirectory() as d,patch.dict(os.environ,{"SUPABASE_ACCESS_TOKEN":"test-only-not-real"}):
            old=os.getcwd()
            try:
                os.chdir(d)
                Path("supabase").mkdir()
                Path("supabase/config.toml").write_text("[functions]\n")
                def fake_cli(cmd,**kw):
                    return subprocess.CompletedProcess(cmd,2,stdout=b"",stderr=b"private")
                with self.assertRaisesRegex(mod.ReadbackBlocked,"BODY_DOWNLOAD_FAILED"):
                    mod.read_body_index(VALIDATOR,runner=fake_cli)
            finally:
                os.chdir(old)

if __name__ == "__main__":
    unittest.main()

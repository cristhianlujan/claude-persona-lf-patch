from __future__ import annotations
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from analysis_a6_a9_app_factory_v1 import create_a6_a9_app
from build_a6_a9_shadow_candidate_v1 import build_candidate

class FactoryTest(unittest.TestCase):
    def test_default_off_no_transport_created(self):
        with patch("profile_runtime_api.app.create_app") as create, patch("analysis_a6_a9_app_factory_v1.PsycopgReadOne") as transport:
            settings=object();create_a6_a9_app(settings)
            create.assert_called_once_with(settings);transport.assert_not_called()

    def test_invalid_config_fails_before_app_or_connection(self):
        with patch("profile_runtime_api.app.create_app") as create, patch("analysis_a6_a9_app_factory_v1.PsycopgReadOne") as transport:
            with self.assertRaises(ValueError):create_a6_a9_app(config={"enabled":True})
            create.assert_not_called();transport.assert_not_called()

    def test_enabled_requires_explicit_connection(self):
        config={"schema_version":"A6_A9_COMPLETION_SHADOW_CONFIGURATION_V1","enabled":True,"bindings":[]}
        with patch("profile_runtime_api.app.create_app") as create:
            with self.assertRaises(ValueError):create_a6_a9_app(config=config)
            create.assert_not_called()

    def test_enabled_composes_without_connecting_or_executing_model(self):
        config={"schema_version":"A6_A9_COMPLETION_SHADOW_CONFIGURATION_V1","enabled":True,"bindings":[]}
        connection=dict(host="invalid.example",dbname="test",user="test-ro",password="synthetic")
        with patch("profile_runtime_api.app.create_app") as create, patch("psycopg.connect") as connect:
            engine=Mock();create_a6_a9_app(object(),config=config,connection=connection,engine_factory=engine)
            self.assertIn("completion_observer",create.call_args.kwargs)
            connect.assert_not_called();engine.assert_not_called()

class BundleTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.repo=self.root/"repo";self.repo.mkdir()
        self.git("init","-q");self.git("config","user.name","Test");self.git("config","user.email","test@example.invalid")
        (self.repo/"source.py").write_text("TRACKED = True\n");self.git("add","source.py");self.git("commit","-qm","test")
        self.revision=self.git("rev-parse","HEAD").strip()
    def tearDown(self):self.tmp.cleanup()
    def git(self,*args):return subprocess.run(["git","-C",str(self.repo),*args],check=True,capture_output=True,text=True).stdout

    def test_pinned_reproducible_and_worktree_secret_excluded(self):
        (self.repo/"source.py").write_text("DIRTY = True\n");(self.repo/"private.env").write_text("SYNTHETIC_SECRET=never-package\n")
        one=build_candidate(self.repo,self.revision,self.root/"one")
        two=build_candidate(self.repo,self.revision,self.root/"two")
        self.assertEqual(one["archive_sha256"],two["archive_sha256"])
        with tarfile.open(one["archive_path"]) as tar:
            self.assertNotIn("private.env",tar.getnames());self.assertEqual(tar.extractfile("source.py").read(),b"TRACKED = True\n")
        self.assertFalse(json.loads(Path(one["manifest_path"]).read_text())["deployment_allowed"])

    def test_exact_revision_and_external_output_required(self):
        for revision,out in [("HEAD",self.root/"bad"),(self.revision,self.repo/"output")]:
            with self.assertRaises(ValueError):build_candidate(self.repo,revision,out)

    def test_existing_artifact_not_overwritten(self):
        first=build_candidate(self.repo,self.revision,self.root/"out");before=Path(first["archive_path"]).read_bytes()
        with self.assertRaises(FileExistsError):build_candidate(self.repo,self.revision,self.root/"out")
        self.assertEqual(Path(first["archive_path"]).read_bytes(),before)

    def test_symlink_rejected_before_output(self):
        (self.repo/"link").symlink_to("source.py");self.git("add","link");self.git("commit","-qm","link")
        with self.assertRaisesRegex(ValueError,"UNSUPPORTED"):build_candidate(self.repo,self.git("rev-parse","HEAD").strip(),self.root/"out")
        self.assertFalse((self.root/"out").exists())

if __name__=="__main__":unittest.main()

"""Adversarial, offline tests for PG-01 governed Edge readback."""
import importlib.util
import io
import json
import unittest
from pathlib import Path
from urllib.error import HTTPError

SCRIPT = Path(__file__).with_name("edge_pg01_oidc_readback_v1.py")
spec = importlib.util.spec_from_file_location("pg01_readback", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Response:
    status = 200
    def __init__(self, payload):
        self.payload = payload
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def read(self, _limit):
        return json.dumps(self.payload).encode()

class Tests(unittest.TestCase):
    def setUp(self):
        self.doc = {"slug":"lf-pg01-oidc-authority-v1","status":"ACTIVE","verify_jwt":False,"version":3}

    def call(self, doc, mode="postdeploy", min_version=1):
        return module.check(mode,"fake-token",min_version, lambda req,timeout: Response(doc))

    def test_valid(self):
        self.assertEqual(self.call(self.doc,min_version=3)["result"],"READBACK_PASS")

    def test_strict_version(self):
        for version in (0,1,2,True,"4",None):
            with self.subTest(version=version):
                with self.assertRaises(ValueError):
                    self.call({**self.doc,"version":version},min_version=3)

    def test_wrong_slug(self):
        with self.assertRaisesRegex(ValueError,"SLUG_MISMATCH"):
            self.call({**self.doc,"slug":"another"})

    def test_wrong_jwt_mode(self):
        with self.assertRaisesRegex(ValueError,"STATUS_OR_JWT_MODE_MISMATCH"):
            self.call({**self.doc,"verify_jwt":True})

    def test_wrong_status(self):
        with self.assertRaisesRegex(ValueError,"STATUS_OR_JWT_MODE_MISMATCH"):
            self.call({**self.doc,"status":"INACTIVE"})

    def test_missing_token(self):
        with self.assertRaisesRegex(ValueError,"TOKEN_MISSING"):
            module.check("postdeploy","")

    def test_invalid_modes(self):
        with self.assertRaisesRegex(ValueError,"INVALID_MODE"):
            module.check("unsafe","fake-token")

    def test_404_predeploy_only(self):
        def not_found(_req,timeout):
            raise HTTPError(module.URL,404,"absent",{},io.BytesIO())
        self.assertEqual(module.check("predeploy","fake-token",opener=not_found)["result"],"PREDEPLOY_ABSENT")
        with self.assertRaisesRegex(ValueError,"READBACK_HTTP_404"):
            module.check("postdeploy","fake-token",opener=not_found)

    def test_invalid_minimum(self):
        for value in (0,True,-1,"3"):
            with self.subTest(value=value),self.assertRaisesRegex(ValueError,"INVALID_MIN_VERSION"):
                module.check("postdeploy","fake-token",value)

if __name__=="__main__":
    unittest.main()

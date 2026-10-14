"""Read-only scoped Supabase Management API token canary tests."""
import io
import json
import unittest
from urllib.error import HTTPError
from edge_management_credential_canary_v1 import (
    GET_URL, TARGET_SLUG, CanaryBlocked, verify_function_metadata,
    read_existing_function,
)

def meta():
    return {"slug": TARGET_SLUG, "status": "ACTIVE", "version": 23, "verify_jwt": False}

class FakeResponse:
    status = 200
    def __init__(self, data): self._data=data
    def __enter__(self): return self
    def __exit__(self, *args): return False
    def read(self, limit): return json.dumps(self._data).encode("utf-8")

class CanaryTests(unittest.TestCase):
    def test_valid_metadata(self):
        result = verify_function_metadata(meta())
        self.assertEqual(result["result"], "EDGE_MANAGEMENT_READ_PASS")
        self.assertFalse(result["deployed"])
        self.assertFalse(result["r17_authorized"])
        self.assertEqual(result["cp2_runs_started"], 0)

    def test_performs_exact_get(self):
        observed=[]
        def opener(req,timeout):
            observed.append((req.method,req.full_url,req.get_header("Authorization"),timeout))
            return FakeResponse(meta())
        result=read_existing_function("test-not-real-token",opener)
        self.assertEqual(observed,[("GET",GET_URL,"Bearer test-not-real-token",20)])
        self.assertEqual(result["target"], TARGET_SLUG)

    def test_missing_token(self):
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_TOKEN_MISSING"):
            read_existing_function("")

    def test_mismatch_slug(self):
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_WRONG_FUNCTION"):
            verify_function_metadata(dict(meta(),slug="unrelated-function"))

    def test_unexpected_inactive(self):
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_FUNCTION_NOT_ACTIVE"):
            verify_function_metadata(dict(meta(),status="INACTIVE"))

    def test_verify_jwt_changed(self):
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_JWT_MODE_DRIFT"):
            verify_function_metadata(dict(meta(),verify_jwt=True))

    def test_invalid_version(self):
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_INVALID_VERSION"):
            verify_function_metadata(dict(meta(),version=True))

    def test_forged_nonobject(self):
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_RESPONSE_NOT_OBJECT"):
            verify_function_metadata([])

    def test_unauthorized_scrubs_token_and_body(self):
        def denial(req,timeout):
            raise HTTPError(req.full_url,401,"secret-internal-detail",hdrs=None,fp=io.BytesIO(b"secret"))
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_CREDENTIAL_DENIED_401") as err:
            read_existing_function("secret-token",denial)
        self.assertNotIn("secret-token",str(err.exception))
        self.assertNotIn("secret-internal-detail",str(err.exception))

    def test_forbidden(self):
        def denial(req,timeout):
            raise HTTPError(req.full_url,403,"not-permitted",hdrs=None,fp=None)
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_CREDENTIAL_DENIED_403"):
            read_existing_function("fake",denial)

    def test_not_found(self):
        def denial(req,timeout):
            raise HTTPError(req.full_url,404,"missing",hdrs=None,fp=None)
        with self.assertRaisesRegex(CanaryBlocked,"EDGE_MANAGEMENT_TARGET_NOT_FOUND"):
            read_existing_function("fake",denial)

    def test_no_unsafe_http_method_in_implementation(self):
        import inspect
        import edge_management_credential_canary_v1 as mod
        src = inspect.getsource(mod)
        self.assertIn('method="GET"',src)
        for op in ('method="POST"','method="PUT"','method="PATCH"','method="DELETE"'):
            self.assertNotIn(op,src)

if __name__=="__main__":
    unittest.main()

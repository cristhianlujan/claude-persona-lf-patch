import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_download_v1 import acquire

URL = "https://example.org/a.zip"


class Response(io.BytesIO):
    status = 200
    def __init__(self, data, size):
        super().__init__(data)
        self.headers = {"Content-Length":str(size)}
    def geturl(self):
        return URL


class TestAcquire(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = Path(self.dir.name)/"snapshot.zip"
        self.opener = Mock()
        self.policy = dict(allowed_urls={URL},max_bytes=3,attempts=2,socket_timeout=1,
                           deadline_seconds=2,backoff_seconds=.001,opener=self.opener)
    def test_partial_retry(self):
        self.opener.open.side_effect = [Response(b"a",3), Response(b"abc",3)]
        result = acquire(URL,self.path,**self.policy)
        self.assertEqual(result["attempts"],2)
        self.assertEqual(result["sha256"],hashlib.sha256(b"abc").hexdigest())
        self.assertEqual(list(self.path.parent.iterdir()),[self.path])
    def test_hash_failure_and_no_overwrite(self):
        self.opener.open.side_effect = [Response(b"abc",3),Response(b"abc",3)]
        with self.assertRaisesRegex(ValueError,"^SNAPSHOT_CHANGED$"):
            acquire(URL,self.path,expected_sha="0"*64,**self.policy)
        self.assertEqual(list(self.path.parent.iterdir()),[])
        self.path.write_bytes(b"original")
        with self.assertRaises(FileExistsError):
            acquire(URL,self.path,**self.policy)
        self.assertEqual(self.path.read_bytes(),b"original")
    def test_limit(self):
        self.opener.open.return_value = Response(b"abcd",3)
        with self.assertRaisesRegex(ValueError,"^DOWNLOAD_LIMIT$"):
            acquire(URL,self.path,**self.policy)
        self.assertEqual(list(self.path.parent.iterdir()),[])


if __name__ == "__main__":
    unittest.main()

import tempfile
import unittest
from pathlib import Path
from native_transport_capture_v1 import archive_pre_dispatch, CaptureRejected, sha, strict_json_bytes


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.root = Path(t.name)
        self.ref = self.root / 'reference.png'
        self.logo = self.root / 'logo.png'
        self.ref.write_bytes(b'fixture-reference')
        self.logo.write_bytes(b'fixture-logo')
        self.wire = strict_json_bytes({'prompt': 'Escena de prueba', 'attachments': [
            {'filename': 'reference.png', 'sha256': sha(self.ref.read_bytes())}]})
        self.refs = {'reference.png': str(self.ref)}
        self.fixed = {'Logo': {'path': str(self.logo), 'sha256': sha(self.logo.read_bytes()),
                               'source_ref': 'fixture:logo'}}

    def archive(self):
        return archive_pre_dispatch(self.wire, self.refs, self.fixed, self.root / 'attempt')

    def test_preserves_exact_bytes(self):
        r = self.archive()
        self.assertEqual((self.root / 'attempt/payload.json').read_bytes(), self.wire)
        self.assertEqual((self.root / 'attempt/protected/asset_1').read_bytes(), self.logo.read_bytes())
        self.assertEqual(r['reception_status'], 'NOT_SENT')
        self.assertFalse(r['invocation_recorded'])

    def test_reference_drift(self):
        self.ref.write_bytes(b'changed')
        with self.assertRaisesRegex(CaptureRejected, 'NATIVE_ARCHIVE_ATTACHMENT_DRIFT'):
            self.archive()
        self.assertFalse((self.root / 'attempt').exists())

    def test_logo_drift(self):
        self.logo.write_bytes(b'changed')
        with self.assertRaisesRegex(CaptureRejected, 'NATIVE_ARCHIVE_PROTECTED_DRIFT'):
            self.archive()
        self.assertFalse((self.root / 'attempt').exists())

    def test_no_overwrite(self):
        self.archive()
        with self.assertRaisesRegex(CaptureRejected, 'NATIVE_ARCHIVE_OUTPUT_EXISTS'):
            self.archive()
        self.assertEqual((self.root / 'attempt/payload.json').read_bytes(), self.wire)

"""D-07 regression against fixture; NOT evidence of real inventory validation."""
import hashlib
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from test_core import fixture
from pip1_core.core import PIPError, load_inventory

class OuterEnvelopeHashTests(unittest.TestCase):
    def source(self, root, mutate=None):
        obj = fixture()
        if mutate:
            mutate(obj)
        p = Path(root)/'inventory.json'
        p.write_text(json.dumps(obj, ensure_ascii=False, indent=2),encoding='utf-8')
        return p

    def test_correct_file_hash_accepted(self):
        with TemporaryDirectory() as tmp:
            p = self.source(tmp)
            expected = hashlib.sha256(p.read_bytes()).hexdigest()
            self.assertEqual(len(load_inventory(p,expected_file_sha256=expected).all_ids()),108)

    def test_changed_outer_proposal_detected_with_exact_file_hash(self):
        with TemporaryDirectory() as tmp:
            p = self.source(tmp)
            original = hashlib.sha256(p.read_bytes()).hexdigest()
            obj=json.loads(p.read_text())
            obj['excluded_proposals'][0]['reason']='PROPOSED_NOT_REQUIRED BUT TAMPERED'
            p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')
            with self.assertRaisesRegex(PIPError,'FULL_FILE_SHA256_MISMATCH'):
                load_inventory(p,expected_file_sha256=original)

    def test_changed_outer_proposal_without_expected_hash_is_a_documented_gap(self):
        with TemporaryDirectory() as tmp:
            p=self.source(tmp)
            obj=json.loads(p.read_text())
            obj['excluded_proposals'][1]['reason']='MODIFIED_TEXT_NOT_COVERED_BY_CORE_DIGEST'
            p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')
            with self.assertRaisesRegex(PIPError,'EXTERNAL_PIN_REQUIRED'):
                load_inventory(p)

    def test_invalid_expected_file_hash_is_blocked(self):
        with TemporaryDirectory() as tmp:
            p=self.source(tmp)
            with self.assertRaisesRegex(PIPError,'INVALID_EXPECTED_FILE_SHA256'):
                load_inventory(p,expected_file_sha256='bad')

if __name__=='__main__':
    unittest.main()

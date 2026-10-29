"""D-05: reference hash and source validation regression (not a real-file claim)."""
import unittest
from unittest.mock import patch
from pathlib import Path
from tempfile import TemporaryDirectory
from verify_exact_inventory import main, EXPECTED_FILE_SHA256

class TestSourceGuards(unittest.TestCase):
    def test_expected_full_sha256_is_pinned(self):
        self.assertEqual(EXPECTED_FILE_SHA256, 'fc4cd3a387858d3091bee99cbec85721744792db7fed5ffdc1cc348b1a2719c9')

    def test_invalid_source_does_not_create_verified_output(self):
        with TemporaryDirectory() as t:
            src, out = Path(t)/'source.json',Path(t)/'verified.json'
            src.write_text('{"inventory_core":{}}')
            with patch('sys.argv',['verify_exact_inventory.py','--file',str(src),'--out',str(out)]):
                with self.assertRaisesRegex(SystemExit,'BLOCKED: git blob SHA mismatch'):
                    main()
            self.assertFalse(out.exists())

if __name__ == '__main__':
    unittest.main()

import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "adapters"))
from sunat_company_v1 import MONTHLY_FIELDS, company, batches


class TestCompany(unittest.TestCase):
    def setUp(self):
        self.month = dict.fromkeys(MONTHLY_FIELDS, "")
        self.month.update(RUC="20000000001", Estado="ACTIVO", NroTrab="-", UBIGEO="110101")
        self.red = dict(RUC=self.month["RUC"], nombre=" EMPRESA Á ", estado="activo",
                        condicion="", ubigeo="150101")
        self.proof = dict(ordinal=1, zip_sha256="a"*64, header_sha256="b"*64,
                          url="https://example.org/test.zip")

    def build(self):
        return company(self.month, self.red, self.proof, dict(self.proof, ordinal=2))

    def test_capture(self):
        first = self.build()
        c = first["capture"]
        self.assertIsNone(c["normalized"]["workers_integer_literal"])
        self.assertTrue(c["derived"]["discrepancies"]["ubigeo"])
        self.assertFalse(c["derived"]["discrepancies"]["estado"])
        self.assertEqual(c["observations"]["reduced"]["raw"]["nombre"], " EMPRESA Á ")
        self.assertEqual(first, self.build())
        self.month["NroTrab"] = "0"
        self.assertEqual(self.build()["capture"]["normalized"]["workers_integer_literal"], 0)
        self.assertNotEqual(first["capture_sha256"], self.build()["capture_sha256"])

    def test_failures(self):
        self.red["RUC"] = "20000000002"
        with self.assertRaisesRegex(ValueError, "^JOIN_RUC$"):
            self.build()
        self.proof["ordinal"] = True
        with self.assertRaisesRegex(ValueError, "^SOURCE_ORDINAL$"):
            self.build()

    def test_batches(self):
        row = self.build()
        one, = batches([row], 1, 10000)
        self.assertEqual(json.loads(one), [row])
        self.assertEqual(list(batches([row]*2, 4, len(one))), [one, one])
        with self.assertRaisesRegex(ValueError, "^ROW_EXCEEDS_BATCH$"):
            list(batches([row], 4, len(one)-1))
        row["capture"]["normalized"]["razon_social"] = "changed"
        with self.assertRaisesRegex(ValueError, "^CAPTURE_HASH$"):
            list(batches([row], 1, 10000))


if __name__ == "__main__":
    unittest.main()

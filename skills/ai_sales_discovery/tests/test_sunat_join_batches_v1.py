import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"adapters"))
from sunat_join_batches_v1 import joined_batches
from sunat_company_v1 import MONTHLY_FIELDS


class TestJoin(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.policy=dict(spool_pages=500,max_source_rows=20,max_batch_rows=1,max_batch_bytes=8000,
                         directory=self.temp.name)

    def stream(self, keys, monthly):
        for ordinal, key in enumerate(keys,1):
            ruc=str(20000000000+key)
            proof=dict(ordinal=ordinal, zip_sha256="1"*64,header_sha256="2"*64,url="https://example.org/input")
            if monthly:
                m = dict.fromkeys(MONTHLY_FIELDS,"")
                m.update(RUC=ruc,NroTrab="NO DISPONIBLE")
                yield m,proof
            else:
                yield dict(RUC=ruc,nombre="Fixture",estado="",condicion="",ubigeo=""),proof

    def test_unique_only_and_replay(self):
        def run():
            return list(joined_batches(self.stream([4,3,2,1,1,5],True),
                         self.stream([2,2,1,3,4,6],False),**self.policy))
        payload=run()
        self.assertEqual(payload,run())
        self.assertEqual([json.loads(b)[0]["capture"]["normalized"]["ruc"] for b in payload],
                         ["20000000003","20000000004"])
        self.assertEqual(list(Path(self.temp.name).iterdir()),[])

    def test_terminal_crc_and_cleanup(self):
        def fails_at_eof():
            yield from self.stream([1],False)
            raise ValueError("TERMINAL_CRC")
        with self.assertRaisesRegex(ValueError,"^TERMINAL_CRC$"):
            next(joined_batches(self.stream([1],True),fails_at_eof(),**self.policy))
        self.assertEqual(list(Path(self.temp.name).iterdir()),[])

    def test_backpressure_and_cancel(self):
        self.policy["max_source_rows"]=1
        with self.assertRaisesRegex(ValueError,"^SOURCE_ROW_LIMIT$"):
            next(joined_batches(self.stream([1,2],True),(),**self.policy))
        batches=joined_batches(self.stream([1],True),self.stream([1],False),**self.policy)
        next(batches)
        batches.close()
        self.assertEqual(list(Path(self.temp.name).iterdir()),[])


if __name__=="__main__":
    unittest.main()

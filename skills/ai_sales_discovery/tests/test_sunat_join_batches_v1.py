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

    def test_commercial_gate_before_batches_threshold_50_and_sunat_dual(self):
        # Immutable observations: 49 and missing are not market, 50 qualifies exactly.
        samples=[
            (1,"49","ACTIVO","ACTIVO","HABIDO","HABIDO"),
            (2,"50","ACTIVO","ACTIVO","HABIDO","HABIDO"),
            (3,"NO DISPONIBLE","ACTIVO","ACTIVO","HABIDO","HABIDO"),
            (4,"50","ACTIVO","ACTIVO","NO HABIDO","HABIDO"),
            (5,"51","ACTIVO","BAJA DE OFICIO","HABIDO","HABIDO"),
            (6,"250","ACTIVO","ACTIVO","HABIDO","HABIDO"),
        ]
        def feed(monthly):
            for key,workers,em,er,cm,cr in samples:
                ruc=str(20000000000+key)
                evidence=dict(ordinal=key,zip_sha256="1"*64,header_sha256="2"*64,
                              url="https://example.org/input")
                if monthly:
                    row=dict.fromkeys(MONTHLY_FIELDS,"")
                    row.update(RUC=ruc,NroTrab=workers,Estado=em,Condicion=cm,
                               UBIGEO="150101")
                else:
                    row=dict(RUC=ruc,nombre="Fixture",estado=er,condicion=cr,ubigeo="150101")
                yield row,evidence
        def run(threshold=None):
            return list(joined_batches(feed(True),feed(False),**self.policy,
                                       commercial_min_workers=threshold))
        full=run()
        filtered=run(50)
        self.assertEqual(len(full),6)  # Prior pinned source branch is unchanged.
        self.assertEqual(
            [json.loads(p)[0]["capture"]["normalized"]["ruc"] for p in filtered],
            ["20000000002","20000000006"])
        self.assertEqual(
            [json.loads(p)[0]["capture"]["normalized"]["workers_integer_literal"] for p in filtered],
            [50,250])
        self.assertEqual(filtered,run(50))  # Replay deterministic.
        self.assertEqual(list(Path(self.temp.name).iterdir()),[])
        with self.assertRaisesRegex(ValueError,"^SUNAT_COMMERCIAL_POLICY_REQUIRED$"):
            run(0)

    def test_rejected_duplicate_still_poisoned_at_extraction(self):
        # Rejected duplicate is NOT removed from evidence of repeated RUC.
        # Otherwise the valid duplicate could be accepted accidentally.
        proof=dict(ordinal=1,zip_sha256="1"*64,header_sha256="2"*64,url="https://example.org/input")
        ruc="20000000999"
        def monthly():
            for workers in ("50","49"):
                row=dict.fromkeys(MONTHLY_FIELDS,"")
                row.update(RUC=ruc,NroTrab=workers,Estado="ACTIVO",
                           Condicion="HABIDO",UBIGEO="150101")
                yield row,proof
        def reduced():
            yield dict(RUC=ruc,nombre="Fixture",estado="ACTIVO",
                       condicion="HABIDO",ubigeo="150101"),proof
        self.assertEqual(list(joined_batches(monthly(),reduced(),**self.policy,
                                            commercial_min_workers=50)),[])
        # Same protection for a duplicate from the reduced feed.
        good=dict(RUC=ruc,nombre="Fixture",estado="ACTIVO",condicion="HABIDO",ubigeo="150101")
        def reduced_dup():
            yield dict(good),proof
            yield dict(good,estado="BAJA DE OFICIO"),proof
        def monthly_one():
            row=dict.fromkeys(MONTHLY_FIELDS,"")
            row.update(RUC=ruc,NroTrab="50",Estado="ACTIVO",
                       Condicion="HABIDO",UBIGEO="150101")
            yield row,proof
        self.assertEqual(list(joined_batches(monthly_one(),reduced_dup(),**self.policy,
                                            commercial_min_workers=50)),[])
        self.assertEqual(list(Path(self.temp.name).iterdir()),[])

    def test_existing_ruc_excluded_before_payload_and_invalid_inputs_fail_closed(self):
        def stream(monthly):
            for k in (1,2):
                ruc=str(20000000000+k)
                proof=dict(ordinal=k,zip_sha256="1"*64,header_sha256="2"*64,url="https://example.org/input")
                if monthly:
                    row=dict.fromkeys(MONTHLY_FIELDS,"")
                    row.update(RUC=ruc,NroTrab="50",Estado="ACTIVO",
                               Condicion="HABIDO",UBIGEO="150101")
                else:
                    row=dict(RUC=ruc,nombre="Fixture",estado="ACTIVO",
                             condicion="HABIDO",ubigeo="150101")
                yield row,proof
        def run(skip=None,threshold=50):
            return list(joined_batches(stream(True),stream(False),**self.policy,
                                       commercial_min_workers=threshold,existing_rucs=skip))
        self.assertEqual(len(run()),2)
        payloads=run({"20000000001"})
        self.assertEqual(len(payloads),1)
        self.assertEqual(json.loads(payloads[0])[0]["capture"]["normalized"]["ruc"],"20000000002")
        with self.assertRaisesRegex(ValueError,"^SUNAT_EXISTING_RUCS_CONTRACT$"):
            run(["20000000001"])
        with self.assertRaisesRegex(ValueError,"^SUNAT_EXISTING_RUCS_CONTRACT$"):
            run(set(),None)
        with self.assertRaisesRegex(ValueError,"^SUNAT_EXISTING_RUCS_CONTRACT$"):
            run({"INVALID"})
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

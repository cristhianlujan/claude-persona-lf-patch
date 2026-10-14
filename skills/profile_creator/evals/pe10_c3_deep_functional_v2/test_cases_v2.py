"""Preflight of V2 case bank. Not a GPT Native execution or semantic evaluation."""
from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
import sqlite3
import unittest
HERE=Path(__file__).resolve().parent
def readj(p):return json.loads((HERE/p).read_text(encoding="utf-8"))

class CasesV2Tests(unittest.TestCase):
    def test_twelve_balanced_cases(self):
        cases=readj("cases_v2.json")["cases"]
        self.assertEqual(len(cases),12)
        self.assertEqual(len({c["case_id"] for c in cases}),12)
        self.assertEqual(Counter(c["profile_slug"] for c in cases),{"quality_pack":4,"ui_architect":4,"product_director_lf":4})
        self.assertTrue(all(c["prompt"].strip() and c["output_requested"] for c in cases))
        for case in cases:
            for filename in case["fixture_files"]:self.assertTrue((HERE/filename).is_file(),filename)
    def test_hidden_oracle_frozen_for_every_case(self):
        bank=readj("cases_v2.json")
        oracle=readj("hidden_oracle_v2.json")
        expected={x["case_id"].rsplit("-",1)[-1] for x in bank["cases"]}
        self.assertEqual(set(oracle["case_oracles"]),expected)
        self.assertTrue(oracle["scoring"]["no_length_bonus"])
        self.assertTrue(oracle["paired_policy"]["arm_labels_blinded"])
    def test_stage_delivery_is_sequential(self):
        case=[c for c in readj("cases_v2.json")["cases"] if c["case_id"].endswith("212")][0]
        self.assertEqual(case["fixture_files"],["stages/case_212_stage_1.json"])
        stages=[readj(f"stages/case_212_stage_{i}.json") for i in (1,2,3)]
        self.assertEqual([s["stage"] for s in stages],[1,2,3])
        self.assertEqual([s["prior_turn_required"] for s in stages],[False,True,True])
        self.assertFalse("Y como titular actual" in stages[0]["input"])
    def test_reconciliation_fixture_reproducible(self):
        conn=sqlite3.connect(":memory:")
        conn.executescript((HERE/"fixtures/case_201_seed.sql").read_text(encoding="utf-8"))
        october=conn.execute("""SELECT COALESCE(SUM(monto),0) FROM pagos
                                  WHERE estado='CONFIRMED' AND fecha>='2026-10-01' AND fecha<'2026-11-01'""").fetchone()[0]
        settled=conn.execute("""SELECT COALESCE(SUM(monto),0) FROM liquidaciones
                                   WHERE fecha>='2026-10-01' AND fecha<'2026-11-01'""").fetchone()[0]
        self.assertEqual((october,settled,october-settled),(200,120,80))
        mismatches=conn.execute("""
        SELECT p.id, p.monto, p.fecha, ofr.obligacion_id AS correct_obligation,
               con.obligacion_id AS matched_obligation, ca.ref_externa
        FROM pagos p JOIN ofertas ofr ON p.oferta_id=ofr.id
        JOIN gateway g ON g.pago_id=p.id
        JOIN conciliaciones con ON con.gateway_id=g.id
        JOIN cartera ca ON ca.id=ofr.obligacion_id
        WHERE con.obligacion_id<>ofr.obligacion_id
        ORDER BY p.id
        """).fetchall()
        self.assertEqual(mismatches,[("P2",80,"2026-10-04","O2","O1","EXT-77"),
                                     ("P3",35,"2026-09-29","O3","O1","EXT-77")])
        collision=conn.execute("""SELECT ref_externa,COUNT(*),COUNT(DISTINCT carga_id)
                                  FROM cartera GROUP BY ref_externa HAVING COUNT(DISTINCT carga_id)>1""").fetchall()
        self.assertEqual(collision,[("EXT-77",3,3)])
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM bajas").fetchone()[0],0)
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM aprobaciones WHERE estado='APPROVED'").fetchone()[0],3)
        conn.close()
if __name__=="__main__":unittest.main()

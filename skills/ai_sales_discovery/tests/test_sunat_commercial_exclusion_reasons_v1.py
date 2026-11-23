"""Deterministic positive/negative checks for read-only SUNAT cause audit."""
import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "adapters"))
from sunat_commercial_exclusion_reasons_v1 import (
    rejection_reasons, aggregate_reasons, REASON_ORDER)


def item(n=50, em="ACTIVO", er="ACTIVO", cm="HABIDO", cr="HABIDO"):
    return {"capture": {
        "version": "sunat.company.v1", "source": "SUNAT",
        "normalized": {"workers_integer_literal": n},
        "observations": {
            "monthly": {"raw": {"Estado": em, "Condicion": cm}},
            "reduced": {"raw": {"estado": er, "condicion": cr}},
        },
    }}


def batches(rows):
    for idx, entries in enumerate(rows, 1):
        yield {"ordinal": idx, "rows": len(entries)}, json.dumps(entries).encode()


class TestAudit(unittest.TestCase):
    def test_each_failure_and_exact_threshold(self):
        cases = [
            (item(None), "SIN_DATO_EMPLEADOS"),
            (item(49), "MENOS_50_EMPLEADOS"),
            (item(em="BAJA"), "ESTADO_MENSUAL_NO_ACTIVO"),
            (item(er="BAJA"), "ESTADO_REDUCIDO_NO_ACTIVO"),
            (item(cm="NO HABIDO"), "CONDICION_MENSUAL_NO_HABIDO"),
            (item(cr="NO HABIDO"), "CONDICION_REDUCIDA_NO_HABIDO"),
        ]
        for sample, code in cases:
            with self.subTest(code=code):
                self.assertEqual(rejection_reasons(sample, min_workers=50), (code,))
        self.assertEqual(rejection_reasons(item(50), min_workers=50), ())
        self.assertEqual(len(REASON_ORDER), 7)

    def test_exclusive_and_overlapping_counts(self):
        dataset = [[item(50)], [item(None, em="BAJA"), item(49),
                                item(200, cr="NO HABIDO"), item(50)]]
        result = aggregate_reasons(batches(dataset), historical_batches=1,
                                   min_workers=50)
        self.assertEqual(result["historical_rows_skipped"], 1)
        self.assertEqual(result["scanned_remaining_rows"], 4)
        self.assertEqual(result["excluded_by_commercial_policy"], 3)
        self.assertEqual(result["eligible_before_existing_ruc_dedupe"], 1)
        self.assertEqual(result["multiple_causes"], 1)
        self.assertEqual(result["primary_reasons"]["SIN_DATO_EMPLEADOS"], 1)
        self.assertEqual(result["primary_reasons"]["MENOS_50_EMPLEADOS"], 1)
        self.assertEqual(result["primary_reasons"]["CONDICION_REDUCIDA_NO_HABIDO"], 1)
        self.assertEqual(result["overlapping_reasons"]["ESTADO_MENSUAL_NO_ACTIVO"], 1)
        self.assertEqual(sum(result["primary_reasons"].values()), 3)

    def test_contract_fail_closed(self):
        self.assertEqual(rejection_reasons({}, min_workers=50), ("CAPTURA_INVALIDA",))
        with self.assertRaisesRegex(ValueError, "AUDIT_POLICY_REQUIRED"):
            rejection_reasons(item(), min_workers=0)
        with self.assertRaisesRegex(ValueError, "AUDIT_BATCH_ORDER"):
            aggregate_reasons(iter([({"ordinal": 2, "rows": 1},
                                     json.dumps([item()]).encode())]),
                              historical_batches=0, min_workers=50)
        with self.assertRaisesRegex(ValueError, "AUDIT_BATCH_ROWS"):
            aggregate_reasons(iter([({"ordinal": 1, "rows": 2},
                                     json.dumps([item()]).encode())]),
                              historical_batches=0, min_workers=50)


if __name__ == "__main__":
    unittest.main()

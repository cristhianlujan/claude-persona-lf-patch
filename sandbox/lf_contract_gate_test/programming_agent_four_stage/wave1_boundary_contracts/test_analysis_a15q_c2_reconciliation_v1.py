#!/usr/bin/env python3
"""Tests for the A15Q_C2 reconciliation comparison (fixtures are test data, never evidence)."""
import copy
import unittest

import analysis_a15q_c2_reconciliation_v1 as m


def sb_from(git):
    rows = []
    for u in m.UNITS:
        rows.append({"checkpoint_code": f"{u}Q_C1", "status": "DONE",
                     "evidence_ref": f"github://x/runs/1;gitcommit:abc;artifact:sha256:{'1'*64};sha256:{git['c1_source_sha256'][u]};actor:lf-migration-train[bot]"})
        for c in (2, 3):
            h = f"{abs(hash((u, c))) % 10**8:08d}".encode().hex().ljust(64, "0")[:64]
            rows.append({"checkpoint_code": f"{u}Q_C{c}", "status": "DONE", "stored_raw_sha256": h,
                         "evidence_ref": f"supabase://programacion.engineering_plan_units/{u}Q#x;raw_sha256:{h};tier:T"})
    rows.append({"checkpoint_code": "A15Q_C1", "status": "DONE",
                 "evidence_ref": f"github://x;sha256:{git['a15_manifest_sha256']};actor:lf-migration-train[bot]"})
    return {"rows": rows, "checkpoint_rows": 45, "pg01_fn_md5": "m" * 32, "pg01_fn_expected_md5": "m" * 32}


class T(unittest.TestCase):
    def setUp(self):
        self.git = m.git_side()
        self.sb = sb_from(self.git)

    def test_positive_on_real_git_side(self):
        self.assertEqual(self.git.get("git_internal_drift"), None)
        self.assertEqual(m.reconcile(self.git, self.sb), [])

    def bad(self, fn, prefix):
        sb = copy.deepcopy(self.sb); git = copy.deepcopy(self.git); fn(sb, git)
        out = m.reconcile(git, sb)
        self.assertTrue(any(x.startswith(prefix) for x in out), (prefix, out))

    def row(self, sb, code):
        return next(r for r in sb["rows"] if r["checkpoint_code"] == code)

    def test_negatives(self):
        self.bad(lambda s, g: g["c1_source_sha256"].__setitem__("A7", "0" * 64), "C1_SHA_MISMATCH:A7")
        self.bad(lambda s, g: self.row(s, "A3Q_C2").__setitem__("stored_raw_sha256", "0" * 64), "RAW_SHA_MISMATCH:A3Q_C2")
        self.bad(lambda s, g: self.row(s, "A14Q_C3").__setitem__("status", "PENDING"), "NOT_DONE:A14Q_C3")
        self.bad(lambda s, g: s["rows"].remove(self.row(s, "A9Q_C1")), "NOT_DONE:A9Q_C1")
        self.bad(lambda s, g: s.__setitem__("checkpoint_rows", 44), "CHECKPOINT_ROWS_NOT_45")
        self.bad(lambda s, g: s.__setitem__("pg01_fn_md5", "z" * 32), "PG01_GUARD_FINGERPRINT")
        self.bad(lambda s, g: s.__setitem__("pg01_fn_md5", None), "PG01_GUARD_FINGERPRINT")
        self.bad(lambda s, g: g["pg01_contract"].__setitem__("blob", "0" * 40), "PG01_CONTRACT_DRIFT")
        self.bad(lambda s, g: g.__setitem__("a15_manifest_sha256", "0" * 64), "A15_C1_MANIFEST_MISMATCH")
        self.bad(lambda s, g: self.row(s, "A15Q_C1").__setitem__("status", "PENDING"), "A15_C1_MANIFEST_MISMATCH")
        self.bad(lambda s, g: g.__setitem__("git_internal_drift", ["A2"]), "GIT_INTERNAL_DRIFT")
        self.bad(lambda s, g: g["dossier"].__setitem__("qualified_count", 1), "DOSSIER_SHAPE")

    def test_fresh_git_drift_detected(self):
        import tempfile, shutil, os
        tmp = tempfile.mkdtemp()
        try:
            for rel in ("docs/programming-agent", m.HERE.relative_to(m.REPO).as_posix()):
                shutil.copytree(m.REPO / rel, os.path.join(tmp, rel), dirs_exist_ok=True)
            p = os.path.join(tmp, m.HERE.relative_to(m.REPO).as_posix(), "analysis_stop_rule_contract_v1.json")
            open(p, "a").write(" ")
            g = m.git_side(__import__("pathlib").Path(tmp))
            self.assertIn("A8", g["git_internal_drift"])
            self.assertTrue(any(x.startswith("GIT_INTERNAL_DRIFT") for x in m.reconcile(g, self.sb)))
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()

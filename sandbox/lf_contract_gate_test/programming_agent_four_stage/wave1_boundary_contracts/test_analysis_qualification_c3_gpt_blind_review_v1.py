"""Tests for the generic C3 blind-review packet and its review verifier (synthetic reviews; no model is called)."""
import copy
import json
import unittest

import analysis_qualification_c3_gpt_blind_review_v1 as m

RAW = json.dumps({"hechos": ["Los clientes abandonan; no hay cifras aportadas por nadie.", "El piloto es urgente, sin fecha."],
                  "sin_solucion": True}, ensure_ascii=False, indent=2)
INP = {"input_literal": "Los clientes abandonan y el piloto es urgente.", "input_sha256": m.sha("Los clientes abandonan y el piloto es urgente."),
       "request_ref": "REQ-T"}
CFG = {"criterion": "Revisor confirma sin invención",
       "checks": [{"code": "K1", "statement": "uno"}, {"code": "K2", "statement": "dos"}, {"code": "K3", "statement": "tres"}],
       "replacements": [["no hay cifras aportadas por nadie.", "el 40% abandona."]], "decoy_must_fail_checks": ["K3"]}


def good_review(p, k):
    items = []
    for it in p["items"]:
        real = it["item_id"] == k["real_item_id"]
        checks = [{"code": c["code"], "result": "FAIL" if (not real and c["code"] == "K3") else "PASS",
                   "evidence_refs": ["Los clientes abandonan"], "note": "Observación suficiente."} for c in p["checks"]]
        items.append({"item_id": it["item_id"], "checks": checks,
                      "verdict": "PASS" if real else "FAIL", "rationale": "Racional suficientemente largo aquí."})
    return {"schema_version": m.REVIEW_SCHEMA, "unit": "AXQ", "items": items}


class T(unittest.TestCase):
    def setUp(self):
        self.p, self.k = m.build_packet("AX", CFG, RAW, INP, "https://chat/x")
        self.r = good_review(self.p, self.k)

    def v(self, r):
        return m.verify_review(json.dumps(r, ensure_ascii=False), self.p, self.k)

    def test_deterministic(self):
        p2, k2 = m.build_packet("AX", CFG, RAW, INP, "https://chat/x")
        self.assertEqual(self.p, p2)
        self.assertEqual(self.k, k2)

    def test_blind(self):
        s = json.dumps(self.p, ensure_ascii=False)
        self.assertNotIn("DECOY", s)
        self.assertNotIn("https://chat/x", s)
        self.assertNotIn("real_item_id", s)

    def test_good(self):
        self.assertEqual(self.v(self.r), "PASS")

    def test_rules_block(self):
        cfg = dict(CFG, rules_start="REGLA:", rules_end="\nFIN")
        pr = "producer text. REGLA: haz X y Y.\nFIN more"
        p, _ = m.build_packet("AX", cfg, RAW, INP, "https://chat/x", pr)
        self.assertEqual(p["rules_text"], "REGLA: haz X y Y.")
        self.assertIn("REGLAS DE LA ETAPA", p["prompt_for_gpt"])
        self.assertIn("REGLA: haz X y Y.", p["prompt_for_gpt"])
        self.assertNotIn("producer text", p["prompt_for_gpt"])
        with self.assertRaises(ValueError):
            m.build_packet("AX", cfg, RAW, INP, "https://chat/x")
        self.assertNotIn("rules_text", self.p)

    def test_decoy_unique_replacement(self):
        with self.assertRaises(ValueError):
            m.make_decoy(RAW, [["no existe", "x"]])
        with self.assertRaises(ValueError):
            m.make_decoy(RAW, [["Los", "Las"]]) if RAW.count("Los") != 1 else (_ for _ in ()).throw(ValueError())

    def neg(self, fn, code):
        r = copy.deepcopy(self.r)
        fn(r)
        self.assertEqual(self.v(r), "BLOCK:" + code)

    def test_negatives(self):
        real = lambda r: next(i for i in r["items"] if i["item_id"] == self.k["real_item_id"])
        dec = lambda r: next(i for i in r["items"] if i["item_id"] == self.k["decoy_item_id"])
        self.neg(lambda r: r.pop("unit"), "TOP_KEYS")
        self.neg(lambda r: r.update(schema_version="X"), "SCHEMA_OR_UNIT")
        self.neg(lambda r: r["items"].reverse(), "ITEMS_SHAPE")
        self.neg(lambda r: real(r).update(extra=1), "ITEM_KEYS")
        self.neg(lambda r: real(r)["checks"].reverse(), "CHECK_CODES")
        self.neg(lambda r: real(r)["checks"][0].update(result="MAYBE"), "CHECK_KEYS")
        self.neg(lambda r: real(r)["checks"][0].update(evidence_refs=[]), "EVIDENCE_SHAPE")
        self.neg(lambda r: real(r)["checks"][0].update(evidence_refs=["texto inventado que no existe"]), "EVIDENCE_NOT_VERBATIM")
        self.neg(lambda r: real(r)["checks"][0].update(note="corto"), "NOTE_SHORT")
        self.neg(lambda r: real(r).update(verdict="FAIL"), "VERDICT_INCONSISTENT")
        self.neg(lambda r: real(r).update(rationale="corto"), "RATIONALE_SHORT")
        self.neg(lambda r: (real(r)["checks"][1].update(result="FAIL"), real(r).update(verdict="FAIL")), "REAL_ITEM_NOT_PASS")
        self.neg(lambda r: (dec(r)["checks"][2].update(result="PASS"), dec(r).update(verdict="PASS")), "DECOY_NOT_FAIL")
        self.neg(lambda r: (dec(r)["checks"][2].update(result="PASS"), dec(r)["checks"][0].update(result="FAIL")), "DECOY_REQUIRED_CHECK_NOT_FAIL")
        self.assertEqual(m.verify_review("no json", self.p, self.k), "BLOCK:NOT_JSON")

    def test_swapped_roles_blocked(self):
        r = good_review(self.p, {**self.k, "real_item_id": self.k["decoy_item_id"], "decoy_item_id": self.k["real_item_id"]})
        self.assertEqual(self.v(r), "BLOCK:REAL_ITEM_NOT_PASS")


if __name__ == "__main__":
    unittest.main()

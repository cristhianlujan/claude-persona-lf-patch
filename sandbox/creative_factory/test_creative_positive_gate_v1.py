"""Tests de decisión creativa sin pedidos, imágenes, Native ni Supabase."""
import copy
import hashlib
import unittest

from creative_positive_gate_v1 import CreativeProcessBlocked, prepare_positive_review, SCHEMA


def fixture():
    literal = "Explora una Home SALY con creatividad y mejor jerarquía visual."
    hier = ["Tarjeta principal", "Logo oficial"]
    plan = {
        "business_code": "SALY",
        "literal_request": literal,
        "blueprint": {
            "schema_version": "CREATIVE_VISUAL_BLUEPRINT_V1",
            "mode": "PLAN_ONLY", "brand": "SALY",
            "intent": "Explorar dirección de arte del Home SALY",
            "art": "Una pantalla móvil de lectura clara y composición original",
            "hierarchy": hier,
            "guided": ["Ritmo consistente de separaciones"],
            "free": ["Tarjeta principal"],
            "design_lock": {
                "LOCK": {"hierarchy": hier},
                "GUIDED": ["Ritmo consistente de separaciones"],
                "FREE": ["Tarjeta principal"]
            }
        },
        "presentation": {"mode": "FULL_SCENE", "destination": "Pantalla móvil SALY"},
        "direction": {
            k: {"instruction": "Presenta una relación clara entre cifra, acción y contexto",
                "rationale": "La cifra disponible es la primera lectura",
                "requirements": ["R1"]}
            for k in ("scene", "style", "background", "typography", "hierarchy", "visual_impact")
        },
        "components": [
            {"name": "Tarjeta principal", "owner": "NATIVE", "freedom": "FREE",
             "instruction": "Propón agrupación alternativa de monto y acción",
             "copy": [], "source_ids": ["REQUEST"], "requirements": ["R1"]},
            {"name": "Logo oficial", "owner": "COMPOSITOR", "freedom": "LOCK",
             "instruction": "Componer el activo de marca vigente en su zona fija",
             "copy": [], "source_ids": ["BRAND"], "requirements": ["R2"]},
        ],
        "sources": [{
            "id": "BRAND", "business_code": "SALY", "ref": "source://brand/saly",
            "version": "v1", "status": "APPROVED",
            "text": "Logo oficial SALY aprobado por el titular",
            "sha256": hashlib.sha256(
                b"Logo oficial SALY aprobado por el titular").hexdigest()
        }],
        "requirements": [
            {"id": "R1", "source": "REQUEST", "quote": "creatividad"},
            {"id": "R2", "source": "BRAND", "quote": "Logo oficial SALY"}
        ]
    }
    decision = {
        "schema_version": SCHEMA, "mode": "EXPLORE_CREATIVE",
        "mode_evidence": {"source": "REQUEST", "quote": "creatividad"},
        "positive_outcomes": [
            {"goal": "Jerarquia", "visual_instruction":
             "Resalta el monto principal con tamaño relativo y contraste legibles",
             "source_ids": ["REQUEST"]},
            {"goal": "Lectura", "visual_instruction":
             "Agrupa los datos de descuento con sus etiquetas en un bloque secundario",
             "source_ids": ["REQUEST"]},
            {"goal": "Accion", "visual_instruction":
             "Da al botón de adelanto una posición dominante y cercana al disponible",
             "source_ids": ["REQUEST"]},
        ],
        "creative_zones": [
            {"component": "Tarjeta principal", "freedom": "FREE",
             "positive_direction":
             "Compón una tarjeta protagonista con el monto dominante y ritmo espacial claro"},
            {"component": "Logo oficial", "freedom": "LOCK",
             "positive_direction":
             "Reserva el espacio exacto del logo para la composición posterior oficial"}
        ],
        "alternatives": [
            {"id": "A", "visual_thesis": "Tarjeta compacta",
             "design_move": "Agrupa monto y acción en una sola tarjeta con ritmo vertical",
             "tradeoff": "Usa menos aire, gana proximidad"},
            {"id": "B", "visual_thesis": "Lectura editorial",
             "design_move": "Presenta el monto como titular separado de un bloque secundario apilado",
             "tradeoff": "Usa más aire, gana énfasis"}
        ],
        "selected_alternative": {
            "id": "B", "reason":
            "Da prioridad al disponible como primer foco de lectura sin esconder detalles"
        },
        "transport": {
            "recipient": "NATIVE_GRAPHIC_GENERATOR",
            "presentation": "FULL_SCENE",
            "source_ids": ["REQUEST", "BRAND"],
            "transmitted": False, "render_authorized": False,
        }
    }
    return plan, decision


class PositiveGateTests(unittest.TestCase):
    def test_explore_positive(self):
        plan, dec = fixture()
        original = copy.deepcopy((plan, dec))
        got = prepare_positive_review(plan, dec)
        self.assertEqual((plan, dec), original)
        self.assertEqual(got["status"], "CREATIVE_REVIEW_PREPARED_SEMANTIC_QA_PENDING")
        self.assertEqual(got["selected_alternative"], "B")
        self.assertIn("Presenta el monto como titular", got["prompt_review"])
        self.assertNotIn(" | NATIVE | ", got["prompt_review"])
        self.assertNotIn(" | COMPOSITOR | ", got["prompt_review"])
        self.assertNotIn("NOT_EVALUATED", got["prompt_review"])
        self.assertFalse(got["native_transmitted"])
        self.assertFalse(got["image_generation_allowed"])
        self.assertFalse(got["order_created"])
        self.assertEqual(got["qa_independent"], "NOT_EVALUATED")
        self.assertFalse(got["source_binary_attested"])
        self.assertEqual(len(got["prompt_sha256"]), 64)

    def test_correction_strict_legacy_no_free(self):
        p, d = fixture()
        p["blueprint"]["free"] = []
        p["blueprint"]["design_lock"]["FREE"] = []
        p["components"][0]["freedom"] = "LOCK"
        d["mode"] = "CORRECTION_STRICT"
        d["creative_zones"][0]["freedom"] = "LOCK"
        d["alternatives"] = [d["alternatives"][0]]
        d["selected_alternative"]["id"] = "A"
        got = prepare_positive_review(p, d)
        self.assertEqual(got["mode"], "CORRECTION_STRICT")

    def reject(self, code, modifier):
        p, d = fixture()
        modifier(p, d)
        with self.assertRaisesRegex(CreativeProcessBlocked, code):
            prepare_positive_review(p, d)

    def test_explore_no_free_rejected(self):
        self.reject("CREATIVE_EXPLORE_FREEDOM_EMPTY",
                    lambda p, d: (p["blueprint"].update(free=[]),
                                  p["blueprint"]["design_lock"].update(FREE=[]),
                                  p["components"][0].update(freedom="LOCK"),
                                  d["creative_zones"][0].update(freedom="LOCK")))

    def test_zone_widens_lock_rejected(self):
        self.reject("CREATIVE_ZONE_LOCK_MISMATCH",
                    lambda p, d: d["creative_zones"][1].update(freedom="FREE"))

    def test_copy_authored_requirement_rejected(self):
        self.reject("CREATIVE_BASE_COPY_UNGROUNDED",
                    lambda p, d: p["components"][0].update(copy=["S/ 90,000"]))

    def test_cross_business_source_rejected(self):
        self.reject("CREATIVE_BASE_SOURCE_CROSS_BUSINESS",
                    lambda p, d: p["sources"][0].update(business_code="LF"))

    def test_false_transport_authority_rejected(self):
        self.reject("CREATIVE_TRANSPORT_FALSE_AUTHORITY",
                    lambda p, d: d["transport"].update(transmitted=True))

    def test_fake_asset_assertion_rejected(self):
        self.reject("CREATIVE_TRANSPORT_FIELDS",
                    lambda p, d: d["transport"].update(binary_verified=True))

    def test_unbound_quote_rejected(self):
        self.reject("CREATIVE_MODE_NOT_GROUNDED",
                    lambda p, d: d["mode_evidence"].update(quote="cambia todo"))

    def test_fake_source_rejected(self):
        self.reject("CREATIVE_TRANSPORT_SOURCE_UNGROUNDED",
                    lambda p, d: d["transport"].update(source_ids=["FAKE"]))

    def test_cosmetic_only_rejected(self):
        self.reject("CREATIVE_ALTERNATIVES_NOT_DISTINCT",
                    lambda p, d: d["alternatives"][1].update(
                        design_move=d["alternatives"][0]["design_move"]))

    def test_unselected_concept_rejected(self):
        self.reject("CREATIVE_SELECTION_UNSUPPORTED",
                    lambda p, d: d["selected_alternative"].update(id="C"))

    def test_weak_generic_positive_rejected(self):
        self.reject("CREATIVE_OUTCOME_NOT_RENDERABLE",
                    lambda p, d: d["positive_outcomes"][0].update(
                        visual_instruction="más premium"))

    def test_inherited_lock_rejected(self):
        self.reject("CREATIVE_EXPLORE_CONTRADICTORY_LOCK",
                    lambda p, d: p["blueprint"].update(
                        restrictions=["Sin adornos ni elementos nuevos."]))

    def test_inherited_intent_rejected(self):
        self.reject("CREATIVE_EXPLORE_CONTRADICTORY_LOCK",
                    lambda p, d: p["blueprint"].update(
                        intent="Corregir las dos pantallas anteriores, no rediseñar"))

    def test_malformed_restrictions_rejected(self):
        self.reject("CREATIVE_RESTRICTIONS_SHAPE",
                    lambda p, d: p["blueprint"].update(restrictions="No tocar"))

    def test_unhashable_source_rejected_with_named_control(self):
        self.reject("CREATIVE_TRANSPORT_SOURCE_UNGROUNDED",
                    lambda p, d: d["transport"].update(source_ids=[["BRAND"]]))

    def test_duplicate_transport_ref_rejected(self):
        self.reject("CREATIVE_TRANSPORT_SOURCE_DUPLICATE",
                    lambda p, d: d["transport"].update(source_ids=["REQUEST", "REQUEST"]))

    def test_strict_single_positive_outcome(self):
        p, d = fixture()
        p["blueprint"]["free"] = []
        p["blueprint"]["design_lock"]["FREE"] = []
        p["components"][0]["freedom"] = "LOCK"
        d["mode"] = "CORRECTION_STRICT"
        d["creative_zones"][0]["freedom"] = "LOCK"
        d["positive_outcomes"] = d["positive_outcomes"][:1]
        d["alternatives"] = d["alternatives"][:1]
        d["selected_alternative"]["id"] = "A"
        self.assertEqual(prepare_positive_review(p, d)["mode"], "CORRECTION_STRICT")

    def test_missing_zone_rejected(self):
        self.reject("CREATIVE_ZONE_COVERAGE",
                    lambda p, d: d.update(creative_zones=d["creative_zones"][:1]))


if __name__ == "__main__":
    unittest.main()

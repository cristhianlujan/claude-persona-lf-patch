import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DOC = json.loads((ROOT / "story_onb004_legal_demo_routes_v1.json").read_text(encoding="utf-8"))

EXPECTED_ROUTES = {
    "LEGAL_POLITICA_PRIVACIDAD": "/legal/politica-de-privacidad",
    "LEGAL_TERMINOS_CONDICIONES": "/legal/terminos-y-condiciones",
    "LEGAL_POLITICA_COOKIES": "/legal/politica-de-cookies",
    "PANT_LIBRO_RECLAMACIONES": "/libro-de-reclamaciones",
}

assert DOC["schema_version"] == "STORY_ONB004_LEGAL_DEMO_ROUTES_V1"
assert DOC["status"] == "CANDIDATO"
assert DOC["legal_review"]["required"] is True
assert DOC["legal_review"]["state"] == "PENDING_LEGAL_REVIEW"
assert DOC["legal_review"]["production_use_allowed"] is False
assert DOC["legal_review"]["runtime_activation_allowed"] is False
assert DOC["legal_review"]["promotion_allowed"] is False

routes = {r["route_code"]: r for r in DOC["routes"]}
assert set(routes) == set(EXPECTED_ROUTES)
for code, path in EXPECTED_ROUTES.items():
    route = routes[code]
    assert route["route_pattern"] == path
    assert route["status"] == "CANDIDATO"
    assert route["authentication_required"] is False
    assert route["legal_review_state"] == "PENDING_LEGAL_REVIEW"

rules = DOC["service_model_guardrails"]
for required_true in (
    "original_and_current_owner_must_be_visible",
    "offer_exists_only_after_match",
    "customer_decides_whether_to_accept",
    "no_automatic_acceptance",
    "no_debt_consolidation_claim",
    "no_guaranteed_discount",
    "no_guaranteed_score_improvement",
    "no_guaranteed_credit_bureau_removal",
    "one_time_or_installment_payment_only_if_offered",
    "carta_de_no_adeudo_support_after_fulfillment",
    "marketing_consent_optional",
    "operational_communications_not_conditioned_on_marketing_consent",
):
    assert rules[required_true] is True, required_true

terms = " ".join(s["text"] for s in DOC["candidate_copy"]["terms"]["sections"])
for phrase in (
    "no otorga crédito",
    "no consolida deudas",
    "acreedor original",
    "titular actual",
    "no garantiza descuentos",
    "no garantiza la mejora del score crediticio",
    "Carta de No Adeudo",
):
    assert phrase in terms, phrase

privacy = DOC["candidate_copy"]["privacy"]
assert "Ley 29733 - Ley de Protección de Datos Personales" in privacy["legal_framework"]
assert "DS 016-2024-JUS - Reglamento de la Ley 29733" in privacy["legal_framework"]
privacy_text = " ".join(s["text"] for s in privacy["sections"])
assert "match con titulares actuales" in privacy_text
assert "comunicaciones comerciales requieren una autorización separada" in privacy_text

complaints = DOC["candidate_copy"]["complaints"]
assert complaints["public_without_authentication"] is True
assert complaints["current_reference_response_days_business"] == 15
assert complaints["response_period_state"] == "PENDING_LEGAL_REVALIDATION_BEFORE_PRODUCTION"

story_effect = DOC["story_effect"]
assert story_effect["demo_route_pattern_blocker"] == "RESOLVED_FOR_DEMO_CANDIDATE"
assert story_effect["production_legal_readiness"] == "BLOCKED_PENDING_LEGAL_REVIEW"
assert story_effect["do_not_mark_story_production_ready"] is True

assert all(b["copy_reuse"] == "DENY" for b in DOC["benchmark_basis"])

print("STORY_ONB004_LEGAL_DEMO_ROUTES_V1 PASS")

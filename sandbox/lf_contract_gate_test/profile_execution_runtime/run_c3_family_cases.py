#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re

import run_c3_core_cases_v2 as c3v2

core = c3v2.core
base = c3v2.base


def _case(key: str, family: str, mode: str, title: str, bullets: list[str], specialties: str) -> dict:
    requirements = "\n".join(f"- {b}" for b in bullets)
    return {
        "key": key,
        "family": family,
        "mode": mode,
        "input": f"""Define una nueva pantalla: {title}.

Requisitos autorizados y obligatorios:
{requirements}

Modo operativo: {mode}.
Especialidades activas: {specialties}.

Conserva todos los requisitos suministrados.
No inventes montos, fechas, criterios, canales, efectos legales ni estados no proporcionados.""",
    }


FAMILIES = {
    "OFFER_PRICING": [
        _case("OFFER_01", "OFFER_PRICING", "PILOT", "oferta de deuda", ["Deuda original: S/ 8,000", "Oferta: S/ 3,200", "Ahorro: S/ 4,800", "Formas de pago: contado o cuotas", "Debe existir un CTA principal."], "financial UX, trust clarity"),
        _case("OFFER_02", "OFFER_PRICING", "EXPERT", "comparación de oferta", ["Deuda original: S/ 12,500", "Oferta vigente: S/ 7,250", "Debe mostrarse el ahorro calculado como concepto, sin inventar otro monto.", "Debe existir opción de pago único.", "No debe mostrarse una tasa de interés no proporcionada."], "financial UX, offers campaigns"),
        _case("OFFER_03", "OFFER_PRICING", "FULL", "resumen de negociación", ["Saldo informado: S/ 4,950", "Monto de cierre autorizado: S/ 2,700", "Debe diferenciarse claramente saldo informado y monto de cierre.", "No inventar descuentos porcentuales.", "Debe existir una acción para continuar."], "financial UX, trust clarity"),
        _case("OFFER_04", "OFFER_PRICING", "PILOT", "oferta con dos alternativas", ["Alternativa A: pago único de S/ 1,900", "Alternativa B: pago en cuotas por un total de S/ 2,400", "Las dos alternativas deben ser visibles.", "No inventar número de cuotas para la alternativa B.", "Debe existir selección explícita de alternativa."], "financial UX, choice architecture"),
        _case("OFFER_05", "OFFER_PRICING", "EXPERT", "oferta sin monto definitivo", ["Debe mostrarse que existe una oferta disponible.", "El monto definitivo todavía no fue proporcionado.", "No debe inventarse un monto de oferta.", "Debe existir un CTA para revisar la oferta.", "No debe presentarse urgencia artificial."], "financial UX, trust clarity"),
    ],
    "INSTALLMENTS_LIFECYCLE": [
        _case("INST_01", "INSTALLMENTS_LIFECYCLE", "EXPERT", "gestión de pago en cuotas", ["Deben existir exactamente 3 cuotas.", "Debe ser visible el concepto de vencimiento de cada cuota, sin inventar fechas concretas.", "Medio de pago: tarjeta.", "Debe existir manejo visible de fallo y reintento.", "Debe existir comprobante.", "La carta de no adeudo solo puede mostrarse como disponible después de completar todas las cuotas."], "payments recovery, trust clarity, documents evidence"),
        _case("INST_02", "INSTALLMENTS_LIFECYCLE", "FULL", "plan de cuatro cuotas", ["Deben existir exactamente 4 cuotas.", "Cada cuota debe tener un estado visible.", "No inventar fechas de vencimiento.", "Debe distinguirse cuota pendiente de cuota pagada.", "El cierre del plan ocurre solo después de pagar la cuarta cuota."], "payments recovery, state design"),
        _case("INST_03", "INSTALLMENTS_LIFECYCLE", "PILOT", "primer pago de plan", ["Debe mostrarse que el plan todavía no inició.", "El primer pago activa el plan.", "No debe mostrarse el plan como completado antes del primer pago.", "Debe existir confirmación después del primer pago.", "No inventar número total de cuotas."], "payments recovery, trust clarity"),
        _case("INST_04", "INSTALLMENTS_LIFECYCLE", "EXPERT", "cuota con reintento", ["Debe existir un estado de pago fallido.", "El reintento solo está disponible después de un fallo.", "Un reintento exitoso cambia el estado a pagado.", "Debe existir comprobante después de pago exitoso.", "No inventar penalidades por fallo."], "payments recovery, state design"),
        _case("INST_05", "INSTALLMENTS_LIFECYCLE", "FULL", "cierre de plan", ["Debe mostrarse el progreso del plan de cuotas.", "La última cuota debe identificarse como final.", "La carta de no adeudo no está disponible mientras existan cuotas pendientes.", "La carta de no adeudo pasa a disponible después del pago final.", "No inventar tiempos de emisión de la carta."], "payments recovery, documents evidence"),
    ],
    "IDENTITY_AUTH": [
        _case("ID_01", "IDENTITY_AUTH", "FULL", "identidad y autenticación", ["DNI requerido.", "OTP requerido.", "El OTP se solicita después de ingresar el DNI.", "No inventar una cantidad máxima de intentos.", "Debe existir un estado visible de OTP inválido."], "identity consent privacy, trust clarity"),
        _case("ID_02", "IDENTITY_AUTH", "PILOT", "validación de identidad", ["DNI requerido.", "Fecha de nacimiento opcional.", "No inventar validaciones biométricas.", "Debe existir una acción para validar identidad.", "La continuación ocurre solo después de validación exitosa."], "identity consent privacy"),
        _case("ID_03", "IDENTITY_AUTH", "EXPERT", "OTP con reenvío", ["OTP requerido.", "Debe existir opción de reenviar OTP.", "No inventar tiempo de espera para reenvío.", "Debe existir estado de OTP expirado.", "Un OTP expirado no permite continuar."], "identity consent privacy, recovery UX"),
        _case("ID_04", "IDENTITY_AUTH", "FULL", "sesión autenticada", ["La pantalla requiere identidad validada.", "Debe mostrarse un estado de sesión no validada.", "No inventar duración de sesión.", "El contenido protegido solo se muestra después de validar identidad.", "Debe existir una acción para volver a validar."], "identity consent privacy, state design"),
        _case("ID_05", "IDENTITY_AUTH", "EXPERT", "datos mínimos de identidad", ["DNI requerido.", "Nombres requeridos.", "Correo electrónico opcional.", "No solicitar información laboral.", "No inventar criterios de elegibilidad a partir de identidad."], "identity consent privacy, data minimization"),
    ],
    "CONSENT_CHANNELS": [
        _case("CONSENT_01", "CONSENT_CHANNELS", "FULL", "consentimiento de contacto", ["Consentimiento explícito para contacto por WhatsApp y correo electrónico.", "WhatsApp y correo electrónico deben nombrarse de forma visible.", "El consentimiento no puede inferirse por continuar.", "Debe existir una acción explícita de aceptación.", "No inventar otros canales de contacto."], "identity consent privacy, trust clarity"),
        _case("CONSENT_02", "CONSENT_CHANNELS", "EXPERT", "preferencias de canal", ["WhatsApp está disponible como canal.", "Correo electrónico está disponible como canal.", "SMS no fue autorizado y no debe ofrecerse.", "Debe poder elegirse entre los canales autorizados.", "No seleccionar un canal por defecto sin indicación."], "consent privacy, choice architecture"),
        _case("CONSENT_03", "CONSENT_CHANNELS", "PILOT", "consentimiento opcional", ["El consentimiento de comunicaciones comerciales es opcional.", "La negativa no debe bloquear la continuación.", "Debe distinguirse consentimiento opcional de aceptación obligatoria de la operación.", "No inventar beneficios por aceptar comunicaciones.", "Debe existir una opción visible para no aceptar."], "consent privacy, trust clarity"),
        _case("CONSENT_04", "CONSENT_CHANNELS", "FULL", "revocación de canal", ["Debe mostrarse que una preferencia de contacto puede modificarse.", "WhatsApp es el canal actualmente seleccionado.", "No inventar una fecha de vigencia del cambio.", "Debe existir una acción para cambiar preferencia.", "No afirmar efectos legales no proporcionados."], "consent privacy, settings UX"),
        _case("CONSENT_05", "CONSENT_CHANNELS", "EXPERT", "doble canal autorizado", ["Contacto por WhatsApp autorizado.", "Contacto por correo electrónico autorizado.", "Ambos canales deben conservarse como autorizados.", "No sustituir un canal por el otro.", "No inventar autorización para llamadas telefónicas."], "consent privacy, channel governance"),
    ],
    "DOCUMENTS_EVIDENCE": [
        _case("DOC_01", "DOCUMENTS_EVIDENCE", "FULL", "carga documental", ["La carga de documento es opcional.", "Debe indicarse claramente que el documento es opcional.", "No inventar un tipo de documento obligatorio.", "Debe existir una acción de carga.", "La omisión del documento no debe bloquear la continuación."], "documents evidence, trust clarity"),
        _case("DOC_02", "DOCUMENTS_EVIDENCE", "EXPERT", "comprobante de pago", ["Debe existir comprobante después de un pago exitoso.", "No mostrar comprobante antes de confirmar el pago.", "Debe existir una acción para revisar el comprobante.", "No inventar número de operación.", "No inventar fecha de emisión."], "documents evidence, payments recovery"),
        _case("DOC_03", "DOCUMENTS_EVIDENCE", "FULL", "carta de no adeudo", ["Debe existir el concepto de carta de no adeudo.", "La carta solo está disponible después de completar la obligación.", "Mientras la obligación esté pendiente, la carta no debe mostrarse como disponible.", "No inventar plazo de emisión.", "Debe existir un estado visible de disponibilidad."], "documents evidence, trust clarity"),
        _case("DOC_04", "DOCUMENTS_EVIDENCE", "PILOT", "evidencia opcional", ["Puede adjuntarse evidencia de pago de forma opcional.", "No inventar formatos permitidos.", "No inventar tamaño máximo de archivo.", "Debe existir una acción para adjuntar evidencia.", "La evidencia adjunta debe mostrarse como registrada."], "documents evidence"),
        _case("DOC_05", "DOCUMENTS_EVIDENCE", "EXPERT", "documentación pendiente", ["Debe mostrarse un estado de documentación pendiente.", "Debe mostrarse un estado de documentación recibida.", "No inventar documentos faltantes concretos.", "La transición a recibida ocurre después de registrar la documentación.", "Debe existir trazabilidad visible del estado."], "documents evidence, state design"),
    ],
    "TEMPORAL_CONDITIONAL": [
        _case("TEMP_01", "TEMPORAL_CONDITIONAL", "EXPERT", "acción condicionada", ["El CTA de pago solo está disponible después de seleccionar una oferta.", "Antes de seleccionar una oferta, el CTA no debe mostrarse como habilitado.", "No inventar un tiempo límite.", "Debe existir una selección de oferta.", "Debe existir un estado visible del CTA."], "state design, trust clarity"),
        _case("TEMP_02", "TEMPORAL_CONDITIONAL", "FULL", "confirmación posterior", ["La confirmación solo aparece después de completar la operación.", "Mientras la operación esté pendiente, debe mostrarse estado pendiente.", "No mostrar éxito antes de completar la operación.", "No inventar duración del proceso.", "Debe existir una acción para revisar el estado."], "state design, payments recovery"),
        _case("TEMP_03", "TEMPORAL_CONDITIONAL", "PILOT", "vigencia conceptual", ["Debe mostrarse el concepto de vigencia de la oferta.", "No inventar fecha concreta de expiración.", "Cuando la oferta ya no esté vigente, debe existir un estado expirado.", "Una oferta expirada no permite continuar al pago.", "Debe existir una acción para volver a revisar ofertas."], "offers campaigns, state design"),
        _case("TEMP_04", "TEMPORAL_CONDITIONAL", "EXPERT", "dependencia documental", ["La descarga del documento solo se habilita después de que el documento esté disponible.", "Antes de estar disponible, debe mostrarse estado pendiente.", "No inventar fecha de disponibilidad.", "Debe existir una acción de descarga cuando corresponda.", "No mostrar el documento como emitido antes de estar disponible."], "documents evidence, state design"),
        _case("TEMP_05", "TEMPORAL_CONDITIONAL", "FULL", "secuencia de validación", ["Primero debe validarse identidad.", "Después de validar identidad puede solicitarse consentimiento.", "La oferta solo se muestra después de identidad validada y consentimiento requerido completado.", "No alterar el orden de la secuencia.", "No inventar pasos intermedios."], "identity consent privacy, offers campaigns"),
    ],
    "ALTERNATIVES_CARDINALITY": [
        _case("CARD_01", "ALTERNATIVES_CARDINALITY", "EXPERT", "dos alternativas", ["Deben existir exactamente 2 alternativas de pago.", "Alternativa 1: pago único.", "Alternativa 2: pago en cuotas.", "No agregar una tercera alternativa.", "Debe poder seleccionarse solo una alternativa a la vez."], "choice architecture, financial UX"),
        _case("CARD_02", "ALTERNATIVES_CARDINALITY", "FULL", "tres canales", ["Deben mostrarse exactamente 3 canales autorizados: WhatsApp, correo electrónico y llamada.", "Los tres canales deben permanecer visibles.", "No inventar un cuarto canal.", "Debe poder elegirse un canal preferido.", "No eliminar canales no seleccionados."], "channel governance, choice architecture"),
        _case("CARD_03", "ALTERNATIVES_CARDINALITY", "PILOT", "dos documentos opcionales", ["Existen exactamente 2 documentos opcionales: comprobante y constancia.", "Ambos documentos son opcionales.", "No convertirlos en obligatorios.", "No agregar otros documentos.", "Debe poder adjuntarse uno, ambos o ninguno."], "documents evidence, choice architecture"),
        _case("CARD_04", "ALTERNATIVES_CARDINALITY", "EXPERT", "cuatro cuotas exactas", ["Deben existir exactamente 4 cuotas.", "Las cuatro cuotas deben ser visibles.", "No agregar ni eliminar cuotas.", "No inventar montos por cuota.", "Debe existir estado individual para cada cuota."], "payments recovery, state design"),
        _case("CARD_05", "ALTERNATIVES_CARDINALITY", "FULL", "una acción primaria", ["Debe existir exactamente 1 CTA principal.", "Puede existir una acción secundaria para volver.", "La acción secundaria no debe competir como CTA principal.", "No agregar otro CTA principal.", "Debe conservarse la jerarquía entre acción principal y secundaria."], "visual hierarchy, trust clarity"),
    ],
    "NEGATIVE_CONSTRAINTS": [
        _case("NEG_01", "NEGATIVE_CONSTRAINTS", "FULL", "elegibilidad sin criterios", ["Debe existir un mensaje de elegibilidad.", "No inventar criterios de elegibilidad.", "No inventar score crediticio.", "No inventar ingreso mínimo.", "Debe existir una acción para continuar si corresponde."], "trust clarity, eligibility messaging"),
        _case("NEG_02", "NEGATIVE_CONSTRAINTS", "EXPERT", "oferta sin urgencia artificial", ["Debe mostrarse una oferta disponible.", "No inventar fecha de expiración.", "No inventar contador regresivo.", "No afirmar que es la última oportunidad.", "Debe existir una acción para revisar condiciones."], "offers campaigns, trust clarity"),
        _case("NEG_03", "NEGATIVE_CONSTRAINTS", "PILOT", "pago sin penalidades inventadas", ["Debe existir opción de pago con tarjeta.", "Debe existir manejo de fallo.", "No inventar penalidad por fallo.", "No inventar comisión adicional.", "Debe existir opción de reintento después de fallo."], "payments recovery, trust clarity"),
        _case("NEG_04", "NEGATIVE_CONSTRAINTS", "FULL", "documento sin efecto legal inventado", ["Debe mostrarse una constancia disponible.", "No afirmar que la constancia elimina obligaciones legales no proporcionadas.", "No inventar una garantía legal.", "Debe existir acción de descarga.", "Debe conservarse lenguaje factual."], "documents evidence, trust clarity"),
        _case("NEG_05", "NEGATIVE_CONSTRAINTS", "EXPERT", "identidad sin datos extra", ["DNI requerido.", "No solicitar salario.", "No solicitar estado civil.", "No solicitar empleador.", "Debe existir una acción para validar el DNI."], "identity consent privacy, data minimization"),
    ],
    "STATES_RECOVERY": [
        _case("STATE_01", "STATES_RECOVERY", "EXPERT", "pago fallido", ["Debe existir estado de pago fallido.", "Debe existir acción de reintento.", "El reintento solo está disponible después del fallo.", "Un pago exitoso posterior cambia el estado a pagado.", "No inventar causa específica del fallo."], "payments recovery, state design"),
        _case("STATE_02", "STATES_RECOVERY", "FULL", "operación pendiente", ["Debe existir estado pendiente.", "Debe existir estado completado.", "No mostrar completado mientras siga pendiente.", "Debe existir una acción para actualizar el estado.", "No inventar tiempo de resolución."], "state design, trust clarity"),
        _case("STATE_03", "STATES_RECOVERY", "PILOT", "documento en procesamiento", ["Debe existir estado en procesamiento.", "Debe existir estado disponible.", "La descarga solo aparece en estado disponible.", "No inventar tiempo de procesamiento.", "Debe existir una acción para revisar nuevamente."], "documents evidence, state design"),
        _case("STATE_04", "STATES_RECOVERY", "EXPERT", "OTP inválido", ["Debe existir estado de OTP inválido.", "Debe existir acción para intentar nuevamente.", "No inventar número máximo de intentos.", "Un OTP válido permite continuar.", "Un OTP inválido no permite continuar."], "identity consent privacy, recovery UX"),
        _case("STATE_05", "STATES_RECOVERY", "FULL", "oferta expirada", ["Debe existir estado de oferta vigente.", "Debe existir estado de oferta expirada.", "Una oferta expirada no permite pago.", "No inventar fecha de expiración.", "Debe existir una acción para revisar nuevas ofertas."], "offers campaigns, state design"),
    ],
    "MULTI_DOMAIN_COMPLEX": [
        _case("MIX_01", "MULTI_DOMAIN_COMPLEX", "FULL", "identidad, oferta y pago", ["DNI requerido.", "OTP requerido después del DNI.", "Debe mostrarse una oferta sin inventar monto.", "Debe existir selección entre pago único o cuotas.", "La acción de pago solo se habilita después de seleccionar una alternativa.", "No inventar criterios de elegibilidad."], "identity consent privacy, financial UX, payments recovery"),
        _case("MIX_02", "MULTI_DOMAIN_COMPLEX", "EXPERT", "cuotas, fallo y documento", ["Deben existir exactamente 3 cuotas.", "Debe existir manejo de fallo y reintento.", "Debe existir comprobante después de pago exitoso.", "La carta de no adeudo solo está disponible después de completar todas las cuotas.", "No inventar fechas concretas.", "No inventar penalidades."], "payments recovery, documents evidence, trust clarity"),
        _case("MIX_03", "MULTI_DOMAIN_COMPLEX", "FULL", "consentimiento, canales y oferta", ["Consentimiento explícito para WhatsApp y correo electrónico.", "No inventar SMS como canal.", "Debe mostrarse el concepto de vigencia de oferta sin fecha concreta.", "Una oferta expirada no permite continuar.", "Debe existir mensaje de elegibilidad sin inventar criterios.", "Debe existir una acción principal."], "consent privacy, offers campaigns, trust clarity"),
        _case("MIX_04", "MULTI_DOMAIN_COMPLEX", "PILOT", "documento opcional y estado", ["La carga de documento es opcional.", "La omisión del documento no bloquea la continuación.", "Debe existir estado pendiente de operación.", "Debe existir estado completado después de finalizar.", "No inventar tiempo de procesamiento.", "Debe existir una acción para revisar estado."], "documents evidence, state design"),
        _case("MIX_05", "MULTI_DOMAIN_COMPLEX", "EXPERT", "oferta con evidencia y recuperación", ["Debe mostrarse una oferta disponible.", "Debe existir opción de pago con tarjeta.", "Debe existir estado de pago fallido y reintento.", "El comprobante solo aparece después de pago exitoso.", "No inventar monto de oferta.", "No inventar fecha de expiración."], "financial UX, payments recovery, documents evidence"),
    ],
}


def _normalize(value: str) -> str:
    return re.sub(r"\s+", " ", value.casefold()).strip()


def _authorized_currency(input_text: str) -> set[str]:
    return {
        re.sub(r"[^0-9]", "", value)
        for value in re.findall(r"S/\s*([0-9][0-9.,]*)", input_text, flags=re.I)
    }


def _authority(input_text: str, output_text: str) -> tuple[bool, dict]:
    allowed_currency = _authorized_currency(input_text)
    output_currency = {
        re.sub(r"[^0-9]", "", value)
        for value in re.findall(r"S/\s*([0-9][0-9.,]*)", output_text, flags=re.I)
    }
    invented_currency = sorted(v for v in output_currency if v and v not in allowed_currency)
    date_pattern = r"\b\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b"
    allowed_dates = set(re.findall(date_pattern, input_text))
    invented_dates = sorted(set(re.findall(date_pattern, output_text)) - allowed_dates)
    banned_claims = [
        "garantizado",
        "garantizada",
        "obligatorio por ley",
        "legalmente asegurado",
        "última oportunidad",
        "ultima oportunidad",
    ]
    input_low = input_text.casefold()
    output_low = output_text.casefold()
    invented_claims = sorted(term for term in banned_claims if term in output_low and term not in input_low)
    detail = {
        "invented_currency": invented_currency,
        "invented_dates": invented_dates,
        "invented_claim_terms": invented_claims,
    }
    return not any(detail.values()), detail


def _quality(case: dict, result: dict) -> dict:
    materialized = c3v2._materialized_text(result)
    bullets = c3v2._bullets(case["input"])
    normalized_materialized = _normalize(materialized)
    requirement_map = {
        f"REQ_{idx:02d}": _normalize(bullet) in normalized_materialized
        for idx, bullet in enumerate(bullets, 1)
    }
    canonical_pass, canonical_errors = core._canonical(result)
    authority_pass, authority_detail = _authority(case["input"], result.get("governed_output", ""))
    unresolved_placeholder = bool(re.search(r"\[[^\]\n]{2,80}\]", materialized))
    vector = {
        "json_ok": bool(result.get("json_ok")),
        "canonical_pass": canonical_pass,
        "structural_pass": bool(result.get("structural_pass")),
        "bounded_pass": bool(result.get("bounded_pass")),
        "requirements_pass": bool(requirement_map) and all(requirement_map.values()),
        "no_fences": not bool(result.get("fence")) and not bool(result.get("raw_fence")),
        "placeholder_pass": bool(result.get("placeholder_pass")) and not unresolved_placeholder,
        "authority_pass": authority_pass,
    }
    return {
        "vector": vector,
        "pass": all(vector.values()),
        "requirements": requirement_map,
        "canonical_errors": canonical_errors,
        "authority_detail": authority_detail,
        "unresolved_placeholder": unresolved_placeholder,
    }


def _metrics(result: dict) -> dict:
    return {
        "runtime_seconds": result["runtime_seconds"],
        "profile_context_bytes": result["profile_context_bytes"],
        "output_bytes": result["output_bytes"],
        "raw_output_bytes": result["raw_output_bytes"],
        "llm_calls": result["llm_calls"],
        "round_trips": result["round_trips"],
        "max_output_tokens": result["max_output_tokens"],
    }


def main() -> int:
    family = os.environ.get("C3_FAMILY", "").strip().upper()
    if family not in FAMILIES:
        print("C3_FAMILY_ERROR=" + json.dumps({"requested": family, "available": sorted(FAMILIES)}, ensure_ascii=False))
        return 2

    full = base.SKILL.read_text(encoding="utf-8")
    c3 = base.select_c3(full)
    results = []

    for case in FAMILIES[family]:
        base.INPUT = case["input"]
        base.ALLOWED_CURRENCY_AMOUNTS = _authorized_currency(case["input"])
        count = len(c3v2._bullets(case["input"]))
        base.OUTPUT_GUARD = (
            c3v2._guard_for_input(case["input"])
            + f"\n\nFAMILY MATRIX GATE — exact one-to-one coverage\n"
              f"component_tree MUST contain exactly {count} entries in the same order as REQ-1..REQ-{count}. "
              "For entry N, component_tree[N-1].content MUST be the verbatim text of REQ-N. "
              "Never duplicate one REQ while omitting another."
        )

        a = base.run(f"A_FULL_{case['key']}", full, constrained=False)
        c = base.run(f"C3_SELECTED_{case['key']}", c3, constrained=True)
        qa = _quality(case, a)
        qc = _quality(case, c)
        not_worse = all((not qa["vector"][k]) or qc["vector"][k] for k in qc["vector"])
        perf = {
            "context_reduction_pct": round((1 - c["profile_context_bytes"] / a["profile_context_bytes"]) * 100, 2),
            "runtime_change_pct": round((c["runtime_seconds"] / a["runtime_seconds"] - 1) * 100, 2) if a["runtime_seconds"] else None,
            "output_change_pct": round((c["output_bytes"] / a["output_bytes"] - 1) * 100, 2) if a["output_bytes"] else None,
            "llm_calls_change": c["llm_calls"] - a["llm_calls"],
            "round_trips_change": c["round_trips"] - a["round_trips"],
        }
        case_pass = bool(qc["pass"] and not_worse)
        summary = {
            "case": case["key"],
            "family": family,
            "mode": case["mode"],
            "pass": case_pass,
            "quality_c3_not_worse": not_worse,
            "A_quality": qa,
            "C3_quality": qc,
            "A_metrics": _metrics(a),
            "C3_metrics": _metrics(c),
            "performance": perf,
        }
        results.append(summary)
        print("C3_FAMILY_CASE=" + json.dumps(summary, ensure_ascii=False, sort_keys=True))

    passed = sum(1 for item in results if item["pass"])
    family_pass = passed == len(results)
    print("C3_FAMILY_SUMMARY=" + json.dumps({
        "family": family,
        "cases_passed": passed,
        "cases_total": len(results),
        "family_pass": family_pass,
    }, ensure_ascii=False, sort_keys=True))
    print("C3_FAMILY_VERDICT=" + ("FAMILY_5_OF_5_PASS" if family_pass else "NO_MASSIFY"))
    return 0 if family_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())

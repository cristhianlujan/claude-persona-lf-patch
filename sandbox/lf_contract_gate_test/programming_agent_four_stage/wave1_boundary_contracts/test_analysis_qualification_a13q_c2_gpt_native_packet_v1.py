#!/usr/bin/env python3
"""Tests for the A13Q_C2 GPT Native packet. RAW below is a MECHANICS FIXTURE, never evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analysis_qualification_a13q_c2_gpt_native_packet_v1 as pk  # noqa: E402
import analysis_qualification_gpt_native_equivalent_v1 as eq  # noqa: E402

H = lambda c: c * 64  # noqa: E731
PACKET = pk.build_packet()
CTX = json.loads(PACKET["input"]["input_literal"])


def good_raw() -> dict:
    disp = [{"finding_ref": f["ref"], "disposition": "NO_CHANGE" if "0_CRITICAL" in f["result"] else "REQUIRES_MODEL_CHANGE",
             "reason": "Resultado del hallazgo evaluado frente al criterio de cambio."} for f in CTX["findings"]]
    root = CTX["root_finding_candidates"][0]
    return {"schema_version": pk.OUT_SCHEMA, "request_ref": pk.REQUEST_REF, "dispositions": disp,
            "method_change": {"root_finding_code": root["code"], "root_finding_ref": root["evidence_ref"], "target_component": pk.TARGET,
                              "before_version": copy.deepcopy(CTX["before_version"]), "after_version_label": "PROPUESTA-POLITICA-PROFUNDIDAD-V1",
                              "change_rule": "Definir una política general y monótona que asigne el nivel de profundidad a partir de señales gobernadas, sin depender de la familia del cambio.",
                              "generalization_properties": ["Aplica a cualquier familia de cambios.", "Sin pesos arbitrarios en la clasificación.", "La profundidad no concede permiso de ejecución."],
                              "case_specific_patch": False, "hardcodes_case_family": False,
                              "unchanged_components": ["handoff_contract", "impact_model", "specialist_selection", "stop_rule"]},
            "regression_plan": {"planned_checks": ["Repetir la autoprueba de contratos de la ola.", "Verificar que los resultados A10 a A12 se conservan."], "executed": False, "observed_result": None},
            "holdout_boundary": {"holdout_used_for_tuning": False}, "no_ready_claim": True,
            "change_statement": "Propuesta de cambio de método, no ejecutada ni verificada; no se usó el holdout."}


def run(raw, packet=PACKET, chat_ref="chat://fixture", chat_sha=H("b"), approval=H("a")):
    data = raw if isinstance(raw, bytes) else json.dumps(raw, ensure_ascii=False).encode("utf-8")
    return pk.intake(packet, data, chat_ref, chat_sha, approval)


def mutate(fn):
    raw = good_raw()
    fn(raw)
    return raw


def mc(r):
    return r["method_change"]


NEG = {
    "RAW_NOT_JSON": lambda: b"no es json",
    "RAW_NOT_OBJECT": lambda: b"[1]",
    "KEYS_OR_SCHEMA": lambda: mutate(lambda r: r.update(extra=1)),
    "REQUEST_REF_MISMATCH": lambda: mutate(lambda r: r.update(request_ref="REQ-X")),
    "READY_CLAIM": lambda: mutate(lambda r: r.update(no_ready_claim=False)),
    "DISPOSITIONS_SHAPE": lambda: mutate(lambda r: r["dispositions"][0].update(latency_ms=3)),
    "DISPOSITIONS_SHAPE ": lambda: mutate(lambda r: r["dispositions"][0].update(reason="corto")),
    "DISPOSITION_FINDING_SET_MISMATCH": lambda: mutate(lambda r: r["dispositions"].pop()),
    "DISPOSITION_FINDING_SET_MISMATCH ": lambda: mutate(lambda r: r["dispositions"][0].update(finding_ref="lf_eventos://99999")),
    "DISPOSITION_INVALID": lambda: mutate(lambda r: r["dispositions"][0].update(disposition="READY")),
    "DISPOSITION_WRONG": lambda: mutate(lambda r: r["dispositions"][0].update(disposition="REQUIRES_MODEL_CHANGE")),
    "DISPOSITION_WRONG ": lambda: mutate(lambda r: r["dispositions"][3].update(disposition="NO_CHANGE")),
    "METHOD_CHANGE_KEYS": lambda: mutate(lambda r: mc(r).update(provider="x")),
    "ROOT_FINDING_MISMATCH": lambda: mutate(lambda r: mc(r).update(root_finding_code="OTRO")),
    "ROOT_FINDING_MISMATCH ": lambda: mutate(lambda r: mc(r).update(root_finding_ref="lf_eventos://20527")),
    "TARGET_COMPONENT_WRONG": lambda: mutate(lambda r: mc(r).update(target_component="stop_rule")),
    "BEFORE_VERSION_MISMATCH": lambda: mutate(lambda r: mc(r)["before_version"].update(logic_head="0" * 40)),
    "AFTER_VERSION_INVALID": lambda: mutate(lambda r: mc(r).update(after_version_label=CTX["before_version"]["logic_head"])),
    "AFTER_VERSION_INVALID ": lambda: mutate(lambda r: mc(r).update(after_version_label="a" * 40)),
    "AFTER_VERSION_INVALID  ": lambda: mutate(lambda r: mc(r).update(after_version_label="v2")),
    "CHANGE_RULE_MISSING": lambda: mutate(lambda r: mc(r).update(change_rule="corta")),
    "GENERALIZATION_PROPERTIES_INVALID": lambda: mutate(lambda r: mc(r).update(generalization_properties=["una propiedad larga.", "otra propiedad larga."])),
    "GENERALIZATION_PROPERTIES_INVALID ": lambda: mutate(lambda r: mc(r).update(generalization_properties=["misma propiedad larga"] * 3)),
    "CASE_SPECIFIC_CHANGE": lambda: mutate(lambda r: mc(r).update(case_specific_patch=True)),
    "CASE_SPECIFIC_CHANGE ": lambda: mutate(lambda r: mc(r).update(hardcodes_case_family=True)),
    "UNCHANGED_COMPONENTS_INVALID": lambda: mutate(lambda r: mc(r).update(unchanged_components=["stop_rule", pk.TARGET])),
    "UNCHANGED_COMPONENTS_INVALID ": lambda: mutate(lambda r: mc(r).update(unchanged_components=["inventado"])),
    "REGRESSION_PLAN_KEYS": lambda: mutate(lambda r: r["regression_plan"].update(duration=1)),
    "REGRESSION_PLAN_CHECKS": lambda: mutate(lambda r: r["regression_plan"].update(planned_checks=["solo una prueba planeada"])),
    "EXECUTION_CLAIMED": lambda: mutate(lambda r: r["regression_plan"].update(executed=True)),
    "EXECUTION_CLAIMED ": lambda: mutate(lambda r: r["regression_plan"].update(observed_result="PASS")),
    "HOLDOUT_BOUNDARY": lambda: mutate(lambda r: r["holdout_boundary"].update(holdout_used_for_tuning=True)),
    "STATEMENT_MISSING": lambda: mutate(lambda r: r.update(change_statement="corto")),
}


def test_packet_deterministic_and_bound():
    assert pk.build_packet() == PACKET and PACKET["limits"]["provider_attested"] is False
    assert PACKET["input"]["input_sha256"] == hashlib.sha256(PACKET["input"]["input_literal"].encode()).hexdigest()
    assert len(CTX["findings"]) == 4 and len(CTX["model_components"]) == 5


def test_positive():
    verdict, rec = run(good_raw())
    assert verdict == eq.PASS_C2 and rec["runtime_provider_attested"] is False


def test_raw_negatives():
    for code, build in NEG.items():
        verdict, rec = run(build())
        assert rec is None and verdict == "BLOCK:" + code.strip(), (code, verdict)


def test_shape_garbage_is_blocked_not_crash():
    for fn in (lambda r: r.update(dispositions=5), lambda r: r.update(method_change=5), lambda r: mc(r).update(generalization_properties=5),
               lambda r: r.update(regression_plan=5), lambda r: r.update(holdout_boundary=5), lambda r: mc(r).update(before_version=5), lambda r: mc(r).update(unchanged_components=5)):
        verdict, rec = run(mutate(fn))
        assert rec is None and verdict.startswith("BLOCK:"), verdict


def test_packet_binding_negatives():
    bad = copy.deepcopy(PACKET)
    bad["input"]["input_literal"] += " "
    assert run(good_raw(), packet=bad)[0] == "BLOCK:PACKET_TAMPERED"
    assert run(good_raw(), packet={})[0] == "BLOCK:PACKET_SCHEMA_INVALID"
    assert run(good_raw(), chat_ref="")[0] == "BLOCK:CHAT_TRANSCRIPT_REF_MISSING"
    assert run(good_raw(), chat_sha="zz")[0] == "BLOCK:CHAT_TRANSCRIPT_DIGEST_FORMAT"
    assert run(good_raw(), approval="s")[0] == "BLOCK:OWNER_APPROVAL_DIGEST_FORMAT"


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS_A13Q_C2_GPT_NATIVE_PACKET positives=1 raw_negatives=%d shape_garbage=7 packet_binding_negatives=5 packet_sha256=%s "
          "api_calls=0 fixture_raw_is_not_evidence=true" % (len(NEG), PACKET["packet_sha256"][:16]))


if __name__ == "__main__":
    main()

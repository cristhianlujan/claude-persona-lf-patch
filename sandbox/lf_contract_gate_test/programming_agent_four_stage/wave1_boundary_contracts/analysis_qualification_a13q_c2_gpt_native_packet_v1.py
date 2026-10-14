#!/usr/bin/env python3
"""A13Q_C2 frozen GPT Native packet (criterion amended: docs/programming-agent/ANALYSIS_C2_CRITERIA_AMENDMENT_A9_A14_V1.md).

Input: the findings of A10, A11, A12 and the A14 preflight (each with its result string), the root-finding candidate, the version before the change and the model components.
GPT must PROPOSE the method change: a disposition per finding, one generalizable change (root finding, target component, before/after version, rule, properties) and a regression plan
that is only planned. Nothing is re-executed: executed=false and observed_result=null. Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
Rules fixed BEFORE seeing any GPT output: findings whose result matches (^|_)0_CRITICAL must be NO_CHANGE; the other finding must be REQUIRES_MODEL_CHANGE;
the root finding is the supplied candidate; the target is change_classification_contract; the after version is a label, never a 40-hex commit.
The A1-pilot solution-inference word list is not applied (see A11).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import analysis_qualification_gpt_native_packet_common_v1 as common  # noqa: E402

UNIT = "A13"
OUT_SCHEMA = "A13_METHOD_CHANGE_OUTPUT_V1"
INPUT_FILE = HERE / "a13q_c2_input_findings_v1.json"
INPUT_FILE_SHA256 = "b0299a3ceb323fafebb397992ea68f8936839852b715419e891f5c9e91d1a080"
REQUEST_REF = "REQ-LF-A1Q-C2-PILOT-0001"
KEYS = ["schema_version", "request_ref", "dispositions", "method_change", "regression_plan", "holdout_boundary", "no_ready_claim", "change_statement"]
DISPOSITIONS = ["NO_CHANGE", "REQUIRES_MODEL_CHANGE"]
TARGET = "change_classification_contract"
DISP_KEYS = {"finding_ref", "disposition", "reason"}
MC_KEYS = {"root_finding_code", "root_finding_ref", "target_component", "before_version", "after_version_label", "change_rule", "generalization_properties",
           "case_specific_patch", "hardcodes_case_family", "unchanged_components"}
BV_KEYS = {"contract", "logic_head"}
RP_KEYS = {"planned_checks", "executed", "observed_result"}
HB_KEYS = {"holdout_used_for_tuning"}
NO_CHANGE_RE = re.compile(r"(^|_)0_CRITICAL")
HEX40 = re.compile(r"^[0-9a-f]{40}$")


def input_obj() -> dict:
    return common.load_frozen(INPUT_FILE, INPUT_FILE_SHA256, "A13")


def prompt_for(ctx_text: str) -> str:
    return (
        "Este mensaje es independiente: ignora cualquier otro paquete o salida anterior de este chat. "
        "Eres el productor de la etapa A13 (cambio de método) del perfil de análisis. Recibes los hallazgos de las etapas anteriores (findings), la versión actual (before_version), "
        "el candidato a hallazgo raíz (root_finding_candidates) y los componentes del modelo (model_components) (abajo). NO se re-ejecuta nada: solo PROPONES el cambio de método. "
        "Para cada hallazgo decide si exige cambiar el modelo o no, según su resultado. Si alguno lo exige, propón UN cambio general (aplicable a cualquier familia de cambios, no un parche para un caso). "
        "Devuelve SOLO un objeto JSON, sin texto adicional, con exactamente estas claves: " + ", ".join(KEYS) + ". schema_version='" + OUT_SCHEMA + "'. request_ref='" + REQUEST_REF + "'. "
        "dispositions: lista con un registro por hallazgo, con exactamente las claves " + ", ".join(sorted(DISP_KEYS)) + ": finding_ref (la ref del hallazgo), disposition: " + "|".join(DISPOSITIONS) +
        ", reason (texto de al menos 20 caracteres). "
        "method_change: objeto con exactamente las claves " + ", ".join(sorted(MC_KEYS)) + ": root_finding_code y root_finding_ref copiados del candidato a hallazgo raíz; target_component: un componente de model_components; "
        "before_version: objeto con exactamente las claves " + ", ".join(sorted(BV_KEYS)) + " igual a la versión actual suministrada; after_version_label: texto propuesto de al menos 8 caracteres para la versión resultante, "
        "distinto del logic_head actual y que NO sea un hash de 40 caracteres hexadecimales (no se creó ningún commit); change_rule: texto de al menos 80 caracteres que describa la regla general propuesta; "
        "generalization_properties: lista de al menos 3 textos distintos de al menos 10 caracteres; case_specific_patch: false; hardcodes_case_family: false; "
        "unchanged_components: lista con los componentes que NO cambian (subconjunto de model_components, sin incluir el target_component). "
        "regression_plan: objeto con exactamente las claves " + ", ".join(sorted(RP_KEYS)) + ": planned_checks lista de al menos 2 textos de al menos 10 caracteres; executed: false; observed_result: null (nada se ejecutó). "
        "holdout_boundary: objeto con exactamente la clave holdout_used_for_tuning: false. no_ready_claim=true. "
        "change_statement: texto de al menos 40 caracteres que diga que el cambio es una propuesta no ejecutada ni verificada. "
        "No incluyas latencia, tokens, proveedor ni identificadores de ejecución.\n\nENTRADA (JSON):\n" + ctx_text)


def build_packet(root: Path = common.REPO) -> dict:
    checks = {"request_ref_equals": REQUEST_REF, "dispositions": DISPOSITIONS, "target_component": TARGET, "disp_keys": sorted(DISP_KEYS), "mc_keys": sorted(MC_KEYS),
              "bv_keys": sorted(BV_KEYS), "rp_keys": sorted(RP_KEYS), "hb_keys": sorted(HB_KEYS), "no_change_pattern": NO_CHANGE_RE.pattern}
    return common.build(UNIT, OUT_SCHEMA, KEYS, input_obj(), "A13 findings fixture (" + INPUT_FILE_SHA256 + ")", REQUEST_REF, prompt_for, checks,
                        "analysis_qualification_a13q_c2_gpt_native_packet_v1.py::semantic_checks", root)


def _txt(v, n) -> bool:
    return isinstance(v, str) and len(v.strip()) >= n


def semantic_checks(packet: dict, out: dict) -> str | None:
    chk = packet["deterministic_checks"]
    ctx = json.loads(packet["input"]["input_literal"])
    findings = {f["ref"]: f for f in ctx["findings"]}
    comps = {c["component"] for c in ctx["model_components"]}
    root = ctx["root_finding_candidates"][0]
    if set(out) != set(KEYS) or out.get("schema_version") != OUT_SCHEMA:
        return "KEYS_OR_SCHEMA"
    if out["request_ref"] != chk["request_ref_equals"]:
        return "REQUEST_REF_MISMATCH"
    if out["no_ready_claim"] is not True:
        return "READY_CLAIM"
    d = out["dispositions"]
    if not (isinstance(d, list) and all(isinstance(x, dict) and set(x) == set(chk["disp_keys"]) and _txt(x["reason"], 20) for x in d)):
        return "DISPOSITIONS_SHAPE"
    refs = [x["finding_ref"] for x in d]
    if len(refs) != len(set(refs)) or set(refs) != set(findings):
        return "DISPOSITION_FINDING_SET_MISMATCH"
    for x in d:
        if x["disposition"] not in chk["dispositions"]:
            return "DISPOSITION_INVALID"
        expect = "NO_CHANGE" if re.search(chk["no_change_pattern"], findings[x["finding_ref"]]["result"]) else "REQUIRES_MODEL_CHANGE"
        if x["disposition"] != expect:
            return "DISPOSITION_WRONG"
    mc = out["method_change"]
    if not (isinstance(mc, dict) and set(mc) == set(chk["mc_keys"])):
        return "METHOD_CHANGE_KEYS"
    if mc["root_finding_code"] != root["code"] or mc["root_finding_ref"] != root["evidence_ref"]:
        return "ROOT_FINDING_MISMATCH"
    if mc["target_component"] != chk["target_component"]:
        return "TARGET_COMPONENT_WRONG"
    bv = mc["before_version"]
    if not (isinstance(bv, dict) and set(bv) == set(chk["bv_keys"]) and bv == ctx["before_version"]):
        return "BEFORE_VERSION_MISMATCH"
    av = mc["after_version_label"]
    if not _txt(av, 8) or av.strip() == bv["logic_head"] or HEX40.match(av.strip()):
        return "AFTER_VERSION_INVALID"
    if not _txt(mc["change_rule"], 80):
        return "CHANGE_RULE_MISSING"
    gp = mc["generalization_properties"]
    if not (isinstance(gp, list) and len(gp) >= 3 and all(_txt(x, 10) for x in gp) and len(set(gp)) == len(gp)):
        return "GENERALIZATION_PROPERTIES_INVALID"
    if mc["case_specific_patch"] is not False or mc["hardcodes_case_family"] is not False:
        return "CASE_SPECIFIC_CHANGE"
    uc = mc["unchanged_components"]
    if not (isinstance(uc, list) and len(uc) == len(set(uc)) and all(isinstance(x, str) for x in uc) and set(uc) <= comps and mc["target_component"] not in uc):
        return "UNCHANGED_COMPONENTS_INVALID"
    rp = out["regression_plan"]
    if not (isinstance(rp, dict) and set(rp) == set(chk["rp_keys"])):
        return "REGRESSION_PLAN_KEYS"
    pc = rp["planned_checks"]
    if not (isinstance(pc, list) and len(pc) >= 2 and all(_txt(x, 10) for x in pc)):
        return "REGRESSION_PLAN_CHECKS"
    if rp["executed"] is not False or rp["observed_result"] is not None:
        return "EXECUTION_CLAIMED"
    hb = out["holdout_boundary"]
    if not (isinstance(hb, dict) and set(hb) == set(chk["hb_keys"])) or hb["holdout_used_for_tuning"] is not False:
        return "HOLDOUT_BOUNDARY"
    if not _txt(out["change_statement"], 40):
        return "STATEMENT_MISSING"
    return None


def intake(packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256):
    return common.intake(UNIT, semantic_checks, packet, raw_bytes, chat_ref, chat_sha256, approval_doc_sha256)


if __name__ == "__main__":
    common.cli(UNIT, build_packet, intake)

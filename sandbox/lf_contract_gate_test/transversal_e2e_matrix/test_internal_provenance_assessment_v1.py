#!/usr/bin/env python3
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
assessment = json.loads((HERE / "internal_provenance_assessment_v1.json").read_text(encoding="utf-8"))
ops = assessment["operations"]

assert assessment["counts"]["unrouted_operations"] == 22
assert len(ops) == 22
assert len({o["operation_code"] for o in ops}) == 22

productionish = [
    o for o in ops
    if o["provenance_assessment"] not in {"NOT_APPLICABLE_INACTIVE", "NOT_APPLICABLE_TEST_ONLY"}
]
assert len(productionish) == 10
assert all(o["provenance_assessment"] != "PROVEN" for o in productionish)

statuses = {o["operation_code"]: o["provenance_assessment"] for o in ops}
assert statuses["ANALISIS_RIESGO_CONTENIDO_LF"] == "HISTORICAL_CHAIN_ONLY"
assert statuses["EXTRACCION_FUENTES_DIGITALES_LF"] == "HISTORICAL_CHAIN_ONLY"
assert statuses["HOMOLOGACION_FUENTES_DIGITALES_LF"] == "HISTORICAL_CHAIN_ONLY"
assert statuses["ORQUESTACION_PIPELINE_LF"] == "HISTORICAL_CHAIN_ONLY"
assert statuses["DS_BUILD_PROTOCOL_LF"] == "CONTRACT_REQUIRES_ROUTER_READ_BUT_ENTRY_NOT_BOUND"
assert statuses["GITHUB_CONTRACT_GATE_LF"] == "CONTRACT_REQUIRES_ROUTER_READ_BUT_ENTRY_NOT_BOUND"
assert statuses["VULNERABILITY_COVERAGE_REPAIR_LF"] == "CONTRACT_REQUIRES_ROUTER_READ_BUT_ENTRY_NOT_BOUND"
assert statuses["ESCRITURA_BASE_CONOCIMIENTO_LF"] == "NO_EXECUTION_EVIDENCE"
assert statuses["EXTRACCION_DOCUMENTOS_REGULATORIOS_LF"] == "NO_EXECUTION_EVIDENCE"
assert statuses["EXTRACCION_NOTICIAS_FINANCIERAS_LF"] == "NO_EXECUTION_EVIDENCE"

# Historical parent chains and declarative router_read clauses cannot be promoted into
# structural PASS without an execution-entry binding proving Router/authority provenance.
assert assessment["conclusion"]["productionish_structurally_proven"] == 0
assert assessment["conclusion"]["historical_or_contract_evidence_is_not_waiver"] is True
assert assessment["conclusion"]["status"] == "BLOCK_STRUCTURAL_PROVENANCE_NOT_PROVEN"

print("TRANSVERSAL_INTERNAL_PROVENANCE_ASSESSMENT_V1_PASS productionish=10 structurally_proven=0")

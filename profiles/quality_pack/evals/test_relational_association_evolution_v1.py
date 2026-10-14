"""Frozen Quality Pack 201 regression; synthetic SQLite only. No production writes."""
from __future__ import annotations
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SEED = ROOT / "skills/profile_creator/evals/pe10_c3_deep_functional_v2/fixtures/case_201_seed.sql"
PROFILE = ROOT / "profiles/quality_pack/SKILL.md"

# Previous GPT Native original case 201 (archived matched execution) used this
# NULL-sensitive predicate, reporting P4 as ERROR_ASOCIACION even without a join:
ORIGINAL_SQL = """
SELECT p.id pago, co.id conciliacion,
 CASE WHEN co.obligacion_id=o.obligacion_id
 THEN 'OK' ELSE 'ERROR_ASOCIACION' END veredicto
FROM pagos p
LEFT JOIN gateway g ON g.pago_id=p.id
LEFT JOIN ofertas o ON o.id=p.oferta_id
LEFT JOIN conciliaciones co ON co.gateway_id=g.id
ORDER BY p.id
"""
CANDIDATE_SQL = """
SELECT p.id pago, p.estado pago_estado,
 g.id gateway, co.id conciliacion,
 o.obligacion_id expected_obligation, co.obligacion_id observed_obligation,
 CASE WHEN g.id IS NULL THEN 'SIN_GATEWAY'
 WHEN co.id IS NULL THEN 'SIN_CONCILIACION'
 WHEN o.obligacion_id IS NULL THEN 'SIN_IDENTIDAD_ORIGEN'
 WHEN co.obligacion_id IS o.obligacion_id THEN 'CORRECTO'
 ELSE 'CRUZADO' END classification
FROM pagos p
LEFT JOIN ofertas o ON o.id=p.oferta_id
LEFT JOIN gateway g ON g.pago_id=p.id
LEFT JOIN conciliaciones co ON co.gateway_id=g.id
ORDER BY p.id
"""

def main() -> int:
    checks = {}
    def check(name, test): checks[name] = bool(test)
    source = PROFILE.read_text(encoding="utf-8")
    check("candidate_section_in_real_profile_source", "## Conditional relational-association audit" in source)
    check("left_join_missing_separated_in_profile", "left join that yields no child row" in source)
    check("no_new_mandatory_quota", "not a general mandatory query quota" in source)
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    db.executescript(SEED.read_text(encoding="utf-8"))
    db.execute("PRAGMA query_only=ON")
    original = [dict(r) for r in db.execute(ORIGINAL_SQL)]
    candidate = [dict(r) for r in db.execute(CANDIDATE_SQL)]
    og = {r["pago"]:r["veredicto"] for r in original}
    cg = {r["pago"]:r["classification"] for r in candidate}
    check("baseline_reproduces_P4_false_positive", og["P4"]=="ERROR_ASOCIACION")
    check("candidate_excludes_P4_false_positive", cg["P4"]=="SIN_GATEWAY")
    check("candidate_preserves_proven_crosses", {p for p,s in cg.items() if s=="CRUZADO"}=={"P2","P3"})
    check("candidate_preserves_correct_association", cg["P1"]=="CORRECTO")
    check("crosses_exact_real_ids", {(r["pago"],r["expected_obligation"],r["observed_obligation"]) for r in candidate if r["classification"]=="CRUZADO"}=={("P2","O2","O1"),("P3","O3","O1")})
    check("rejected_not_crossed", next(r["pago_estado"] for r in candidate if r["pago"]=="P4")=="REJECTED")
    check("baseline_and_candidate_read_only", db.execute("PRAGMA query_only").fetchone()[0]==1)
    # Mutation: confirmed payment + gateway but absent conciliation.
    db.execute("PRAGMA query_only=OFF")
    db.execute("INSERT INTO pagos VALUES ('P5','F2',12,'CONFIRMED','2026-10-08')")
    db.execute("INSERT INTO gateway VALUES ('G5','P5','TX-105',12,'CONFIRMED')")
    db.execute("PRAGMA query_only=ON")
    original2 = {r["pago"]:r["veredicto"] for r in map(dict,db.execute(ORIGINAL_SQL))}
    candidate2 = {r["pago"]:r["classification"] for r in map(dict,db.execute(CANDIDATE_SQL))}
    check("mutation_baseline_wrongly_flags_missing", original2["P5"]=="ERROR_ASOCIACION")
    check("mutation_candidate_separates_missing", candidate2["P5"]=="SIN_CONCILIACION")
    check("mutation_does_not_hide_real_crosses", {k for k,v in candidate2.items() if v=="CRUZADO"}=={"P2","P3"})
    db.close()
    output = {
      "schema": "QP_RELATIONAL_EVOLUTION_REPLAY_V1",
      "engine": "sqlite", "synthetic_fixture_only": True,
      "case": "PESC3-V2-201",
      "original_false_positive": ["P4"],
      "original_crossed_records": [p for p,s in og.items() if s=="ERROR_ASOCIACION"],
      "candidate_crossed_records": [p for p,s in cg.items() if s=="CRUZADO"],
      "assertions": checks, "passed": all(checks.values()),
      "checks":len(checks), "passed_count":sum(checks.values()),
      "semantic_review": "NOT_EXECUTED",
      "runtime_delivery": "NOT_VERIFIED", "profile_activated":False
    }
    print(json.dumps(output,ensure_ascii=False,sort_keys=True))
    return 0 if output["passed"] else 1

if __name__ == "__main__":
    raise SystemExit(main())

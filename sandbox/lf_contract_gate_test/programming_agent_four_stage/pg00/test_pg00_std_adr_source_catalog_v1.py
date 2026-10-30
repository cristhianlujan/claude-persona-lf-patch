import json,re
from pathlib import Path
d=json.loads(Path(__file__).with_name("pg00_std_adr_source_catalog_v1.json").read_text())
assert d["state"]=="SOURCE_ONLY_CANDIDATE_NOT_RELEASED"
rows=d["rules"]
assert len(rows)==17
for n,row in enumerate(rows,1):
 assert row["adr"]==f"ADR-PROG-STD-{n:03}"
 assert row["source_state"]=="vigente" and row["release_state"]=="NOT_RELEASED"
 assert row["decision_text"].strip() and row["title"].strip()
assert "POR DEFINIR" in rows[16]["decision_text"].upper()
assert "repo + commit" in rows[14]["decision_text"]
assert len(d["limitations"])>=4
print("PG00_C3_ADR_SOURCE_CATALOG_PASS rules=17 released=0 d15_unresolved=True d17_budget_unresolved=True")

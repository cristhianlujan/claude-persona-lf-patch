import json
from pathlib import Path
p=Path(__file__).with_name("pg00_front_domain_map_candidate_v1.json")
m=json.loads(p.read_text())
assert m["state"]=="DRAFT_NOT_RELEASED"
assert m["authority_boundary"]=="EXAMPLES_ONLY_NOT_COMPLETE_NOR_AUTHORIZED"
assert len(m["adr_references"])==17
assert len(set(m["adr_references"]))==17
assert m["front_kind_domains"]=={"UI_VISUAL":["STD-FE","NAV","MSG"],"API_CONTRACT":["API","SEC"],"PERMISSION":["SEC"]}
assert m["conditional_domains"]["DATA_CONTRACT"]["base_domains"]==["DB"]
assert "DATA_CONTRACT" not in m["front_kind_domains"]
assert "PG00_C3 official issuance and version authority" in m["omissions"]
print("PG00_DOMAIN_MAP_CANDIDATE_PASS: NOT_RELEASED, 3 examples, 1 conditional, 17 ADR references")

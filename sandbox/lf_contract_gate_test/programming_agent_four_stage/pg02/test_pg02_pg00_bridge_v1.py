from pg02_pg00_bridge_v1 import classify_with_pg00
from pg02_classifier_v1 import PG02Blocked
decisions=[{"adr":f"ADR-PROG-STD-{i:03}","estado":"vigente"} for i in range(1,18)]
for rows, release, expected in [
 (decisions,None,"PG00_MAPPING_NOT_RELEASED"),
 (decisions,{"state":"SOURCE_ONLY_CANDIDATE"},"PG00_MAPPING_NOT_RELEASED"),
 (decisions[:-1],None,"PG00_DECISIONS_INCOMPLETE"),
 (decisions[:-1]+[decisions[0]],None,"PG00_DECISIONS_DUPLICATE"),
 (decisions[:-1]+[{"adr":"ADR-PROG-STD-018","estado":"vigente"}],None,"PG00_DECISIONS_MISMATCH"),
 ([{**x, "estado":"pendiente"} if x["adr"].endswith("001") else x for x in decisions],None,"PG00_DECISION_NOT_VIGENTE"),
]:
 try: classify_with_pg00({},rows,release,expected_release_sha256="0"*64)
 except PG02Blocked as e: assert str(e)==expected,(expected,str(e))
 else: raise AssertionError(expected)
print("PG02_PG00_BRIDGE_FAIL_CLOSED_PASS negatives=6")

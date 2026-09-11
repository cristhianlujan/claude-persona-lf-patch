from __future__ import annotations
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
 e=json.loads((HERE/'e2e_quality_preservation_extension_v1.json').read_text())
 b=json.loads((HERE/'e2e_campaign_blueprint_v1.json').read_text())
 assert e['case_count_unchanged']==50==b['case_count']
 assert len(e['mandatory_subprobes']['E2E-07-02'])==5
 assert set(e['hard_targets'].values())=={0}
 assert {'PROFILE_CARD_READINESS_PROJECTION','S30_SEMANTIC_OBLIGATION_MANIFEST','SEMANTIC_DELTA_COVERAGE','MATERIALIZATION_PRESERVATION_READBACK'}==set(e['navigation_insertion'])
 existing={c['case_id'] for c in b['cases']}
 assert set(e['mandatory_subprobes']).issubset(existing)
 print(json.dumps({'result':'PASS','base_cases':50,'quality_overlay_cases':len(e['mandatory_subprobes']),'semantic_subprobes':5,'hard_targets_zero':True},sort_keys=True))
if __name__=='__main__': main()

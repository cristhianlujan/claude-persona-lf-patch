#!/usr/bin/env python3
import json
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parent
BINDINGS = ROOT / 'ui_architect_learning_consumer_bindings_v1.yaml'
PACK = ROOT / 'ui_architect_learning_context_pack_v1.json'

REQUIRED_BINDING_FIELDS = {
    'consumer_id','consumer_type','capability_id','router_action','invoke_when','must_not_invoke_when',
    'input_contract','minimum_context','selected_evidence_refs','policy_capsule_ref','output_schema_ref',
    'judges','fallback','timeout_budget','context_budget','lifecycle_state','version','source_learning_ids',
    'champion_id','challenger_id','provenance'
}

EXPECTED = {
    'DIGITAL_SELF_SERVICE': {'35cfab0c-1d91-4aa4-9761-f8af91181e17','7d55562e-9266-478b-b071-dca7ba1ade1a'},
    'PAYMENT_NO_ADEUDO': {'bd2a3a05-b53b-400c-846d-3634e422a500','92fc4ad2-1581-4aa1-b01b-e986bb3cc71c'},
}

def main():
    b = yaml.safe_load(BINDINGS.read_text())
    p = json.loads(PACK.read_text())
    assert b['consumer']['consumer_id'] == 'PERFIL-UI-ARCHITECT'
    assert b['consumer']['prerequisite'] == 'PRODUCT_DIRECTION_AUTHORIZED_CURRENT'
    assert p['consumer_id'] == 'PERFIL-UI-ARCHITECT'
    assert p['prerequisite'] == 'PRODUCT_DIRECTION_AUTHORIZED_CURRENT'
    assert p['selection']['semantic_search'] is False
    assert p['selection']['llm_calls'] == 0
    assert p['selection']['round_trips'] == 0
    assert p['selection']['max_context_bytes'] == 5000
    assert p['writes_per_reader'] == 0
    assert p['fallback'] == 'NO_COMPETITIVE_CONTEXT'
    assert p['production_authorized'] is False
    seen = set()
    for row in b['bindings']:
        missing = REQUIRED_BINDING_FIELDS - set(row)
        assert not missing, (row.get('binding_id'), sorted(missing))
        assert row['consumer_id'] == 'PERFIL-UI-ARCHITECT'
        assert row['fallback'] == 'NO_COMPETITIVE_CONTEXT'
        assert row['lifecycle_state'] == 'READY_FOR_BINDING'
        assert row['context_budget']['selection'] == 'DETERMINISTIC_FIRST'
        assert row['context_budget']['max_bytes'] <= 5000
        assert 'prerequisite_no_bypass' in row['judges']
        assert 'product_direction_missing_or_stale' in row['must_not_invoke_when']
        ids = set(row['source_learning_ids'])
        assert ids == EXPECTED[row['capability_id']]
        refs = {x.rsplit('/',1)[-1] for x in row['selected_evidence_refs']}
        assert refs == ids
        assert row['binding_id'] not in seen
        seen.add(row['binding_id'])
    assert len(seen) == 2
    print('UI_ARCHITECT_LEARNING_READONLY_CONTRACT=PASS bindings=2/2 exact_ids=4/4 prerequisite_no_bypass=2/2 llm_selector=0 round_trips=0 writes=0')

if __name__ == '__main__':
    main()

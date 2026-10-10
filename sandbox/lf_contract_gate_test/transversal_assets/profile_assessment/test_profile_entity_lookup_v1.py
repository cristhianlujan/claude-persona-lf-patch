from profile_entity_lookup_v1 import plan_entity_lookup

def run():
    result = plan_entity_lookup({})
    assert result['action'] == 'BLOCKED'
    print('PASS_ENTITY_LOOKUP_MINIMUM')

if __name__ == '__main__':
    run()

def synthetic_verifier(kind, record):
    field={"scope":"scope_receipt_ref","catalog":"receipt_ref","lookup":"receipt_ref"}[kind]
    return str(record.get(field,"")).startswith("fixture://")

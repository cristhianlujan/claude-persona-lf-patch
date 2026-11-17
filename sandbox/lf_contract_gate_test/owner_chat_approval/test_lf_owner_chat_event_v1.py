from datetime import datetime, timedelta, timezone
import pytest
from sandbox.lf_contract_gate_test.owner_chat_approval.owner_chat_fixture_v1 import OWNER, OTHER_SUB, REPO, CHANNEL, CHANNEL_CLAUDE, CHANNEL_GPT, TEST_EMAIL, TEST_EMAIL_SHA, AUTHORIZED_ACCOUNT_FIXTURE
from scripts.lf_owner_chat_event_v1 import (
    ChatOrderRejected, canonical, expected_order, sha256_literal, verify_order
)

NOW=datetime(2026,11,17,2,38,tzinfo=timezone.utc)
SCOPE={"action":"MERGE_GOVERNANCE_PR","repository":REPO,"pr_number":4063,"head_sha":"a"*40}
RULE_SCOPE={"action":"PROMOTE_RULE_BATCH","repository":SCOPE["repository"],"execution_id":"EXEC-TEST-1234567890","rule_codes":["RULE-001","RULE-002"],"rule_snapshots_sha256":"b"*64}
ACTORS={"owner_sub":OWNER,"channel_code":CHANNEL,"repository_full_name":REPO,"authorized_accounts":AUTHORIZED_ACCOUNT_FIXTURE,"owner_account_email":TEST_EMAIL,"proposer_subject":"profile-proposer-1","registrar_subject":"orchestration-recorder-1"}

def event(scope=None, catalog=None, **patch):
    scope=scope or SCOPE
    ev={"event_kind":"USER_MESSAGE","origin":CHANNEL,"actor_sub":ACTORS["owner_sub"],"channel_code":CHANNEL_CLAUDE,"session_account_sha256":TEST_EMAIL_SHA,"conversation_id":"conversation-test-001","message_id":"message-test-001","text_literal":expected_order(scope,catalog),"sent_at":(NOW-timedelta(minutes=1)).isoformat().replace("+00:00","Z"),"scope":scope}
    ev.update(patch)
    return ev

def verify(ev=None, scope=None, **changes):
    return verify_order(event=ev if ev is not None else event(scope),expected_scope=scope or SCOPE,now=NOW,**(ACTORS|changes))

def reject(code, ev=None, scope=None, **changes):
    with pytest.raises(ChatOrderRejected,match=code): verify(ev,scope,**changes)

def test_happy_pr_and_batch():
    for scope in (SCOPE,RULE_SCOPE):
        r=verify(scope=scope)
        assert r['scope_sha256']==sha256_literal(canonical(scope))
        assert r['identity_mode']=='ACCOUNT_SESSION'
        assert r['channel_code']==CHANNEL_CLAUDE
        assert r['session_account_sha256']==TEST_EMAIL_SHA
        assert r['sent_at_lima'].endswith('-05:00')
        assert r['text_literal'].startswith('APRUEBO ')

def test_no_order(): reject('INVALID_ORDER_LITERAL_OR_SHORT_HASH',event(text_literal=''))
def test_wrong_scope(): reject('WRONG_EXACT_SCOPE', event(),{**SCOPE,'pr_number':4062})
def test_wrong_head(): reject('WRONG_EXACT_SCOPE', event(),{**SCOPE,'head_sha':'b'*40})
def test_repo_must_match_canonical_config(): reject('REPOSITORY_CONFIG_MISMATCH', event(), repository_full_name='other/repository')
def test_expired(): reject('EXPIRED_ORDER',event(sent_at=(NOW-timedelta(minutes=16)).isoformat().replace('+00:00','Z')))
def test_wrong_session_hash(): reject('ACCOUNT_SESSION_NOT_AUTHORIZED',event(session_account_sha256='a'*64))
def test_gpt_session_happy(): assert verify(event(channel_code=CHANNEL_GPT))['identity_mode']=='ACCOUNT_SESSION'
def test_both_channels_use_one_shared_hash():
    assert len(AUTHORIZED_ACCOUNT_FIXTURE)==2
    assert {entry[1] for entry in AUTHORIZED_ACCOUNT_FIXTURE}=={TEST_EMAIL_SHA}
def test_email_uppercase_whitespace_is_normalized():
    assert verify(event(),owner_account_email=" \t"+TEST_EMAIL.upper()+"  \n")['identity_mode']=='ACCOUNT_SESSION'
def test_different_installation_email_rejected():
    reject('ACCOUNT_SESSION_NOT_AUTHORIZED',event(),owner_account_email="different"+"@"+"example.invalid")
def test_missing_owner_installation_email(): reject('ACCOUNT_EMAIL_MISSING',event(),owner_account_email='')
def test_missing_account_sha(): reject('ACCOUNT_SESSION_INVALID',event(session_account_sha256=''))
def test_inactive_claude_account(): reject('ACCOUNT_SESSION_NOT_AUTHORIZED',event(),authorized_accounts=((CHANNEL_CLAUDE,TEST_EMAIL_SHA,False),))
def test_model_cannot_set_mode(): reject('EVENT_CONTRACT_INVALID',event(identity_mode='ACCOUNT_SESSION'))
def test_wrong_owner(): reject('WRONG_OWNER',event(actor_sub=OTHER_SUB))
def test_model_claim(): reject('NOT_AN_ORCHESTRATED_USER_TURN',event(event_kind='ASSISTANT_MESSAGE'))
def test_forged_origin(): reject('NOT_AN_ORCHESTRATED_USER_TURN',event(origin='MODEL_GENERATED_JSON'))
def test_same_proposer_and_registrar(): reject('NO_PROPOSER_REGISTRAR_SEPARATION',event(),registrar_subject=ACTORS['proposer_subject'])
def test_registrar_same_owner(): reject('NO_PROPOSER_REGISTRAR_SEPARATION',event(),registrar_subject=ACTORS['owner_sub'])
def test_tamper_literal(): reject('INVALID_ORDER_LITERAL_OR_SHORT_HASH',event(text_literal=expected_order(SCOPE)+'-EDIT'))
def test_hash_truncated_wrong(): reject('INVALID_ORDER_LITERAL_OR_SHORT_HASH',event(text_literal='APRUEBO deadbeefdead '+canonical(SCOPE)))
def test_duplicate_rules(): reject('INVALID_RULE_SET',event(),{**RULE_SCOPE,'rule_codes':['RULE-001','RULE-001']})
def test_invalid_action(): reject('ACTION_OR_FIELDS_NOT_CATALOGUED',event(),{**SCOPE,'action':'DELETE_DATABASE'})
def test_future(): reject('FUTURE_MESSAGE',event(sent_at=(NOW+timedelta(minutes=2)).isoformat().replace('+00:00','Z')))
def test_catalog_extension():
    scope={'action':'FUTURE_SCOPED_ACTION','repository':SCOPE['repository'],'thing':'immutable'}
    catalog={'FUTURE_SCOPED_ACTION':frozenset(scope)}
    assert verify_order(event=event(scope,catalog=catalog),expected_scope=scope,now=NOW,catalog=catalog,**ACTORS)['scope']==scope

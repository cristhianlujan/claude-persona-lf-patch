"""Synthetic tests for RENDER_READY admission. Never execute/authorize real render."""
import base64
import copy
import hashlib
import json
import unittest
from datetime import datetime, timezone, timedelta

from render_ready_gate_v1 import RenderAdmissionRejected, validate_render_ready

NOW = datetime(2026, 11, 22, 19, 0, tzinfo=timezone.utc)
V = "2026-11-22T18:00:00+00:00"
P = {"schema_version": "CREATIVE_EXECUTION_POLICY_V1", "config_scope": "CREATIVE_FACTORY",
     "QUEUE_MAX": 5, "MAX_ATTEMPTS": 3, "QUEUE_TIMEOUT_SECONDS": 300, "LEASE_SECONDS": 600,
     "versions": {k: V for k in ("QUEUE_MAX", "MAX_ATTEMPTS", "QUEUE_TIMEOUT_SECONDS", "LEASE_SECONDS")}}
E = {"mode": "GPT_NATIVE", "provider_identity": "OPENAI_CHATGPT_NATIVE",
     "conversation_scope": "EXISTING_CONVERSATION_ONLY", "native_api_invocation": False,
     "native_session_creation": False, "remote_api_fallback": "FORBIDDEN", "provider_attested": False}
RUN = {"order_id": 40, "item_id": 50, "run_id": 60, "claim_id": 70,
       "queue_mode": "SERIAL_V1", "rendering_authority": True,
       "render_authorized": True, "review_only": False,
       "order_status": "EN_PROCESO", "item_status": "PRODUCIENDO",
       "run_state": "EJECUTANDO", "claim_state": "ACTIVE",
       "worker_ref": "NATIVE-WORKER", "claim_worker_ref": "NATIVE-WORKER",
       "lease_until": (NOW + timedelta(minutes=5)).isoformat(),
       "deadline_at": (NOW + timedelta(minutes=4)).isoformat(),
       "attempt_number": 1, "execution_policy": P,
       "input_snapshot_sha256": hashlib.sha256(b"frozen input").hexdigest(),
       "contract_sha256": hashlib.sha256(b"creative contract").hexdigest()}
BODY = {"prompt": "Crea el arte SALY con identidad oficial congelada.", "attachments": []}


def make_wire(run=RUN, executor=E, body=BODY):
    raw = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode('utf-8')
    return {
        "schema_version": "SALY_NATIVE_RENDER_WIRE_V1",
        "status": "RENDER_WIRE_FROZEN_AUTHORIZED",
        "render_authorized": True, "native_transmitted": False,
        "order_id": run["order_id"], "item_id": run["item_id"],
        "run_id": run["run_id"], "claim_id": run["claim_id"],
        "executor_mode": executor["mode"], "executor_provider": executor["provider_identity"],
        "input_snapshot_sha256": run["input_snapshot_sha256"],
        "contract_sha256": run["contract_sha256"],
        "wire_base64": base64.b64encode(raw).decode('ascii'),
        "wire_sha256": hashlib.sha256(raw).hexdigest(),
        "prompt_sha256": hashlib.sha256(body["prompt"].encode('utf-8')).hexdigest(),
        "provider_receipt": None,
    }


class Fixture:
    def __init__(self, mode="GPT_NATIVE"):
        self.policy = copy.deepcopy(P)
        self.run = copy.deepcopy(RUN)
        self.executor = copy.deepcopy(E)
        if mode == "CLAUDE_NATIVE":
            self.executor.update(mode="CLAUDE_NATIVE", provider_identity="ANTHROPIC_CLAUDE_NATIVE")
        self.wire = make_wire(self.run, self.executor)
        self.policy_calls = self.binding_calls = self.wire_calls = 0

    def read_policy(self, at):
        self.policy_calls += 1
        return copy.deepcopy(self.policy)

    def read_binding(self, run_id):
        self.binding_calls += 1
        return copy.deepcopy(self.run)

    def read_wire(self, item_id, run_id):
        self.wire_calls += 1
        return copy.deepcopy(self.wire)

    def apply(self, **kw):
        args = dict(order_id=40, item_id=50, run_id=60, asof=NOW,
                    executor=self.executor, policy_reader=self.read_policy,
                    binding_reader=self.read_binding, render_wire_reader=self.read_wire)
        args.update(kw)
        return validate_render_ready(**args)


class Tests(unittest.TestCase):
    def blocked(self, code, change, mode="GPT_NATIVE", **params):
        f = Fixture(mode)
        change(f)
        with self.assertRaises(RenderAdmissionRejected) as e:
            f.apply(**params)
        self.assertEqual(e.exception.code, code)
        return f

    def test_gpt_contract_only(self):
        f = Fixture()
        r = f.apply()
        self.assertEqual(r['status'], 'RENDER_READY_CANDIDATE_VALIDATED_NOT_DISPATCHED')
        self.assertEqual(r['executor_mode'], 'GPT_NATIVE')
        self.assertFalse(r['db_done_allowed'])
        self.assertFalse(r['image_generation_executed'])
        self.assertEqual((f.policy_calls,f.binding_calls,f.wire_calls), (1,1,1))
        self.assertNotIn('claim_token', r)

    def test_claude_contract_only(self):
        f = Fixture('CLAUDE_NATIVE')
        r = f.apply()
        self.assertEqual(r['executor_provider'], 'ANTHROPIC_CLAUDE_NATIVE')
        self.assertFalse(r['provider_attested'])

    def test_live_missing_config_blocks(self):
        self.blocked('CREATIVE_RENDER_POLICY_SOURCE_INVALID', lambda f: setattr(f, 'policy', {}))

    def test_required_key_missing(self):
        self.blocked('CREATIVE_RENDER_POLICY_KEY_INVALID:QUEUE_MAX', lambda f: f.policy.pop('QUEUE_MAX'))

    def test_integer_not_literal(self):
        self.blocked('CREATIVE_RENDER_POLICY_KEY_INVALID:LEASE_SECONDS', lambda f: f.policy.update(LEASE_SECONDS='600'))

    def test_future_version(self):
        self.blocked('CREATIVE_RENDER_POLICY_VERSION_INVALID:MAX_ATTEMPTS', lambda f: f.policy['versions'].update(MAX_ATTEMPTS='2030-11-22T00:00:00Z'))

    def test_unbound_policy_reader(self):
        self.blocked('CREATIVE_RENDER_TRUSTED_READER_MISSING', lambda f: None, policy_reader=None)

    def test_wrong_provider(self):
        self.blocked('CREATIVE_RENDER_PROVIDER_MODE_MISMATCH', lambda f: f.executor.update(provider_identity='ANTHROPIC_CLAUDE_NATIVE'))

    def test_remote_api_not_used(self):
        self.blocked('CREATIVE_RENDER_NATIVE_SESSION_INVALID', lambda f: f.executor.update(native_api_invocation=True))

    def test_new_native_session_forbidden(self):
        self.blocked('CREATIVE_RENDER_NATIVE_SESSION_INVALID', lambda f: f.executor.update(native_session_creation=True))

    def test_invalid_run_id(self):
        self.blocked('CREATIVE_RENDER_ENTITY_ID_INVALID', lambda f: None, run_id=0)

    def test_legacy_review_only_blocked(self):
        self.blocked('CREATIVE_RENDER_ORDER_AUTHORITY_MISSING', lambda f: f.run.update(review_only=True,render_authorized=False))

    def test_existing_saly_order_blocked(self):
        self.blocked('CREATIVE_RENDER_ORDER_AUTHORITY_MISSING', lambda f: f.run.update(queue_mode=None,rendering_authority=False))

    def test_render_authorized_flag_required(self):
        self.blocked('CREATIVE_RENDER_ORDER_AUTHORITY_MISSING', lambda f: f.run.update(render_authorized=False))

    def test_review_only_flag_denied(self):
        self.blocked('CREATIVE_RENDER_ORDER_AUTHORITY_MISSING', lambda f: f.run.update(review_only=True))

    def test_worker_mismatch(self):
        self.blocked('CREATIVE_RENDER_RUN_CLAIM_NOT_ACTIVE', lambda f: f.run.update(claim_worker_ref='OTHER'))

    def test_expired_lease(self):
        self.blocked('CREATIVE_RENDER_LEASE_OR_DEADLINE_EXPIRED', lambda f: f.run.update(lease_until=(NOW-timedelta(seconds=1)).isoformat()))

    def test_attempt_limit(self):
        self.blocked('CREATIVE_RENDER_ATTEMPT_EXCEEDED', lambda f: f.run.update(attempt_number=4))

    def test_run_policy_snapshot_drift(self):
        self.blocked('CREATIVE_RENDER_RUN_POLICY_DRIFT', lambda f: f.run.update(execution_policy={**P,'LEASE_SECONDS':601}))

    def test_claim_cross_run(self):
        self.blocked('CREATIVE_RENDER_RUN_CLAIM_BINDING_MISMATCH', lambda f: f.run.update(run_id=61))

    def test_review_wire_not_render_wire(self):
        self.blocked('CREATIVE_RENDER_WIRE_NOT_AUTHORIZED', lambda f: f.wire.update(schema_version='SALY_CANONICAL_NATIVE_WIRE_V1',status='CANONICAL_WIRE_REVIEW_ONLY',render_authorized=False))

    def test_wire_cross_claim(self):
        self.blocked('CREATIVE_RENDER_WIRE_BINDING_MISMATCH', lambda f: f.wire.update(claim_id=9))

    def test_wire_source_drift(self):
        self.blocked('CREATIVE_RENDER_WIRE_SOURCE_PIN_DRIFT', lambda f: f.wire.update(contract_sha256=hashlib.sha256(b'other').hexdigest()))

    def test_wire_changed_bytes(self):
        self.blocked('CREATIVE_RENDER_WIRE_SHA256_MISMATCH', lambda f: f.wire.update(wire_base64=base64.b64encode(b'altered').decode()))

    def test_wire_duplicate_json_key(self):
        def mutation(f):
            raw=b'{"prompt":"A","prompt":"B","attachments":[]}'
            f.wire['wire_base64']=base64.b64encode(raw).decode()
            f.wire['wire_sha256']=hashlib.sha256(raw).hexdigest()
        self.blocked('CREATIVE_RENDER_WIRE_DUPLICATE_JSON_KEY',mutation)

    def test_prompt_sha_changed(self):
        self.blocked('CREATIVE_RENDER_PROMPT_HASH_DRIFT', lambda f: f.wire.update(prompt_sha256='0'*64))

    def test_token_in_graphic_prompt(self):
        def mutation(f):
            raw_body={"prompt":"Genera token: claim_token XYZ","attachments":[]}
            f.wire=make_wire(f.run,f.executor,raw_body)
        self.blocked('CREATIVE_RENDER_TOKEN_IN_NATIVE_PAYLOAD',mutation)

    def test_fake_receipt(self):
        self.blocked('CREATIVE_RENDER_PROVIDER_RECEIPT_PRETENDED', lambda f: f.wire.update(provider_receipt={'ok':True}))

    def test_incomplete_snapshot_pin(self):
        self.blocked('CREATIVE_RENDER_RUN_SNAPSHOT_PIN_MISSING', lambda f: f.run.update(contract_sha256=None))

    def test_naive_clock(self):
        self.blocked('CREATIVE_RENDER_ASOF_INVALID', lambda f: None, asof=datetime(2026,11,22,19))

    def test_review_item_not_ready(self):
        self.blocked('CREATIVE_RENDER_ORDER_ITEM_NOT_READY', lambda f: f.run.update(item_status='PENDIENTE'))


if __name__ == '__main__':
    unittest.main(verbosity=2)

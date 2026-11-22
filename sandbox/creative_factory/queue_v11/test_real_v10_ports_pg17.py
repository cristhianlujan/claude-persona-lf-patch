"""V11 -> actual V10 PostgreSQL 17 candidate bridge, still synthetic Native.

Run ONLY against disposable saly_queue_test on local loopback after setup_pg17.
V09 is stubbed here and separately exercised by its original test module.
This checks actual V10 SQL RPC, reservation row SELECT/readback and replay.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

from sandbox.creative_factory.queue_v11.native_handoff_reservation_bridge_v1 import (
    HandoffReservationRejected, prepare_native_reservation_handoff_v1,
)

assert os.environ.get("PGHOST") in ("127.0.0.1", "localhost"), "BLOCK_REMOTE_DB"
assert os.environ.get("PGDATABASE") == "saly_queue_test", "BLOCK_NON_DISPOSABLE_DB"
assert not os.environ.get("PGPASSWORD") and not os.environ.get("LF_SUPABASE_DB_PASSWORD"), "BLOCK_CREDENTIAL_ENV"


def sql(statement: str):
    r = subprocess.run(["psql", "-XAt", "-v", "ON_ERROR_STOP=1", "-c", statement],
                       text=True, capture_output=True, timeout=30, check=False)
    if r.returncode:
        raise RuntimeError("V11_SQL_READBACK_OR_RESERVE_FAILED:" + r.stderr[-900:])
    return r.stdout.strip()


def row(statement: str):
    response = sql(statement)
    return json.loads(response)


data = row("""SELECT row_to_json(s)::text FROM
  (SELECT order_id,item_id,run_id,claim_id,claim_token::text AS claim_token,
          wire_sha256,prompt_sha256,archive_sha256
   FROM saly.test_v10_context LIMIT 1) s""")
required = ("order_id","item_id","run_id","claim_id",
            "claim_token","wire_sha256","prompt_sha256","archive_sha256")
assert all(data.get(k) is not None for k in required), "V11_FIXTURE_CONTEXT_INCOMPLETE"

with tempfile.TemporaryDirectory(prefix="saly-v11-pg17-local-") as td:
    base=Path(td)/"private"
    base.mkdir(mode=0o700)
    archive=base/"archive"
    archive.mkdir(mode=0o700)
    (archive/"archive.json").write_bytes(b'{"status":"HANDOFF_PREPARED_NOT_SENT"}')
    archived={
        "schema_version":"SALY_NATIVE_RENDER_ARCHIVE_BRIDGE_V1",
        "status":"HANDOFF_ARCHIVED_NOT_SENT",
        "order_id":data["order_id"],"item_id":data["item_id"],
        "run_id":data["run_id"],"claim_id":data["claim_id"],
        "executor_mode":"GPT_NATIVE",
        "wire_sha256":data["wire_sha256"],
        "prompt_sha256":data["prompt_sha256"],
        "archive_path":str(archive),
        "native_transmitted":False,"provider_attested":False,
        "host_delivery_verified":False,"db_done_allowed":False,
    }
    executor={"mode":"GPT_NATIVE","provider_identity":"OPENAI_CHATGPT_NATIVE"}
    calls={"reserve":0,"readback":0,"credential":0}
    def credential(runid):
        calls["credential"]+=1
        assert runid == data["run_id"]
        return {key:data[key] for key in (
            "order_id","item_id","run_id","claim_id","claim_token")}

    def reserve(token,runid,mode,wire,archivehash,key):
        calls["reserve"]+=1
        assert token==data["claim_token"] and runid==data["run_id"]
        assert mode=="GPT_NATIVE" and wire==data["wire_sha256"]
        assert re.fullmatch("[0-9a-f]{64}",archivehash)
        assert re.fullmatch("[A-Za-z0-9._:-]{1,128}",key)
        # Fixture-owned SQL parameters only; no user-controlled string.
        stmt=("SELECT saly.creative_queue_native_reserve_dispatch_v1("
              f"'{token}'::uuid,{runid},'{mode}','{wire}','{archivehash}',"
              f"'{key}')::text")
        return row(stmt)

    def reservation_readback(res_id):
        calls["readback"]+=1
        assert type(res_id) is int and res_id>0
        stmt=f"""SELECT row_to_json(s)::text FROM
          (SELECT id,order_id,item_id,run_id,claim_id,request_key,
             executor_mode,executor_provider,wire_sha256,prompt_sha256,
             archive_reported_sha256,input_snapshot_sha256,state
           FROM saly.creative_queue_native_dispatch_reservations_v1
           WHERE id={res_id}) s"""
        return row(stmt)

    def gate(**kw):
        assert kw["order_id"]==data["order_id"] if "order_id" in kw else True
        return {
          "schema_version":"SALY_NATIVE_DISPATCH_FENCE_V1",
          "status":"FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT",
          "order_id":data["order_id"],"item_id":data["item_id"],
          "run_id":data["run_id"],"claim_id":data["claim_id"],
          "wire_sha256":data["wire_sha256"],
          "native_transmitted":False,"provider_attested":False,
          "host_delivery_verified":False,"db_done_allowed":False,
        }

    def invoke(payload=archived, key="V11-REAL-SQL-BRIDGE-001"):
        with patch("sandbox.creative_factory.queue_v11.native_handoff_reservation_bridge_v1.verify_dispatch_fence_v1",
                   side_effect=gate):
            return prepare_native_reservation_handoff_v1(
                archived=payload,executor=executor,request_key=key,
                db_clock_reader=lambda:None,
                policy_reader=lambda _:None,
                binding_reader=lambda _:None,
                render_wire_reader=lambda _a,_b:None,
                claim_credential_reader=credential,
                reserve_dispatch=reserve,
                reservation_readback=reservation_readback)

    first=invoke()
    assert first["status"]=="RESERVATION_READBACK_VERIFIED_NOT_SENT"
    assert first["dispatch_authorized"] is False
    assert first["host_delivery_verified"] is False
    assert "claim_token" not in first
    assert first["archive_manifest_sha256"]==hashlib.sha256(
        (archive/"archive.json").read_bytes()).hexdigest()
    print("PASS_V11_REAL_V10_PG17_SQL_INSERT_AND_ROW_READBACK")

    second=invoke()
    assert second["status"]=="IDEMPOTENT_RESERVATION_READBACK_NOT_SENT"
    assert second["reservation_id"]==first["reservation_id"]
    assert second["dispatch_authorized"] is False
    print("PASS_V11_REAL_V10_PG17_REPLAY_UNCHANGED_AND_NOT_SENT")

    forged={**archived,"wire_sha256":"0"*64}
    try:
        invoke(payload=forged,key="V11-REAL-SQL-BRIDGE-001")
        raise AssertionError("V11_FORGED_WIRE_ACCEPTED")
    except HandoffReservationRejected as exc:
        assert exc.code=="SALY_V11_DB_RESERVATION_FAILED",exc.code
    print("PASS_V11_REAL_V10_PG17_REJECTS_FORGED_WIRE")

    assert sql("SELECT count(*) FROM saly.creative_queue_native_dispatch_reservations_v1")=="1"
    assert sql("SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1")=="0"
    assert sql("SELECT count(*) FROM saly.creative_runs WHERE state='EJECUTANDO'")=="1"
    assert calls["reserve"]==3 and calls["readback"]==2
    print("PASS_V11_REAL_V10_PG17_ONE_RESERVATION_ZERO_DELIVERY_ZERO_DONE")

"""V10 B25/B28: prove mutations fail SPECIFIC behavior, not syntax/another guard.

Runs against isolated PG17 on loopback using a disposable DB only.
"""
import os
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
v10 = root / "queue_v10"
source = (v10 / "001_saly_native_dispatch_reservation_candidate.sql").read_text()
assert os.environ.get("PGHOST") in ("127.0.0.1", "localhost"), "BLOCK_REMOTE_DB"
assert os.environ.get("PGDATABASE") == "saly_queue_test", "BLOCK_NON_DISPOSABLE_DB"
assert not os.environ.get("PGPASSWORD") and not os.environ.get("LF_SUPABASE_DB_PASSWORD"), "BLOCK_DB_SECRET_ENV"


def sql_file(path: Path) -> None:
    r = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", str(path)],
                       capture_output=True, text=True, timeout=90, check=False)
    if r.returncode:
        raise AssertionError(f"SETUP_FAILED: {path.name}: {(r.stdout + r.stderr)[-2000:]}")


def mutant_probe(sql: str, expected: str, mutant_name: str) -> None:
    r = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       capture_output=True, text=True, timeout=90, check=False)
    s = r.stdout + "\n" + r.stderr
    if r.returncode == 0 or expected not in s:
        raise AssertionError(f"MUTANT_NOT_KILLED_BY_EXPECTED_ASSERTION:{mutant_name}:{s[-1200:]}")
    if "syntax error" in s.lower() or "does not exist" in s.lower():
        raise AssertionError(f"MUTANT_KILLED_BY_WRONG_FAILURE:{mutant_name}:{s[-1200:]}")
    print(f"MUTANT_KILLED_BY_EXPECTED_ASSERTION:{mutant_name}")


# Each probe isolates the target behavioral guard. A broad test that had
# already written a row could mask WIRE_DRIFT with REPLAY_CONFLICT (B25).
wire_probe = """
DO $probe$
DECLARE c record;
BEGIN
 SELECT * INTO STRICT c FROM saly.test_v10_context LIMIT 1;
 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
    c.claim_token,c.run_id,'GPT_NATIVE',repeat('0',64),c.archive_sha256,'V10-PROBE-WIRE');
  RAISE EXCEPTION 'V10_MUTANT_WIRE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_WIRE_DRIFT' THEN RAISE; END IF;
 END;
END $probe$;
"""
replay_probe = """
DO $probe$
DECLARE c record;
BEGIN
 SELECT * INTO STRICT c FROM saly.test_v10_context LIMIT 1;
 PERFORM saly.creative_queue_native_reserve_dispatch_v1(
   c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-PROBE-REPLAY-1');
 BEGIN
  PERFORM saly.creative_queue_native_reserve_dispatch_v1(
    c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,'V10-PROBE-REPLAY-2');
  RAISE EXCEPTION 'V10_MUTANT_REPLAY_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT' THEN RAISE; END IF;
 END;
END $probe$;
"""
mutants = [
    ("WIRE_HASH_GUARD",
     "THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_WIRE_DRIFT'; END IF;",
     "THEN NULL; END IF;",
     "V10_MUTANT_WIRE_ACCEPTED", wire_probe),
    ("REPLAY_CONFLICT_GUARD",
     "THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT'; END IF;",
     "THEN NULL; END IF;",
     "V10_MUTANT_REPLAY_ACCEPTED", replay_probe),
]
for name, before, after, expected_assert, probe in mutants:
    if source.count(before) != 1:
        raise AssertionError(f"MUTATION_TARGET_NOT_UNIQUE:{name}")
    sql_file(root / "queue_v02" / "fixture_pg17.sql")
    sql_file(root / "queue_v05" / "001_saly_native_render_wire_candidate.sql")
    sql_file(root / "queue_v06" / "001_saly_delivery_attestation_guard_candidate.sql")
    with tempfile.TemporaryDirectory(prefix="saly-v10-pg17-mutant-") as temp:
        mutant = Path(temp) / "mutated.sql"
        mutant.write_text(source.replace(before, after))
        sql_file(mutant)
        sql_file(v10 / "setup_pg17.sql")
        mutant_probe(probe, expected_assert, name)
print("PASS_V10_2_OF_2_PG17_BEHAVIORAL_MUTANTS")

"""V10 B25/B28 mutation evidence using disposable real PG17, never Supabase.

A killed mutant must reach the specific test assertion, not fail at SQL parse
or an unrelated guard. Source is always reset/restored by the bash driver.
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


def sql_file(path: Path, expect_success=True) -> str:
    r = subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", str(path)],
                       capture_output=True, text=True, timeout=90, check=False)
    data = r.stdout + "\n" + r.stderr
    if expect_success and r.returncode:
        raise AssertionError(f"SETUP_FAILED: {path.name}: {data[-2000:]}")
    return data if r.returncode else "OK"


mutants = [
    ("WIRE_HASH_GUARD",
     "THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_WIRE_DRIFT'; END IF;",
     "THEN NULL; END IF;",
     "V10_TEST_BAD_WIRE_HASH_ACCEPTED"),
    ("REPLAY_CONFLICT_GUARD",
     "THEN RAISE EXCEPTION 'CREATIVE_DISPATCH_RESERVATION_REPLAY_CONFLICT'; END IF;",
     "THEN NULL; END IF;",
     "V10_TEST_REPLAY_MISMATCH_ACCEPTED"),
]
for name, before, after, expected_assert in mutants:
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
        actual = sql_file(v10 / "test_pg17_candidate.sql", expect_success=False)
        if actual == "OK" or expected_assert not in actual:
            raise AssertionError(f"MUTANT_NOT_KILLED_BY_EXPECTED_ASSERTION:{name}:{actual[-1800:]}")
        if "syntax error" in actual.lower() or "does not exist" in actual.lower():
            raise AssertionError(f"MUTANT_KILLED_BY_WRONG_FAILURE:{name}")
        print(f"MUTANT_KILLED_BY_EXPECTED_ASSERTION:{name}")
print("PASS_V10_2_OF_2_PG17_BEHAVIORAL_MUTANTS")

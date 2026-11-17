"""Rollback fixtures for one-use logic (SQLite). NOT PostgreSQL 17/18."""
import sqlite3

SCHEMA = """CREATE TABLE approvals(
  message_id TEXT PRIMARY KEY, scope_sha TEXT NOT NULL,
  actor TEXT NOT NULL, active INT NOT NULL,
  expires_at INT NOT NULL, action TEXT NOT NULL,
  model_generated INT NOT NULL, consumed INT NOT NULL DEFAULT 0
)"""
NOW = 10000


def fixture(order=True, **patch):
    conn = sqlite3.connect(":memory:")
    conn.execute(SCHEMA)
    if order:
        rec = dict(message_id="fixture-message-0001", scope_sha="a"*64,
                   actor="fixture-owner", active=1, expires_at=NOW+600,
                   action="MERGE_GOVERNANCE_PR", model_generated=0, consumed=0)
        rec.update(patch)
        conn.execute("INSERT INTO approvals VALUES (?,?,?,?,?,?,?,?)", tuple(rec.values()))
        conn.commit()
    return conn


def consume(conn, *, scope="a"*64, actor="fixture-owner",
            action="MERGE_GOVERNANCE_PR", now=NOW):
    result = conn.execute(
        """UPDATE approvals SET consumed=1
        WHERE message_id=? AND scope_sha=? AND actor=?
        AND action=? AND active=1 AND expires_at>?
        AND model_generated=0 AND consumed=0""",
        ("fixture-message-0001", scope, actor, action, now))
    return result.rowcount == 1


def test_positive_with_rollback():
    conn = fixture()
    conn.execute("BEGIN")
    assert consume(conn)
    conn.rollback()
    assert conn.execute("SELECT consumed FROM approvals").fetchone()[0] == 0


def test_missing_order():
    assert not consume(fixture(order=False))


def test_wrong_scope():
    assert not consume(fixture(), scope="b"*64)


def test_wrong_actor():
    assert not consume(fixture(), actor="model")


def test_expired():
    assert not consume(fixture(expires_at=NOW-1))


def test_replay():
    conn = fixture()
    conn.execute("BEGIN")
    assert consume(conn)
    assert not consume(conn)
    conn.rollback()


def test_revoked():
    assert not consume(fixture(active=0))


def test_self_approval():
    assert not consume(fixture(model_generated=1))


def test_wrong_action():
    assert not consume(fixture(), action="PROMOTE_RULE_BATCH")

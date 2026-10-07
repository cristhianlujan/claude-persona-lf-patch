from __future__ import annotations

import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, call, patch


try:
    import psycopg  # noqa: F401
    from psycopg.pq import TransactionStatus
except ModuleNotFoundError:
    psycopg_stub = types.ModuleType("psycopg")

    class OperationalError(Exception):
        pass

    class InterfaceError(Exception):
        pass

    class TransactionStatus:
        IDLE = 0
        ACTIVE = 1
        INTRANS = 2
        INERROR = 3
        UNKNOWN = 4

    psycopg_stub.Connection = object
    psycopg_stub.Cursor = object
    psycopg_stub.OperationalError = OperationalError
    psycopg_stub.InterfaceError = InterfaceError
    psycopg_stub.connect = MagicMock()

    pq_stub = types.ModuleType("psycopg.pq")
    pq_stub.TransactionStatus = TransactionStatus

    types_stub = types.ModuleType("psycopg.types")
    json_stub = types.ModuleType("psycopg.types.json")

    class Jsonb:
        def __init__(self, value):
            self.value = value

    json_stub.Jsonb = Jsonb
    types_stub.json = json_stub

    sys.modules["psycopg"] = psycopg_stub
    sys.modules["psycopg.pq"] = pq_stub
    sys.modules["psycopg.types"] = types_stub
    sys.modules["psycopg.types.json"] = json_stub


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "hetzner_queue_worker_connection_under_test",
    SCRIPTS / "hetzner_queue_worker.py",
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeInfo:
    def __init__(self, status, backend_pid: int = 4242):
        self.transaction_status = status
        self.backend_pid = backend_pid


class FakeConnection:
    def __init__(self, status=TransactionStatus.IDLE, *, rollback_error: Exception | None = None):
        self.closed = False
        self.info = FakeInfo(status)
        self.rollback_error = rollback_error
        self.rollback_calls = 0
        self.close_calls = 0

    def rollback(self) -> None:
        self.rollback_calls += 1
        if self.rollback_error is not None:
            raise self.rollback_error
        self.info.transaction_status = TransactionStatus.IDLE

    def close(self) -> None:
        self.close_calls += 1
        self.closed = True


class StopDaemon(Exception):
    pass


class HetznerQueueConnectionTest(unittest.TestCase):
    def test_connect_uses_persistent_session_settings(self) -> None:
        fake = FakeConnection()
        with (
            patch.dict(
                MODULE.os.environ,
                {
                    "LF_SUPABASE_DB_PASSWORD": "secret",
                    "SUPABASE_PROJECT_ID": "mhwmirqcgxxukpctffuv",
                    "SUPABASE_POOLER_HOST": "aws-1-us-east-1.pooler.supabase.com",
                },
                clear=False,
            ),
            patch.object(MODULE.psycopg, "connect", return_value=fake) as connect,
        ):
            self.assertIs(MODULE._connect(), fake)

        connect.assert_called_once_with(
            host="aws-1-us-east-1.pooler.supabase.com",
            port=5432,
            user="postgres.mhwmirqcgxxukpctffuv",
            password="secret",
            dbname="postgres",
            sslmode="require",
            autocommit=False,
            application_name="lf-hetzner-queue-worker",
            connect_timeout=10,
            keepalives=1,
            keepalives_idle=30,
            keepalives_interval=10,
            keepalives_count=3,
            options="-c idle_in_transaction_session_timeout=60000",
        )

    def test_run_once_uses_supplied_connection_without_connecting(self) -> None:
        conn = FakeConnection()
        with (
            patch.object(MODULE, "_connect") as connect,
            patch.object(MODULE, "_reconcile_governed_pending", return_value=0),
            patch.object(MODULE, "_claim", return_value=None),
        ):
            self.assertFalse(MODULE.run_once(conn))
        connect.assert_not_called()

    def test_daemon_reconnects_after_operational_error_and_continues(self) -> None:
        first = FakeConnection()
        second = FakeConnection()

        def sleep(seconds: float) -> None:
            if seconds == 3.0:
                raise StopDaemon()

        with (
            patch.object(MODULE, "_connect", side_effect=[first, second]) as connect,
            patch.object(
                MODULE,
                "run_once",
                side_effect=[MODULE.psycopg.OperationalError("lost"), False],
            ) as run_once,
            patch.object(MODULE.time, "sleep", side_effect=sleep) as sleep_mock,
            patch.object(MODULE, "_emit_heartbeat"),
        ):
            with self.assertRaises(StopDaemon):
                MODULE._run_daemon(3.0)

        self.assertEqual(connect.call_count, 2)
        self.assertEqual(run_once.call_args_list, [call(first), call(second)])
        self.assertTrue(first.closed)
        self.assertEqual(sleep_mock.call_args_list, [call(1.0), call(3.0)])

    def test_cleanup_leaves_idle_connection_untouched(self) -> None:
        conn = FakeConnection(TransactionStatus.IDLE)
        self.assertIs(MODULE._cleanup_transaction(conn), conn)
        self.assertEqual(conn.rollback_calls, 0)
        self.assertFalse(conn.closed)

    def test_cleanup_rolls_back_inerror_connection_to_idle(self) -> None:
        conn = FakeConnection(TransactionStatus.INERROR)
        self.assertIs(MODULE._cleanup_transaction(conn), conn)
        self.assertEqual(conn.rollback_calls, 1)
        self.assertEqual(conn.info.transaction_status, TransactionStatus.IDLE)
        self.assertFalse(conn.closed)

    def test_cleanup_discards_connection_when_rollback_fails(self) -> None:
        conn = FakeConnection(
            TransactionStatus.INERROR,
            rollback_error=RuntimeError("rollback failed"),
        )
        self.assertIsNone(MODULE._cleanup_transaction(conn))
        self.assertEqual(conn.rollback_calls, 1)
        self.assertTrue(conn.closed)

    def test_heartbeat_emits_startup_and_periodic_after_fifteen_minutes(self) -> None:
        conn = FakeConnection(TransactionStatus.IDLE)
        with (
            patch.object(MODULE, "_connect", return_value=conn),
            patch.object(MODULE, "run_once", return_value=False),
            patch.object(MODULE.time, "monotonic", side_effect=[0.0, 901.0]),
            patch.object(MODULE.time, "sleep", side_effect=StopDaemon()),
            patch.object(MODULE, "_emit_heartbeat") as heartbeat,
        ):
            with self.assertRaises(StopDaemon):
                MODULE._run_daemon(3.0)

        self.assertEqual(heartbeat.call_args_list[0], call(phase="startup"))
        heartbeat.assert_any_call(
            cycles=1,
            work=0,
            reconnects=0,
            conn=conn,
        )


if __name__ == "__main__":
    unittest.main()

"""Explicit psycopg RO transport and trusted completion binding. Source only."""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import threading

from analysis_a6_a9_readonly_caller_v1 import DecisionContextShadowCaller, ExpectedContext, HEX64, READ_SQL, SqlReadPort

PROFILE = "PERFIL-PROGRAMMING-ANALYSIS-LF"
OPTIONS = "-c default_transaction_read_only=on -c statement_timeout=1500 -c lock_timeout=500 -c idle_in_transaction_session_timeout=2000"


class PsycopgReadOne:
    """Explicit approved credentials only; never inherit a privileged runtime DSN.

    Deployment must qualify the role/target/SSL trust. RO mode is defense in
    depth, not proof of least privilege or operational admission.
    """
    def __init__(self, *, connection, connect=None):
        allowed = {"host", "port", "dbname", "user", "password", "sslmode", "sslrootcert"}
        if (not isinstance(connection, dict) or set(connection) - allowed
                or any(not isinstance(connection.get(k), str) or not connection[k].strip()
                       for k in ("host", "dbname", "user", "password"))
                or connection.get("sslmode", "verify-full") not in {"verify-full", "verify-ca"}
                or type(connection.get("port", 5432)) is not int
                or not 1 <= connection.get("port", 5432) <= 65535):
            raise ValueError("EXPLICIT_RO_CONNECTION_INVALID")
        self.__connection = dict(connection)
        self.__connection.setdefault("sslmode", "verify-full")
        self.__connect = connect

    def __call__(self, sql, params):
        if sql != READ_SQL or not isinstance(params, tuple) or len(params) != 3:
            raise ValueError("FIXED_READ_ONLY_QUERY_REQUIRED")
        connect = self.__connect
        if connect is None:
            from psycopg import connect
        conn = connect(**self.__connection, connect_timeout=2, options=OPTIONS,
                       autocommit=True, application_name="lf-a6-a9-shadow-ro")
        try:
            with conn.cursor() as cursor:
                cursor.execute("BEGIN READ ONLY")
                cursor.execute(READ_SQL, params)
                row = cursor.fetchone()
                if not isinstance(row, (tuple, list)) or len(row) != 1 or not isinstance(row[0], dict):
                    raise ValueError("RO_READBACK_INVALID")
                if row[0].get("transaction_read_only") is not True:
                    raise ValueError("RO_TRANSACTION_REQUIRED")
                return row[0]
        finally:
            try:
                conn.rollback()
            finally:
                conn.close()


@dataclass(frozen=True)
class CompletionBinding:
    request_id: str
    request_sha256: str
    kind: str
    expected: ExpectedContext

    def valid(self):
        return (isinstance(self.request_id, str) and 0 < len(self.request_id) <= 200
                and isinstance(self.request_sha256, str) and HEX64.fullmatch(self.request_sha256) is not None
                and self.kind in {"execute", "queue_execute", "artifact_set_execute"}
                and isinstance(self.expected, ExpectedContext) and self.expected.valid())


class A6A9CompletionObserver:
    """Injected into create_app only by a separately authorized composition.

    Trusted allowlist fixes request hash and immutable context identity before
    execution. No binding from model output, latest lookup, or untrusted hints.
    Called on CompletionObservation daemon, never on the response path.
    """
    def __init__(self, read_one, *, enabled=False, bindings=()):
        if type(enabled) is not bool or not isinstance(bindings, tuple) or len(bindings) > 64:
            raise ValueError("SHADOW_CONFIGURATION_INVALID")
        if any(not isinstance(b, CompletionBinding) or not b.valid() for b in bindings):
            raise ValueError("SHADOW_BINDING_INVALID")
        keys = [(b.kind, b.request_id) for b in bindings]
        if len(set(keys)) != len(keys):
            raise ValueError("SHADOW_BINDING_DUPLICATE")
        self._bindings = dict(zip(keys, bindings))
        self._enabled = enabled
        self._caller = DecisionContextShadowCaller(SqlReadPort(read_one))
        self._events = deque(maxlen=64)
        self._lock = threading.Lock()

    @classmethod
    def from_config(cls, config, read_one):
        """Parse an explicitly supplied trusted config; no file/env auto-load."""
        keys = {"schema_version", "enabled", "bindings"}
        if (not isinstance(config, dict) or set(config) != keys
                or config["schema_version"] != "A6_A9_COMPLETION_SHADOW_CONFIGURATION_V1"
                or not isinstance(config["bindings"], list) or len(config["bindings"]) > 64):
            raise ValueError("SHADOW_CONFIGURATION_INVALID")
        bindings = []
        try:
            for item in config["bindings"]:
                if not isinstance(item, dict) or set(item) != {"request_id", "request_sha256", "kind", "expected"}:
                    raise ValueError("SHADOW_BINDING_INVALID")
                bindings.append(CompletionBinding(item["request_id"], item["request_sha256"], item["kind"],
                                                  ExpectedContext(**item["expected"])))
        except (TypeError, KeyError) as exc:
            raise ValueError("SHADOW_BINDING_INVALID") from exc
        return cls(read_one, enabled=config["enabled"], bindings=tuple(bindings))

    def diagnostics(self):
        import copy
        with self._lock:
            return copy.deepcopy(list(self._events))

    def __call__(self, notice):
        if not self._enabled:
            return
        state = "SKIPPED_BINDING"
        try:
            binding = self._bindings.get((notice.get("kind"), notice.get("request_id")))
            if (binding is not None and notice.get("profiles") == (PROFILE,)
                    and notice.get("request_sha256") == binding.request_sha256):
                dispatched = self._caller.resolve(binding.expected, enabled=True)
                # Wait is off the active path, bounded, and holds one capacity slot.
                state = dispatched.observation.wait(2.0)["state"]
        except Exception:
            state = "ERROR"
        with self._lock:
            self._events.append({"state": state, "advisory_only": True,
                                 "route_effect_allowed": False, "operational_admission": False,
                                 "planning_allowed": False, "execution_allowed": False,
                                 "persistence_allowed": False})

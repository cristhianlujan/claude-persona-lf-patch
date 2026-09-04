#!/usr/bin/env python3
"""Lock the ACT-0001 text-profile producer to Hetzner primary with explicit GitHub backup."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase" / "migrations" / "20260904091702_lf_profile_runtime_queue_native_hetzner_producer_v1.sql"
SERVICE = ROOT / "services" / "profile_runtime_api"


def fail(code: str) -> None:
    raise SystemExit(code)


def require(text: str, token: str, code: str) -> None:
    if token not in text:
        fail(code)


def main() -> int:
    if not MIGRATION.is_file():
        fail("HETZNER_PRODUCER_MIGRATION_MISSING")
    migration = MIGRATION.read_text(encoding="utf-8")

    required_migration = {
        "fn_lf_profile_runtime_enqueue_text_v1": "CANONICAL_TEXT_PRODUCER_MISSING",
        "'PROFILE_EXECUTION'": "ROUTER_PROFILE_EXECUTION_BINDING_MISSING",
        "'READY_TO_EXECUTE'": "ROUTER_READY_GATE_MISSING",
        "then 'HETZNER'": "HETZNER_DEFAULT_SELECTION_MISSING",
        "GITHUB_ACTIONS_EXPLICIT_BACKUP_REASON_REQUIRED": "GITHUB_BACKUP_REASON_GUARD_MISSING",
        "HETZNER_IMAGE_REQUEST_ENVELOPE_REQUIRED_NO_IMPLICIT_GITHUB_FALLBACK": "IMAGE_ENVELOPE_FAIL_CLOSED_GUARD_MISSING",
        "grant execute on function programacion.fn_lf_profile_runtime_enqueue_text_v1": "SERVICE_ROLE_PRODUCER_GRANT_MISSING",
    }
    for token, code in required_migration.items():
        require(migration, token, code)

    if "new.runtime_target := 'GITHUB_ACTIONS'" in migration:
        fail("IMPLICIT_GITHUB_DOWNGRADE_REINTRODUCED")

    app = (SERVICE / "profile_runtime_api" / "app.py").read_text(encoding="utf-8")
    engine = (SERVICE / "profile_runtime_api" / "engine.py").read_text(encoding="utf-8")
    models = (SERVICE / "profile_runtime_api" / "models.py").read_text(encoding="utf-8")
    worker = (SERVICE / "scripts" / "hetzner_queue_worker.py").read_text(encoding="utf-8")

    require(models, "class QueueExecuteRequest", "QUEUE_EXECUTE_MODEL_MISSING")
    require(app, '"/v1/profile/queue-execute"', "QUEUE_EXECUTE_ENDPOINT_MISSING")
    require(engine, "def run_queue_execute", "QUEUE_EXECUTE_ENGINE_MISSING")
    require(worker, "HETZNER_QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE", "QUEUE_IMAGE_ENVELOPE_GUARD_MISSING")
    require(worker, '"/v1/profile/queue-execute"', "WORKER_QUEUE_EXECUTE_ROUTE_MISSING")
    require(worker, '"/v1/profile/execute"', "WORKER_GOVERNED_EXECUTE_ROUTE_MISSING")

    print("PROFILE_RUNTIME_HETZNER_PRODUCER_PASS primary=HETZNER text_queue_native=true image_requires_envelope=true github_backup=explicit_reason_only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

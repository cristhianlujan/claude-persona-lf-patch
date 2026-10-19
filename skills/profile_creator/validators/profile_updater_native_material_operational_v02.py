"""C5 native-chat pre-admission adapter: compose two EXISTING trusted readbacks.

This does not alter the canonical OIDC dispatch/step recorder. The host owns
authenticated GitHub source content reads and Supabase ledger SELECTs.
No service-role secrets, network calls, API model sessions or fallback methods.
"""
from __future__ import annotations

from typing import Any, Callable

from profile_updater_native_material_bridge_v02 import verify_native_material_candidate
from profile_updater_native_material_ledger_v02 import make_native_review_ledger_reader


def verify_native_material_pre_admission(
    *, handoff: dict[str, Any], capture: dict[str, Any],
    current_surface: str, independent_review_receipt_id: str,
    github_source_readback: Callable[[str], bytes | None],
    supabase_read_one: Callable[[str, tuple[str]], dict[str, Any] | None],
) -> dict[str, Any]:
    """Returns REVIEWED_PRE_ADMISSION or raises; NEVER records canonical steps.

    Only the native *authoring material* path uses this entrypoint; remote
    method packs continue through their independently qualified executor.
    """
    ledger_readback = make_native_review_ledger_reader(supabase_read_one)
    result = verify_native_material_candidate(
        handoff=handoff,
        capture=capture,
        expected_current_surface=current_surface,
        trusted_source_readback=github_source_readback,
        trusted_review_readback=ledger_readback,
        review_receipt_id=independent_review_receipt_id,
    )
    if result.get("external_method_execution_certified") is not False or (
        result.get("cutover_eligible") is not False or
        result.get("canonical_steps_recorded") is not False
    ):
        raise ValueError("NATIVE_AUTHORING_PRE_ADMISSION_ESCALATED")
    return result

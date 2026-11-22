"""SALY V12: govern a pending-only image task in the SAME ChatGPT chat.

Two entrypoints for the native chat owner:
  prepare_chat_generation_v1: one atomic DB start -> independent readback ->
  user-visible request summary -> invoke image_gen in THIS conversation.
  complete_chat_generation_v1: called AFTER image_gen has actually returned
  image bytes -> independent QA -> save QA comment and terminal status atomically
  -> readback. No timer, host APIs, provider attestations or false DONE.
SQL adapters are mandatory and must be runtime-owned, never in request JSON.
The adapter is not supplied by this candidate; unit fakes are NOT production.
"""
from __future__ import annotations

import hashlib
import re
from collections.abc import Callable, Mapping, Sequence
from typing import Any

HEXDIGEST = re.compile(r"^[0-9a-f]{64}$")
ORDER_CODE = re.compile(r"^[A-Z][A-Z0-9_-]{2,63}$")
ITEM_CODE = re.compile(r"^[A-Z][A-Z0-9_-]{1,63}$")


class ChatFlowRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ChatFlowRejected(code)


def port_call(fn: Callable[..., Any], code: str, *args: Any) -> Any:
    try:
        return fn(*args)
    except ChatFlowRejected:
        raise
    except Exception as exc:
        raise ChatFlowRejected(code) from exc


def _ports(*values: Any) -> None:
    require(all(callable(v) for v in values), "SALY_CHAT_TRUSTED_DB_OR_QA_PORT_MISSING")


def select_pending_v1(*, order_code: str, allowed_item_codes: Sequence[str],
                      items: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Filter ONLY the named order. Never transform another order's pending rows."""
    require(type(order_code) is str and ORDER_CODE.fullmatch(order_code) is not None,
            "SALY_CHAT_ORDER_SCOPE_REQUIRED")
    require(type(allowed_item_codes) in (list, tuple)
            and bool(allowed_item_codes)
            and len(set(allowed_item_codes)) == len(allowed_item_codes)
            and all(type(v) is str and ITEM_CODE.fullmatch(v) is not None
                    for v in allowed_item_codes),
            "SALY_CHAT_ITEM_SCOPE_REQUIRED")
    require(isinstance(items, (list, tuple))
            and all(isinstance(r, Mapping) for r in items),
            "SALY_CHAT_READBACK_INVALID")
    selected = []
    seen = set()
    for r in items:
        if r.get("order_code") != order_code or r.get("item_code") not in allowed_item_codes:
            continue
        item_id = r.get("item_id")
        require(type(item_id) is int and item_id > 0 and item_id not in seen,
                "SALY_CHAT_SELECTION_DUPLICATED_OR_INVALID")
        seen.add(item_id)
        # Persisted image may exist while item says PENDIENTE: reconcile, don't regenerate.
        if r.get("item_state") == "PENDIENTE" and r.get("existing_artifact_linked") is True:
            raise ChatFlowRejected("SALY_CHAT_STALE_PENDING_WITH_ARTIFACT")
        if r.get("item_state") != "PENDIENTE":
            continue
        require(r.get("order_state") in ("PLANIFICADO", "EN_PROCESO"),
                "SALY_CHAT_ORDER_NOT_ACTIVE")
        selected.append(r)
    if not selected:
        return {"status": "NO_PENDING_IN_SCOPE", "order_code": order_code,
                "selected_count": 0, "next_item": None}
    first = min(selected, key=lambda r: (r.get("ordinal", 10**9), r["item_id"]))
    return {"status": "PENDING_SELECTED", "order_code": order_code,
            "selected_count": len(selected),
            "next_item": {"item_id": first["item_id"],
                          "item_code": first["item_code"]}}


def prepare_chat_generation_v1(
    *, order_code: str, allowed_item_codes: Sequence[str],
    pending_reader: Callable[[str], Sequence[Mapping[str, Any]]] | None,
    begin_atomic: Callable[[str, int], Mapping[str, Any]] | None,
    processing_readback: Callable[[int], Mapping[str, Any]] | None,
) -> dict[str, Any]:
    """Must NOT send to image_gen until the DB state PRODUCIENDO is reread."""
    _ports(pending_reader, begin_atomic, processing_readback)
    rows = port_call(pending_reader, "SALY_CHAT_PENDING_READ_FAILED", order_code)
    choice = select_pending_v1(order_code=order_code,
                               allowed_item_codes=allowed_item_codes, items=rows)
    if choice["next_item"] is None:
        return choice
    item_id = choice["next_item"]["item_id"]
    started = port_call(begin_atomic, "SALY_CHAT_BEGIN_ATOMIC_FAILED",
                        order_code, item_id)
    require(isinstance(started, Mapping)
            and started.get("status") == "PROCESSING_STARTED"
            and type(started.get("run_id")) is int and started["run_id"] > 0,
            "SALY_CHAT_BEGIN_NOT_CONFIRMED")
    row = port_call(processing_readback, "SALY_CHAT_BEGIN_READBACK_FAILED",
                    started["run_id"])
    require(isinstance(row, Mapping)
            and row.get("run_id") == started["run_id"]
            and row.get("order_code") == order_code
            and row.get("item_id") == item_id
            and row.get("item_code") == choice["next_item"]["item_code"]
            and row.get("item_state") == "PRODUCIENDO"
            and row.get("run_state") == "EJECUTANDO"
            and row.get("order_state") == "EN_PROCESO"
            and type(row.get("prompt")) is str
            and bool(row["prompt"].strip())
            and type(row.get("prompt_sha256")) is str
            and HEXDIGEST.fullmatch(row["prompt_sha256"]) is not None
            and hashlib.sha256(row["prompt"].encode("utf-8")).hexdigest()
                == row["prompt_sha256"],
            "SALY_CHAT_PROCESSING_READBACK_MISMATCH")
    require(type(row.get("order_title")) is str and bool(row["order_title"].strip())
            and type(row.get("item_title")) is str and bool(row["item_title"].strip()),
            "SALY_CHAT_LABELS_MISSING")
    # Render instruction is returned only after the authoritative state transition.
    return {
        "schema_version": "SALY_CHAT_GENERATION_PREPARED_V1",
        "status": "EN_PROCESO_VERIFICADO_MOSTRAR_EN_CHAT",
        "order_code": order_code, "order_title": row["order_title"],
        "item_code": row["item_code"], "item_title": row["item_title"],
        "run_id": started["run_id"], "item_id": item_id,
        "chat_message": (f"Pedido: {order_code} — {row['order_title']}\n"
                         f"Solicitud: {row['item_code']} — {row['item_title']}\n"
                         f"Estado: EN PROCESO\n"
                         f"Generación: imagen en esta conversación"),
        "native_prompt": row["prompt"],
        "prompt_sha256": row["prompt_sha256"],
        "next_action": "CALL_IMAGE_GEN_IN_CURRENT_CHAT",
        "image_generated": False,
        "qa_completed": False,
        "status_terminado": False,
    }


def complete_chat_generation_v1(
    *, run_id: int, image_bytes: bytes,
    processing_readback: Callable[[int], Mapping[str, Any]] | None,
    qa_reviewer: Callable[[bytes, Mapping[str, Any]], Mapping[str, Any]] | None,
    save_qa_and_finish_atomic: Callable[[int, str, str, str, str], Mapping[str, Any]] | None,
    final_readback: Callable[[int], Mapping[str, Any]] | None,
) -> dict[str, Any]:
    """Call ONCE only after native image tool returns a real PNG.

    QA reviewer must be independent of render worker and have actual image bytes.
    DB adapter must atomically save comment, finalize RUN/item, and release claim.
    No QA PASS, no terminal state. A failed QA remains BLOQUEADO.
    """
    _ports(processing_readback, qa_reviewer, save_qa_and_finish_atomic, final_readback)
    require(type(run_id) is int and run_id > 0, "SALY_CHAT_RUN_ID_INVALID")
    require(type(image_bytes) is bytes and len(image_bytes) > 32
            and image_bytes.startswith(b"\x89PNG\r\n\x1a\n"),
            "SALY_CHAT_GENERATION_NOT_FINISHED_OR_NOT_PNG")
    state = port_call(processing_readback,
                      "SALY_CHAT_POST_RENDER_READBACK_FAILED", run_id)
    require(isinstance(state, Mapping)
            and state.get("run_id") == run_id
            and state.get("run_state") == "EJECUTANDO"
            and state.get("item_state") == "PRODUCIENDO"
            and type(state.get("worker_ref")) is str
            and bool(state["worker_ref"].strip()),
            "SALY_CHAT_RUN_NOT_PROCESSING")
    digest = hashlib.sha256(image_bytes).hexdigest()
    # Reviewer sees immutable bytes and a new plain dict; never worker-supplied QA.
    review = port_call(qa_reviewer, "SALY_CHAT_QA_FAILED",
                       image_bytes, dict(state))
    require(isinstance(review, Mapping)
            and review.get("verdict") in ("PASS", "FAIL")
            and type(review.get("comment")) is str
            and bool(review["comment"].strip())
            and len(review["comment"]) <= 4000
            and type(review.get("reviewer_ref")) is str
            and bool(review["reviewer_ref"].strip())
            and review["reviewer_ref"].strip().casefold()
                != state["worker_ref"].strip().casefold(),
            "SALY_CHAT_QA_EVIDENCE_INVALID")
    saved = port_call(save_qa_and_finish_atomic,
                      "SALY_CHAT_QA_SAVE_OR_TERMINAL_FAILED", run_id, digest,
                      review["verdict"], review["comment"],
                      review["reviewer_ref"])
    expected_item_state = "APROBADO" if review["verdict"] == "PASS" else "BLOQUEADO"
    expected_claim_state = "DONE" if review["verdict"] == "PASS" else "BLOCKED"
    require(isinstance(saved, Mapping)
            and saved.get("status") == "QA_SAVED_AND_FINALIZED",
            "SALY_CHAT_QA_SAVE_NOT_CONFIRMED")
    final = port_call(final_readback, "SALY_CHAT_FINAL_READBACK_FAILED", run_id)
    require(isinstance(final, Mapping)
            and final.get("run_id") == run_id
            and final.get("item_state") == expected_item_state
            and final.get("claim_state") == expected_claim_state
            and final.get("qa_comment") == review["comment"]
            and final.get("qa_verdict") == review["verdict"]
            and final.get("qa_reviewer_ref") == review["reviewer_ref"]
            and final.get("artifact_sha256") == digest
            and final.get("comment_persisted") is True,
            "SALY_CHAT_FINAL_READBACK_MISMATCH")
    # DB state stays as approved SQL enum, chat-facing alias is TERMINADO.
    return {
        "schema_version": "SALY_CHAT_GENERATION_COMPLETED_V1",
        "status": "TERMINADO" if review["verdict"] == "PASS" else "BLOQUEADO_QA",
        "run_id": run_id, "image_sha256": digest,
        "qa_verdict": review["verdict"], "qa_comment": review["comment"],
        "qa_comment_saved": True, "db_item_state": final["item_state"],
        "db_claim_state": final["claim_state"],
        "order_closed": final.get("order_state") == "COMPLETADO",
        "may_regenerate_without_new_request": False,
    }

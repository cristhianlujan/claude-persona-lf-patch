"""SALY V07: verify RAW image references before a Native creative tool call.

Consumes the frozen V05 SQL render wire plus bytes provided by an *authorized*
source reader. Does not send to Native, attest a provider/host, or touch DB.
The real source reader must bind a registered file_ref to authenticated Drive.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import re
import struct
from collections.abc import Callable, Mapping
from typing import Any

PROVIDERS = {"GPT_NATIVE": "OPENAI_CHATGPT_NATIVE",
             "CLAUDE_NATIVE": "ANTHROPIC_CLAUDE_NATIVE"}
SHA64 = re.compile(r"^[a-f0-9]{64}$")
SAFE_FILENAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_. -]{0,127}$")
PNG_SIG = b"\x89PNG\r\n\x1a\n"


class NativeSourceRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def need(ok: bool, code: str) -> None:
    if not ok:
        raise NativeSourceRejected(code)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _pairs_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k, v in pairs:
        need(k not in out, "SALY_NATIVE_SOURCE_DUPLICATE_WIRE_FIELD")
        out[k] = v
    return out


def verify_native_source_bytes(
    *, wire: Mapping[str, Any], binding: Mapping[str, Any],
    read_registered_file: Callable[[str], bytes] | None,
) -> dict[str, Any]:
    """Fail closed on any missing/drifting byte source; output is NOT a receipt.

    IMPORTANT: 'wire' and 'binding' must originate in a trusted SQL readback,
    and 'read_registered_file' must be a trusted service-owned connector, not
    a tool specified by an order. This function cannot prove those origins.
    """
    need(isinstance(wire, Mapping) and isinstance(binding, Mapping),
         "SALY_NATIVE_SOURCE_INPUT_INVALID")
    need(callable(read_registered_file), "SALY_NATIVE_SOURCE_READER_MISSING")
    need(wire.get("schema_version") == "SALY_NATIVE_RENDER_WIRE_V1"
         and wire.get("status") == "RENDER_WIRE_FROZEN_AUTHORIZED"
         and wire.get("render_authorized") is True
         and wire.get("native_transmitted") is False
         and wire.get("provider_receipt") is None
         and wire.get("host_delivery_verified") is False
         and wire.get("db_done_allowed") is False,
         "SALY_NATIVE_SOURCE_WIRE_NOT_READY")
    mode = wire.get("executor_mode")
    need(mode in PROVIDERS and wire.get("executor_provider") == PROVIDERS.get(mode),
         "SALY_NATIVE_SOURCE_EXECUTOR_MISMATCH")
    for key in ("order_id", "item_id", "run_id", "claim_id",
                "wire_sha256", "prompt_sha256", "input_snapshot_sha256",
                "contract_sha256"):
        need(key in binding and wire.get(key) == binding[key],
             "SALY_NATIVE_SOURCE_BINDING_MISMATCH:" + key)
    encoded = wire.get("wire_base64")
    need(isinstance(encoded, str) and bool(encoded),
         "SALY_NATIVE_SOURCE_BASE64_MISSING")
    try:
        payload_bytes = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise NativeSourceRejected("SALY_NATIVE_SOURCE_BASE64_INVALID") from exc
    need(isinstance(wire.get("wire_sha256"), str)
         and SHA64.fullmatch(wire["wire_sha256"]) is not None
         and digest(payload_bytes) == wire["wire_sha256"],
         "SALY_NATIVE_SOURCE_WIRE_HASH_DRIFT")
    try:
        body = json.loads(payload_bytes.decode("utf-8"),
                          object_pairs_hook=_pairs_no_duplicates)
    except NativeSourceRejected:
        raise
    except (ValueError, UnicodeError) as exc:
        raise NativeSourceRejected("SALY_NATIVE_SOURCE_PAYLOAD_INVALID") from exc
    need(isinstance(body, dict) and set(body) == {"prompt", "attachments"}
         and isinstance(body["prompt"], str) and body["prompt"].strip()
         and isinstance(body["attachments"], list)
         and len(body["attachments"]) > 0,
         "SALY_NATIVE_SOURCE_PAYLOAD_SHAPE")
    need(isinstance(wire.get("prompt_sha256"), str)
         and SHA64.fullmatch(wire["prompt_sha256"]) is not None
         and digest(body["prompt"].encode("utf-8")) == wire["prompt_sha256"],
         "SALY_NATIVE_SOURCE_PROMPT_DRIFT")

    seen_names: set[str] = set()
    seen_refs: set[str] = set()
    verified = []
    for ent in body["attachments"]:
        need(isinstance(ent, dict)
             and set(ent) == {"filename", "sha256", "asset_code", "provider",
                              "file_ref", "mime_type"},
             "SALY_NATIVE_SOURCE_ATTACHMENT_SHAPE")
        name = ent.get("filename")
        ref = ent.get("file_ref")
        pin = ent.get("sha256")
        need(isinstance(name, str) and SAFE_FILENAME.fullmatch(name) is not None
             and name not in (".", "..") and "/" not in name and "\\" not in name
             and name not in seen_names,
             "SALY_NATIVE_SOURCE_FILENAME_INVALID")
        need(isinstance(ref, str) and 1 <= len(ref) <= 256
             and ref not in seen_refs and ent.get("provider") == "GOOGLE_DRIVE"
             and isinstance(ent.get("asset_code"), str)
             and bool(ent["asset_code"].strip()),
             "SALY_NATIVE_SOURCE_REF_INVALID")
        need(isinstance(pin, str) and SHA64.fullmatch(pin) is not None,
             "SALY_NATIVE_SOURCE_SHA_PIN_INVALID")
        need(ent.get("mime_type") == "image/png",
             "SALY_NATIVE_SOURCE_MIME_NOT_SUPPORTED")
        seen_names.add(name)
        seen_refs.add(ref)
        try:
            content = read_registered_file(ref)
        except Exception as exc:
            raise NativeSourceRejected("SALY_NATIVE_SOURCE_READ_FAILED") from exc
        need(type(content) is bytes and len(content) >= 24,
             "SALY_NATIVE_SOURCE_BYTES_MISSING")
        need(digest(content) == pin, "SALY_NATIVE_SOURCE_BYTES_DRIFT")
        need(content[:8] == PNG_SIG and content[12:16] == b"IHDR",
             "SALY_NATIVE_SOURCE_PNG_INVALID")
        width, height = struct.unpack(">II", content[16:24])
        need(width > 0 and height > 0, "SALY_NATIVE_SOURCE_DIMENSIONS_INVALID")
        verified.append({"filename": name, "file_ref": ref, "asset_code": ent["asset_code"],
                         "sha256": pin, "bytes": len(content),
                         "width_px": width, "height_px": height,
                         "status": "SOURCE_BYTES_VERIFIED_NOT_SENT"})
    return {
        "schema_version": "SALY_NATIVE_SOURCE_PREFLIGHT_V1",
        "status": "ALL_REGISTERED_SOURCE_BYTES_VERIFIED_NOT_SENT",
        "order_id": binding["order_id"], "item_id": binding["item_id"],
        "run_id": binding["run_id"], "claim_id": binding["claim_id"],
        "executor_mode": mode, "prompt_sha256": wire["prompt_sha256"],
        "wire_sha256": wire["wire_sha256"],
        "attachments": verified,
        "attachment_count": len(verified),
        "provider_attested": False, "host_delivery_verified": False,
        "native_transmitted": False, "db_done_allowed": False,
        "next_action": "ARCHIVE_WITH_EXISTING_NATIVE_TRANSPORT_CAPTURE_V1",
    }

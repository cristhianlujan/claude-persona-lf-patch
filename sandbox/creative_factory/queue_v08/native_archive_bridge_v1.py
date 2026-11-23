"""SALY V08: connect V07 source preflight to existing Native pre-dispatch archive.

This is a local candidate bridge: no Native tool invocation, DB write,
provider callback, QA promotion, or host delivery. A valid local archive is
NOT authorization to send or mark an order DONE.

The wire and binding must originate from a trusted and fresh runtime readback;
the byte reader, protected-asset pins and destination must be runtime-owned.
These properties cannot be proven by this pure orchestration module.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import stat
import tempfile
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

from sandbox.creative_factory.queue_v07.native_source_preflight_v1 import NativeSourceRejected, verify_native_source_bytes
from sandbox.creative_factory.native_transport_capture_v1 import CaptureRejected, archive_pre_dispatch

_SHA64 = set("0123456789abcdef")


class NativeArchiveRejected(ValueError):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


def _need(ok: bool, code: str) -> None:
    if not ok:
        raise NativeArchiveRejected(code)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha_valid(value: Any) -> bool:
    return type(value) is str and len(value) == 64 and set(value) <= _SHA64


def archive_render_candidate_v1(
    *,
    wire: Mapping[str, Any],
    binding: Mapping[str, Any],
    read_registered_file: Callable[[str], bytes] | None,
    protected_assets: Mapping[str, Mapping[str, Any]],
    required_protected_components: frozenset[str],
    output_dir: str | os.PathLike[str],
) -> dict[str, Any]:
    """Archive exact verified source bytes; deliberately never dispatch.

    protected_assets must come from business identity adapter, not request JSON.
    required_protected_components must come from the same frozen design lock.
    Both must be supplied, even if authoritative set is empty.
    """
    _need(type(wire) is dict and type(binding) is dict,
          "SALY_NATIVE_ARCHIVE_BINDING_INVALID")
    _need(callable(read_registered_file),
          "SALY_NATIVE_SOURCE_READER_MISSING")
    _need(isinstance(protected_assets, Mapping)
          and type(required_protected_components) is frozenset
          and all(type(n) is str and bool(n.strip())
                  for n in required_protected_components),
          "SALY_NATIVE_ARCHIVE_PROTECTED_CONTRACT_INVALID")
    _need(set(protected_assets) == required_protected_components,
          "SALY_NATIVE_ARCHIVE_REQUIRED_PROTECTED_MISSING")
    fixed = {}
    for component, pin in protected_assets.items():
        _need(type(component) is str and bool(component.strip())
              and isinstance(pin, Mapping)
              and set(pin) == {"path", "sha256", "source_ref"}
              and _sha_valid(pin.get("sha256"))
              and type(pin.get("source_ref")) is str
              and bool(pin["source_ref"].strip()),
              "SALY_NATIVE_ARCHIVE_PROTECTED_PIN_INVALID")
        path = Path(pin["path"])
        _need(path.is_file() and not path.is_symlink(),
              "SALY_NATIVE_ARCHIVE_PROTECTED_FILE_INVALID")
        _need(_sha(path.read_bytes()) == pin["sha256"],
              "SALY_NATIVE_ARCHIVE_PROTECTED_DRIFT")
        fixed[component] = dict(pin)

    try:
        out = Path(output_dir)
    except (TypeError, ValueError) as exc:
        raise NativeArchiveRejected("SALY_NATIVE_ARCHIVE_DESTINATION_INVALID") from exc
    _need(out.is_absolute() and out.parent.is_dir()
          and not out.parent.is_symlink() and not out.exists()
          and (stat.S_IMODE(out.parent.stat().st_mode) & 0o077) == 0,
          "SALY_NATIVE_ARCHIVE_DESTINATION_INVALID")

    # Single live read per reference. The same bytes are checked by V07, staged,
    # checked again by the canonical archivador, then reread from final output.
    byte_cache: dict[str, bytes] = {}
    def reader(ref: str) -> bytes:
        _need(ref not in byte_cache, "SALY_NATIVE_ARCHIVE_DUPLICATE_READ")
        _need(callable(read_registered_file),
              "SALY_NATIVE_ARCHIVE_SOURCE_READER_MISSING")
        data = read_registered_file(ref)
        # V07 owns the exact BYTES_MISSING diagnostic; invalid types are
        # rejected before any reference staging or archive write.
        if type(data) is bytes:
            byte_cache[ref] = data
        return data

    try:
        preflight = verify_native_source_bytes(
            wire=wire, binding=binding, read_registered_file=reader)
    except NativeSourceRejected as exc:
        raise NativeArchiveRejected(exc.code) from exc

    try:
        raw = base64.b64decode(wire["wire_base64"], validate=True)
    except (KeyError, ValueError) as exc:
        raise NativeArchiveRejected("SALY_NATIVE_ARCHIVE_WIRE_UNAVAILABLE") from exc
    _need(_sha(raw) == preflight["wire_sha256"],
          "SALY_NATIVE_ARCHIVE_WIRE_DRIFT")

    with tempfile.TemporaryDirectory(prefix=".saly-native-verified-", dir=out.parent) as tmp:
        staging = Path(tmp)
        # The tmp directory and source files are local ephemeral copies. Only
        # originals hashed from the registered provider are accepted.
        references: dict[str, str] = {}
        for item in preflight["attachments"]:
            content = byte_cache[item["file_ref"]]
            target = staging / item["filename"]
            with target.open("xb") as fh:
                fh.write(content)
                fh.flush()
                os.fsync(fh.fileno())
            os.chmod(target, 0o600)
            _need(_sha(target.read_bytes()) == item["sha256"],
                  "SALY_NATIVE_ARCHIVE_STAGE_READBACK_DRIFT")
            references[item["filename"]] = str(target)
        try:
            receipt = archive_pre_dispatch(raw, references, fixed, out)
        except CaptureRejected as exc:
            raise NativeArchiveRejected(exc.code) from exc

    # The existing archivador creates directories using the process umask.
    # Parent is already private 0700. Pin the final directories explicitly,
    # including when the process umask is permissive (e.g. 022).
    for directory in (out, out / "references", out / "protected"):
        if directory.is_dir():
            _need(not directory.is_symlink(),
                  "SALY_NATIVE_ARCHIVE_DIRECTORY_UNSAFE")
            os.chmod(directory, 0o700)
            _need(stat.S_IMODE(directory.stat().st_mode) == 0o700,
                  "SALY_NATIVE_ARCHIVE_PRIVATE_MODE_FAILED")

    _need(receipt.get("status") == "HANDOFF_PREPARED_NOT_SENT"
          and receipt.get("provider_receipt") is None
          and receipt.get("invocation_recorded") is False
          and receipt.get("reception_status") == "NOT_SENT"
          and receipt.get("production_approved") is False,
          "SALY_NATIVE_ARCHIVE_FALSE_DELIVERY")
    _need(receipt.get("payload_sha256") == preflight["wire_sha256"]
          and receipt.get("prompt_sha256") == preflight["prompt_sha256"]
          and receipt.get("payload_bytes") == len(raw),
          "SALY_NATIVE_ARCHIVE_RECEIPT_DRIFT")

    recorded = receipt.get("attachments")
    _need(type(recorded) is list and len(recorded) == len(preflight["attachments"]),
          "SALY_NATIVE_ARCHIVE_ATTACHMENT_RECEIPT_DRIFT")
    by_filename = {x.get("filename"): x for x in recorded
                   if isinstance(x, dict) and type(x.get("filename")) is str}
    _need(len(by_filename) == len(recorded),
          "SALY_NATIVE_ARCHIVE_ATTACHMENT_RECEIPT_DRIFT")
    for item in preflight["attachments"]:
        name = item["filename"]
        _need(name in by_filename and by_filename[name].get("sha256") == item["sha256"]
              and by_filename[name].get("bytes") == item["bytes"],
              "SALY_NATIVE_ARCHIVE_ATTACHMENT_RECEIPT_DRIFT")
        _need(_sha((out / "references" / name).read_bytes()) == item["sha256"],
              "SALY_NATIVE_ARCHIVE_FINAL_SOURCE_DRIFT")
    _need((out / "payload.json").read_bytes() == raw,
          "SALY_NATIVE_ARCHIVE_FINAL_WIRE_DRIFT")
    _need(_sha((out / "prompt.txt").read_bytes()) == preflight["prompt_sha256"],
          "SALY_NATIVE_ARCHIVE_FINAL_PROMPT_DRIFT")
    _need(json.loads((out / "archive.json").read_bytes()) == receipt,
          "SALY_NATIVE_ARCHIVE_FINAL_RECEIPT_DRIFT")

    return {
        "schema_version": "SALY_NATIVE_RENDER_ARCHIVE_BRIDGE_V1",
        "status": "HANDOFF_ARCHIVED_NOT_SENT",
        "order_id": binding["order_id"],
        "item_id": binding["item_id"],
        "run_id": binding["run_id"],
        "claim_id": binding["claim_id"],
        "executor_mode": preflight["executor_mode"],
        "wire_sha256": preflight["wire_sha256"],
        "prompt_sha256": preflight["prompt_sha256"],
        "source_count": preflight["attachment_count"],
        "protected_component_count": len(fixed),
        "archive_path": str(out),
        "native_transmitted": False,
        "provider_attested": False,
        "host_delivery_verified": False,
        "db_done_allowed": False,
        "next_action": "NATIVE_HOST_DISPATCH_REQUIRES_SEPARATE_AUTHORITY_AND_REAL_RECEIPT",
    }

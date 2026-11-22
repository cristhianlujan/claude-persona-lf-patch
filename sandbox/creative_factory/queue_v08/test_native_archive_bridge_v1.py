"""Behavioral tests of the real existing Native archive, not a mock archiver.

All inputs are synthetic. Nothing is uploaded, generated or marked delivered.
"""
from __future__ import annotations

import base64
import copy
import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

from sandbox.creative_factory.queue_v08.native_archive_bridge_v1 import (
    NativeArchiveRejected, archive_render_candidate_v1,
)

SMALL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/tfoAAAAASUVORK5CYII="
)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Case:
    def __init__(self, mode="GPT_NATIVE"):
        self.tmp = tempfile.TemporaryDirectory(prefix="saly-v08-fixture-")
        self.root = Path(self.tmp.name)
        self.private = self.root / "tenant-private"
        self.private.mkdir(mode=0o700)
        self.source = self.root / "synthetic.png"
        self.source.write_bytes(SMALL_PNG)
        self.out = self.private / "archive"
        self.calls = 0
        self.cached_bytes = SMALL_PNG
        self.entry = {
            "filename": "synthetic.png",
            "sha256": sha(SMALL_PNG),
            "asset_code": "SYNTHETIC-ART",
            "provider": "GOOGLE_DRIVE",
            "file_ref": "REGISTERED-SOURCE-1",
            "mime_type": "image/png",
        }
        self.payload = {
            "prompt": "Prueba sintetica sin envio Native.",
            "attachments": [self.entry],
        }
        self.wire = {
            "schema_version": "SALY_NATIVE_RENDER_WIRE_V1",
            "status": "RENDER_WIRE_FROZEN_AUTHORIZED",
            "render_authorized": True,
            "native_transmitted": False,
            "provider_receipt": None,
            "host_delivery_verified": False,
            "db_done_allowed": False,
            "executor_mode": mode,
            "executor_provider": (
                "OPENAI_CHATGPT_NATIVE" if mode == "GPT_NATIVE"
                else "ANTHROPIC_CLAUDE_NATIVE"
            ),
            "order_id": 101, "item_id": 202, "run_id": 303, "claim_id": 404,
            "input_snapshot_sha256": sha(b"frozen-snapshot"),
            "contract_sha256": sha(b"frozen-contract"),
        }
        self.pack()
        self.binding = {k: self.wire[k] for k in (
            "order_id", "item_id", "run_id", "claim_id",
            "wire_sha256", "prompt_sha256",
            "input_snapshot_sha256", "contract_sha256",
        )}
        self.required = frozenset()
        self.fixed = {}

    def pack(self):
        raw = json.dumps(self.payload, ensure_ascii=False,
                         separators=(",", ":")).encode()
        self.wire["wire_base64"] = base64.b64encode(raw).decode()
        self.wire["wire_sha256"] = sha(raw)
        self.wire["prompt_sha256"] = sha(self.payload["prompt"].encode())

    def update_binding(self):
        for k in ("wire_sha256", "prompt_sha256"):
            self.binding[k] = self.wire[k]

    def read(self, ref):
        self.calls += 1
        if ref != "REGISTERED-SOURCE-1":
            raise ValueError("unknown ref")
        return self.cached_bytes

    def call(self, **kw):
        args = {
            "wire": self.wire,
            "binding": self.binding,
            "read_registered_file": self.read,
            "protected_assets": self.fixed,
            "required_protected_components": self.required,
            "output_dir": self.out,
        }
        args.update(kw)
        return archive_render_candidate_v1(**args)

    def close(self):
        self.tmp.cleanup()


class ArchiveBridgeTests(unittest.TestCase):
    def setUp(self):
        self.case = Case()
        self.addCleanup(self.case.close)

    def rejected(self, expected, mutate, **kw):
        mutate(self.case)
        with self.assertRaises(NativeArchiveRejected) as ctx:
            self.case.call(**kw)
        self.assertEqual(ctx.exception.code, expected)
        self.assertFalse(self.case.out.exists(),
                         "failed preflight must not create archive")

    def test_gpt_native_writes_exact_existing_archive(self):
        x = self.case.call()
        self.assertEqual(x["status"], "HANDOFF_ARCHIVED_NOT_SENT")
        self.assertEqual(x["source_count"], 1)
        self.assertFalse(x["native_transmitted"])
        self.assertFalse(x["provider_attested"])
        self.assertFalse(x["host_delivery_verified"])
        self.assertFalse(x["db_done_allowed"])
        self.assertEqual(self.case.calls, 1)
        self.assertEqual((self.case.out / "references" / "synthetic.png").read_bytes(),
                         SMALL_PNG)
        raw = base64.b64decode(self.case.wire["wire_base64"])
        self.assertEqual((self.case.out / "payload.json").read_bytes(), raw)
        self.assertEqual(
            json.loads((self.case.out / "archive.json").read_text())["status"],
            "HANDOFF_PREPARED_NOT_SENT",
        )
        self.assertNotIn("claim_token", x)
        self.assertNotIn("provider_receipt", x)

    def test_claude_native_same_archive_contract(self):
        other = Case("CLAUDE_NATIVE")
        self.addCleanup(other.close)
        x = other.call()
        self.assertEqual(x["executor_mode"], "CLAUDE_NATIVE")
        self.assertEqual(x["source_count"], 1)
        self.assertFalse(x["db_done_allowed"])

    def test_replay_same_archive_path_denied(self):
        self.case.call()
        with self.assertRaises(NativeArchiveRejected) as ctx:
            self.case.call()
        self.assertEqual(ctx.exception.code, "SALY_NATIVE_ARCHIVE_DESTINATION_INVALID")
        self.assertEqual(self.case.calls, 1)

    def test_required_protected_missing(self):
        self.rejected("SALY_NATIVE_ARCHIVE_REQUIRED_PROTECTED_MISSING",
                      lambda c: setattr(c, "required", frozenset({"OFFICIAL_LOGO"})))

    def test_missing_protected_contract(self):
        self.rejected("SALY_NATIVE_ARCHIVE_PROTECTED_CONTRACT_INVALID",
                      lambda c: setattr(c, "required", None))

    def test_protected_asset_actual_bytes(self):
        self.case.required = frozenset({"OFFICIAL_LOGO"})
        self.case.fixed = {
            "OFFICIAL_LOGO": {
                "path": str(self.case.source), "sha256": sha(SMALL_PNG),
                "source_ref": "OFFICIAL-LOGO-REGISTERED-REF",
            }
        }
        result = self.case.call()
        self.assertEqual(result["protected_component_count"], 1)
        self.assertEqual((self.case.out / "protected" / "asset_1").read_bytes(), SMALL_PNG)
        archive = json.loads((self.case.out / "archive.json").read_bytes())
        self.assertEqual(archive["protected_assets"][0]["component"], "OFFICIAL_LOGO")
        self.assertFalse(archive["invocation_recorded"])

    def test_protected_asset_hash_drift(self):
        self.case.required = frozenset({"OFFICIAL_LOGO"})
        self.case.fixed = {"OFFICIAL_LOGO": {
            "path": str(self.case.source), "sha256": sha(b"tampered"),
            "source_ref": "OFFICIAL-LOGO-REGISTERED-REF",
        }}
        self.rejected("SALY_NATIVE_ARCHIVE_PROTECTED_DRIFT", lambda c: None)

    def test_protected_asset_symlink_denied(self):
        link = self.case.root / "soft-link.png"
        link.symlink_to(self.case.source)
        self.case.required = frozenset({"OFFICIAL_LOGO"})
        self.case.fixed = {"OFFICIAL_LOGO": {
            "path": str(link), "sha256": sha(SMALL_PNG),
            "source_ref": "OFFICIAL-LOGO-REGISTERED-REF",
        }}
        self.rejected("SALY_NATIVE_ARCHIVE_PROTECTED_FILE_INVALID", lambda c: None)

    def test_protected_missing_source_ref(self):
        self.case.required = frozenset({"OFFICIAL_LOGO"})
        self.case.fixed = {"OFFICIAL_LOGO": {
            "path": str(self.case.source), "sha256": sha(SMALL_PNG),
            "source_ref": "",
        }}
        self.rejected("SALY_NATIVE_ARCHIVE_PROTECTED_PIN_INVALID", lambda c: None)

    def test_world_readable_destination_parent_denied(self):
        os.chmod(self.case.private, 0o755)
        self.rejected("SALY_NATIVE_ARCHIVE_DESTINATION_INVALID", lambda c: None)

    def test_non_absolute_output_rejected(self):
        self.rejected("SALY_NATIVE_ARCHIVE_DESTINATION_INVALID",
                      lambda c: None, output_dir="archive-relative")

    def test_missing_reader_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_READER_MISSING",
                      lambda c: None, read_registered_file=None)

    def test_read_wrong_file_hash_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_BYTES_DRIFT",
                      lambda c: setattr(c, "cached_bytes", SMALL_PNG + b"CHANGED"))
        self.assertEqual(self.case.calls, 1)

    def test_ref_reader_returns_invalid_type(self):
        self.rejected("SALY_NATIVE_SOURCE_BYTES_MISSING",
                      lambda c: setattr(c, "cached_bytes", "not-bytes"))

    def test_ref_reader_unavailable(self):
        self.rejected("SALY_NATIVE_SOURCE_READ_FAILED",
                      lambda c: None,
                      read_registered_file=lambda ref: (_ for _ in ()).throw(OSError("disconnected")))

    def test_wire_not_render_ready(self):
        self.rejected("SALY_NATIVE_SOURCE_WIRE_NOT_READY",
                      lambda c: c.wire.update(
                          schema_version="SALY_CANONICAL_NATIVE_WIRE_V1",
                          status="CANONICAL_WIRE_REVIEW_ONLY",
                          render_authorized=False))

    def test_fake_host_delivery_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_WIRE_NOT_READY",
                      lambda c: c.wire.update(host_delivery_verified=True))

    def test_wrong_provider_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_EXECUTOR_MISMATCH",
                      lambda c: c.wire.update(executor_provider="WRONG"))

    def test_other_run_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_BINDING_MISMATCH:run_id",
                      lambda c: c.binding.update(run_id=800))

    def test_different_claim_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_BINDING_MISMATCH:claim_id",
                      lambda c: c.wire.update(claim_id=800))

    def test_tampered_raw_wire_denied(self):
        self.rejected("SALY_NATIVE_SOURCE_WIRE_HASH_DRIFT",
                      lambda c: c.wire.update(wire_base64=base64.b64encode(b"oops").decode()))

    def test_tampered_prompt_denied(self):
        def mutation(c):
            c.wire["prompt_sha256"] = "a"*64
            c.binding["prompt_sha256"] = "a"*64
        self.rejected("SALY_NATIVE_SOURCE_PROMPT_DRIFT", mutation)

    def test_filename_path_denied(self):
        def mutation(c):
            c.entry["filename"] = "../secret.png"
            c.pack()
            c.update_binding()
        self.rejected("SALY_NATIVE_SOURCE_FILENAME_INVALID", mutation)

    def test_archive_receipt_does_not_approve_production(self):
        self.case.call()
        archive = json.loads((self.case.out / "archive.json").read_bytes())
        self.assertIsNone(archive["provider_receipt"])
        self.assertFalse(archive["production_approved"])
        self.assertEqual(archive["reception_status"], "NOT_SENT")

if __name__ == "__main__":
    unittest.main(verbosity=2)

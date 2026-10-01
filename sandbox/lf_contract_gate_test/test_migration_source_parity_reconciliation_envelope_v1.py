#!/usr/bin/env python3
"""Regression for reconciliation metadata vs domain parity payload."""

from __future__ import annotations

import hashlib
import unittest

import lf_migration_source_parity as subject
import migration_transport_normalization as transport


VERSION = "20260930064736"
NAME = "contract_check_bridge_retirement_v1"


def reconciliation_source(payload: str, *, owner_binding: str = "true", separator: str = "\n\n") -> str:
    header = "\n".join(
        [
            "-- LF_MIGRATION_RECONCILIATION_SOURCE_V1",
            "-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY",
            f"-- owner_binding_required={owner_binding}",
            "-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF",
            "-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260930064736-20260930-001",
            "-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER",
            "-- source_authority=supabase_migrations.schema_migrations",
            f"-- source_version={VERSION}",
            f"-- source_name={NAME}",
        ]
    )
    return header + separator + payload


class MigrationSourceParityReconciliationEnvelopeV1Tests(unittest.TestCase):
    def test_valid_envelope_is_provenance_not_domain_sql(self):
        payload = "-- original migration comment\n\nselect 1;\n"
        source = reconciliation_source(payload)
        raw_source_sha = hashlib.sha256(subject.canonical(source)).hexdigest()
        payload_sha = transport.direct_source_hash(payload)
        self.assertNotEqual(raw_source_sha, payload_sha)

        local = {VERSION: (NAME, raw_source_sha, source)}
        remote = {VERSION: (NAME, payload_sha)}
        direct, cli, comparisons = subject.evaluate_managed_transport(
            local, remote, {VERSION: 1}
        )

        self.assertEqual((direct, cli), (1, 0))
        self.assertEqual(comparisons[VERSION].representation, "DIRECT_SOURCE")
        self.assertEqual(comparisons[VERSION].direct_sha256, payload_sha)

    def test_payload_drift_still_fails_closed(self):
        ledger_payload = "-- original migration comment\n\nselect 1;\n"
        changed_payload = "-- original migration comment\n\nselect 2;\n"
        source = reconciliation_source(changed_payload)
        local = {
            VERSION: (
                NAME,
                hashlib.sha256(subject.canonical(source)).hexdigest(),
                source,
            )
        }
        remote = {VERSION: (NAME, transport.direct_source_hash(ledger_payload))}

        with self.assertRaisesRegex(SystemExit, "FAIL_LF_MIGRATION_CONTENT_PARITY"):
            subject.evaluate_managed_transport(local, remote, {VERSION: 1})

    def test_invalid_envelope_is_never_stripped(self):
        payload = "select 1;\n"
        source = reconciliation_source(payload, owner_binding="false")
        self.assertFalse(
            subject.reconciliation_source_metadata(
                source, version=VERSION, name=NAME
            )
        )
        local = {
            VERSION: (
                NAME,
                hashlib.sha256(subject.canonical(source)).hexdigest(),
                source,
            )
        }
        remote = {VERSION: (NAME, transport.direct_source_hash(payload))}

        with self.assertRaisesRegex(SystemExit, "FAIL_LF_MIGRATION_CONTENT_PARITY"):
            subject.evaluate_managed_transport(local, remote, {VERSION: 1})

    def test_valid_metadata_without_envelope_separator_blocks(self):
        payload = "select 1;\n"
        source = reconciliation_source(payload, separator="\n")
        self.assertTrue(
            subject.reconciliation_source_metadata(
                source, version=VERSION, name=NAME
            )
        )
        local = {
            VERSION: (
                NAME,
                hashlib.sha256(subject.canonical(source)).hexdigest(),
                source,
            )
        }
        remote = {VERSION: (NAME, transport.direct_source_hash(payload))}

        with self.assertRaisesRegex(
            SystemExit, "FAIL_LF_MIGRATION_RECONCILIATION_ENVELOPE"
        ):
            subject.evaluate_managed_transport(local, remote, {VERSION: 1})


if __name__ == "__main__":
    unittest.main(verbosity=2)

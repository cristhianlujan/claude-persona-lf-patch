#!/usr/bin/env python3
from __future__ import annotations

import unittest

import lf_migration_transport_normalization_sandbox as subject


class TransportNormalizationTests(unittest.TestCase):
    def test_direct_source_representation(self):
        sql = "-- header\nselect 1;\n"
        remote = subject.direct_source_hash(sql)
        out = subject.compare_exact_source(
            version="20260907010101",
            source_name="lf_direct_v1",
            source_sql=sql,
            remote_name="lf_direct_v1",
            remote_sha256=remote,
            remote_statement_count=1,
        )
        self.assertEqual(out.representation, "DIRECT_SOURCE")

    def test_cli_single_statement_representation(self):
        sql = "-- header\n\nselect 1;\n"
        remote = subject.cli_statement_storage_hash(sql)
        self.assertNotEqual(remote, subject.direct_source_hash(sql))
        out = subject.compare_exact_source(
            version="20260907010102",
            source_name="lf_cli_single_v1",
            source_sql=sql,
            remote_name="lf_cli_single_v1",
            remote_sha256=remote,
            remote_statement_count=1,
        )
        self.assertEqual(out.representation, "CLI_STATEMENT_STORAGE")
        self.assertEqual(out.source_statement_count, 1)

    def test_cli_multi_statement_with_dollar_quote(self):
        sql = """-- header

do $body$
begin
  perform 1;
  perform 'literal;inside';
end;
$body$;

revoke all on function public.f() from public;
"""
        parts = subject.split_postgres_statements(sql)
        self.assertEqual(len(parts), 2)
        remote = subject.cli_statement_storage_hash(sql)
        out = subject.compare_exact_source(
            version="20260907010103",
            source_name="lf_cli_multi_v1",
            source_sql=sql,
            remote_name="lf_cli_multi_v1",
            remote_sha256=remote,
            remote_statement_count=2,
        )
        self.assertEqual(out.representation, "CLI_STATEMENT_STORAGE")
        self.assertEqual(out.source_statement_count, 2)

    def test_statement_boundary_collision_rejected_by_remote_count(self):
        valid = "select 1;\nselect 2;"
        missing_delimiter = "select 1\nselect 2;"
        remote = subject.cli_statement_storage_hash(valid)
        self.assertEqual(remote, subject.cli_statement_storage_hash(missing_delimiter))
        with self.assertRaisesRegex(subject.TransportNormalizationError, "CLI_STORAGE_STATEMENT_COUNT_MISMATCH"):
            subject.compare_exact_source(
                version="20260907010106",
                source_name="lf_boundary_v1",
                source_sql=missing_delimiter,
                remote_name="lf_boundary_v1",
                remote_sha256=remote,
                remote_statement_count=2,
            )

    def test_direct_hash_requires_single_ledger_statement(self):
        sql = "select 1;\nselect 2;"
        with self.assertRaisesRegex(subject.TransportNormalizationError, "DIRECT_STORAGE_STATEMENT_COUNT_MISMATCH"):
            subject.compare_exact_source(
                version="20260907010107",
                source_name="lf_direct_count_v1",
                source_sql=sql,
                remote_name="lf_direct_count_v1",
                remote_sha256=subject.direct_source_hash(sql),
                remote_statement_count=2,
            )

    def test_semicolon_in_standard_string_does_not_split(self):
        sql = "select 'a;b;c'::text;\nselect 2;"
        self.assertEqual(len(subject.split_postgres_statements(sql)), 2)

    def test_semicolon_in_e_string_does_not_split(self):
        sql = "select E'a\\\'b;c'::text;\nselect 2;"
        self.assertEqual(len(subject.split_postgres_statements(sql)), 2)

    def test_semicolon_in_comments_does_not_split(self):
        sql = "-- comment ; ignored\nselect 1 /* nested ; /* inner ; */ still */;\nselect 2;"
        self.assertEqual(len(subject.split_postgres_statements(sql)), 2)

    def test_quoted_identifier_semicolon_does_not_split(self):
        sql = 'select 1 as "a;b";\nselect 2;'
        self.assertEqual(len(subject.split_postgres_statements(sql)), 2)

    def test_name_mismatch_fails_closed(self):
        sql = "select 1;"
        with self.assertRaisesRegex(subject.TransportNormalizationError, "NAME_MISMATCH"):
            subject.compare_exact_source(
                version="20260907010104",
                source_name="lf_a",
                source_sql=sql,
                remote_name="lf_b",
                remote_sha256=subject.direct_source_hash(sql),
                remote_statement_count=1,
            )

    def test_content_mutation_fails_closed(self):
        source = "select 1;"
        remote = subject.direct_source_hash("select 2;")
        with self.assertRaisesRegex(subject.TransportNormalizationError, "CONTENT_MISMATCH"):
            subject.compare_exact_source(
                version="20260907010105",
                source_name="lf_mutation_v1",
                source_sql=source,
                remote_name="lf_mutation_v1",
                remote_sha256=remote,
                remote_statement_count=1,
            )

    def test_unterminated_dollar_quote_fails_closed(self):
        with self.assertRaisesRegex(subject.TransportNormalizationError, "UNTERMINATED_DOLLAR_QUOTE"):
            subject.split_postgres_statements("do $x$ begin perform 1; end;")

    def test_unterminated_block_comment_fails_closed(self):
        with self.assertRaisesRegex(subject.TransportNormalizationError, "UNTERMINATED_BLOCK_COMMENT"):
            subject.split_postgres_statements("select 1; /* open")

    def test_version_shape_fails_closed(self):
        with self.assertRaisesRegex(subject.TransportNormalizationError, "VERSION_INVALID"):
            subject.compare_exact_source(
                version="bad",
                source_name="lf_bad_v1",
                source_sql="select 1;",
                remote_name="lf_bad_v1",
                remote_sha256=subject.direct_source_hash("select 1;"),
                remote_statement_count=1,
            )

    def test_remote_statement_count_shape_fails_closed(self):
        with self.assertRaisesRegex(subject.TransportNormalizationError, "REMOTE_STATEMENT_COUNT_INVALID"):
            subject.compare_exact_source(
                version="20260907010108",
                source_name="lf_bad_count_v1",
                source_sql="select 1;",
                remote_name="lf_bad_count_v1",
                remote_sha256=subject.direct_source_hash("select 1;"),
                remote_statement_count=0,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)

"""Unit tests for fail-closed migration route classification."""
import os
import unittest
from unittest.mock import call, patch

import lf_migration_route_guard as guard
from lf_migration_route_guard import classify_files, should_publish_success


class MigrationRouteGuardTests(unittest.TestCase):
    def status(self, filename, status, previous_filename=None):
        row = {"filename": filename, "status": status}
        if previous_filename is not None:
            row["previous_filename"] = previous_filename
        return row

    def test_no_migrations_publishes_for_unchanged_head(self):
        self.assertEqual(
            should_publish_success(
                [{"filename": "README.md", "status": "modified"}],
                pagination_complete=True, expected_head="abc", observed_head="abc",
            )[0],
            True,
        )

    def test_added_migration_requires_train(self):
        self.assertTrue(classify_files([self.status("supabase/migrations/a.sql", "added")], pagination_complete=True).requires_train)

    def test_modified_migration_requires_train(self):
        self.assertTrue(classify_files([self.status("supabase/migrations/a.sql", "modified")], pagination_complete=True).requires_train)

    def test_removed_migration_requires_train(self):
        self.assertTrue(classify_files([self.status("supabase/migrations/a.sql", "removed")], pagination_complete=True).requires_train)

    def test_rename_out_of_migrations_requires_train(self):
        self.assertTrue(classify_files([self.status("archive/a.sql", "renamed", "supabase/migrations/a.sql")], pagination_complete=True).requires_train)

    def test_rename_into_migrations_requires_train(self):
        self.assertTrue(classify_files([self.status("supabase/migrations/a.sql", "renamed", "archive/a.sql")], pagination_complete=True).requires_train)

    def test_three_thousand_files_fails_closed(self):
        files = [{"filename": f"docs/{i}.md"} for i in range(3000)]
        self.assertTrue(classify_files(files, pagination_complete=True).requires_train)

    def test_incomplete_pagination_fails_closed(self):
        self.assertTrue(classify_files([{"filename": "README.md"}], pagination_complete=False).requires_train)

    def test_head_changed_during_verification_does_not_publish(self):
        self.assertFalse(should_publish_success(
            [{"filename": "README.md"}], pagination_complete=True,
            expected_head="abc", observed_head="def",
        )[0])

    def test_malformed_path_fails_closed(self):
        self.assertTrue(classify_files([{"status": "modified"}], pagination_complete=True).requires_train)

    def test_status_publication_failure_continues_and_returns_nonzero(self):
        pull_1 = {"state": "open", "base": {"ref": "main"}, "head": {"sha": "head-1"}}
        pull_2 = {"state": "open", "base": {"ref": "main"}, "head": {"sha": "head-2"}}
        with patch.dict(os.environ, {
            "GITHUB_REPOSITORY": "owner/repo",
            "GH_READ_TOKEN": "read-token",
            "APP_TOKEN": "app-token",
            "GITHUB_EVENT_PATH": "",
            "PR_NUMBER_INPUT": "1,2",
        }), patch.object(guard, "pull_files", return_value=([{"filename": "README.md"}], True)), \
            patch.object(guard, "write_summary") as summary, \
            patch.object(guard, "api_request", side_effect=[
                pull_1, pull_1, guard.ApiError("simulated status API failure"),
                pull_2, pull_2, {},
            ]) as api_request:
            result = guard.main()

        self.assertEqual(result, 1)
        self.assertEqual(api_request.call_count, 6)
        self.assertTrue(any("PR #1: status publication failed" in item.args[0] for item in summary.call_args_list))
        self.assertTrue(any("PR #2: SUCCESS" in item.args[0] for item in summary.call_args_list))
        self.assertTrue(any("failed PRs: #1" in item.args[0] for item in summary.call_args_list))


if __name__ == "__main__":
    unittest.main()

"""Pure state model for the GitHub status routing contract."""
import unittest

GUARD = "lf-migration-route-guard"
VERIFIED = "lf-merge-train/verified"

def guard_eligible(paths, head, statuses):
    if not any(path.startswith("supabase/migrations/") for path in paths):
        return True
    # Only trusted Train App's exact-head verified status may authorize a guard PASS.
    return any(s["context"] == VERIFIED and s["state"] == "success"
               and s["sha"] == head and s["issuer"] == "lf-migration-train-app"
               for s in statuses)

class MigrationRouteGuardTests(unittest.TestCase):
    def test_unrelated_pr_passes(self):
        self.assertTrue(guard_eligible(["docs/readme.md"], "abc", []))

    def test_migration_without_train_does_not_pass(self):
        self.assertFalse(guard_eligible(["supabase/migrations/x.sql"], "abc", []))

    def test_train_verified_exact_head_passes(self):
        self.assertTrue(guard_eligible(["supabase/migrations/x.sql"], "abc",
            [{"context":VERIFIED,"state":"success","sha":"abc","issuer":"lf-migration-train-app"}]))

    def test_old_head_does_not_pass(self):
        self.assertFalse(guard_eligible(["supabase/migrations/x.sql"], "abc",
            [{"context":VERIFIED,"state":"success","sha":"old","issuer":"lf-migration-train-app"}]))

    def test_untrusted_actor_does_not_pass(self):
        self.assertFalse(guard_eligible(["supabase/migrations/x.sql"], "abc",
            [{"context":VERIFIED,"state":"success","sha":"abc","issuer":"unknown"}]))

if __name__ == "__main__":
    unittest.main()

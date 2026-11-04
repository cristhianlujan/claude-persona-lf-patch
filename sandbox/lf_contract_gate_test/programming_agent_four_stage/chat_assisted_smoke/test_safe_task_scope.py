import unittest
from safe_task_scope import ScopeError, validate_allowed_change

ROOT = "sandbox/lf_contract_gate_test/programming_agent_four_stage/chat_assisted_smoke/"
def check(path):
    return validate_allowed_change(path, allowed_prefix=ROOT, protected=(ROOT + "locked.py",))

class ScopeSmokeTests(unittest.TestCase):
    def test_allows_owned_file(self):
        self.assertEqual(check(ROOT + "sample.py"), ROOT + "sample.py")
    def test_blocks_outside_scope(self):
        with self.assertRaisesRegex(ScopeError, "OUTSIDE_ALLOWED_SCOPE"):
            check("src/app/page.tsx")
    def test_blocks_protected_file(self):
        with self.assertRaisesRegex(ScopeError, "PROTECTED_PATH"):
            check(ROOT + "locked.py")
    def test_blocks_traversal(self):
        with self.assertRaisesRegex(ScopeError, "INVALID_PATH"):
            check(ROOT + "../outside.py")
    def test_blocks_absolute(self):
        with self.assertRaisesRegex(ScopeError, "INVALID_PATH"):
            check("/etc/passwd")
    def test_blocks_windows_separator(self):
        with self.assertRaisesRegex(ScopeError, "INVALID_PATH"):
            check(ROOT + "sub\\evil.py")
if __name__ == "__main__":
    unittest.main()

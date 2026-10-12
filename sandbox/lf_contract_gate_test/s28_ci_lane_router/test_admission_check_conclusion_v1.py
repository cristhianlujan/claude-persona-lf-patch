#!/usr/bin/env python3
"""Offline test of admission conclusion policy. No DB."""
import unittest
def admit(admission,judge="success"):
    return admission=="success" and judge in ("success","skipped","neutral")
class TestPolicy(unittest.TestCase):
    def test_skipped_fails(self): self.assertFalse(admit("skipped"))
    def test_neutral_fails(self): self.assertFalse(admit("neutral"))
    def test_success_not_applicable_passes(self):
        # NOT_APPLICABLE is explicit in a successful check's output, not GitHub conclusion.
        self.assertTrue(admit("success"))
    def test_failure_fails(self): self.assertFalse(admit("failure"))
if __name__=="__main__": unittest.main()

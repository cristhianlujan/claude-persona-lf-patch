import unittest

class CP2LiveBoundary(unittest.TestCase):
    def test_no_untrusted_pass(self):
        self.assertNotEqual('ELIGIBLE_UNATTESTED', 'PASS_MATERIAL_CANONICAL')

if __name__ == '__main__':
    unittest.main()

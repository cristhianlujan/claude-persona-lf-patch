import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).with_name("new_runs_vnext.py")
spec = importlib.util.spec_from_file_location("cp2_judge", path)
judge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(judge)

class StubReadback:
    def __init__(self, mode="ok"):
        self.mode = mode
        self.calls = 0
    def call(self, name, args=None):
        self.calls += 1
        if name.endswith("dispatch_context_v1"):
            return {"status":"AUTHORIZED_CONTEXT",
                    "dispatch_permitted":self.mode!="no_cutover",
                    "scope":{"schema_version":"M105_SCOPE_SNAPSHOT_V1",
                             "screen_ids":list(range(1,14))},
                    "release":{"version":"next","previous_version":"old",
                               "manifest_sha256":"a"*64}}
        screen = args["p_pantalla_id"]
        if self.mode=="missing": return []
        return [{"pantalla_id":screen,
                 "run_id":100 if self.mode=="duplicate" else 100+screen,
                 "cp2_verdict":"ERROR_TECNICO" if self.mode=="fail" else "PASS_CP2",
                 "technical_verdict":"ERROR_TECNICO" if self.mode=="fail" else "PASS_TECNICO"}]

class CP2LiveBoundary(unittest.TestCase):
    def test_full_cohort(self):
        self.assertEqual(judge.verify_live(StubReadback())["status"],"PASS_MATERIAL_CANONICAL")
    def test_unsigned_cutover(self):
        self.assertEqual(judge.verify_live(StubReadback("no_cutover"))["status"],
                         "BLOCK_SIGNED_CUTOVER_NOT_AUTHORIZED")
    def test_error(self):
        self.assertEqual(judge.verify_live(StubReadback("fail"))["status"],"FAIL_MATERIAL_CANONICAL")
    def test_duplicate(self):
        self.assertEqual(judge.verify_live(StubReadback("duplicate"))["status"],"BLOCK_RUN_IDENTITY")
    def test_missing(self):
        self.assertEqual(judge.verify_live(StubReadback("missing"))["status"],"BLOCK_READBACK_MISSING")
    def test_local_data_cannot_authorize(self):
        self.assertNotEqual(judge.classify({"schema_version":"IG_M105_CP2_RELEASE_READBACK_V2"}),
                            "PASS_MATERIAL_CANONICAL")

if __name__=="__main__":
    unittest.main()

"""C5 same-chat native review end-to-end at adapter boundary using TEST DOUBLES."""
import sys
import unittest
from pathlib import Path

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
sys.path.insert(0,str(HERE.parent / "validators"))
from test_profile_updater_native_material_bridge_v02 import fixture
from test_profile_updater_native_material_ledger_v02 import RID, ledger_row
from profile_updater_native_material_operational_v02 import verify_native_material_pre_admission
from profile_updater_native_material_bridge_v02 import MaterialBridgeBlocked


def make_bindings():
    handoff, capture, _, _ = fixture()
    row=ledger_row()
    row["subject_sha256"]=capture["raw_output_sha256"]
    row["receipt_payload"]["handoff_sha256"]=handoff["handoff_sha256"]
    row["receipt_payload"]["profile_slug"]=handoff["profile_slug"]
    row["receipt_payload"]["run_id"]=handoff["run_id"]
    read_source=lambda path: b'# Repair profile\nPreserve source evidence'
    def run(row_override=None):
        return verify_native_material_pre_admission(
            handoff=handoff,capture=capture,
            current_surface="CHATGPT_CURRENT_CONVERSATION",
            independent_review_receipt_id=RID,
            github_source_readback=read_source,
            supabase_read_one=lambda sql,parameters:
                row if row_override is None else row_override)
    return handoff,capture,row,run


class OperationalBindingTest(unittest.TestCase):
    def test_positive_bounded_candidate(self):
        _,_,_,run=make_bindings()
        result=run()
        self.assertEqual(result["status"],"NATIVE_MATERIAL_REVIEWED_PRE_ADMISSION")
        self.assertFalse(result["external_method_execution_certified"])
        self.assertFalse(result["canonical_steps_recorded"])
        self.assertFalse(result["production_activated"])

    def test_no_real_ledger_receipt_blocks(self):
        _,_,_,run=make_bindings()
        with self.assertRaisesRegex(MaterialBridgeBlocked,"INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED"):
            run(row_override={})

    def test_independent_subject_mismatch_blocks(self):
        _,_,row,run=make_bindings()
        row["subject_sha256"]="f"*64
        with self.assertRaisesRegex(MaterialBridgeBlocked,"INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED"):
            run()

    def test_review_wrong_run_binding_blocks(self):
        _,_,row,run=make_bindings()
        row["receipt_payload"]["handoff_sha256"]="f"*64
        with self.assertRaisesRegex(MaterialBridgeBlocked,"INDEPENDENT_MATERIAL_REVIEW_UNVERIFIED"):
            run()

if __name__=="__main__":
    unittest.main()

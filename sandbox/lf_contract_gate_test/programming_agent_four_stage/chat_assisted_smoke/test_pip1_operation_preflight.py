import unittest
from pip1_operation_preflight import compare_operation,PreflightError
from pip1_core.core import Pins,RunContract

def fixtures():
    pins=Pins("a"*40,"b"*64,"c"*64,"d"*64)
    run=RunContract("PIP-1","1","exec-synthetic","run-synthetic","chat","fixture",pins)
    op={"execution_id":run.execution_id,"operation_code":"CIERRE_CHECKPOINT_INGENIERIA_LF",
        "target_type":"ENGINEERING_CHECKPOINT","status":"CREATED",
        "manifest":{"pip1_run_id":run.run_id,"inventory_sha256":pins.inventory_sha256,"head_sha":pins.head_sha}}
    return run,op

class Tests(unittest.TestCase):
    def test_matches_but_no_authority(self):
        run,op=fixtures()
        r=compare_operation(run,op,observed_inventory_sha256=run.pins.inventory_sha256)
        self.assertTrue(r["identity_shape_matches"])
        self.assertFalse(r["checkpoint_accredited"])
        self.assertFalse(r["write_authorized"])
    def test_cross_run(self):
        run,op=fixtures();op["manifest"]["pip1_run_id"]="other"
        with self.assertRaisesRegex(PreflightError,"RUN_ID_UNBOUND"):
            compare_operation(run,op,observed_inventory_sha256=run.pins.inventory_sha256)
    def test_cross_execution(self):
        run,op=fixtures();op["execution_id"]="other"
        with self.assertRaisesRegex(PreflightError,"EXECUTION_MISMATCH"):
            compare_operation(run,op,observed_inventory_sha256=run.pins.inventory_sha256)
    def test_head_drift(self):
        run,op=fixtures();op["manifest"]["head_sha"]="f"*40
        with self.assertRaisesRegex(PreflightError,"HEAD_UNBOUND"):
            compare_operation(run,op,observed_inventory_sha256=run.pins.inventory_sha256)
    def test_inventory_drift(self):
        run,op=fixtures()
        with self.assertRaisesRegex(PreflightError,"INVENTORY_DRIFT"):
            compare_operation(run,op,observed_inventory_sha256="e"*64)
    def test_unrelated_operation(self):
        run,op=fixtures();op["operation_code"]="OTHER"
        with self.assertRaisesRegex(PreflightError,"OPERATION_CODE_NOT_COMPATIBLE"):
            compare_operation(run,op,observed_inventory_sha256=run.pins.inventory_sha256)
    def test_no_manifest(self):
        run,op=fixtures();op["manifest"]=None
        with self.assertRaisesRegex(PreflightError,"MANIFEST_NOT_OBJECT"):
            compare_operation(run,op,observed_inventory_sha256=run.pins.inventory_sha256)
if __name__=="__main__":unittest.main()

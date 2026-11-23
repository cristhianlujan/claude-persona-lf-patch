import unittest
from wait_after_image_v1 import wait_for_close

class Clock:
    def __init__(self):
        self.now = 0
        self.slept = []
    def monotonic(self):
        return self.now
    def sleep(self, seconds):
        self.slept.append(seconds)
        self.now += seconds

class TestWait(unittest.TestCase):
    def test_pending_then_closed_after_30_seconds(self):
        clock = Clock()
        samples = iter([
            {"order_status": "EN_PROCESO", "run_state": "EJECUTANDO"},
            {"order_status": "TERMINADO", "run_state": "EXITOSO", "qa_passed": True, "evidence_verified": True}
        ])
        out = wait_for_close(lambda: next(samples), sleep=clock.sleep, monotonic=clock.monotonic, timeout=90)
        self.assertEqual(out["status"], "TERMINADO_VERIFICADO")
        self.assertEqual(out["checks"], 2)
        self.assertEqual(clock.slept, [30])

    def test_timeout_is_not_success(self):
        clock = Clock()
        out = wait_for_close(lambda: {"order_status": "EN_PROCESO", "run_state": "EJECUTANDO"},
                             sleep=clock.sleep, monotonic=clock.monotonic, timeout=65)
        self.assertEqual(out["status"], "TIMEOUT_PENDIENTE")
        self.assertEqual(clock.slept, [30, 30, 5])

    def test_sql_done_without_evidence_is_not_success(self):
        out = wait_for_close(lambda: {"order_status": "TERMINADO", "run_state": "EXITOSO"})
        self.assertEqual(out["status"], "CIERRE_NO_VERIFICADO")

    def test_failed_run(self):
        out = wait_for_close(lambda: {"order_status": "EN_PROCESO", "run_state": "FALLIDO"})
        self.assertEqual(out["status"], "FALLO")

    def test_missing_readback(self):
        out = wait_for_close(lambda: None)
        self.assertEqual(out["status"], "READBACK_INVALID")

if __name__ == "__main__":
    unittest.main()

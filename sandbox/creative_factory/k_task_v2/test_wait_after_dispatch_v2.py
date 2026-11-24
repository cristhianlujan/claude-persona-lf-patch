"""Deterministic simulation of post-dispatch seven-check policy."""
import unittest
from wait_after_dispatch_v2 import wait_after_dispatch


class VirtualClock:
    def __init__(self):
        self.t = 0.0

    def now(self):
        return self.t

    def sleep(self, delta):
        if delta < 0:
            raise AssertionError("BACKWARDS_CLOCK")
        self.t += delta


class TestWait(unittest.TestCase):
    def scenario(self, ready_at):
        clock = VirtualClock()
        expirations = []

        def readback():
            return {"status": "READY" if ready_at is not None and clock.now() >= ready_at else "PENDING"}

        def expire():
            expirations.append(clock.now())
            return {"status": "EXPIRED_CLOSED", "state": "FALLIDO"}

        result = wait_after_dispatch(readback, expire, monotonic=clock.now, sleep=clock.sleep)
        return clock, expirations, result

    def test_ready_at_20_seconds(self):
        clock, expirations, out = self.scenario(20)
        self.assertEqual(out["status"], "READY")
        self.assertEqual(out["first_observed_ready_seconds"], 30)
        self.assertEqual(out["count"], 2)
        self.assertEqual(out["next_step"], "11")
        self.assertEqual(clock.t, 30)
        self.assertEqual(expirations, [])
        print("E20_INPUT=ready_at_20_seconds E20_OUTPUT=", out)

    def test_ready_at_100_seconds(self):
        clock, expirations, out = self.scenario(100)
        self.assertEqual(out["status"], "READY")
        self.assertEqual(out["first_observed_ready_seconds"], 120)
        self.assertEqual(out["count"], 5)
        self.assertEqual(clock.t, 120)
        self.assertEqual(expirations, [])
        print("E100_INPUT=ready_at_100_seconds E100_OUTPUT=", out)

    def test_never_ready(self):
        clock, expirations, out = self.scenario(None)
        self.assertEqual(out["status"], "ESPERA_AGOTADA")
        self.assertEqual(out["run_state"], "FALLIDO")
        self.assertTrue(out["run_expired"])
        self.assertEqual(out["count"], 7)
        self.assertEqual(expirations, [180])
        self.assertEqual(clock.t, 180)
        print("ENEVER_INPUT=never_ready ENEVER_OUTPUT=", out)

    def test_invalid_capture_is_error_not_ready(self):
        clock = VirtualClock()
        expired = []
        out = wait_after_dispatch(
            lambda: {"status": "ERROR", "reason": "IMAGE_EVIDENCE_INVALID"},
            lambda: expired.append(clock.now()),
            monotonic=clock.now, sleep=clock.sleep,
        )
        self.assertEqual(out["status"], "ERROR")
        self.assertEqual(out["count"], 1)
        self.assertEqual(out["elapsed_seconds"], 0)
        self.assertEqual(expired, [])
        print("E_INVALID_INPUT=invalid_capture E_INVALID_OUTPUT=", out)

    def test_expirer_refuses_without_deadline(self):
        clock = VirtualClock()
        out = wait_after_dispatch(lambda: {"status": "PENDING"},
                                  lambda: {"status": "NOT_EXPIRED", "changed": False},
                                  monotonic=clock.now, sleep=clock.sleep)
        self.assertEqual(out["status"], "EXPIRY_NOT_CONFIRMED")
        self.assertEqual(out["count"], 7)
        print("E_EXPIRY_GUARD_OUTPUT=", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)

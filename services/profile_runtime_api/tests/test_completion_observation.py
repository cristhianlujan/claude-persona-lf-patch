from __future__ import annotations
import threading
import unittest
from unittest.mock import patch
from profile_runtime_api.completion_observation import CompletionObservation

META={"kind":"execute","request_id":"test","request_sha256":"a"*64,"profiles":["PROFILE"],"input_literal":"must not leak"}

class CompletionObservationTest(unittest.TestCase):
    def test_disabled_has_no_thread(self):
        with patch("threading.Thread") as thread:
            self.assertEqual(CompletionObservation().submit("job",META),"DISABLED")
            thread.assert_not_called()

    def test_callback_receives_only_detached_metadata(self):
        done=threading.Event();seen=[]
        def callback(notice):seen.append(notice);notice["kind"]="changed";done.set()
        o=CompletionObservation(callback);self.assertEqual(o.submit("job",META),"DISPATCHED");self.assertTrue(done.wait(1))
        self.assertNotIn("input_literal",seen[0]);self.assertNotIn("result",seen[0]);self.assertEqual(META["kind"],"execute")
        self.assertEqual(seen[0]["profiles"],("PROFILE",))

    def test_slow_observers_do_not_queue_or_block(self):
        release=threading.Event();started=threading.Event()
        def callback(_):started.set();release.wait(2)
        o=CompletionObservation(callback)
        try:
            self.assertEqual(o.submit("one",META),"DISPATCHED");self.assertTrue(started.wait(1))
            self.assertEqual(o.submit("two",META),"DISPATCHED")
            self.assertEqual(o.submit("three",META),"SKIPPED_CAPACITY")
        finally:release.set();o.close()
        self.assertEqual(o.submit("four",META),"DISABLED")

    def test_callback_error_releases_capacity_and_does_not_escape(self):
        done=threading.Event()
        def callback(_):done.set();raise RuntimeError("secret")
        o=CompletionObservation(callback)
        with self.assertLogs("profile_runtime_api.completion_observation",level="WARNING") as logs:
            self.assertEqual(o.submit("job",META),"DISPATCHED");self.assertTrue(done.wait(1))
            # Join only in test, never in active path.
            for t in threading.enumerate():
                if t.name=="lf-completion-observation":t.join(1)
        self.assertNotIn("secret",str(logs.output));self.assertTrue(o._slots.acquire(blocking=False));o._slots.release()

    def test_start_failure_releases_slot(self):
        o=CompletionObservation(lambda _:None)
        with patch("threading.Thread.start",side_effect=RuntimeError("synthetic")):
            self.assertEqual(o.submit("job",META),"ERROR")
        self.assertTrue(o._slots.acquire(blocking=False));o._slots.release()

if __name__=="__main__":unittest.main()

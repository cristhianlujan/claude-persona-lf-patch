"""V12 fake-port contract tests. They do not render or change Supabase."""
from __future__ import annotations

import hashlib
import unittest

from sandbox.creative_factory.queue_v12.chat_generation_flow_v1 import (
    ChatFlowRejected, complete_chat_generation_v1, prepare_chat_generation_v1,
    select_pending_v1,
)

PNG = b"\x89PNG\r\n\x1a\n" + b"mock-synthetic-test-only-not-a-real-image-file"*2
PROMPT = "SALY · Render de revisión: pieza HOME sin modificar fuentes."
DIGEST = hashlib.sha256(PNG).hexdigest()
PROMPT_SHA = hashlib.sha256(PROMPT.encode()).hexdigest()


class Ports:
    def __init__(self):
        self.calls = []
        self.entries = [
            {"order_code":"SALY_HOME_BATCH_001","order_state":"PLANIFICADO",
             "item_id":5,"item_code":"HOME","item_state":"PENDIENTE","ordinal":1},
            {"order_code":"SALY_HOME_BATCH_001","order_state":"PLANIFICADO",
             "item_id":6,"item_code":"ADELANTO","item_state":"PENDIENTE","ordinal":2},
            {"order_code":"SALY_HOME_BATCH_001","order_state":"PLANIFICADO",
             "item_id":7,"item_code":"REWARDS","item_state":"PENDIENTE","ordinal":3},
            {"order_code":"SALY_HOME_TEMPLATE_AB_001","order_state":"PLANIFICADO",
             "item_id":8,"item_code":"HOME_A","item_state":"PENDIENTE","ordinal":1},
            {"order_code":"SALY_HOME_TEMPLATE_AB_001","order_state":"PLANIFICADO",
             "item_id":9,"item_code":"HOME_B","item_state":"PENDIENTE","ordinal":2},
        ]
        self.run={
            "run_id":31,"order_code":"SALY_HOME_BATCH_001","order_title":"Tres pantallas SALY",
            "item_id":5,"item_code":"HOME","item_title":"Home principal SALY",
            "item_state":"PRODUCIENDO","run_state":"EJECUTANDO","order_state":"EN_PROCESO",
            "prompt":PROMPT,"prompt_sha256":PROMPT_SHA,"worker_ref":"RENDER_AGENT",
        }
        self.qa = {"verdict":"PASS","comment":"CTA y copy contrastados con la referencia; revisión sintética.",
                   "reviewer_ref":"QA_INDEPENDIENTE"}
        self.saved = None
        self.final = None

    def pending(self, order_code):
        self.calls.append("pending")
        return self.entries

    def begin(self, order_code, item_id):
        self.calls.append("begin")
        if item_id!=5 or order_code!="SALY_HOME_BATCH_001":
            raise ValueError("Wrong scoped item")
        return {"status":"PROCESSING_STARTED","run_id":31}

    def processing(self, run_id):
        self.calls.append("processing")
        return self.run

    def review(self, data, state):
        self.calls.append("qa")
        assert data == PNG and state["run_id"]==31
        return self.qa

    def save(self, run_id, digest, verdict, comment, reviewer):
        self.calls.append("save")
        assert run_id==31 and digest==DIGEST
        self.saved = {"run_id":run_id,"artifact_sha256":digest,
                      "qa_verdict":verdict,"qa_comment":comment,
                      "qa_reviewer_ref":reviewer}
        return {"status":"QA_SAVED_AND_FINALIZED"}

    def read_final(self, run_id):
        self.calls.append("final_readback")
        assert self.saved
        return {**self.saved,"item_state":"APROBADO" if self.qa["verdict"]=="PASS" else "BLOQUEADO",
                "claim_state":"DONE" if self.qa["verdict"]=="PASS" else "BLOCKED",
                "order_state":"EN_PROCESO","comment_persisted":True}

    def prepare(self, **changes):
        kw={"order_code":"SALY_HOME_BATCH_001",
            "allowed_item_codes":["HOME","ADELANTO","REWARDS"],
            "pending_reader":self.pending,"begin_atomic":self.begin,
            "processing_readback":self.processing}
        kw.update(changes)
        return prepare_chat_generation_v1(**kw)

    def complete(self, **changes):
        kw={"run_id":31,"image_bytes":PNG,"processing_readback":self.processing,
            "qa_reviewer":self.review,"save_qa_and_finish_atomic":self.save,
            "final_readback":self.read_final}
        kw.update(changes)
        return complete_chat_generation_v1(**kw)


class TestChatGenerationV12(unittest.TestCase):
    def setUp(self):
        self.p=Ports()

    def expect(self, code, call):
        with self.assertRaises(ChatFlowRejected) as x:
            call()
        self.assertEqual(x.exception.code,code)

    def test_pending_only_exact_3_excludes_other_order(self):
        x=select_pending_v1(order_code="SALY_HOME_BATCH_001",
                            allowed_item_codes=["HOME","ADELANTO","REWARDS"],items=self.p.entries)
        self.assertEqual(x["selected_count"],3)
        self.assertEqual(x["next_item"],{"item_id":5,"item_code":"HOME"})

    def test_completed_and_processing_ignored(self):
        self.p.entries[0]["item_state"]="APROBADO"
        self.p.entries[1]["item_state"]="PRODUCIENDO"
        x=select_pending_v1(order_code="SALY_HOME_BATCH_001",
                            allowed_item_codes=["HOME","ADELANTO","REWARDS"],items=self.p.entries)
        self.assertEqual(x["selected_count"],1)
        self.assertEqual(x["next_item"]["item_code"],"REWARDS")

    def test_no_pending_returns_no_dispatch(self):
        for r in self.p.entries[:3]:r["item_state"]="APROBADO"
        o=self.p.prepare()
        self.assertEqual(o["status"],"NO_PENDING_IN_SCOPE")
        self.assertEqual(self.p.calls,["pending"])

    def test_scope_without_order_rejected(self):
        self.expect("SALY_CHAT_ORDER_SCOPE_REQUIRED",
                    lambda:self.p.prepare(order_code=""))
        self.assertNotIn("begin",self.p.calls)

    def test_scope_without_item_list_rejected(self):
        self.expect("SALY_CHAT_ITEM_SCOPE_REQUIRED",
                    lambda:self.p.prepare(allowed_item_codes=[]))
        self.assertNotIn("begin",self.p.calls)

    def test_duplicate_allowed_codes_rejected(self):
        self.expect("SALY_CHAT_ITEM_SCOPE_REQUIRED",
                    lambda:self.p.prepare(allowed_item_codes=["HOME","HOME"]))

    def test_duplicate_db_item_rejected(self):
        self.p.entries.insert(0,dict(self.p.entries[0]))
        self.expect("SALY_CHAT_SELECTION_DUPLICATED_OR_INVALID",lambda:self.p.prepare())
        self.assertNotIn("begin",self.p.calls)

    def test_stale_pending_artifact_blocks_before_generation(self):
        self.p.entries[0]["existing_artifact_linked"]=True
        self.expect("SALY_CHAT_STALE_PENDING_WITH_ARTIFACT",lambda:self.p.prepare())
        self.assertNotIn("begin",self.p.calls)

    def test_no_foreign_order_selected(self):
        self.p.entries[:]=self.p.entries[3:]
        o=self.p.prepare()
        self.assertEqual(o["status"],"NO_PENDING_IN_SCOPE")
        self.assertNotIn("begin",self.p.calls)

    def test_processed_order_not_eligible(self):
        self.p.entries[0]["order_state"]="COMPLETADO"
        self.expect("SALY_CHAT_ORDER_NOT_ACTIVE",lambda:self.p.prepare())
        self.assertNotIn("begin",self.p.calls)

    def test_begin_processing_precedes_chat_summary(self):
        x=self.p.prepare()
        self.assertEqual(self.p.calls,["pending","begin","processing"])
        self.assertEqual(x["status"],"EN_PROCESO_VERIFICADO_MOSTRAR_EN_CHAT")
        self.assertIn("SALY_HOME_BATCH_001",x["chat_message"])
        self.assertIn("HOME — Home principal SALY",x["chat_message"])
        self.assertEqual(x["native_prompt"],PROMPT)
        self.assertEqual(x["next_action"],"CALL_IMAGE_GEN_IN_CURRENT_CHAT")
        self.assertNotIn("claim_token",str(x))
        self.assertFalse(x["status_terminado"])

    def test_begin_unconfirmed_no_chat_dispatch(self):
        self.expect("SALY_CHAT_BEGIN_NOT_CONFIRMED",
                    lambda:self.p.prepare(begin_atomic=lambda *a:{"status":"FAIL"}))

    def test_begin_port_exception_no_dispatch(self):
        self.expect("SALY_CHAT_BEGIN_ATOMIC_FAILED",
                    lambda:self.p.prepare(begin_atomic=lambda *a:1/0))

    def test_processing_readback_failed_no_chat_dispatch(self):
        self.expect("SALY_CHAT_BEGIN_READBACK_FAILED",
                    lambda:self.p.prepare(processing_readback=lambda _:1/0))

    def test_processing_state_drift_no_chat_dispatch(self):
        self.p.run["item_state"]="PENDIENTE"
        self.expect("SALY_CHAT_PROCESSING_READBACK_MISMATCH",lambda:self.p.prepare())

    def test_prompt_source_hash_drift_rejected(self):
        self.p.run["prompt"]="alterado"
        self.expect("SALY_CHAT_PROCESSING_READBACK_MISMATCH",lambda:self.p.prepare())

    def test_missing_begin_port_rejected(self):
        self.expect("SALY_CHAT_TRUSTED_DB_OR_QA_PORT_MISSING",
                    lambda:self.p.prepare(begin_atomic=None))

    def test_complete_after_tool_result_and_qa_comment_persisted(self):
        o=self.p.complete()
        self.assertEqual(self.p.calls,["processing","qa","save","final_readback"])
        self.assertEqual(o["status"],"TERMINADO")
        self.assertEqual(o["db_item_state"],"APROBADO")
        self.assertEqual(o["db_claim_state"],"DONE")
        self.assertTrue(o["qa_comment_saved"])
        self.assertEqual(o["image_sha256"],DIGEST)
        self.assertFalse(o["may_regenerate_without_new_request"])

    def test_cannot_complete_if_image_not_returned(self):
        self.expect("SALY_CHAT_GENERATION_NOT_FINISHED_OR_NOT_PNG",
                    lambda:self.p.complete(image_bytes=b""))
        self.assertEqual(self.p.calls,[])

    def test_cannot_complete_non_png(self):
        self.expect("SALY_CHAT_GENERATION_NOT_FINISHED_OR_NOT_PNG",
                    lambda:self.p.complete(image_bytes=b"not-a-png"*8))

    def test_cannot_complete_wrong_run_state(self):
        self.p.run["run_state"]="EN_COLA"
        self.expect("SALY_CHAT_RUN_NOT_PROCESSING",lambda:self.p.complete())
        self.assertNotIn("qa",self.p.calls)

    def test_qa_independent_identity_required(self):
        self.p.qa["reviewer_ref"]="RENDER_AGENT"
        self.expect("SALY_CHAT_QA_EVIDENCE_INVALID",lambda:self.p.complete())
        self.assertNotIn("save",self.p.calls)

    def test_qa_comment_required(self):
        self.p.qa["comment"]=""
        self.expect("SALY_CHAT_QA_EVIDENCE_INVALID",lambda:self.p.complete())
        self.assertNotIn("save",self.p.calls)

    def test_invalid_qa_verdict(self):
        self.p.qa["verdict"]="UNKNOWN"
        self.expect("SALY_CHAT_QA_EVIDENCE_INVALID",lambda:self.p.complete())
        self.assertNotIn("save",self.p.calls)

    def test_qa_failure_blocks_not_terminado(self):
        self.p.qa["verdict"]="FAIL"
        self.p.qa["comment"]="Falla de copy en imagen; requiere nueva instrucción gobernada."
        o=self.p.complete()
        self.assertEqual(o["status"],"BLOQUEADO_QA")
        self.assertEqual(o["db_item_state"],"BLOQUEADO")
        self.assertEqual(o["db_claim_state"],"BLOCKED")

    def test_qa_reader_error_blocks(self):
        self.expect("SALY_CHAT_QA_FAILED",
                    lambda:self.p.complete(qa_reviewer=lambda *a:1/0))
        self.assertNotIn("save",self.p.calls)

    def test_qa_save_error_blocks_terminal(self):
        self.expect("SALY_CHAT_QA_SAVE_OR_TERMINAL_FAILED",
                    lambda:self.p.complete(save_qa_and_finish_atomic=lambda *a:1/0))
        self.assertNotIn("final_readback",self.p.calls)

    def test_recording_unconfirmed_blocks(self):
        self.expect("SALY_CHAT_QA_SAVE_NOT_CONFIRMED",
                    lambda:self.p.complete(save_qa_and_finish_atomic=lambda *a:{"status":"PENDING"}))

    def test_stale_final_readback_blocks_terminado(self):
        self.expect("SALY_CHAT_FINAL_READBACK_MISMATCH",
                    lambda:self.p.complete(final_readback=lambda _:{"item_state":"APROBADO"}))

    def test_missing_persisted_comment_blocks_terminado(self):
        def forged(run):
            v=self.p.read_final(run)
            v["comment_persisted"]=False
            return v
        self.expect("SALY_CHAT_FINAL_READBACK_MISMATCH",
                    lambda:self.p.complete(final_readback=forged))

    def test_changed_artifact_sha_blocks_terminado(self):
        def forged(run):
            v=self.p.read_final(run)
            v["artifact_sha256"]="0"*64
            return v
        self.expect("SALY_CHAT_FINAL_READBACK_MISMATCH",
                    lambda:self.p.complete(final_readback=forged))

    def test_no_fake_polling_fields(self):
        out=self.p.prepare()
        for field in ("poll_interval_seconds","host_native","next_run_time","provider_receipt"):
            self.assertNotIn(field,out)


if __name__ == "__main__":
    unittest.main(verbosity=2)

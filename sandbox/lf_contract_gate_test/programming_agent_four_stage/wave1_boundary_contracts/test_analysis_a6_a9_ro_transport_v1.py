from __future__ import annotations
import copy
import threading
import unittest
from unittest.mock import Mock, patch
from analysis_a6_a9_ro_transport_v1 import A6A9CompletionObserver, CompletionBinding, PsycopgReadOne, OPTIONS, PROFILE
from analysis_a6_a9_readonly_caller_v1 import ExpectedContext, READ_SQL

EXPECTED = ExpectedContext("PROGRAMMING_AGENT", "subject://test", "2026-10-24T00:00:00Z", "11111111-1111-4111-8111-111111111111", "a"*64)
CONNECTION = dict(host="db.example.invalid", dbname="postgres", user="approved-ro-test", password="not-a-real-secret")

class TransportTest(unittest.TestCase):
    def transport(self, packet=None):
        cursor = Mock()
        cursor.fetchone.return_value = (packet or {"resolution": {"state": "UNKNOWN"}, "transaction_read_only": True},)
        conn = Mock()
        conn.cursor.return_value.__enter__ = Mock(return_value=cursor)
        conn.cursor.return_value.__exit__ = Mock(return_value=False)
        connect = Mock(return_value=conn)
        return PsycopgReadOne(connection=CONNECTION, connect=connect), connect, conn, cursor

    def test_fixed_parameterized_read_rollback_close(self):
        t,connect,conn,cursor=self.transport()
        params=(EXPECTED.consumer_code,EXPECTED.subject_ref,EXPECTED.as_of)
        packet=t(READ_SQL,params)
        self.assertTrue(packet["transaction_read_only"])
        self.assertEqual(cursor.execute.call_args_list[0].args,("BEGIN READ ONLY",))
        self.assertEqual(cursor.execute.call_args_list[1].args,(READ_SQL,params))
        conn.rollback.assert_called_once();conn.close.assert_called_once()
        opts=connect.call_args.kwargs
        self.assertEqual(opts["options"],OPTIONS);self.assertEqual(opts["connect_timeout"],2)
        self.assertEqual(opts["sslmode"],"verify-full"); self.assertTrue(opts["autocommit"])

    def test_arbitrary_sql_never_connects(self):
        t,c,_,_=self.transport()
        with self.assertRaises(ValueError):t("DELETE FROM context",())
        c.assert_not_called()

    def test_read_error_preserved_and_cleanup(self):
        t,_,conn,cursor=self.transport(); error=RuntimeError("synthetic")
        cursor.execute.side_effect=[None,error]
        with self.assertRaises(RuntimeError) as got:t(READ_SQL,("a","b","c"))
        self.assertIs(got.exception,error);conn.rollback.assert_called_once();conn.close.assert_called_once()

    def test_non_ro_rejected(self):
        t,_,conn,_=self.transport({"transaction_read_only":False})
        with self.assertRaisesRegex(ValueError,"RO_TRANSACTION"):t(READ_SQL,("a","b","c"))
        conn.close.assert_called_once()

    def test_connect_error_no_retry(self):
        connect=Mock(side_effect=TimeoutError("synthetic"));t=PsycopgReadOne(connection=CONNECTION,connect=connect)
        with self.assertRaises(TimeoutError):t(READ_SQL,("a","b","c"))
        connect.assert_called_once()

    def test_invalid_config_and_environment_fallback_rejected(self):
        for connection in ({},dict(CONNECTION,options="unsafe"),dict(CONNECTION,sslmode="disable"),dict(CONNECTION,port=True),dict(CONNECTION,password="")):
            with self.subTest(connection=tuple(connection)):
                with self.assertRaises(ValueError):PsycopgReadOne(connection=connection)

    def test_close_even_if_rollback_fails(self):
        t,_,conn,_=self.transport();conn.rollback.side_effect=RuntimeError("synthetic")
        with self.assertRaises(RuntimeError):t(READ_SQL,("a","b","c"))
        conn.close.assert_called_once()

class BindingTest(unittest.TestCase):
    def setUp(self):
        self.read=Mock(return_value={"resolution":{"schema_version":"LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1","state":"UNKNOWN"},"transaction_read_only":True})
        self.binding=CompletionBinding("test-request","b"*64,"execute",EXPECTED)
        self.notice={"request_id":"test-request","request_sha256":"b"*64,"kind":"execute","profiles":(PROFILE,)}

    def observer(self,**kw):return A6A9CompletionObserver(self.read,bindings=(self.binding,),**kw)

    def test_disabled_never_reads(self):
        o=self.observer();o(self.notice);self.read.assert_not_called();self.assertEqual(o.diagnostics(),[])

    def test_exact_binding_queries_once_original_notice_unchanged(self):
        o=self.observer(enabled=True);before=copy.deepcopy(self.notice);o(self.notice)
        self.read.assert_called_once_with(READ_SQL,(EXPECTED.consumer_code,EXPECTED.subject_ref,EXPECTED.as_of))
        self.assertEqual(before,self.notice);self.assertEqual(o.diagnostics()[0]["state"],"SKIPPED_NO_CONTEXT")
        self.assertFalse(o.diagnostics()[0]["operational_admission"])

    def test_unbound_or_changed_request_never_reads(self):
        for key,value in [("kind","batch"),("request_id","other"),("request_sha256","c"*64),("profiles",("OTHER",))]:
            o=self.observer(enabled=True);o(dict(self.notice,**{key:value}));self.assertEqual(o.diagnostics()[0]["state"],"SKIPPED_BINDING")
        self.read.assert_not_called()

    def test_transport_failure_is_sanitized_advisory(self):
        self.read.side_effect=TimeoutError("secret-uri-do-not-emit")
        o=self.observer(enabled=True);o(self.notice)
        self.assertEqual(o.diagnostics()[0]["state"],"ERROR");self.assertNotIn("secret",str(o.diagnostics()))

    def test_bounded_isolated_diagnostics(self):
        o=self.observer(enabled=True)
        for _ in range(70):o({})
        d=o.diagnostics();self.assertEqual(len(d),64);d[0]["state"]="changed"
        self.assertEqual(o.diagnostics()[0]["state"],"SKIPPED_BINDING")

    def test_config_is_explicit_disabled_and_strict(self):
        config={"schema_version":"A6_A9_COMPLETION_SHADOW_CONFIGURATION_V1","enabled":False,"bindings":[]}
        o=A6A9CompletionObserver.from_config(config,self.read);o(self.notice);self.read.assert_not_called()
        for changed in (dict(config,enabled="false"),dict(config,credential="forbidden"),dict(config,bindings=[{}])):
            with self.assertRaises(ValueError):A6A9CompletionObserver.from_config(changed,self.read)

    def test_config_binds_exact_expected_identity(self):
        from dataclasses import asdict
        config={"schema_version":"A6_A9_COMPLETION_SHADOW_CONFIGURATION_V1","enabled":True,
                "bindings":[{"request_id":"test-request","request_sha256":"b"*64,"kind":"execute","expected":asdict(EXPECTED)}]}
        o=A6A9CompletionObserver.from_config(config,self.read);o(self.notice);self.read.assert_called_once()
        config["bindings"][0]["expected"]["context_sha256"]="c"*64
        self.assertEqual(o._bindings[("execute","test-request")].expected.context_sha256,"a"*64)

    def test_duplicate_or_invalid_binding_rejected(self):
        with self.assertRaises(ValueError):A6A9CompletionObserver(self.read,bindings=(self.binding,self.binding))
        with self.assertRaises(ValueError):self.observer(enabled="true")
        with self.assertRaises(ValueError):A6A9CompletionObserver(self.read,bindings=(CompletionBinding("test","bad","execute",EXPECTED),))

if __name__=="__main__":unittest.main()

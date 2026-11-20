#!/usr/bin/env python3
"""Policy19 ACT-0001 + official writer, PG17.6/18.7 isolated integration.
Every positive effect rolled back. Never invokes Supabase live.
"""
import json
import unittest
from test_policy19_act0001_scope_real_pgdual_v1 import _ScopeLab, POLICY_RUN, ROOT, quote

MIGRATIONS=list((ROOT/"supabase/migrations").glob("*_lf_b2b_policy19_otp_brevo_profiles12_v1.sql"))
if len(MIGRATIONS)!=1:
    raise RuntimeError("LF_POLICY19_MIGRATION_SOURCE_AMBIGUOUS")
SOURCE=MIGRATIONS[0].read_text(encoding="utf-8")
SOURCE_SHA="f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07"
DESCRIPTION_SHA="0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b"
KEYS=["admin_minimum_strength","admin_phishing_resistant_requirement",
      "phishing_resistant_option_required","admin_primary_method","admin_identity_provider",
      "admin_sso_protocol","admin_provider_configuration_status","factor_selection_status"]
ROW_SHA=("SELECT encode(sha256(convert_to(to_jsonb(p)::text,'UTF8')),'hex') "
         "FROM lf_ops.politicas_seguridad p WHERE security_policy_id=19;")
RECEIPT_COUNT=("SELECT count(*) FROM public.lf_router_scope_receipt_v1 WHERE execution_id="
               +quote(POLICY_RUN)+";")

class _GovernedLab(_ScopeLab):
    def test_01_governed_effect_receipt_and_full_rollback(self):
        self.assertEqual(self.sql(ROW_SHA),SOURCE_SHA)
        self.assertEqual(self.sql(RECEIPT_COUNT),"0")
        arr="ARRAY["+(",".join("'"+k+"'" for k in KEYS))+"]"
        inspect=("SELECT jsonb_build_object("
           "'status',p.status,"
           "'description_sha',encode(sha256(convert_to(p.description,'UTF8')),'hex'),"
           "'scope_receipts',(SELECT count(*) FROM public.lf_router_scope_receipt_v1 r "
              "WHERE r.execution_id="+quote(POLICY_RUN)+"),"
           "'scope_sha',(SELECT receipt_sha256 FROM public.lf_router_scope_receipt_v1 r "
              "WHERE r.execution_id="+quote(POLICY_RUN)+"),"
           "'scope_code',(SELECT scope_code FROM public.lf_router_scope_receipt_v1 r "
              "WHERE r.execution_id="+quote(POLICY_RUN)+"),"
           "'keys',(SELECT jsonb_object_agg(k,p.policy_config->k) FROM unnest("+arr+") AS k),"
           "'provenance_count',(SELECT count(*) FROM unnest("+arr+") AS k WHERE p.parameter_provenance?k),"
           "'identity_unverified',(SELECT bool_and(p.parameter_provenance->k->>'identity_verified'='false') FROM unnest("+arr+") AS k),"
           "'profiles',p.policy_config->'admin_profile_ids',"
           "'provenance_valid',programacion.fn_input_parameter_provenance_valid_v1(p.parameter_provenance)"
           ")::text FROM lf_ops.politicas_seguridad p WHERE p.security_policy_id=19;")
        output=self.sql("BEGIN;\n"+SOURCE+"\n"+inspect+"\nROLLBACK;\n"+ROW_SHA).splitlines()
        self.assertGreaterEqual(len(output),2,output)
        data=json.loads(output[-2])
        self.assertEqual(output[-1],SOURCE_SHA)
        self.assertEqual(data["status"],"CANDIDATO")
        self.assertEqual(data["description_sha"],DESCRIPTION_SHA)
        self.assertEqual(data["scope_receipts"],1)
        self.assertEqual(len(data["scope_sha"]),64)
        self.assertEqual(data["scope_code"],"LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1")
        self.assertEqual(data["provenance_count"],8)
        self.assertTrue(data["identity_unverified"])
        self.assertTrue(data["provenance_valid"])
        self.assertEqual(data["profiles"],[1,2])
        self.assertEqual(data["keys"]["admin_primary_method"],"USERNAME_PASSWORD_SERVER_VALIDATED")
        self.assertEqual(data["keys"]["factor_selection_status"],"OWNER_DECIDED_IN_CONVERSATION_PENDING_SIGNATURE_IMPLEMENTATION")
        self.assertEqual(self.sql(RECEIPT_COUNT),"0")
        self.assertEqual(self.sql(ROW_SHA),SOURCE_SHA)
        print("PASS_POLICY19_GOVERNED_SCOPE_WRITER_8_PROVENANCE_ROLLBACK_"+self.IMAGE,flush=True)

    def test_02_wrong_train_pr_fails_closed(self):
        script=("BEGIN; UPDATE public.lf_operation_execution SET manifest=jsonb_set("
           "manifest,'{pr}','\"NOT_3819\"'::jsonb) WHERE execution_id="+quote(POLICY_RUN)+";\n"+SOURCE)
        self.sql(script,error="LF_POLICY19_TRAIN_RUN_NOT_UNIQUE")
        self.assertEqual(self.sql(RECEIPT_COUNT),"0")
        self.assertEqual(self.sql(ROW_SHA),SOURCE_SHA)

    def test_03_forged_router_origin_fails_closed(self):
        script=("BEGIN; UPDATE public.lf_operation_execution SET manifest=jsonb_set("
           "manifest,'{router_authority_receipt,router}','\"FAKE\"'::jsonb)"
           " WHERE execution_id="+quote(POLICY_RUN)+";\n"+SOURCE)
        self.sql(script,error="LF_POLICY19_SCOPE_ROUTER_ORIGIN_NOT_GOVERNED")
        self.assertEqual(self.sql(RECEIPT_COUNT),"0")
        self.assertEqual(self.sql(ROW_SHA),SOURCE_SHA)

    def test_04_policy_preimage_drift_fails_closed(self):
        script=("BEGIN; UPDATE lf_ops.politicas_seguridad SET description='DRIFT' "
                "WHERE security_policy_id=19;\n"+SOURCE)
        self.sql(script,error="LF_POLICY19_SOURCE_PREIMAGE_DRIFT")
        self.assertEqual(self.sql(RECEIPT_COUNT),"0")
        self.assertEqual(self.sql(ROW_SHA),SOURCE_SHA)

class TestGovernedPG176(_GovernedLab,unittest.TestCase):
    IMAGE="postgres:17.6"
    VERSION="170006"

class TestGovernedPG187(_GovernedLab,unittest.TestCase):
    IMAGE="postgres:18.7"
    VERSION="180007"

#!/usr/bin/env python3
"""B08 G04 isolated real SQL writer test; no live Supabase connection.
All positives including APROBAR end in ROLLBACK. Fixtures are not real RUNs.
"""
import hashlib
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid
from datetime import datetime, timezone
from test_ig_rule_lifecycle_pg18 import SLICE, MIGRATION, jq, quote

RULE = "LF-B08-G04-LAB-001"
PARENT = "EXEC-PROFILE-GATE2-B08-G04-LAB-001"
SELF_PARENT = "EXEC-PROFILE-GATE2-B08-G04-SELF-002"
SCREEN = "LF-B08-G04-LAB-SCREEN"

class _B08Lab:
    @classmethod
    def sql(cls, sql, error=None, timeout=300):
        p = subprocess.run(["docker","exec","-i",cls.container,"psql",
            "-X","-q","-A","-t","-v","ON_ERROR_STOP=1",
            "-U","postgres","-d","postgres"],input=sql,text=True,
            capture_output=True,timeout=timeout)
        if error:
            m = re.search(r"ERROR:\s*([A-Z][A-Z0-9_]+)",p.stderr)
            if p.returncode == 0 or m is None or m.group(1) != error:
                raise AssertionError("B08_NEGATIVE_WRONG_ERROR expected="+error+
                    " found="+str(m.group(1) if m else None)+" "+p.stderr[-1200:])
            return p.stderr
        if p.returncode: raise AssertionError("B08_SQL_FAILED "+p.stderr[-1900:])
        return p.stdout.strip()

    @classmethod
    def setUpClass(cls):
        if not shutil.which("docker"): raise AssertionError("B08_DOCKER_REQUIRED")
        if not SLICE.exists() or not MIGRATION.exists():
            raise AssertionError("B08_CANONICAL_SOURCE_MISSING")
        cls.container = "lf-b08-g04-"+uuid.uuid4().hex[:10]
        p = subprocess.run(["docker","run","-d","--rm","--name",cls.container,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",
            cls.IMAGE],capture_output=True,text=True,timeout=240)
        if p.returncode: raise AssertionError("B08_DOCKER_START "+p.stderr[-700:])
        try:
            for _ in range(60):
                r=subprocess.run(["docker","exec",cls.container,"pg_isready",
                    "-U","postgres","-d","postgres"],capture_output=True,
                    text=True,timeout=10)
                if r.returncode==0: break
                time.sleep(1)
            else: raise AssertionError("B08_PG_NOT_READY")
            version=int(cls.sql("SHOW server_version_num;"))
            if version!=cls.VERSION:
                raise AssertionError("B08_VERSION_MISMATCH "+str(version))
            print("PASS_B08_PG_EXACT_VERSION="+str(version),flush=True)
            cls.sql(SLICE.read_text(encoding="utf-8"),timeout=350)
            train_id="43379990001"
            code="20261113030000_lf_ig_rule_lifecycle_writer_v2"
            repo="cristhianlujan/claude-persona-lf-patch"
            path="supabase/migrations/"+code+".sql"
            run="EXEC-DB-TRAIN-PR3803-20261113030000-R"+train_id
            manifest={"producer":"lf-migration-merge-train","pr":3803,
                "train_run_id":train_id,"head_sha":"e"*40,
                "router_authority_receipt":{
                    "schema_version":"LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1",
                    "operation_code":"ACTUALIZACION_DB_LF",
                    "target_repo":repo,"target_code":code,"target_path":path,
                    "route_eligibility_only":True,"scope_attested":False}}
            cls.sql("INSERT INTO public.lf_operation_execution("
                "execution_id,operation_code,target_type,target_code,target_repo,"
                "target_path,status,request_sha256,manifest,idempotency_key,"
                "created_by_execution_id) VALUES("
                +quote(run)+",'ACTUALIZACION_DB_LF','MIGRATION',"
                +quote(code)+","+quote(repo)+","+quote(path)+",'IN_PROGRESS',"
                +quote("f"*64)+","+jq(manifest)+","
                +quote("train:20261113030000:"+"e"*40)+","
                +quote("LF-MIGRATION-TRAIN-RUN-"+train_id)+");")
            src=MIGRATION.read_text(encoding="utf-8")
            if src.count("\nBEGIN;\n")!=1 or src.count("\nCOMMIT;")!=1:
                raise AssertionError("B08_MIGRATION_SOURCE_WRAPPERS_DRIFT")
            cls.sql(src,timeout=350)
            cls.sql("INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado) "
                    "VALUES(999981,"+quote(SCREEN)+",'B08 lab','ACTIVA');")
            cls.patch={"rule_code":RULE,"change_kind":"CREATE","changes":{
                "categoria":"B08_TEST","titulo":"Decisión G04 de laboratorio",
                "descripcion":"Prueba G04 PostgreSQL rollback",
                "razon":"Cobertura temporal G04",
                "es_transversal":False,"valor_config":{},
                "origen":"PG_SANDBOX_ONLY"}}
            cls.seed_parent(PARENT,"product_director_lf")
            cls.seed_parent(SELF_PARENT,"Cristhian Luján")
            cls.preimage=cls.sql("SELECT encode(extensions.digest(convert_to("
                "'LF_RULE_ABSENT:'||"+quote(RULE)+",'UTF8'),'sha256'),'hex');")
            cls.proposal=cls.sql("SELECT encode(extensions.digest(convert_to("
                "(evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}')::text,"
                "'UTF8'),'sha256'),'hex') FROM public.lf_operation_execution_steps "
                "WHERE execution_id="+quote(PARENT)+" AND step_id='execute_profile';")
            if len(cls.preimage)!=64 or len(cls.proposal)!=64:
                raise AssertionError("B08_HASH_SETUP_INVALID")
            cls.assert_empty()
            print("PASS_B08_CANONICAL_WRITER_MIGRATION_SOURCE_SHA256="+
                hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),flush=True)
        except BaseException:
            subprocess.run(["docker","rm","-f",cls.container],capture_output=True,timeout=40)
            raise

    @classmethod
    def tearDownClass(cls):
        if getattr(cls,"container",None):
            subprocess.run(["docker","rm","-f",cls.container],capture_output=True,timeout=40)

    @classmethod
    def seed_parent(cls,run,proposer):
        manifest={"read_only":True,"no_write":True,"no_promotion":True,
            "router_profile_handoff":{"router_authorization_receipt":
                {"profile_execution_allowed":True}},
            "screen_selection_result":{"selected_screen_code":SCREEN}}
        output={"worker":"product_director_lf",
            "output_type":"PRODUCT_DIRECTION_SPEC","self_verdict":"PASS",
            "deliverable_created":{"authority_status":"SUPPORTED",
                "governed_rule_patch":cls.patch,
                "product_decision":{"decision_id":"DEC-B08-LAB",
                    "proposed_by":proposer,
                    "source_refs":[{"authority":"AUTHORITATIVE","current":True,
                        "source_ref":"fixture://b08-g04"}]}}}
        sql="INSERT INTO public.lf_operation_execution("
        sql+="execution_id,operation_code,target_type,target_code,manifest,"
        sql+="request_sha256,idempotency_key,created_by_execution_id) VALUES("
        sql+=quote(run)+",'EJECUCION_PERFIL_LF','PERFIL',"
        sql+="'PERFIL-PRODUCT-DIRECTOR-LF',"+jq(manifest)+","
        sql+=quote("b"*64)+","+quote("g04-"+run)+","+quote(run)+");"
        for step,order,payload in [
            ("input_validate",40,{"status":"READY"}),
            ("execute_profile",60,{"profile_output":output}),
            ("output_validate",65,{"output_contract_result":"PASS"}),
            ("semantic_judge",70,{"semantic_judge_result":
                {"verdict":"PASS_INDEPENDENT_SEMANTIC"},"blocking_codes":[]})]:
            sql+="INSERT INTO public.lf_operation_execution_steps("
            sql+="execution_id,step_order,step_id,status,evidence_payload,"
            sql+="created_by_execution_id) VALUES("+quote(run)+","
            sql+=str(order)+","+quote(step)+",'STEP_PASS_WITH_EVIDENCE',"
            sql+=jq(payload)+","+quote(run)+");"
        cls.sql(sql)

    @classmethod
    def record(cls,verdict="RECHAZAR",**override):
        rec={"codigo_regla":RULE,"propuesta_sha256":cls.proposal,
            "veredicto":verdict,"decisor":"Cristhian Luján",
            "fecha":datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "frase_literal":"Decisión documental íntegra B08 G04 de laboratorio"}
        rec.update(override)
        return rec

    @classmethod
    def call(cls,rec,parent=PARENT,sha=None):
        return "SELECT public.lf_ig_rule_owner_decide_v2("+quote(parent)+","
        +quote(RULE)+","+quote(sha if sha is not None else cls.preimage)+","
        +jq(rec)+")::text;"

    @classmethod
    def counts(cls):
        return tuple(map(int,cls.sql(
            "SELECT (SELECT count(*) FROM public.lf_ig_owner_decision_v2),"
            "(SELECT count(*) FROM lf_ops.reglas WHERE codigo="+quote(RULE)+"),"
            "(SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE rule_code="
            +quote(RULE)+"),"
            "(SELECT count(*) FROM public.lf_ig_rule_change_v2 "
            "WHERE rule_code="+quote(RULE)+");").split("|")))

    @classmethod
    def assert_empty(cls):
        if cls.counts()!=(0,0,0,0):
            raise AssertionError("B08_ROWS_PERSISTED "+str(cls.counts()))

    @classmethod
    def readback(cls):
        return ("SELECT jsonb_build_object("
            "'id',d.decision_id,'project',d.project_code,"
            "'decisor',d.decisor,'proponente',d.proponente,"
            "'owner_bound',(d.owner_sub=o.owner_sub),"
            "'date',d.decision_date,'phrase',d.literal_phrase,"
            "'record',d.decision_record,'record_sha',d.decision_record_sha256,"
            "'computed_sha',encode(extensions.digest(convert_to("
            "d.decision_record::text,'UTF8'),'sha256'),'hex'),"
            "'record_fields',(SELECT count(*) FROM jsonb_object_keys(d.decision_record)),"
            "'identity_mode',d.identity_mode,'parent',d.parent_execution_id,"
            "'parent_operation',p.operation_code,'parent_status',p.status,"
            "'rule',d.rule_code,'kind',d.kind,"
            "'source_sha',d.source_sha256,'proposal_sha',d.proposal_sha256,"
            "'verdict',d.verdict,'patch',d.approved_patch,"
            "'rule_status',(SELECT estado FROM lf_ops.reglas WHERE codigo="
            +quote(RULE)+"),'promotions',(SELECT count(*) "
            "FROM public.lf_rule_promotion_v1 WHERE rule_code="+quote(RULE)+"),"
            "'change_state',(SELECT state FROM public.lf_ig_rule_change_v2 "
            "WHERE parent_execution_id="+quote(PARENT)+" LIMIT 1),"
            "'child_steps',(SELECT count(*) FROM public.lf_operation_execution_steps "
            "WHERE status='PASS_CLEAN' AND execution_id=("
            "SELECT child_execution_id FROM public.lf_ig_rule_change_v2 "
            "WHERE parent_execution_id="+quote(PARENT)+" LIMIT 1)))::text "
            "FROM public.lf_ig_owner_decision_v2 d "
            "JOIN public.lf_ig_project_owner_v2 o ON "
            "o.project_code=d.project_code AND o.owner_name=d.decisor "
            "JOIN public.lf_operation_execution p ON p.execution_id=d.parent_execution_id "
            "WHERE d.parent_execution_id="+quote(PARENT)+";")

    def positive(self,verdict):
        self.assert_empty()
        rec=self.record(verdict)
        result=self.sql("BEGIN; SET LOCAL ROLE service_role;"+self.call(rec)
            +"RESET ROLE;"+self.readback()+"ROLLBACK;",timeout=240)
        lines=[x for x in result.splitlines() if x.startswith("{")]
        self.assertEqual(len(lines),2,result[-1000:])
        ans,db=map(json.loads,lines)
        self.assertEqual(set(rec),{"codigo_regla","propuesta_sha256","veredicto",
            "decisor","fecha","frase_literal"})
        self.assertEqual(ans["identity_verified"],False)
        self.assertEqual(db["identity_mode"],"UNVERIFIED_CHAT_DECLARATION")
        self.assertEqual(db["record_fields"],6)
        self.assertEqual(db["record"],rec)
        self.assertEqual(ans["decision_record"],rec)
        self.assertEqual(db["record_sha"],db["computed_sha"])
        self.assertEqual(db["record_sha"],ans["decision_record_sha256"])
        self.assertEqual(db["source_sha"],self.preimage)
        self.assertEqual(db["proposal_sha"],self.proposal)
        self.assertEqual(db["project"],"LF")
        self.assertEqual(db["decisor"],"Cristhian Luján")
        self.assertEqual(db["proponente"],"product_director_lf")
        self.assertTrue(db["owner_bound"])
        self.assertEqual(db["parent"],PARENT)
        self.assertEqual(db["parent_operation"],"EJECUCION_PERFIL_LF")
        self.assertEqual(db["parent_status"],"IN_PROGRESS")
        self.assertEqual(db["rule"],RULE)
        self.assertEqual(db["kind"],"CREATE")
        self.assertEqual(db["phrase"],rec["frase_literal"])
        self.assertEqual(db["patch"],self.patch)
        self.assertEqual(db["verdict"],verdict)
        self.assertEqual(db["id"],ans["decision_id"])
        if verdict=="RECHAZAR":
            self.assertEqual(ans["status"],"RECHAZADO")
            self.assertIs(ans["write_performed"],False)
            self.assertIsNone(db["rule_status"])
            self.assertEqual(db["promotions"],0)
        else:
            self.assertEqual(ans["status"],"APPROVED_AND_VIGENTE_VERIFIED")
            self.assertEqual(ans["identity_mode"],"UNVERIFIED_CHAT_DECLARATION")
            self.assertEqual(db["rule_status"],"VIGENTE")
            self.assertEqual(db["promotions"],1)
            self.assertEqual(db["change_state"],"VIGENTE_VERIFIED")
            self.assertEqual(db["child_steps"],7)
            self.assertTrue(ans["child_execution_id"])
        self.assert_empty()
        print("PASS_B08_G04_COMPLETE_"+verdict+
            "_SIX_FIELDS_SHA_RECORD_SOURCE_PROPOSAL_IDENTITY_FALSE_MODE_UNVERIFIED"
            "_REGISTER_READBACK_ROLLBACK",flush=True)

    def negative(self,label,error,rec=None,parent=PARENT,sha=None,duplicate=False):
        self.assert_empty()
        rec=rec if rec is not None else self.record()
        sql="BEGIN; SET LOCAL ROLE service_role;"
        if duplicate: sql+=self.call(rec,parent,sha)
        sql+=self.call(rec,parent,sha)+"COMMIT;"
        stderr=self.sql(sql,error=error)
        self.assertIn(error,stderr)
        self.assert_empty()
        print("PASS_B08_G04_NEGATIVE_"+label+"_"+error+
            "_ZERO_NEW_ROWS",flush=True)

    def test_01_documentary_rechazar(self):
        self.positive("RECHAZAR")

    def test_02_documentary_aprobar_rollback(self):
        self.positive("APROBAR")

    def test_11_wrong_decisor(self):
        self.negative("WRONG_DECISOR","LF_IG_OWNER_DECISION_INPUT_INVALID",
            self.record(decisor="UNAUTHORIZED_DECISOR"))

    def test_12_self_approval(self):
        self.negative("SELF_APPROVAL","LF_IG_OWNER_SELF_APPROVAL_FORBIDDEN",
            parent=SELF_PARENT)

    def test_13_stale_source(self):
        self.negative("STALE_SHA","LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT",sha="0"*64)

    def test_14_duplicate(self):
        self.negative("DUPLICATE","LF_IG_OWNER_DECISION_ALREADY_RECORDED_NO_OVERRIDE",
            duplicate=True)

    def test_15_date_invalid(self):
        self.negative("INVALID_DATE","LF_IG_OWNER_DECISION_DATE_INVALID",
            self.record(fecha="not-ISO"))

    def test_16_forged_identity_verified(self):
        self.negative("IDENTITY_TRUE","LF_IG_OWNER_DECISION_RECORD_REQUIRED",
            self.record(identity_verified=True))

    def test_17_date_outside_parent(self):
        self.negative("DATE_OUT_OF_SCOPE","LF_IG_OWNER_DECISION_DATE_OUT_OF_SCOPE",
            self.record(fecha="2020-01-01T00:00:00Z"))


class TestB08PG176(_B08Lab,unittest.TestCase):
    IMAGE="postgres:17.6"
    VERSION=170006

class TestB08PG187(_B08Lab,unittest.TestCase):
    IMAGE="postgres:18.7"
    VERSION=180007

if __name__=="__main__":
    unittest.main()

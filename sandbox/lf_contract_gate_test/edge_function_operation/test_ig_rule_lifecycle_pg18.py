#!/usr/bin/env python3
"""PG18 transactional integration on live-object schema slice. NO Supabase credentials.
Unlike JS planners, this actually executes the current SQL functions and candidate
migration against isolated PostgreSQL 18. It does NOT prove signed external JWT,
native-model independent judge, full 11-step Router→Perfil or live migration.
"""
from __future__ import annotations
import json
import hashlib
from datetime import datetime, timezone
import os
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SLICE = ROOT / "sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_live_object_slice_baseline.sql"
MIGRATION = ROOT / "supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql"
OWNER = "00000000-0000-4000-8000-000000000111"
PARENT = "EXEC-PROFILE-GATE2-IGPG18CREATE0001"
PARENT2 = "EXEC-PROFILE-GATE2-IGPG18UPDATE0002"
RULE = "LF-IG-PG18-TEST-001"
SHA = "a" * 64

def jq(v):
    return "'" + json.dumps(v,ensure_ascii=False,separators=(',',':')).replace("'","''") + "'::jsonb"

def quote(v):
    return "'" + str(v).replace("'","''") + "'"

def fail_assert(cond, why):
    if not cond: raise AssertionError(why)

class PG18RealSQL(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fail_assert(shutil.which("docker") is not None, "PG18_REQUIRED_DOCKER_MISSING")
        fail_assert(SLICE.is_file() and MIGRATION.is_file(), "PG18_REQUIRED_SOURCE_MISSING")
        cls.docker = "lf-ig-pg18-" + uuid.uuid4().hex[:10]
        image = os.environ.get("LF_PG18_IMAGE","postgres:18")
        if image != "postgres:18": raise AssertionError("PG18_IMAGE_MUST_BE_POSTGRES_18")
        r=subprocess.run(["docker","run","-d","--rm","--name",cls.docker,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            text=True,capture_output=True,timeout=240)
        fail_assert(r.returncode==0,"PG18_DOCKER_RUN_FAILED "+r.stderr[-3000:])
        for _ in range(45):
            v=subprocess.run(["docker","exec",cls.docker,"pg_isready","-U","postgres","-d","postgres"],
                text=True,capture_output=True,timeout=10)
            if v.returncode==0: break
            time.sleep(2)
        else: raise AssertionError("PG18_DOCKER_NOT_READY")
        version=cls.sql("SHOW server_version_num;").strip()
        print("REAL_PG_VERSION="+version,flush=True)
        fail_assert(int(version)>=180000 and int(version)<190000,"NOT_PG18")
        cls.sql(SLICE.read_text("utf-8"),timeout=350)
        print("PASS_PG18_LIVE_SCHEMA_SLICE_LOADED",flush=True)
        cls.sql(MIGRATION.read_text("utf-8"),timeout=240)
        print("PASS_PG18_EXACT_MIGRATION_APPLIED",flush=True)

    @classmethod
    def tearDownClass(cls):
        if getattr(cls,"docker",None):
            subprocess.run(["docker","rm","-f",cls.docker],
                           text=True,capture_output=True,timeout=30)

    @classmethod
    def sql(cls,s,timeout=90,expect_fail=None):
        p=subprocess.run(["docker","exec","-i",cls.docker,"psql","-X","-q","-A","-t",
            "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
            input=s,text=True,capture_output=True,timeout=timeout)
        if expect_fail:
            fail_assert(p.returncode!=0 and expect_fail in p.stderr,
                        "NEGATIVE_DID_NOT_BLOCK:"+expect_fail+"\n"+p.stdout+"\n"+p.stderr[-1400:])
            return p.stderr
        if p.returncode!=0:
            raise AssertionError("PG18_SQL_FAILURE:\n"+p.stderr[-3500:]+"\nQUERY="+s[:1000])
        return p.stdout.strip()

    @classmethod
    def parent(cls,parent,patch,request="b"*64,proposed_by="product_director_lf"):
        # Isolated parent provenance fixture. These four prerequisite evidence
        # rows are NOT a real native model or judge invocation.
        data={"worker":"product_director_lf","output_type":"PRODUCT_DIRECTION_SPEC",
            "self_verdict":"PASS","deliverable_created":{"authority_status":"SUPPORTED","governed_rule_patch":patch,
              "product_decision":{"decision_id":"DEC-IGPG18","proposed_by":proposed_by,"source_refs":[
                {"authority":"AUTHORITATIVE","current":True,"source_ref":"fixture://pg18"}]}}}
        manifest={"read_only":True,"no_write":True,"no_promotion":True,
          "router_profile_handoff":{"router_authorization_receipt":{"profile_execution_allowed":True}},
          "screen_selection_result":{"selected_screen_code":"LF-PG18-SCREEN"}}
        base=f"""INSERT INTO public.lf_operation_execution(
        execution_id,operation_code,target_type,target_code,manifest,request_sha256,
        idempotency_key,created_by_execution_id)
        VALUES({quote(parent)},'EJECUCION_PERFIL_LF','PERFIL',
        'PERFIL-PRODUCT-DIRECTOR-LF',{jq(manifest)},{quote(request)},
        {quote('ig-pg18-parent:'+parent)},{quote(parent)});"""
        rows=[
          ("input_validate",40,{"status":"READY"}),
          ("execute_profile",60,{"profile_output":data}),
          ("output_validate",65,{"output_contract_result":"PASS"}),
          ("semantic_judge",70,{"semantic_judge_result":{"verdict":"PASS_INDEPENDENT_SEMANTIC"},"blocking_codes":[]})
        ]
        for sid,order,evidence in rows:
            base+=f"""INSERT INTO public.lf_operation_execution_steps(
             execution_id,step_order,step_id,status,evidence_payload,created_by_execution_id)
             VALUES({quote(parent)},{order},{quote(sid)},'STEP_PASS_WITH_EVIDENCE',{jq(evidence)},{quote(parent)});"""
        cls.sql(base)

    @classmethod
    def proposal_sha(cls,parent):
        return cls.sql("""SELECT encode(extensions.digest(convert_to(
          (evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}')::text,
          'UTF8'),'sha256'),'hex')
          FROM public.lf_operation_execution_steps
          WHERE execution_id="""+quote(parent)+""" AND step_id='execute_profile';""")

    @classmethod
    def rule_record(cls,parent,rule=RULE,verdict="APROBAR",**override):
        stamp=datetime.now(timezone.utc).replace(microsecond=0).isoformat()
        sha=cls.proposal_sha(parent)
        data={"codigo_regla":rule,"propuesta_sha256":sha,"veredicto":verdict,
          "decisor":"Cristhian Luján","fecha":stamp,
          "frase_literal":f"{verdict} regla {rule}; decisión documental temporal."}
        data.update(override)
        return data

    @classmethod
    def owner_decide(cls,parent,preimage,verdict="APROBAR",rule=RULE,record=None,expect_fail=None):
        payload=record if record is not None else cls.rule_record(parent,rule,verdict)
        return cls.sql(f"""BEGIN;
         SET LOCAL ROLE service_role;
         SELECT public.lf_ig_rule_owner_decide_v2(
          {quote(parent)},{quote(rule)},{quote(preimage)},{jq(payload)})::text;
         COMMIT;""",expect_fail=expect_fail)

    @classmethod
    def asset_record(cls,asset,preimage,**override):
        data={"codigo_activo":asset,"preimagen_sha256":preimage,"veredicto":"APROBAR",
          "decisor":"Cristhian Luján",
          "fecha":datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
          "frase_literal":f"APROBAR backfill de owner para {asset} en base temporal."}
        data.update(override)
        return data

    @classmethod
    def invoke(cls,parent,skill,patch,preimage,owner_decision):
        inp={"regla_codigo":RULE,"analysis_snapshot_sha256":preimage,"decision_id":"DEC-IGPG18",
          "candidate_patch":patch,"owner_decision_id":owner_decision}
        return json.loads(cls.sql(f"SELECT public.lf_skill_invoke_v1({quote(skill)},{quote(parent)},{jq(inp)})::text;"))

    def test_integrated_create_vigente_asset(self):
        # Temporary owner declaration is seeded by the migration, without Auth.
        self.assertEqual(self.sql("""SELECT count(*) FROM public.lf_ig_project_owner_v2
          WHERE project_code='LF' AND owner_name='Cristhian Luján'
          AND status='TEMP_DOCUMENTARY_ACTIVE';"""),"1")
        self.assertEqual(self.sql("""SELECT count(*) FROM public.lf_ig_project_owner_v2
          WHERE project_code='SALY';"""),"0")
        self.sql("""INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado)
          VALUES(999991,'LF-PG18-SCREEN','PG18 isolated screen','ACTIVA');""")
        patch={"rule_code":RULE,"change_kind":"CREATE","changes":{
          "categoria":"TEST","titulo":"Regla PG18 creada","descripcion":"Alta governada prueba PostgreSQL 18",
          "razon":"Prueba PG18 integrada","es_transversal":False,"valor_config":{},"origen":"PG18_ONLY"}}
        pre=self.sql("SELECT encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||"+quote(RULE)+",'UTF8'),'sha256'),'hex');")
        self.parent(PARENT,patch)
        # A fake receipt must not create a candidate or invoke the official writer.
        fake=self.invoke(PARENT,"RULE_CREATE_APPLY",patch,pre,
                         "00000000-0000-4000-8000-000000000999")
        fail_assert(fake["status"]=="BLOCKED","FAKE_APPROVAL_CREATED_CHILD "+str(fake))
        fail_assert(self.sql("SELECT count(*) FROM lf_ops.reglas WHERE codigo="+quote(RULE)+";")=="0",
                    "FAKE_APPROVAL_WROTE_RULE")
        # Record missing; false identity, wrong proposal SHA, absent phrase.
        self.owner_decide(PARENT,pre,record={},
          expect_fail="LF_IG_OWNER_DECISION_RECORD_REQUIRED")
        self.owner_decide(PARENT,pre,
          record=self.rule_record(PARENT,propuesta_sha256="0"*64),
          expect_fail="LF_IG_OWNER_PROPOSAL_SHA256_MISMATCH")
        self.owner_decide(PARENT,pre,
          record=self.rule_record(PARENT,decisor="OTRO DECISOR"),
          expect_fail="LF_IG_OWNER_DECISION_INPUT_INVALID")
        self.owner_decide(PARENT,pre,
          record=self.rule_record(PARENT,frase_literal=""),
          expect_fail="LF_IG_OWNER_DECISION_INPUT_INVALID")
        self.owner_decide(PARENT,"0"*64,
          expect_fail="LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT")
        fail_assert(self.sql("SELECT count(*) FROM public.lf_ig_owner_decision_v2 WHERE rule_code="+quote(RULE)+";")=="0",
          "NEGATIVES_PERSISTED_OWNER_APPROVAL")
        d=json.loads(self.owner_decide(PARENT,pre).splitlines()[-1])
        fail_assert(d["status"]=="APPROVED_AND_VIGENTE_VERIFIED" and d.get("child_execution_id"),
                    "OWNER_AUTO_CREATE_PROMOTE_FAILED "+str(d))
        approval=self.sql("SELECT decision_record::text FROM public.lf_ig_owner_decision_v2 WHERE decision_id="+quote(d["decision_id"])+"::uuid;")
        fail_assert(json.loads(approval)==d["decision_record"],"OWNER_DECISION_LITERAL_READBACK_MISMATCH")
        sha=self.sql("SELECT decision_record_sha256 FROM public.lf_ig_owner_decision_v2 WHERE decision_id="+quote(d["decision_id"])+"::uuid;")
        fail_assert(sha==d["decision_record_sha256"] and len(sha)==64,"OWNER_DECISION_SHA_READBACK_MISMATCH")
        # The official vinculation would have run independently. For PG18
        # bind the synthetic rule to the synthetic screen before testing replay.
        self.sql(f"INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id) SELECT id,999991 FROM lf_ops.reglas WHERE codigo={quote(RULE)};")
        # Negative replay after promotion: exact old preimage cannot be reused.
        self.owner_decide(PARENT,pre,expect_fail="LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT")
        cid=d["child_execution_id"]
        row=self.sql(f"""SELECT estado||'|'||pendiente_decision::text FROM lf_ops.reglas WHERE codigo={quote(RULE)};""")
        fail_assert(row=="VIGENTE|false","AUTO_CHAIN_NOT_VIGENTE "+row)
        cnt=self.sql("SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id="+quote(cid)+" AND status='PASS_CLEAN';")
        fail_assert(cnt=="7","CREATE_NOT_7_STEPS "+cnt)
        replay=self.invoke(PARENT,"RULE_CREATE_APPLY",patch,pre,d["decision_id"])
        fail_assert(replay.get("replay")==True,"CREATE_REPLAY_NOT_IDEMPOTENT "+str(replay))
        final=json.loads(self.sql(f"SELECT public.lf_ig_rule_finalize_v2({quote(cid)})::text;"))
        fail_assert(final["status"]=="VIGENTE_VERIFIED","CREATE_PROMOTION_FAIL "+str(final))
        row=self.sql(f"SELECT estado||'|'||pendiente_decision::text FROM lf_ops.reglas WHERE codigo={quote(RULE)};")
        fail_assert(row=="VIGENTE|false","CREATE_NOT_VIGENTE "+row)
        promoc=self.sql("SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE status='APPLIED' AND rule_code="+quote(RULE)+";")
        fail_assert(promoc=="1","PROMOTION_RECEIPT_MISSING")
        pre2=self.sql(f"SELECT public.lf_asset_snapshot_sha_v1('REGLA',{quote(RULE)});")
        patch2={"rule_code":RULE,"change_kind":"DOCUMENTARY_ONLY",
          "changes":{"descripcion":"Corrección aprobada y validada PG18."}}
        self.parent(PARENT2,patch2)
        d2=json.loads(self.owner_decide(PARENT2,pre2).splitlines()[-1])
        fail_assert(d2.get("status")=="APPROVED_AND_VIGENTE_VERIFIED" and
                    d2.get("child_execution_id"),"VIGENTE_OWNER_AUTO_CHAIN_FAIL "+str(d2))
        staged=self.sql("SELECT count(*) FROM public.lf_ig_rule_change_v2 WHERE child_execution_id="+
                         quote(d2['child_execution_id'])+" AND kind='CORRECT_VIGENTE' AND state='VIGENTE_VERIFIED';")
        fail_assert(staged=="1","VIGENTE_STAGE_OR_FINALIZE_NOT_RECORDED")
        fin=json.loads(self.sql(f"SELECT public.lf_ig_rule_finalize_v2({quote(d2['child_execution_id'])})::text;"))
        fail_assert(fin["status"]=="VIGENTE_VERIFIED" and fin.get("replay")==True,
                    "VIGENTE_FINALIZE_REPLAY_FAIL "+str(fin))
        desc=self.sql(f"SELECT descripcion FROM lf_ops.reglas WHERE codigo={quote(RULE)};")
        fail_assert(desc=="Corrección aprobada y validada PG18.","VIGENTE_PATCH_NOT_APPLIED")
        n_promos=self.sql("SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE rule_code="+quote(RULE)+" AND status='APPLIED';")
        fail_assert(n_promos=="1","VIGENTE_CORRECTION_FORGED_PROMOTION_RECEIPT")
        # Functional security mutation is intentionally fail-closed without an
        # independently authenticated impact/QA receipt. PostgreSQL must roll
        # back the owner decision, child and mutable rule atomically.
        parent3="EXEC-PROFILE-GATE2-IGPG18FUNCT0003"
        sha_before=self.sql(f"SELECT public.lf_asset_snapshot_sha_v1('REGLA',{quote(RULE)});")
        badpatch={"rule_code":RULE,"change_kind":"FUNCTIONAL",
                  "changes":{"valor_config":{"deny_by_default":False}}}
        self.parent(parent3,badpatch)
        self.sql(f"""BEGIN; SET LOCAL ROLE authenticated;
          SET LOCAL request.jwt.claim.sub={quote(OWNER)};
          SET LOCAL request.jwt.claim.role='authenticated';
          SET LOCAL request.jwt.claims={quote(json.dumps({'sub':OWNER,'aal':'aal2','role':'authenticated'}))};
          SELECT public.lf_ig_rule_owner_decide_v2({quote(parent3)},{quote(RULE)},
            {quote(sha_before)},'APPROVE'); ROLLBACK;""",
          expect_fail="LF_IG_VIGENTE_FUNCTIONAL_IMPACT_RECEIPT_MISSING")
        sha_after=self.sql(f"SELECT public.lf_asset_snapshot_sha_v1('REGLA',{quote(RULE)});")
        fail_assert(sha_after==sha_before,"FUNCTIONAL_NEGATIVE_MUTATED_ACTIVE_RULE")
        pending=self.sql("SELECT count(*) FROM public.lf_ig_owner_decision_v2 WHERE parent_execution_id="+quote(parent3)+";")
        fail_assert(pending=="0","FAILED_FUNCTIONAL_APPROVAL_PERSISTED")
        # Existing CANDIDATO regression: V2 invokes the original candidate-only
        # official writer (does not silently replace legacy semantics).
        cand="LF-IG-PG18-TEST-CANDIDATE"
        candparent="EXEC-PROFILE-GATE2-IGPG18CAND0004"
        self.sql(f"""INSERT INTO lf_ops.reglas(
            codigo,categoria,titulo,descripcion,estado,pendiente_decision,es_transversal,
            created_by) VALUES({quote(cand)},'TEST','Candidata PG18',
            'Regla candidata antes de modificar','CANDIDATO',true,false,
            {quote(candparent)});
          INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
            SELECT id,999991 FROM lf_ops.reglas WHERE codigo={quote(cand)};""")
        candsha=self.sql("SELECT public.lf_asset_snapshot_sha_v1('REGLA',"+quote(cand)+");")
        candpatch={"rule_code":cand,"change_kind":"DOCUMENTARY_ONLY",
          "changes":{"descripcion":"Candidata corregida por escritor oficial PG18."}}
        self.parent(candparent,candpatch)
        cand_result=json.loads(self.owner_decide(candparent,candsha,rule=cand).splitlines()[-1])
        fail_assert(cand_result.get("status")=="APPROVED_AND_VIGENTE_VERIFIED",
                    "CANDIDATO_LEGACY_WRITER_REGRESSION "+str(cand_result))
        candrow=self.sql(f"SELECT estado||'|'||descripcion FROM lf_ops.reglas WHERE codigo={quote(cand)};")
        fail_assert(candrow=="VIGENTE|Candidata corregida por escritor oficial PG18.",
                    "CANDIDATO_WRITER_POSTSTATE_FAILED "+candrow)
        candpromo=self.sql("SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE rule_code="+quote(cand)+" AND status='APPLIED';")
        fail_assert(candpromo=="1","CANDIDATO_PROMOTION_NOT_APPLIED")
        print("PASS_PG18_CANDIDATO_EXISTING_WRITER_REGRESSION",flush=True)
        # Rejection is recorded as a human decision but never starts a child.
        reject_code="LF-IG-PG18-TEST-REJECT"
        reject_parent="EXEC-PROFILE-GATE2-IGPG18REJECT005"
        reject_patch={"rule_code":reject_code,"change_kind":"CREATE",
          "changes":{"categoria":"TEST","titulo":"Rechazo PG18",
            "descripcion":"Regla rechazada sin escritura PG18",
            "es_transversal":False}}
        reject_sha=self.sql("SELECT encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||"+
            quote(reject_code)+",'UTF8'),'sha256'),'hex');")
        self.parent(reject_parent,reject_patch)
        denied=json.loads(self.owner_decide(reject_parent,reject_sha,verdict="REJECT",rule=reject_code).splitlines()[-1])
        fail_assert(denied.get("status")=="REJECT" and denied.get("write_performed") is False,
                    "OWNER_REJECT_WRITE_FLOW_WRONG "+str(denied))
        fail_assert(self.sql("SELECT count(*) FROM lf_ops.reglas WHERE codigo="+quote(reject_code)+";")=="0",
                    "REJECT_CREATED_RULE")
        print("PASS_PG18_OWNER_REJECT_NO_CHILD_NO_RULE",flush=True)
        print("PASS_PG18_FUNCTIONAL_CHANGE_ROLLBACK_AND_NO_FALSE_PROMOTION",flush=True)
        print("PASS_PG18_SQL_RULE_CREATE_PROMOTE_VIGENTE_CORRECT",flush=True)

        # Asset-owner backfill authority on a disposable ACTUALIZACION_DB_LF RUN.
        train="EXEC-IG-PG18-TRAIN-0001"
        asset="LF-IG-PG18-ACTIVO"
        self.sql(f"""INSERT INTO public.lf_operation_execution(
            execution_id,operation_code,target_type,target_code,request_sha256,
            idempotency_key,created_by_execution_id)
          VALUES({quote(train)},'ACTUALIZACION_DB_LF','DB','lf_activos',
            {quote('c'*64)},{quote('ig-pg18-train:'+train)},{quote(train)});
          INSERT INTO public.lf_operation_execution_steps(
            execution_id,step_order,step_id,status,evidence_payload,created_by_execution_id)
          VALUES({quote(train)},10,'preflight','PASS_CLEAN',
            '{{"source":"PG18_SANDBOX_ONLY"}}'::jsonb,{quote(train)});
          INSERT INTO public.lf_activos(
            id,codigo_activo,nombre_canonico,tipo_activo,estado_documental,estado_operativo,
            owner_name,source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,
            source_row_number,migration_batch_id,created_by_execution_id)
          VALUES(999999,{quote(asset)},'PG18 test asset','CAPABILITY','CANDIDATO',
            'READ_ONLY','OLD_OWNER','PG18_ONLY','PG18_ONLY','PG18_ONLY',1,
            '00000000-0000-4000-8000-000000000991'::uuid,{quote(train)});""")
        assetsha=self.sql(f"""SELECT encode(extensions.digest(
            convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex')
            FROM public.lf_activos a WHERE codigo_activo={quote(asset)};""")
        # A fake preimage cannot gain a backfill receipt.
        self.sql(f"""BEGIN; SET LOCAL ROLE authenticated;
          SET LOCAL request.jwt.claim.sub={quote(OWNER)};
          SET LOCAL request.jwt.claim.role='authenticated';
          SET LOCAL request.jwt.claims={quote(json.dumps({'sub':OWNER,'aal':'aal2','role':'authenticated'}))};
          SELECT public.lf_ig_asset_owner_approve_v2({quote(train)},{quote(asset)},
            {quote('0'*64)},'LF_OWNER_PG18'); ROLLBACK;""",
          expect_fail="LF_IG_ASSET_PREIMAGE_STALE")
        signed=self.sql(f"""BEGIN; SET LOCAL ROLE authenticated;
          SET LOCAL request.jwt.claim.sub={quote(OWNER)};
          SET LOCAL request.jwt.claim.role='authenticated';
          SET LOCAL request.jwt.claims={quote(json.dumps({'sub':OWNER,'aal':'aal2','role':'authenticated'}))};
          SELECT public.lf_ig_asset_owner_approve_v2({quote(train)},{quote(asset)},
            {quote(assetsha)},'LF_OWNER_PG18')::text; COMMIT;""")
        receipt=json.loads(signed.splitlines()[-1])
        fail_assert(receipt["status"]=="APPROVED","ASSET_APPROVAL_MISSING")
        # Direct anon invocation must fail; apply is service_role-only.
        self.sql(f"BEGIN; SET LOCAL ROLE anon; SELECT public.lf_ig_asset_owner_apply_v2({quote(receipt['receipt_id'])}::uuid); ROLLBACK;",
          expect_fail="permission denied")
        applied=json.loads(self.sql(f"""BEGIN; SET LOCAL ROLE service_role;
          SELECT public.lf_ig_asset_owner_apply_v2({quote(receipt['receipt_id'])}::uuid)::text; COMMIT;""").splitlines()[-1])
        fail_assert(applied["status"]=="APPLIED_VERIFIED" and applied["old_sha256"]!=applied["new_sha256"],
          "ASSET_READBACK_HASH_FAILED "+str(applied))
        owner=self.sql("SELECT owner_name FROM public.lf_activos WHERE codigo_activo="+quote(asset)+";")
        fail_assert(owner=="LF_OWNER_PG18","ASSET_OWNER_NOT_APPLIED")
        self.sql(f"BEGIN; SET LOCAL ROLE service_role; SELECT public.lf_ig_asset_owner_apply_v2({quote(receipt['receipt_id'])}::uuid); ROLLBACK;",
          expect_fail="LF_IG_ASSET_OWNER_RECEIPT_NOT_APPROVED")
        actualsha=self.sql(f"""SELECT encode(extensions.digest(
            convert_to((to_jsonb(a)-'updated_at')::text,'UTF8'),'sha256'),'hex')
            FROM public.lf_activos a WHERE codigo_activo={quote(asset)};""")
        fail_assert(actualsha==applied["new_sha256"],"ASSET_CANONICAL_HASH_READBACK_MISMATCH")
        print("PASS_PG18_SQL_ASSET_OWNER_PREIMAGE_AUTH_AND_READBACK",flush=True)


if __name__=="__main__":
    unittest.main()

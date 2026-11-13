"""PostgreSQL 17.6/18.7: real policy19 eight-config guarded migration using full
provenance validation/trigger source extracted read-only from live PostgreSQL.
All positive effects rolled back. Does not connect to live Supabase.
"""
import hashlib, json, pathlib, re, subprocess, time, unittest, uuid
ROOT=pathlib.Path(__file__).resolve().parents[3]
FIX=ROOT/"docs/rule-quality-lote37/apply_preparation/policy19_pg_isolated_fixture.sql"
PROV=pathlib.Path(__file__).with_name("policy19_live_provenance_guard_lab.sql")
MIG=ROOT/"audits/login-policy19-l37/02_pre_act0001_original_migration_snapshot.sql"
BEFORE="f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07"
DESC="0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b"
KEYS=("admin_minimum_strength","admin_phishing_resistant_requirement",
"phishing_resistant_option_required","admin_primary_method","admin_identity_provider",
"admin_sso_protocol","admin_provider_configuration_status","factor_selection_status")

class Policy19Lab(unittest.TestCase):
    def sql(self,script,error=None):
        for tries in range(18):
            p=subprocess.run(["docker","exec","-i",self.container,"psql","-X","-q",
                "-v","ON_ERROR_STOP=1","-A","-t","-U","postgres","-d","postgres"],
                input=script,text=True,capture_output=True,timeout=240)
            if p.returncode and "connection to server on socket" in p.stderr and "No such file or directory" in p.stderr and tries<17:
                time.sleep(1);continue
            break
        if error:
            m=re.search(r"ERROR:\s*([A-Z][A-Z0-9_]+)",p.stderr)
            self.assertNotEqual(p.returncode,0)
            self.assertEqual(m.group(1) if m else None,error,p.stderr[-1400:])
            return p.stderr
        self.assertEqual(p.returncode,0,p.stderr[-1400:])
        return p.stdout.strip()
    def lab(self,image,version):
        self.container="lf-l36-p19-"+uuid.uuid4().hex[:10]
        p=subprocess.run(["docker","run","-d","--rm","--name",self.container,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            capture_output=True,text=True,timeout=220)
        self.assertEqual(p.returncode,0,p.stderr[-1000:])
        try:
            for _ in range(60):
                r=subprocess.run(["docker","exec",self.container,"pg_isready","-U","postgres"],capture_output=True,timeout=10)
                if r.returncode==0: break
                time.sleep(1)
            else: self.fail("POSTGRES_READY_TIMEOUT")
            self.assertEqual(self.sql("SHOW server_version_num;"),version)
            self.sql(FIX.read_text(encoding="utf-8"))
            self.sql(PROV.read_text(encoding="utf-8"))
            rowsha="SELECT encode(sha256(convert_to(to_jsonb(p)::text,'UTF8')),'hex') FROM lf_ops.politicas_seguridad p WHERE security_policy_id=19;"
            old=self.sql(rowsha)
            self.assertEqual(old,BEFORE)
            original_config=self.sql("SELECT encode(sha256(convert_to(policy_config::text,'UTF8')),'hex') FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;")
            verify=("SELECT jsonb_build_object('status',status,'description_sha',"
                "encode(sha256(convert_to(description,'UTF8')),'hex'),"
                "'new_config_fields',(SELECT jsonb_object_agg(k,policy_config->k) FROM unnest(ARRAY["
                +",".join("'"+k+"'" for k in KEYS)
                +"]) k),'provenance_count',(SELECT count(*) FROM jsonb_object_keys(parameter_provenance) k WHERE k IN ("
                +",".join("'"+k+"'" for k in KEYS)
                +")),'non_otp_preserved',policy_config->'admin_profile_ids'='[1,2]'::jsonb,"
                "'canonical_provenance',programacion.fn_input_parameter_provenance_valid_v1(parameter_provenance)"
                ")::text FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;")
            # Single explicit transaction; test both readback INSIDE and original SHA OUTSIDE.
            lines=self.sql("BEGIN;\n"+MIG.read_text(encoding="utf-8")+"\n"+verify+"\nROLLBACK;\n"+rowsha).splitlines()
            self.assertGreaterEqual(len(lines),2,repr(lines))
            data=json.loads(lines[-2])
            self.assertEqual(lines[-1],BEFORE,"EXACT_ROLLBACK_FULLROW_DRIFT")
            self.assertEqual(data["status"],"CANDIDATO")
            self.assertEqual(data["description_sha"],DESC)
            self.assertEqual(data["provenance_count"],8)
            self.assertTrue(data["canonical_provenance"])
            self.assertTrue(data["non_otp_preserved"])
            conf=data["new_config_fields"]
            self.assertEqual(len(conf),8)
            self.assertEqual(conf["admin_minimum_strength"],"APPROVED_MFA")
            self.assertEqual(conf["admin_primary_method"],"USERNAME_PASSWORD_SERVER_VALIDATED")
            self.assertEqual(conf["phishing_resistant_option_required"],False)
            self.assertEqual(self.sql(rowsha),BEFORE)
            self.assertEqual(self.sql("SELECT encode(sha256(convert_to(policy_config::text,'UTF8')),'hex') FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;"),original_config)
            print("PASS_POLICY19_EIGHT_FIELDS_ATOMIC_APPLY_PROVENANCE_READBACK_EXACT_ROLLBACK_"+image+"_version="+version,flush=True)
            # Failure closed: mutated before-row SHA, original SQL unchanged.
            self.sql("UPDATE lf_ops.politicas_seguridad SET description='DRIFT_TEST' WHERE security_policy_id=19;")
            self.sql(MIG.read_text(encoding="utf-8"),error="LF_POLICY19_SOURCE_PREIMAGE_DRIFT")
            self.assertEqual(self.sql("SELECT description FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;"),"DRIFT_TEST")
            self.assertEqual(self.sql("SELECT encode(sha256(convert_to(policy_config::text,'UTF8')),'hex') FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;"),original_config)
            print("PASS_POLICY19_EIGHT_FIELDS_STALE_PREIMAGE_BLOCKED_NO_MUTATION_"+image,flush=True)
            # Live provenance guard copied EXACT: missing entry must reject.
            self.sql("UPDATE lf_ops.politicas_seguridad SET policy_config=jsonb_set(policy_config,'{admin_primary_method}',"
                " '\"UNAUTHORIZED_CHANGE\"'::jsonb) WHERE security_policy_id=19;",
                error="PARAMETER_PROVENANCE_REQUIRED")
            self.assertEqual(self.sql("SELECT policy_config->>'admin_primary_method' FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;"),"GOOGLE_WORKSPACE_SAML_SSO")
            print("PASS_POLICY19_PROVENANCE_TRIGGER_REJECTS_MISSING_PROOF_"+image,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",self.container],capture_output=True,text=True,timeout=60)
    def test_pg176(self):self.lab("postgres:17.6","170006")
    def test_pg187(self):self.lab("postgres:18.7","180007")

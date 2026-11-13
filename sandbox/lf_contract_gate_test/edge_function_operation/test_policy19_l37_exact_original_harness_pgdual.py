#!/usr/bin/env python3
"""L37 original harness diagnostic + independent exact-SQL dual PG verification.
The ORIGINAL three Login L37 files are never edited or monkeypatched.
No Supabase connection; all SQL changes occur in disposable Docker containers.
"""
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import time
import uuid
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
DIR = ROOT / "docs/rule-quality-lote37/apply_preparation"
SOURCE_SHA = "f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07"
DESCRIPTION_SHA = "0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b"
EXPECTED_GIT_BLOB = {
    "policy19_description_only_candidate.sql": "f20ef63ee8ebf4be546e7eb3f67c24abef79e44f",
    "policy19_pg_isolated_fixture.sql": "f028c0733f1eba7dbb70af74f6dd85b314ea3adf",
    "test_policy19_pg17_pg18_rollback.py": "6229860936ecd13844cf7cc79eafe776af2b6ab7",
}
FIXTURE = DIR / "policy19_pg_isolated_fixture.sql"
CANDIDATE = DIR / "policy19_description_only_candidate.sql"
ORIGINAL = DIR / "test_policy19_pg17_pg18_rollback.py"

class TestPolicy19L37OriginalAndIndependent(unittest.TestCase):
    def test_01_original_unmodified_harness_diagnostic(self):
        for name, expected in EXPECTED_GIT_BLOB.items():
            data = (DIR / name).read_bytes()
            git_sha = hashlib.sha1(
                b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
            self.assertEqual(git_sha, expected, "L37_SOURCE_BYTES_CHANGED:" + name)
            print("PASS_POLICY19_ORIGINAL_UNMODIFIED_BLOB " + name + " " + git_sha,flush=True)
        result = subprocess.run([sys.executable,str(ORIGINAL)],cwd=str(ROOT),
            capture_output=True,text=True,timeout=400)
        print("L37_ORIGINAL_HARNESS_EXIT=" + str(result.returncode),flush=True)
        print("L37_ORIGINAL_HARNESS_STDOUT=" + result.stdout[-1000:],flush=True)
        print("L37_ORIGINAL_HARNESS_STDERR=" + result.stderr[-1700:],flush=True)
        # Actual original L37 assertion is demonstrably erroneous:
        # SELECT (boolean)::text returns "true", not psql's uncast "t".
        # Do not falsely report that the original harness passed.
        self.assertNotEqual(result.returncode,0)
        self.assertIn("AssertionError: POLICY_CONFIG_CHANGED",result.stderr)
        print("OBSERVED_L37_ORIGINAL_HARNESS_FAIL_BOOL_TEXT_T_VS_TRUE",flush=True)

    @staticmethod
    def psql(container, sql, expected_error=None, timeout=200):
        for n in range(20):
            p = subprocess.run(["docker","exec","-i",container,"psql",
                "-X","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres",
                "-A","-t","-q"],input=sql,text=True,capture_output=True,timeout=timeout)
            # Retry only if connection never existed. No SQL error is replayed.
            if (p.returncode!=0 and "connection to server on socket" in p.stderr
                    and "No such file or directory" in p.stderr and n<19):
                time.sleep(1)
                continue
            break
        if expected_error:
            m=re.search(r"ERROR:\s*([A-Z][A-Z0-9_]+)",p.stderr)
            if p.returncode==0 or not m or m.group(1)!=expected_error:
                raise AssertionError("NEGATIVE_ERROR_MISMATCH expected="
                    +expected_error+" actual="+str(m.group(1) if m else None)
                    +" stderr="+p.stderr[-1000:])
            return p.stderr
        if p.returncode:
            raise AssertionError("L37_INDEPENDENT_SQL_FAILED "+p.stderr[-1800:])
        return p.stdout.strip()

    def execute_version(self,image,expected_version):
        container="lf-policy19-independent-"+uuid.uuid4().hex[:9]
        r=subprocess.run(["docker","run","-d","--rm","--name",container,
            "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
            capture_output=True,text=True,timeout=240)
        self.assertEqual(r.returncode,0,"DOCKER_RUN "+r.stderr[-800:])
        try:
            for _ in range(70):
                ready=subprocess.run(["docker","exec",container,"pg_isready",
                    "-U","postgres","-d","postgres"],capture_output=True,timeout=10)
                if ready.returncode==0: break
                time.sleep(1)
            else: raise AssertionError("L37_PG_READY_TIMEOUT")
            version=self.psql(container,"SHOW server_version_num;")
            self.assertEqual(version,expected_version)
            self.psql(container,FIXTURE.read_text(encoding="utf-8"))
            full_sha=("SELECT encode(pg_catalog.sha256(convert_to(to_jsonb(p)::text,"
                "'UTF8')),'hex') FROM lf_ops.politicas_seguridad p "
                "WHERE security_policy_id=19;")
            config_sha=("SELECT encode(pg_catalog.sha256(convert_to(policy_config::text,"
                "'UTF8')),'hex') FROM lf_ops.politicas_seguridad "
                "WHERE security_policy_id=19;")
            self.assertEqual(self.psql(container,full_sha),SOURCE_SHA)
            original_config_sha=self.psql(container,config_sha)
            positive="BEGIN;\n"+CANDIDATE.read_text(encoding="utf-8")+"""
SELECT jsonb_build_object(
  'description_sha',encode(pg_catalog.sha256(convert_to(description,'UTF8')),'hex'),
  'policy_config_sha',encode(pg_catalog.sha256(convert_to(policy_config::text,'UTF8')),'hex'),
  'admin_minimum_strength',policy_config->>'admin_minimum_strength',
  'admin_profile_ids',policy_config->'admin_profile_ids',
  'status',status,
  'no_google_saml_in_text',position('Google Workspace SAML' in description)=0,
  'otp_brevo_in_text',position('OTP por correo/Brevo' in description)>0
)::text FROM lf_ops.politicas_seguridad WHERE security_policy_id=19;
ROLLBACK;
"""+full_sha
            values=self.psql(container,positive).splitlines()
            self.assertGreaterEqual(len(values),2,"MISSING_READBACK")
            state=json.loads(values[-2])
            self.assertEqual(state["description_sha"],DESCRIPTION_SHA)
            self.assertEqual(state["policy_config_sha"],original_config_sha)
            self.assertEqual(state["admin_minimum_strength"],"PHISHING_RESISTANT")
            self.assertEqual(state["admin_profile_ids"],[1,2])
            self.assertEqual(state["status"],"CANDIDATO")
            self.assertTrue(state["otp_brevo_in_text"])
            self.assertTrue(state["no_google_saml_in_text"])
            self.assertEqual(values[-1],SOURCE_SHA,"FULLROW_ROLLBACK_SHA_DRIFT")
            self.assertEqual(self.psql(container,full_sha),SOURCE_SHA)
            self.assertEqual(self.psql(container,config_sha),original_config_sha)
            print("PASS_POLICY19_SQL_UNMODIFIED_APPLY_READBACK_ROLLBACK_"
                +image+"_version="+version,flush=True)
            # Reproduce L37 negative: only alter disposable fixture.
            self.psql(container,
                "UPDATE lf_ops.politicas_seguridad SET description='DRIFT_INJECTED' "
                "WHERE security_policy_id=19;")
            self.psql(container,CANDIDATE.read_text(encoding="utf-8"),
                expected_error="LF_POLICY19_SOURCE_PREIMAGE_DRIFT")
            self.assertEqual(self.psql(container,
                "SELECT description FROM lf_ops.politicas_seguridad "
                "WHERE security_policy_id=19;"),"DRIFT_INJECTED")
            self.assertEqual(self.psql(container,config_sha),original_config_sha)
            self.assertEqual(self.psql(container,
                "SELECT status FROM lf_ops.politicas_seguridad "
                "WHERE security_policy_id=19;"),"CANDIDATO")
            print("PASS_POLICY19_SQL_UNMODIFIED_STALE_PREIMAGE_ERROR_"
                +image+"_ZERO_UNAUTHORIZED_CHANGE",flush=True)
        finally:
            subprocess.run(["docker","rm","-f",container],
                capture_output=True,text=True,timeout=90)

    def test_02_original_fixture_and_candidate_exact_sql_pg17_pg18(self):
        self.execute_version("postgres:17.6","170006")
        self.execute_version("postgres:18.7","180007")
        print("PASS_POLICY19_ORIGINAL_SQL_FIXTURE_DUAL_PG17_6_PG18_7_ROLLBACK",flush=True)

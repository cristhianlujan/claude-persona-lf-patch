"""Disposable PG17.6 only. Exercise the same-run caller and both lock orders."""
import json
import os
from concurrent.futures import ThreadPoolExecutor
from contextlib import chdir
from pathlib import Path
import runpy
import subprocess
from tempfile import TemporaryDirectory
import time
from unittest.mock import patch
from uuid import uuid4

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = "EXEC-PROFILE-GATE2-" + "A" * 24
NONE = {"selected_skill_codes": [], "reason": "Optional skills unnecessary for this RUN"}


def verify(test):
    container = "lf-pre40-" + uuid4().hex[:12]
    subprocess.run(["docker", "run", "--rm", "-d", "--name", container,
                    "-e", "POSTGRES_PASSWORD=fixture", "postgres:17.6"], check=True, timeout=180)
    test.addCleanup(subprocess.run, ["docker", "rm", "-f", container], check=False)
    psql = ["docker", "exec", "-i", container, "psql", "-XqAt", "-U", "postgres", "-v", "ON_ERROR_STOP=1"]

    def sql(statement):
        result = subprocess.run(psql, input=statement, text=True, capture_output=True, timeout=30)
        test.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    for _ in range(90):
        ready = subprocess.run(["docker", "exec", container, "pg_isready", "-h", "127.0.0.1", "-U", "postgres"],
                               capture_output=True, timeout=10)
        if ready.returncode == 0:
            break
        time.sleep(1)
    test.assertEqual(sql("show server_version_num;"), "170006")
    migration, = (ROOT / "supabase/migrations").glob("*_lf_native_skill_selection_pre40_v1.sql")
    for script in [HERE / "setup.sql", HERE / "preimage.sql", migration]:
        sql(script.read_text())

    sql(f"select fixture_run('{RUN}');")
    def step40(run):
        return f"from lf_operation_execution_steps where execution_id='{run}' and step_id='input_validate'"

    # Replace the external OIDC/HTTP transports. Execute the real issue parser,
    # Python caller, Edge handler, plan, selector, binder and patched bridge.
    with TemporaryDirectory() as temp, chdir(temp):
        profile = Path("profiles/pre40/SKILL.md")
        profile.parent.mkdir(parents=True)
        profile.write_text("# Isolated profile")
        event = Path("event.json").resolve()
        env = {"LF_PROFILE_EDGE_URL":"https://fixture.invalid", "GITHUB_REPOSITORY":"fixture/lf",
               "GITHUB_SHA":"a" * 40, "GITHUB_EVENT_PATH":str(event), "GITHUB_EVENT_NAME":"issues",
               "LF_PROFILE_RESUME_REQUEST_MODE":"ISSUE", "PRE40_CONTAINER":container}
        with patch.dict(os.environ, env):
            main = runpy.run_path(str(ROOT / "scripts/lf_profile_native_resume.py"))["main"]
            node = ["node"]
            if int(subprocess.check_output(["node","-p","process.versions.node.split('.')[0]"], text=True)) < 23:
                node = ["npx","--yes","--package=node@24.12.0","--","node"]
            def transport(_url, body, _headers):
                raw = subprocess.check_output([*node, "--experimental-transform-types", str(HERE / "edge.mjs")],
                                              input=json.dumps(body), text=True, timeout=90)
                code, response = json.loads(raw)
                test.assertEqual(code, 200, response)
                return code, response
            for fields, phase in [({}, "SKILL_SELECTION_REQUIRED"),
                                  ({"skill_selection_decision":NONE}, "NATIVE_MODEL_INPUT_READY")]:
                payload = {"schema_version":"LF_PROFILE_NATIVE_RESUME_REQUEST_V1", "execution_id":RUN, **fields}
                event.write_text(json.dumps({"action":"labeled","label":{"name":"lf-profile-resume-governed"},
                    "issue":{"state":"open","repository_url":"https://api.github.com/repos/fixture/lf",
                             "body":json.dumps(payload)}}))
                with patch.dict(main.__globals__, {"oidc":lambda:"fixture", "call_json":transport}):
                    test.assertEqual(main(), 1)  # A governed checkpoint is deliberately incomplete.
                checkpoint = json.loads(Path("profile-native-continuation.json").read_text())
                test.assertEqual((checkpoint["execution_id"], checkpoint["phase"]), (RUN, phase))
                if not fields:
                    test.assertEqual(sql("select count(*) " + step40(RUN)), "0")
                    plan = json.loads(Path("profile-native-operation-plan.json").read_text())
                    test.assertEqual([s["skill_code"] for s in plan["skill_candidates"]], ["A","B"])
                    test.assertEqual(plan["selection_receipt"]["selection_mode"], "OPTIONAL_FAIL_OPEN")
    evidence = json.loads(sql("select evidence_payload " + step40(RUN)))
    test.assertIs(evidence["skill_selection_closed"], True)
    test.assertEqual(evidence["skill_execution_receipts"], [])
    test.assertIn("SKILL_EXPLICIT_NONE", [f["finding_code"] for f in evidence["skill_selection_findings"]])
    print("PASS_PRE40_PYTHON_EDGE_PG17_OPTIONAL_NONE_SAME_RUN", flush=True)

    def race(run, first, second, expected_first, expected_second):
        sql(f"select fixture_run('{run}');")
        with subprocess.Popen(psql, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as owner:
            try:
                owner.stdin.write("BEGIN;\n" + first + ";\n")
                owner.stdin.flush()
                test.assertEqual(json.loads(owner.stdout.readline())["status"], expected_first)
                with ThreadPoolExecutor(max_workers=1) as pool:
                    waiting = pool.submit(sql, "SET application_name='pre40_waiter';\n" + second + ";")
                    try:
                        for _ in range(100):
                            locked = sql("select exists(select 1 from pg_stat_activity where application_name='pre40_waiter' and cardinality(pg_blocking_pids(pid))>0);")
                            if locked == "t" or waiting.done():
                                break
                            time.sleep(0.05)
                        test.assertEqual(locked, "t", "no observed overlap at RUN row lock")
                    finally:
                        owner.stdin.write("COMMIT;\n\\q\n")
                        owner.stdin.flush()
                    reply = json.loads(waiting.result(timeout=30))
                    test.assertEqual(reply.get("blocking_code", reply["status"]), expected_second)
            finally:
                if owner.poll() is None:
                    owner.stdin.close()
        test.assertEqual(sql("select count(*) " + step40(run)), "1")

    for bind_first in (True, False):
        run = RUN + ("B" if bind_first else "C")
        bind = f"select lf_profile_skill_selection_run_bind_v1('{run}','{json.dumps(NONE)}'::jsonb,'{run}')"
        bridge = f"select lf_profile_native_bridge_prepare_v1('{run}',repeat('a',40),'sha256:'||repeat('b',64),'{run}')"
        if bind_first:
            race(run, bind, bridge, "BOUND", "NATIVE_MODEL_INPUT_READY")
        else:
            sql("update lf_skill_selector_policy_v1 set enabled=false;")
            race(run, bridge, bind, "NATIVE_MODEL_INPUT_READY", "SKILL_SELECTION_ALREADY_CLOSED")
            test.assertEqual(sql(f"select manifest ? 'skill_selection_decision' from lf_operation_execution where execution_id='{run}'"), "f")
    print("PASS_PRE40_PG17_BOTH_LOCK_ORDERS", flush=True)
